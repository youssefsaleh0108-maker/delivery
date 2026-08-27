import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'delivery_address.dart';

/// Picks or enters the delivery address.
///
/// A bottom sheet rather than a route: choosing an address is a decision made *while* looking at
/// the storefront, and pushing a full screen loses that context.
///
/// Drawn from the redesign's `customer-set-address` (node 22:204): the 24-radius white panel, the
/// tinted location tile on each saved address, the Home / Work / Other label chips, the
/// label-over-input field shape and the 16-radius confirm button. The frame's 320px map with its
/// draggable "Set here" pin is **not** reproduced — there is no geocoder, no places search and
/// nowhere to put a coordinate, so a pin that moves and changes nothing would be a control that
/// lies. The typed line and the area picker are what actually decide where an order goes.
Future<void> showAddressSheet(BuildContext context, DeliveryAddressStore store,
    {DeliveryZoneApi? zoneApi, GeocodingApi? geocodingApi}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DeliveryColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
    ),
    builder: (BuildContext context) =>
        _AddressSheet(store: store, zoneApi: zoneApi, geocodingApi: geocodingApi),
  );
}

class _AddressSheet extends StatefulWidget {
  const _AddressSheet({required this.store, this.zoneApi, this.geocodingApi});

  final DeliveryAddressStore store;

  /// Optional so the sheet still works with no areas configured, and so a test can pump it
  /// without a server.
  final DeliveryZoneApi? zoneApi;

  /// The place search behind the field above the typed line. Optional like [zoneApi]: without it
  /// the sheet is exactly what it was — a typed line and an area — and nothing pretends to
  /// search.
  final GeocodingApi? geocodingApi;

  @override
  State<_AddressSheet> createState() => _AddressSheetState();
}

/// Which of the design's three label chips is lit.
enum _LabelChoice { home, work, other }

