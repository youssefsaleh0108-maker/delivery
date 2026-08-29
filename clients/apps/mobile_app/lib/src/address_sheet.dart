import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'delivery_address.dart';

/// Picks or enters the delivery address.
///
/// A bottom sheet rather than a route: choosing an address is a decision made *while* looking at
/// the storefront, and pushing a full screen loses that context.
///
/// Drawn from the redesign's `customer-set-address` (node 22:204): the 24-radius white panel, the
/// tinted location tile on each saved address, the Home / Work / Other label chips, the
/// label-over-input field shape and the 16-radius confirm button — and the frame's map with its
/// draggable "Set here" pin, which is real now. The pin's coordinates are saved with the address,
/// travel with the order at placement, and are what the tracking service measures the rider's ETA
/// against; the reverse geocoder names the district under the pin and fills an empty address line
/// with the street it found. The typed line and the area picker still decide where the order goes
/// — the pin is what makes the last hundred metres findable.
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

  // ------------------------------------------------------------------ the map picker

  /// The canvas height for the picker.
  ///
  /// The frame draws 320 for a sheet that has nothing above the map. This sheet also carries the
  /// saved-address list and the place search, and at 320 the confirm button leaves the screen on a
  /// normal phone — so the canvas is the design's shape at a height the sheet can actually hold.
  static const double _mapHeight = 220;

  /// Where the picker opens when the customer has never dropped a pin.
  ///
  /// The platform's own configured zone (`delivery.platform.zone`, `Asia/Beirut`) expressed as a
  /// point. It is a **viewport and nothing else**: it is never written to the address, never sent
  /// with an order, and never shown as a coordinate. The pin is only ever recorded when the
  /// customer presses "Set here", which is them choosing this point rather than the app claiming
  /// it knows where they are.
  static const LatLng _openingView = LatLng(33.8938, 35.5018);

  final MapController _map = MapController();

  /// The camera's current centre — what the fixed pin is over, and what "Set here" commits.
  late LatLng _centre;

  /// [MapController.move] throws before the map has been laid out, so a candidate picked while the
  /// map is still building is remembered and applied in [MapOptions.onMapReady].
  bool _mapReady = false;
  LatLng? _pendingMove;

  /// True while the reverse geocoder is answering a dropped pin.
  bool _reversing = false;

  @override
  void initState() {
    super.initState();
    // In initState rather than a field initialiser: `widget` is not available while fields are
    // being initialised.
    _zoneId = widget.store.selected?.zoneId;
    _lat = widget.store.selected?.latitude;
    _lng = widget.store.selected?.longitude;
    _centre = _lat != null && _lng != null ? LatLng(_lat!, _lng!) : _openingView;
    _loadZones();
    // No saved pin: quietly aim the camera at the phone instead of the city-wide default. VIEWPORT
    // only, same as [_openingView] — nothing is committed until "Set here", and every refusal
    // (services off, denied, no fix) just leaves the default view without a word. The pushy
    // version of this question belongs to the "My location" button, where it was asked for.
    if (_lat == null && _lng == null) {
      DeviceLocation.current().then((DeviceLocationResult fix) {
        if (!mounted || _lat != null) return;
        if (fix is LocationFix) {
          _moveTo(LatLng(fix.latitude, fix.longitude), 16);
          setState(() {});
        }
      });
    }
  }

  /// True while the "My location" button is resolving a fix.
  bool _locating = false;

  /// The button's flow: fix → pin it; services off → offer the switch; denied → say so.
  Future<void> _useMyLocation(DeliveryStrings t) async {
    setState(() => _locating = true);
    final DeviceLocationResult result = await DeviceLocation.current();
    if (!mounted) return;
    setState(() => _locating = false);

    switch (result) {
      case LocationFix(:final double latitude, :final double longitude):
        _moveTo(LatLng(latitude, longitude), 16);
        // Pressing the button IS choosing the point, so it commits like "Set here" does.
        await _setPinHere();
      case LocationServicesOff():
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(t.locServicesOff),
            action: SnackBarAction(
              label: t.locTurnOn,
              onPressed: DeviceLocation.openLocationSettings,
            ),
          ));
      case LocationDenied():
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(t.locPermissionNeeded)));
      case LocationDeniedForever():
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(t.locPermissionNeeded),
            action: SnackBarAction(
              label: t.locOpenSettings,
              onPressed: DeviceLocation.openAppSettings,
            ),
          ));
      case LocationFailed():
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(t.locNoFix)));
    }
  }

  /// Points the camera at a place, whether or not the map has finished building.
  void _moveTo(LatLng point, double zoom) {
    _centre = point;
    if (!_mapReady) {
      _pendingMove = point;
      return;
    }
    _map.move(point, zoom);
  }

  /// Commits the point under the pin: the design's "Set here".
  ///
  /// The coordinate is the camera's, which is a fact about what the customer dragged the map to.
  /// Everything the reverse geocoder adds afterwards — the district caption, and the street when
  /// the address line is still empty — is a convenience layered on top and never blocks the pin.
  Future<void> _setPinHere() async {
    final LatLng point = _centre;
    setState(() {
      _lat = point.latitude;
      _lng = point.longitude;
      _locality = null;
    });

    final GeocodingApi? api = widget.geocodingApi;
    if (api == null) return;
    setState(() => _reversing = true);
    try {
      final ReverseGeocodeResult? reverse =
          await api.reverse(point.latitude, point.longitude);
      if (!mounted) return;
      setState(() {
        _reversing = false;
        // Only if the pin has not moved again since the question was asked.
        if (_lat != point.latitude || _lng != point.longitude) return;
        _locality = reverse?.locality;
        // A pin dropped before anything was typed fills the line with the street the provider
        // named. Anything already typed wins — a flat number is knowledge the geocoder lacks.
        if (reverse != null && _line.text.trim().isEmpty) {
          _line.text = reverse.label;
        }
      });
    } catch (_) {
      // The pin stands. A point without a named district is still a point, and the address line
      // stays whatever the customer typed.
      if (mounted) setState(() => _reversing = false);
    }
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
      // The map follows the search, so the pin the customer just chose is the one under the
      // crosshair — otherwise the map would sit somewhere else contradicting the chip below it.
      _moveTo(LatLng(candidate.latitude, candidate.longitude), 16);
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
    _map.dispose();
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

                // The frame's map, directly over the address line it feeds.
                _mapSection(t),
                const SizedBox(height: DeliverySpacing.md),

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

  // ------------------------------------------------------------------ the map picker

  /// The design's map canvas: a real OpenStreetMap basemap, a fixed centre pin, and the "Set here"
  /// pill that commits the point under it.
  ///
  /// The pin is fixed and the map moves under it rather than the pin being dragged across a still
  /// map. Both are "a draggable pin" to the person using it; only this one keeps the target under
  /// the finger that is not covering it, and it is the pattern every map picker on the phone
  /// already taught them.
  Widget _mapSection(DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          t.custPinYourDoor,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
        const SizedBox(height: DeliverySpacing.sm - 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          child: SizedBox(
            height: _mapHeight,
            child: OsmBasemap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _centre,
                initialZoom: _lat != null && _lng != null ? 16 : 12,
                minZoom: 3,
                maxZoom: 18,
                backgroundColor: DeliveryColors.background,
                // Rotation off: a rotated basemap under a fixed pin makes "which way is the
                // street" a puzzle, and nothing here needs a bearing.
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.drag |
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.pinchMove |
                      InteractiveFlag.doubleTapZoom |
                      InteractiveFlag.scrollWheelZoom,
                ),
                onMapReady: () {
                  _mapReady = true;
                  final LatLng? pending = _pendingMove;
                  if (pending != null) {
                    _pendingMove = null;
                    _map.move(pending, 16);
                  }
                },
                onPositionChanged: (MapCamera camera, bool _) => _centre = camera.center,
              ),
              // No layer over the tiles: the pin is an overlay rather than a marker precisely
              // because it must NOT move with the map.
              fallback: const _MapUnavailableSurface(),
              overlay: (bool tilesLive) => _mapOverlay(t, tilesLive),
            ),
          ),
        ),
        if (_reversing) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          Row(
            children: <Widget>[
              const SizedBox.square(
                dimension: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: DeliveryColors.brand),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              Text(
                t.custNamingThisPlace,
                style: const TextStyle(
                    fontSize: 12, color: DeliveryColors.muted, height: 1.35),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// The crosshair pin and the "Set here" pill.
  ///
  /// Drawn over the tiles when there are tiles, and withheld when there are not: a pin over a
  /// blank rectangle would commit a coordinate the customer had no way of aiming.
  Widget _mapOverlay(DeliveryStrings t, bool tilesLive) {
    if (!tilesLive) return const SizedBox.shrink();

    return Stack(
      children: <Widget>[
        // The fixed pin. Ignores pointers so every gesture reaches the map underneath it.
        const Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Padding(
                // Lifts the glyph so its POINT, not its middle, sits on the camera centre.
                padding: EdgeInsets.only(bottom: 22),
                child: Icon(Icons.place, size: 34, color: DeliveryColors.brand),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          // Clear of the licence notice pinned to the bottom corner beneath it.
          bottom: DeliverySpacing.md,
          start: DeliverySpacing.sm,
          end: DeliverySpacing.sm,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              YdPillButton(
                label: t.custSetHere,
                // The crosshair glyph moved to "My location", whose job it names; committing the
                // point under the pin is a place, so it gets the place glyph.
                icon: Icons.place,
                size: YdPillButtonSize.compact,
                expand: false,
                onPressed: _setPinHere,
              ),
              const SizedBox(width: DeliverySpacing.sm),
              YdPillButton.secondary(
                label: t.locMyLocation,
                icon: Icons.my_location_rounded,
                size: YdPillButtonSize.compact,
                expand: false,
                busy: _locating,
                onPressed: _locating ? null : () => _useMyLocation(t),
              ),
            ],
          ),
        ),
      ],
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

// ---------------------------------------------------------------------------- the basemap

/// The platform's one OpenStreetMap canvas, used by every map the customer sees.
///
/// It lives here because the address picker is the lowest screen in the customer graph that needs
/// it; the tracking panel imports it rather than growing a second copy that could drift on tile
/// source, attribution or failure behaviour.
///
/// **Tiles come from OpenStreetMap's own servers and are attributed, always.** The attribution is
/// not optional decoration — it is the condition under which the tiles may be used at all — so it
/// is drawn by this widget rather than left to each caller to remember, and it cannot be turned
/// off. [userAgentPackageName] identifies the app to those servers, as their usage policy requires.
///
/// **When tiles do not arrive, the map is replaced rather than left broken.** A basemap that
/// answers with nothing renders as a grey lattice of missing squares, which reads as a bug in the
/// app rather than as an unreachable tile server. Instead: a few failures with nothing ever having
/// loaded swaps the whole canvas for [fallback], the screen's own styled surface, and the overlay
/// is told so it can withhold controls that only make sense over real streets. One tile that does
/// load pins the map as working — after that a failure is a gap in a real map, not a dead one.
class OsmBasemap extends StatefulWidget {
  const OsmBasemap({
    super.key,
    required this.options,
    required this.fallback,
    this.layers = const <Widget>[],
    this.overlay,
    this.mapController,
  });

  /// Standard OSM raster tiles. Fixed rather than a parameter: one tile source means one
  /// attribution and one usage policy to honour.
  static const String tileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// How this app identifies itself to the tile servers, per their usage policy.
  static const String userAgentPackageName = 'shop.youdrop.app';

  /// The attribution OpenStreetMap's licence requires on every map drawn from its tiles.
  ///
  /// Deliberately not an l10n key: it is a licence notice naming a project, and translating
  /// "OpenStreetMap contributors" would be translating somebody's name.
  static const String attribution = '© OpenStreetMap contributors';

  final MapOptions options;

  /// Layers drawn over the tiles, in flutter_map's own coordinate space — markers, polylines.
  final List<Widget> layers;

  /// Drawn over the whole canvas in screen space, in BOTH states. `tilesLive` is false while the
  /// fallback is showing, so a control that needs real streets under it can withhold itself.
  final Widget Function(bool tilesLive)? overlay;

  /// The screen's own styled surface, shown instead of the map when tiles cannot be fetched.
  final Widget fallback;

  final MapController? mapController;

  @override
  State<OsmBasemap> createState() => _OsmBasemapState();
}

class _OsmBasemapState extends State<OsmBasemap> {
  /// How many tiles may fail before the canvas is called dead.
  ///
  /// More than one because a single 404 at the edge of the world is normal; small because a
  /// viewport is a dozen tiles and waiting for all of them to fail is waiting for nothing.
  static const int _failureBudget = 4;

  int _failures = 0;

  /// True once any tile has actually arrived. Latches: a map that worked stays a map.
  bool _tilesLive = false;

  bool _dead = false;

  void _onTileError() {
    if (_tilesLive || _dead) return;
    _failures++;
    if (_failures < _failureBudget) return;
    // The error arrives from an image stream, which can be mid-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tilesLive) setState(() => _dead = true);
    });
  }

  void _onTileLoaded() {
    if (_tilesLive) return;
    _tilesLive = true;
    if (!_dead) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _dead = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget canvas = _dead
        ? widget.fallback
        : FlutterMap(
            mapController: widget.mapController,
            options: widget.options,
            children: <Widget>[
              TileLayer(
                urlTemplate: OsmBasemap.tileUrlTemplate,
                userAgentPackageName: OsmBasemap.userAgentPackageName,
                // No fade: the canvas is often a few hundred pixels inside a sheet, where the
                // animation is invisible and only costs a ticker per tile.
                tileDisplay: const TileDisplay.instantaneous(),
                // OSM's servers publish to zoom 19 and answer 404 above it. Asking anyway would
                // manufacture the exact failures this widget treats as a dead map.
                maxNativeZoom: 19,
                errorTileCallback: (TileImage _, Object __, StackTrace? ___) => _onTileError(),
                tileBuilder: (BuildContext _, Widget tile, TileImage image) {
                  if (image.loadFinishedAt != null && !image.loadError) _onTileLoaded();
                  return tile;
                },
              ),
              ...widget.layers,
            ],
          );

    return Stack(
      children: <Widget>[
        Positioned.fill(child: canvas),
        // The licence notice, on top of everything, whenever tiles are what is being shown.
        if (!_dead)
          PositionedDirectional(
            bottom: 0,
            end: 0,
            child: Container(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 5, vertical: 2),
              color: DeliveryColors.white.withValues(alpha: 0.78),
              child: const Text(
                OsmBasemap.attribution,
                // The notice names a project and carries a copyright glyph; it reads the same way
                // in both directions and must not be mirrored into nonsense.
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: 9,
                  color: DeliveryColors.muted,
                  height: 1.2,
                ),
              ),
            ),
          ),
        if (widget.overlay != null) Positioned.fill(child: widget.overlay!(!_dead)),
      ],
    );
  }
}

/// What the address picker shows where the map would be when the tile server cannot be reached.
///
/// The page background with the same faint lattice the tracking canvas uses, and one sentence
/// saying what happened — so the sheet still reads as a designed surface and the customer knows
/// the typed line is now the whole answer.
class _MapUnavailableSurface extends StatelessWidget {
  const _MapUnavailableSurface();

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Container(
      color: DeliveryColors.background,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.map_outlined, size: 22, color: DeliveryColors.faint),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            t.custMapUnavailable,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: DeliveryColors.muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