class _AddressSheetState extends State<_AddressSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _line =
      TextEditingController(text: widget.store.selected?.line ?? '');
  late final TextEditingController _label =
      TextEditingController(text: widget.store.selected?.label ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.store.selected?.notes ?? '');

  /// The areas to choose from, or empty when the platform has not defined any.
  ///
  /// Loaded rather than required: a deployment with no areas configured must still be able to save
  /// an address, and the picker simply does not appear.
  List<DeliveryZone> _zones = <DeliveryZone>[];
  String? _zoneId;

  /// The chip that is lit. `other` is the only one that shows the free-text label field, which is
  /// exactly what the design's "Other" chip implies and what the label already was.
  _LabelChoice _labelChoice = _LabelChoice.other;

  // ------------------------------------------------------------------ the place search

  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  List<PlaceCandidate> _candidates = <PlaceCandidate>[];
  bool _searching = false;
  bool _searchFailed = false;

  /// The last query the server actually answered, so "no places found" is only ever said about a
  /// question that was asked — not flashed at a query still waiting out its debounce.
  String? _answeredQuery;

  /// The pin the picker dropped, travelling with the saved address and then with the order.
  ///
  /// Kept when the customer edits the line afterwards — adding a flat number does not move the
  /// building — and removable through the chip's close affordance when the pin genuinely no
  /// longer describes the address.
  double? _lat;
  double? _lng;

  /// The reverse geocoder's town or district for the picked point, when it knows one. Purely a
  /// caption under the pin chip.
  String? _locality;

  @override
  void initState() {
    super.initState();
    // In initState rather than a field initialiser: `widget` is not available while fields are
    // being initialised.
    _zoneId = widget.store.selected?.zoneId;
    _lat = widget.store.selected?.latitude;
    _lng = widget.store.selected?.longitude;
    _loadZones();
  }

  void _onSearchTyped(String text) {
    _searchDebounce?.cancel();
    if (text.trim().isEmpty) {
      setState(() {
        _candidates = <PlaceCandidate>[];
        _searching = false;
        _searchFailed = false;
      });
      return;
    }
    // Under three characters the server answers with an empty list without spending geocoding
    // budget, so firing per pause is safe by design.
    _searchDebounce = Timer(const Duration(milliseconds: 400), () => _runSearch(text.trim()));
  }

  Future<void> _runSearch(String text) async {
    final GeocodingApi? api = widget.geocodingApi;
    if (api == null || !mounted) return;
    setState(() {
      _searching = true;
      _searchFailed = false;
    });
    try {
      final PlaceSearchResult result = await api.searchPlaces(text);
      if (!mounted || _search.text.trim() != text) return;
      setState(() {
        _candidates = result.results;
        _searching = false;
        _answeredQuery = text;
      });
    } catch (_) {
      if (!mounted || _search.text.trim() != text) return;
      setState(() {
        _searching = false;
        _searchFailed = true;
        _candidates = <PlaceCandidate>[];
      });
    }
  }

  /// Takes a candidate: the line fills with its label, the pin is kept, and the reverse geocoder
  /// is asked what neighbourhood the point is in — a caption, never a blocker.
  void _pickCandidate(PlaceCandidate candidate) {
    setState(() {
      _line.text = candidate.label;
      _lat = candidate.latitude;
      _lng = candidate.longitude;
      _locality = null;
      _candidates = <PlaceCandidate>[];
      _search.clear();
    });
    final GeocodingApi? api = widget.geocodingApi;
    if (api == null) return;
    unawaited(api.reverse(candidate.latitude, candidate.longitude).then(
      (ReverseGeocodeResult? reverse) {
        if (!mounted || reverse == null) return;
        // Only if the pin has not moved since the question was asked.
        if (_lat == candidate.latitude && _lng == candidate.longitude) {
          setState(() => _locality = reverse.locality);
        }
      },
      onError: (Object _) {
        // The caption stays empty. A pin without a named district is still a pin.
      },
    ));
  }

  void _clearPin() => setState(() {
        _lat = null;
        _lng = null;
        _locality = null;
      });

  /// Lights the chip that matches an already-saved label, so re-opening the sheet on "Home" does
  /// not present it as a custom label nobody chose.
  void _syncLabelChoice(DeliveryStrings t) {
    final String current = _label.text.trim().toLowerCase();
    if (current == t.custLabelHome.toLowerCase()) {
      _labelChoice = _LabelChoice.home;
    } else if (current == t.custLabelWork.toLowerCase()) {
      _labelChoice = _LabelChoice.work;
    } else {
      _labelChoice = _LabelChoice.other;
    }
  }

  bool _labelSynced = false;

  Future<void> _loadZones() async {
    final DeliveryZoneApi? api = widget.zoneApi;
    if (api == null) return;
    try {
      final List<DeliveryZone> zones = await api.picker();
      if (!mounted) return;
      setState(() {
        _zones = zones;
        // A saved address may name an area that has since been retired: it is no longer in the
        // picker, so keeping the id selected would show a blank dropdown that silently submits an
        // area nobody offers. Clearing it makes the customer choose again.
        if (_zoneId != null && !zones.any((DeliveryZone z) => z.id == _zoneId)) {
          _zoneId = null;
        }
      });
    } catch (_) {
      // No picker rather than no sheet. An address without an area is still a usable address.
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _line.dispose();
    _label.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final DeliveryZone? zone = _zoneId == null
        ? null
        : _zones.where((DeliveryZone z) => z.id == _zoneId).firstOrNull;
    await widget.store.select(DeliveryAddress(
      line: _line.text.trim(),
      label: _label.text.trim().isEmpty ? null : _label.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      zoneId: zone?.id,
      // Stored alongside the id so the address still reads correctly if the area is later retired.
      zoneName: zone?.name,
      // The picker's pin, when one was dropped. It travels with the order at placement so the
      // tracking service has a point to measure the rider's ETA against.
      latitude: _lat,
      longitude: _lng,
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    if (!_labelSynced) {
      _syncLabelChoice(t);
      _labelSynced = true;
    }

    return Padding(
      // Lifts the sheet clear of the keyboard, which otherwise covers the field being typed into.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: DeliveryColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: DeliverySpacing.md),
                Text(
                  t.whereShouldWeBring,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: DeliverySpacing.md),

                if (widget.store.recents.isNotEmpty) ...<Widget>[
                  Text(
                    t.recent,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.muted,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.sm),
                  for (final DeliveryAddress address in widget.store.recents) ...<Widget>[
                    _recentRow(t, address),
                    const SizedBox(height: DeliverySpacing.sm),
                  ],
                  const SizedBox(height: DeliverySpacing.sm),
                  const Divider(height: 1, thickness: 1, color: DeliveryColors.border),
                  const SizedBox(height: DeliverySpacing.md),
                ],

                if (widget.geocodingApi != null) ...<Widget>[
                  _searchSection(t),
                  const SizedBox(height: DeliverySpacing.md),
                ],

                _field(
                  label: t.address,
                  child: TextFormField(
                    controller: _line,
                    autofocus: widget.store.recents.isEmpty,
                    textInputAction: TextInputAction.next,
                    style: _inputStyle,
                    decoration: _boxDecoration(t.addressHint),
                    validator: (String? v) =>
                        (v == null || v.trim().length < 5) ? t.addressTooShort : null,
                  ),
                ),

                // The pin the picker dropped, named and removable. Only ever shown when real
                // coordinates exist — an address typed by hand has no chip and no pretence.
                if (_lat != null && _lng != null) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.sm),
                  _pinChip(t),
                ],

                // The area, directly under the street. It is part of the address rather than a
                // setting — and it is what decides whether a shop will come at all, and for how
                // much.
                if (_zones.isNotEmpty) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.md),
                  _field(
                    label: t.area,
                    child: DropdownButtonFormField<String>(
                      initialValue: _zoneId,
                      isExpanded: true,
                      style: _inputStyle,
                      decoration: _boxDecoration(t.area),
                      items: <DropdownMenuItem<String>>[
                        for (final DeliveryZone zone in _zones)
                          DropdownMenuItem<String>(
                            value: zone.id,
                            child: Text(
                              zone.region == null || zone.region!.isEmpty
                                  ? zone.name
                                  : '${zone.name} · ${zone.region}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (String? id) => setState(() => _zoneId = id),
                      // Required once areas exist. An address with no area is priced at the flat
                      // fee, which is right for one saved before areas and wrong for one typed now.
                      validator: (String? v) => v == null ? t.pickYourArea : null,
                    ),
                  ),
                ],

                const SizedBox(height: DeliverySpacing.md),
                _labelChips(t),

                const SizedBox(height: DeliverySpacing.md),
                _field(
                  label: t.riderNotesOptional,
                  child: TextFormField(
                    controller: _notes,
                    style: _inputStyle,
                    decoration: _boxDecoration(t.riderNotesHint),
                  ),
                ),

                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _save,
                    child: Text(
                      t.deliverHere,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: DeliverySpacing.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const TextStyle _inputStyle =
      TextStyle(fontSize: 14, color: DeliveryColors.ink, height: 1.35);

  /// The design's input box: white, 1px [DeliveryColors.borderFaint], radius 12, 14px padding.
  InputDecoration _boxDecoration(String hint) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: DeliveryColors.white,
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 14, color: DeliveryColors.faint, height: 1.35),
      contentPadding: const EdgeInsetsDirectional.all(14),
      border: border(DeliveryColors.borderFaint, 1),
      enabledBorder: border(DeliveryColors.borderFaint, 1),
      focusedBorder: border(DeliveryColors.brand, 1.5),
      errorBorder: border(DeliveryAccent.critical.color, 1),
      focusedErrorBorder: border(DeliveryAccent.critical.color, 1.5),
    );
  }

  // ------------------------------------------------------------------ the search section

  /// The place search: the design's input shape with a magnifier, the candidate rows under it,
  /// and one quiet line for the empty and failed answers.
  Widget _searchSection(DeliveryStrings t) {
    final String query = _search.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _search,
          onChanged: _onSearchTyped,
          textInputAction: TextInputAction.search,
          style: _inputStyle,
          decoration: _boxDecoration(t.searchForAPlace).copyWith(
            prefixIcon: const Icon(Icons.search_rounded,
                size: 18, color: DeliveryColors.faint),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 40, minHeight: 20),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsetsDirectional.all(12),
                    child: SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: DeliveryColors.brand),
                    ),
                  )
                : null,
          ),
        ),
        if (_candidates.isNotEmpty) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          Container(
            decoration: BoxDecoration(
              color: DeliveryColors.white,
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              border: Border.all(color: DeliveryColors.borderFaint),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < _candidates.length; i++) ...<Widget>[
                  if (i > 0)
                    const Divider(height: 1, thickness: 1, color: DeliveryColors.borderFaint),
                  _candidateRow(_candidates[i]),
                ],
              ],
            ),
          ),
        ] else if (!_searching && _searchFailed) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            t.couldNotSearchPlaces,
            style: const TextStyle(
                fontSize: 12, color: DeliveryColors.muted, height: 1.35),
          ),
        ] else if (!_searching && query.length >= 3 && query == _answeredQuery) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            t.noPlacesFound,
            style: const TextStyle(
                fontSize: 12, color: DeliveryColors.muted, height: 1.35),
          ),
        ],
      ],
    );
  }

  Widget _candidateRow(PlaceCandidate candidate) {
    return InkWell(
      onTap: () => _pickCandidate(candidate),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: DeliverySpacing.md - DeliverySpacing.xs,
            vertical: DeliverySpacing.sm + 2),
        child: Row(
          children: <Widget>[
            Icon(
              // A near match is presented as a guess, exactly as the provider called it.
              candidate.confident ? Icons.place_rounded : Icons.place_outlined,
              size: 16,
              color: DeliveryColors.brand,
            ),
            const SizedBox(width: DeliverySpacing.sm),
            Expanded(
              child: Text(
                // Provider text rendered as text, never as markup.
                candidate.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, color: DeliveryColors.ink, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The brand-tinted "Pinned on the map" chip, with the reverse geocoder's district as its
  /// caption when one came back, and the close affordance that drops the pin.
  Widget _pinChip(DeliveryStrings t) {
    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: DeliverySpacing.sm + 2, vertical: DeliverySpacing.xs + 2),
          decoration: BoxDecoration(
            color: DeliveryColors.brandSoft,
            borderRadius: BorderRadius.circular(DeliveryRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.push_pin_outlined, size: 12, color: DeliveryColors.brand),
              const SizedBox(width: DeliverySpacing.xs),
              Flexible(
                child: Text(
                  _locality == null || _locality!.isEmpty
                      ? t.addressPinnedOnMap
                      : '${t.addressPinnedOnMap} · $_locality',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.brand,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: DeliverySpacing.xs),
              InkWell(
                borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                onTap: _clearPin,
                child: const Icon(Icons.close_rounded,
                    size: 12, color: DeliveryColors.brand),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// A SemiBold 13 caption over its input, with the design's 6px gap.
  Widget _field({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: DeliverySpacing.sm - 2),
        child,
      ],
    );
  }

  // ------------------------------------------------------------------ the label chips

  Widget _labelChips(DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          t.custLabelAddressAs,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: DeliveryColors.muted,
            height: 1.2,
          ),
        ),
        const SizedBox(height: DeliverySpacing.sm),
        Row(
          children: <Widget>[
            Flexible(
              child: YdChip(
                label: t.custLabelHome,
                icon: Icons.home_outlined,
                selected: _labelChoice == _LabelChoice.home,
                onTap: () => _chooseLabel(_LabelChoice.home, t.custLabelHome),
              ),
            ),
            const SizedBox(width: DeliverySpacing.sm),
            Flexible(
              child: YdChip(
                label: t.custLabelWork,
                icon: Icons.work_outline_rounded,
                selected: _labelChoice == _LabelChoice.work,
                onTap: () => _chooseLabel(_LabelChoice.work, t.custLabelWork),
              ),
            ),
            const SizedBox(width: DeliverySpacing.sm),
            Flexible(
              child: YdChip(
                label: t.custLabelOther,
                icon: Icons.more_horiz_rounded,
                selected: _labelChoice == _LabelChoice.other,
                onTap: () => _chooseLabel(_LabelChoice.other, null),
              ),
            ),
          ],
        ),
        // "Other" is the only one that needs saying out loud, so it is the only one that opens
        // the free-text field the label has always been.
        if (_labelChoice == _LabelChoice.other) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          TextFormField(
            controller: _label,
            textInputAction: TextInputAction.next,
            style: _inputStyle,
            decoration: _boxDecoration(t.labelHint),
          ),
        ],
      ],
    );
  }

  /// Picks a chip, writing its label into the field the address is actually saved from.
  void _chooseLabel(_LabelChoice choice, String? label) {
    setState(() {
      _labelChoice = choice;
      if (label != null) {
        _label.text = label;
      } else if (_label.text.trim() == DeliveryStrings.of(context).custLabelHome ||
          _label.text.trim() == DeliveryStrings.of(context).custLabelWork) {
        // Coming off Home or Work clears the label those chips wrote, rather than presenting it
        // as something the customer typed.
        _label.clear();
      }
    });
  }

  // ------------------------------------------------------------------ saved addresses

  /// One saved address, as the design draws its detected-location card: a brand-tinted radius-12
  /// tile holding a 20px pin, then a bold label over a 12px muted line.
  Widget _recentRow(DeliveryStrings t, DeliveryAddress address) {
    final bool isSelected = widget.store.selected == address;

    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        color: isSelected ? DeliveryColors.brandSoft : DeliveryColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          side: BorderSide(
            color: isSelected ? DeliveryColors.brandLine : DeliveryColors.borderFaint,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await widget.store.select(address);
            if (mounted) Navigator.of(context).pop();
          },
          child: Padding(
            padding: const EdgeInsetsDirectional.all(DeliverySpacing.sm),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsetsDirectional.all(10),
                  decoration: BoxDecoration(
                    color: DeliveryColors.brandSoft,
                    borderRadius: BorderRadius.circular(DeliveryRadius.md),
                  ),
                  child: const Icon(Icons.place_outlined,
                      size: 20, color: DeliveryColors.brand),
                ),
                const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        address.label == null || address.label!.isEmpty
                            ? address.line
                            : address.label!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.ink,
                          height: 1.25,
                        ),
                      ),
                      if (address.label != null && address.label!.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          address.line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: DeliveryColors.muted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: t.forgetThisAddress,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 16, color: DeliveryColors.faint),
                  onPressed: () async {
                    await widget.store.forget(address);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
