import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'store_pin_map.dart';

/// Shop Configuration — everything a merchant needs to get their store listed and keep it accurate.
///
/// The map thumbnail under the address card is a real OpenStreetMap view now, and the shop's pin
/// is placed and cleared through the store's own `location` endpoints. It keeps the exact slot the
/// frame gives it — 100px, same radius, same place in the column — and falls back to the styled
/// lattice this screen used to draw whenever the tiles will not load.
///
/// Drawn to the 2026-08 Figma frame `merchant-shop-config` (3:2039): a 120px cover area with a
/// "Change Cover" badge over a scrim, a bordered address card above a map thumbnail, and one
/// "Operating Details" card holding the hours, the minimum order and the delivery fee as labelled
/// boxes, closed by a full-width brand save button.
///
/// The frame draws four fields. This shop has more, and every one of them is load-bearing: the
/// storefront made a store mandatory but left no way to manage one, a merchant's first product
/// auto-provisions a DRAFT store called "My Store" with no opening hours, and `publish` refuses a
/// store without hours. So the profile fields, the ETA window, the logo and the publish/busy
/// controls all stay — restyled into the frame's own card-and-labelled-box language rather than
/// dropped, because dropping them would strand a real merchant in DRAFT with no way out.
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key, required this.api, this.geocoding});

  final StoreApi api;

  /// Lets the map picker turn the typed address into a point instead of making the merchant pan
  /// across a country. Optional: without it the picker still works, it just has no search box.
  final GeocodingApi? geocoding;

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _name = TextEditingController();
  final TextEditingController _tagline = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _tags = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _fee = TextEditingController();
  final TextEditingController _minOrder = TextEditingController();
  final TextEditingController _etaMin = TextEditingController();
  final TextEditingController _etaMax = TextEditingController();

  StoreVertical _vertical = StoreVertical.restaurant;
  List<OpeningWindow> _hours = <OpeningWindow>[];

  /// The frame shows opening hours as one summary line. Seven editable rows behind a summary is
  /// the same information one tap further away, and it keeps the frame's rhythm intact for the
  /// merchant who is not here to change their hours today.
  bool _hoursOpen = false;

  Store? _store;
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _name, _tagline, _description, _tags, _address, _fee, _minOrder, _etaMin, _etaMax
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // One page is plenty: this screen edits a single shop, and a merchant with many picks the first.
      final List<Store> mine = (await widget.api.mine(size: 20)).content;
      if (!mounted) return;
      if (mine.isEmpty) {
        // A merchant with no products yet has no store: nothing has triggered the
        // auto-provisioning. Say so rather than showing an empty form that cannot save.
        setState(() {
          _store = null;
          _loading = false;
        });
        return;
      }
      final Store store = mine.first;
      final List<OpeningWindow> hours = await widget.api.hours(store.id);
      if (!mounted) return;
      setState(() {
        _store = store;
        _hours = hours.isEmpty ? _defaultWeek() : hours;
        _loading = false;
      });
      _fillForm(store);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// A sensible week for a store that has never had hours set, so publishing is one tap away
  /// rather than fourteen fields of typing.
  static List<OpeningWindow> _defaultWeek() => <OpeningWindow>[
        for (int day = 1; day <= 7; day++)
          OpeningWindow(dayOfWeek: day, opensAt: '09:00', closesAt: '22:00'),
      ];

  void _fillForm(Store store) {
    _name.text = store.name;
    _tagline.text = store.tagline ?? '';
    _description.text = store.description ?? '';
    _tags.text = store.tags.join(', ');
    _address.text = store.address ?? '';
    _fee.text = store.deliveryFee.toStringAsFixed(2);
    _minOrder.text = store.minOrder.toStringAsFixed(2);
    _etaMin.text = '${store.etaMinMinutes}';
    _etaMax.text = '${store.etaMaxMinutes}';
    _vertical = store.vertical;
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _saving = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_message(e, DeliveryStrings.of(context))),
          backgroundColor: DeliveryColors.brandDark,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Surfaces the server's own explanation rather than a generic failure — "a store needs opening
  /// hours before it can be listed" is the whole reason publish fails, and hiding it would leave
  /// the merchant guessing.
  /// Takes the strings as an argument: this is static, so there is no context to read them from.
  static String _message(Object error, DeliveryStrings t) {
    final RegExpMatch? detail =
        RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(error.toString());
    return detail != null ? detail.group(1)! : t.thatDidNotWorkWith('$error');
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final Store store = _store!;
    await _run(() async {
      await widget.api.updateProfile(
        store.id,
        name: _name.text.trim(),
        vertical: _vertical,
        tagline: _tagline.text.trim().isEmpty ? null : _tagline.text.trim(),
        description: _description.text.trim().isEmpty ? null : _description.text.trim(),
        tags: _tags.text
            .split(',')
            .map((String t) => t.trim())
            .where((String t) => t.isNotEmpty)
            .toList(),
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      );
      await widget.api.updateCommercials(
        store.id,
        deliveryFee: double.parse(_fee.text),
        minOrder: double.parse(_minOrder.text),
        etaMinMinutes: int.parse(_etaMin.text),
        etaMaxMinutes: int.parse(_etaMax.text),
      );
      await widget.api.setHours(store.id, _hours);
    }, DeliveryStrings.of(context).shopSaved);
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final Store? store = _store;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: Column(
        children: <Widget>[
          YdScreenHeader(
            title: t.merchbShopConfiguration,
            // The frame's subtitle is the shop's own name.
            subtitle: store?.name,
          ),
          Expanded(child: _body(t, store)),
        ],
      ),
    );
  }

  Widget _body(DeliveryStrings t, Store? store) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    if (_error != null) {
      return YdEmptyState(
        icon: Icons.cloud_off_rounded,
        title: t.couldNotLoadYourShop,
        message: '$_error',
        action: YdPillButton.secondary(
          label: t.tryAgain,
          onPressed: _load,
          size: YdPillButtonSize.compact,
          expand: false,
        ),
      );
    }
    if (store == null) {
      return YdEmptyState(
        icon: Icons.storefront_outlined,
        title: t.noShopYet,
        message: t.shopCreatedAutomatically,
      );
    }

    return Align(
      alignment: AlignmentDirectional.topCenter,
      child: ConstrainedBox(
        // The frame is a phone column. On a portal pane it stays a column rather than stretching a
        // 12px-padded input box the width of a monitor.
        constraints: const BoxConstraints(maxWidth: 760),
        child: Form(
          key: _formKey,
          child: Scrollbar(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                DeliverySpacing.lg - DeliverySpacing.xs,
                DeliverySpacing.lg - DeliverySpacing.xs,
                DeliverySpacing.lg - DeliverySpacing.xs,
                DeliverySpacing.lg - DeliverySpacing.xs +
                    MediaQuery.paddingOf(context).bottom,
              ),
              children: <Widget>[
                _statusCard(t, store),
                const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                _bannerSection(t, store),
                const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                _profileCard(t),
                const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                _addressSection(t, store),
                const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                _operatingCard(t),
                const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                _saveButton(t),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- status

  /// Whether the shop is taking orders, and the three things a merchant can do about it.
  ///
  /// The frame puts the publish toggle on the dashboard rather than here, but Busy / Not busy /
  /// Publish are the controls that decide whether this shop appears on the storefront at all, and
  /// this is the screen that gets a shop listed. They stay, in the frame's button language.
  Widget _statusCard(DeliveryStrings t, Store store) {
    // The listing status, not the clock. Availability is open/busy/closed for the night; whether
    // the shop is on the storefront at all is its status, and that is what "Listed" here means.
    // Reading availability instead left a suspended shop still reading "Listed on the storefront".
    final bool listed = store.status.isListed;

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              StoreAvatar(name: store.name, logoUrl: store.logoUrl, size: 44),
              const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      t.merchbShopStatus,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: DeliverySpacing.xs),
                    Text(
                      listed ? t.listedOnStorefront : t.notListedYet,
                      style: const TextStyle(fontSize: 12, color: DeliveryColors.faint, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              StoreStatePill(state: _stateOf(store.availability)),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          Wrap(
            spacing: DeliverySpacing.sm,
            runSpacing: DeliverySpacing.sm,
            children: <Widget>[
              // Busy is a 30-minute flag that clears itself, so it is safe to offer as one tap.
              _ActionButton(
                label: t.busy30m,
                icon: Icons.timelapse_rounded,
                onPressed: _saving
                    ? null
                    : () => _run(
                          () => widget.api.setBusy(store.id, minutes: 30).then((_) {}),
                          t.markedBusy30,
                        ),
              ),
              _ActionButton(
                label: t.notBusy,
                icon: Icons.check_circle_outline_rounded,
                onPressed: _saving
                    ? null
                    : () => _run(
                          () => widget.api.clearBusy(store.id).then((_) {}),
                          t.noLongerBusy,
                        ),
              ),
              _ActionButton(
                label: t.publish,
                icon: Icons.rocket_launch_rounded,
                primary: true,
                onPressed: _saving
                    ? null
                    : () => _run(
                          () => widget.api.publish(store.id).then((_) {}),
                          t.yourShopIsLive,
                        ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- banner

  Widget _bannerSection(DeliveryStrings t, Store store) {
    final bool hasCover = store.coverUrl != null && store.coverUrl!.isNotEmpty;
    final bool hasLogo = store.logoUrl != null && store.logoUrl!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionLabel(t.merchbBannerAndLogo),
        const SizedBox(height: DeliverySpacing.sm),
        SizedBox(
          height: 120,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(DeliveryRadius.lg),
                child: hasCover
                    ? Image.network(
                        store.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => StoreMonogram(name: store.name, radius: 0),
                      )
                    : StoreMonogram(name: store.name, radius: 0),
              ),
              // The frame's scrim, so the badge stays legible over any photograph.
              DecoratedBox(
                decoration: BoxDecoration(
                  color: DeliveryColors.ink.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(DeliveryRadius.lg),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _saving ? null : () => _pickAndUpload(store, 'cover'),
                  borderRadius: BorderRadius.circular(DeliveryRadius.lg),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: DeliverySpacing.md - DeliverySpacing.xs,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: DeliveryColors.ink.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                      ),
                      child: Text(
                        hasCover ? t.merchbChangeCover : t.upload,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: DeliveryColors.white,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (hasCover)
                PositionedDirectional(
                  top: DeliverySpacing.sm,
                  end: DeliverySpacing.sm,
                  child: Material(
                    color: DeliveryColors.white,
                    shape: const CircleBorder(),
                    child: IconButton(
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      tooltip: t.remove,
                      onPressed: _saving
                          ? null
                          : () => _run(
                                () => widget.api
                                    .removeImage(storeId: store.id, slot: 'cover')
                                    .then((_) {}),
                                t.labelRemoved(t.cover),
                              ),
                      icon: const Icon(Icons.close, color: DeliveryColors.brand),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        // The logo, which the frame does not draw and the storefront cannot do without — a shop
        // with no logo is a monogram on every card a customer sees.
        YdCard.bordered(
          padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
          radius: DeliveryRadius.md,
          child: Row(
            children: <Widget>[
              StoreAvatar(name: store.name, logoUrl: store.logoUrl, size: 44),
              const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      t.logo,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.ink,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.logoHint,
                      style: const TextStyle(
                        fontSize: 11,
                        color: DeliveryColors.faint,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              _ChipButton(
                label: hasLogo ? t.merchbChangeLogo : t.upload,
                onPressed: _saving ? null : () => _pickAndUpload(store, 'logo'),
              ),
              if (hasLogo)
                IconButton(
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  tooltip: t.remove,
                  onPressed: _saving
                      ? null
                      : () => _run(
                            () => widget.api
                                .removeImage(storeId: store.id, slot: 'logo')
                                .then((_) {}),
                            t.labelRemoved(t.logo),
                          ),
                  icon: const Icon(Icons.close, color: DeliveryColors.faint),
                ),
            ],
          ),
        ),
        const SizedBox(height: DeliverySpacing.sm),
        Text(
          t.generatedTileBlurb,
          style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.35),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- profile

  Widget _profileCard(DeliveryStrings t) {
    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CardTitle(t.profile, subtitle: t.howYourShopAppears),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _CardField(
            label: t.shopName,
            child: TextFormField(
              controller: _name,
              style: _cardValueStyle,
              cursorColor: DeliveryColors.brand,
              decoration: _cardBoxDecoration(),
              validator: (String? v) =>
                  (v == null || v.trim().isEmpty) ? t.requiredField : null,
            ),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _CardField(
            label: t.tagline,
            child: TextFormField(
              controller: _tagline,
              style: _cardValueStyle,
              cursorColor: DeliveryColors.brand,
              decoration: _cardBoxDecoration(hint: t.taglineHint),
            ),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _CardField(
            label: t.categoryLabel,
            child: DropdownButtonFormField<StoreVertical>(
              initialValue: _vertical,
              isExpanded: true,
              style: _cardValueStyle,
              icon: const Icon(Icons.expand_more, size: 16, color: DeliveryColors.ink),
              decoration: _cardBoxDecoration(),
              items: StoreVertical.values
                  .map((StoreVertical v) => DropdownMenuItem<StoreVertical>(
                        value: v,
                        child: Text(v.labelIn(t), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (StoreVertical? v) => setState(() => _vertical = v ?? _vertical),
            ),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _CardField(
            label: t.tags,
            child: TextFormField(
              controller: _tags,
              style: _cardValueStyle,
              cursorColor: DeliveryColors.brand,
              decoration: _cardBoxDecoration(hint: t.tagsHint),
            ),
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _CardField(
            label: t.descriptionLabel,
            child: TextFormField(
              controller: _description,
              maxLines: 3,
              style: _cardValueStyle,
              cursorColor: DeliveryColors.brand,
              decoration: _cardBoxDecoration(),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- address

  /// The pin the merchant just placed, or removed, saved through the store's own endpoints.
  ///
  /// Goes through [_run] like every other write on this screen, so a refusal is reported in the
  /// same words and the form reloads from the server rather than from what we hoped happened.
  Future<void> _editPin(DeliveryStrings t, Store store) async {
    final StorePinChoice? choice = await showStorePinPicker(
      context,
      latitude: store.latitude,
      longitude: store.longitude,
      geocoding: widget.geocoding,
      // Whatever is in the address box now, not what was loaded — a merchant who has just typed
      // their street should find it offered, not the old one.
      addressHint: _address.text.trim().isEmpty ? null : _address.text.trim(),
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case StorePinPlaced(point: final LatLng point):
        await _run(
          () => widget.api
              .setPin(store.id, lat: point.latitude, lng: point.longitude)
              .then((_) {}),
          t.merchPinSaved,
        );
      case StorePinRemoved():
        await _run(
          () => widget.api.clearPin(store.id).then((_) {}),
          t.merchPinCleared,
        );
    }
  }

  Widget _addressSection(DeliveryStrings t, Store store) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionLabel(t.merchbShopAddress),
        const SizedBox(height: DeliverySpacing.sm),
        Container(
          padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
          decoration: BoxDecoration(
            color: DeliveryColors.white,
            border: Border.all(color: DeliveryColors.border),
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.place_outlined, size: 18, color: DeliveryColors.brand),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _address,
                  style: const TextStyle(fontSize: 13, color: DeliveryColors.ink, height: 1.35),
                  cursorColor: DeliveryColors.brand,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: t.addressLabel,
                    hintStyle: const TextStyle(fontSize: 13, color: DeliveryColors.faint),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: DeliverySpacing.sm),
        // The frame's 100px map slot, now a real one. Same size, same radius, same place in the
        // column — what changed is that it draws where the shop actually is and is the way to
        // move it.
        StorePinPreview(
          latitude: store.latitude,
          longitude: store.longitude,
          onTap: _saving ? null : () => _editPin(t, store),
        ),
        const SizedBox(height: DeliverySpacing.xs + 2),
        Text(
          t.merchPinWhyItMatters,
          style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.35),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- operating

  Widget _operatingCard(DeliveryStrings t) {
    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CardTitle(t.merchbOperatingDetails, subtitle: t.whatCustomersAreCharged),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _CardField(
            label: t.openingHours,
            child: Semantics(
              button: true,
              label: t.merchbEditHours,
              child: Material(
                color: DeliveryColors.background,
                borderRadius: BorderRadius.circular(DeliveryRadius.sm + 2),
                child: InkWell(
                  onTap: () => setState(() => _hoursOpen = !_hoursOpen),
                  borderRadius: BorderRadius.circular(DeliveryRadius.sm + 2),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(
                      DeliverySpacing.md - DeliverySpacing.xs,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            _hoursSummary(t),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: DeliveryColors.ink,
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: DeliverySpacing.sm),
                        Icon(
                          _hoursOpen ? Icons.expand_less : Icons.schedule,
                          size: 16,
                          color: DeliveryColors.faint,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_hoursOpen) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            for (int i = 0; i < _hours.length; i++) _hoursRow(t, i),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setState(() => _hours = <OpeningWindow>[
                      ..._hours,
                      const OpeningWindow(dayOfWeek: 1, opensAt: '14:00', closesAt: '19:00'),
                    ]),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(t.addASecondWindow),
                style: TextButton.styleFrom(foregroundColor: DeliveryColors.brand),
              ),
            ),
            Text(
              t.secondWindowBlurb,
              style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.35),
            ),
          ],
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _CardField(
                  label: t.minimumOrder,
                  child: _number(t, _minOrder, decimals: true),
                ),
              ),
              const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
              Expanded(
                child: _CardField(
                  label: t.deliveryFeeLabelMerchant,
                  child: _number(t, _fee, decimals: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _CardField(label: t.etaFromMin, child: _number(t, _etaMin)),
              ),
              const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
              Expanded(
                child: _CardField(label: t.etaToMin, child: _number(t, _etaMax)),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            t.serverAppliesTerms,
            style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.35),
          ),
        ],
      ),
    );
  }

  /// The one-line answer to "when are you open", or the honest admission that it is complicated.
  String _hoursSummary(DeliveryStrings t) {
    if (_hours.isEmpty) {
      return t.merchbHoursNone;
    }
    final OpeningWindow first = _hours.first;
    final bool everyDayOnce = _hours.length == 7 &&
        _hours.map((OpeningWindow w) => w.dayOfWeek).toSet().length == 7;
    final bool sameWindow = _hours.every((OpeningWindow w) =>
        w.opensAtLabel == first.opensAtLabel && w.closesAtLabel == first.closesAtLabel);

    return everyDayOnce && sameWindow
        ? t.merchbHoursDaily(first.opensAtLabel, first.closesAtLabel)
        : t.merchbHoursCustom;
  }

  Widget _hoursRow(DeliveryStrings t, int index) {
    final OpeningWindow window = _hours[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 3,
            child: _CardField(
              label: t.merchbDay,
              child: DropdownButtonFormField<int>(
                initialValue: window.dayOfWeek,
                isExpanded: true,
                style: _cardValueStyle,
                icon: const Icon(Icons.expand_more, size: 16, color: DeliveryColors.ink),
                decoration: _cardBoxDecoration(),
                items: <DropdownMenuItem<int>>[
                  for (int d = 1; d <= 7; d++)
                    DropdownMenuItem<int>(
                      value: d,
                      child: Text(
                        _dayName(t, d),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (int? d) => setState(() => _hours[index] = OpeningWindow(
                      dayOfWeek: d ?? window.dayOfWeek,
                      opensAt: window.opensAt,
                      closesAt: window.closesAt,
                    )),
              ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            flex: 2,
            child: _CardField(
              label: t.opens,
              child: _timeField(
                t,
                window.opensAtLabel,
                (String v) => setState(() => _hours[index] = window.copyWith(opensAt: v)),
              ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            flex: 2,
            child: _CardField(
              label: t.closes,
              child: _timeField(
                t,
                window.closesAtLabel,
                (String v) => setState(() => _hours[index] = window.copyWith(closesAt: v)),
              ),
            ),
          ),
          IconButton(
            tooltip: t.removeThisWindow,
            onPressed: () => setState(() => _hours.removeAt(index)),
            icon: const Icon(Icons.close_rounded, size: 18, color: DeliveryColors.faint),
          ),
        ],
      ),
    );
  }

  /// Monday is 1, matching the ISO day the wire uses.
  static String _dayName(DeliveryStrings t, int day) => switch (day) {
        1 => t.merchbDayMonday,
        2 => t.merchbDayTuesday,
        3 => t.merchbDayWednesday,
        4 => t.merchbDayThursday,
        5 => t.merchbDayFriday,
        6 => t.merchbDaySaturday,
        _ => t.merchbDaySunday,
      };

  /// A plain HH:mm field rather than a time picker: a merchant setting seven days of hours types
  /// far faster than they tap through fourteen dialogs.
  Widget _timeField(DeliveryStrings t, String value, ValueChanged<String> onChanged) {
    return TextFormField(
      initialValue: value,
      style: _cardValueStyle,
      cursorColor: DeliveryColors.brand,
      decoration: _cardBoxDecoration(hint: t.merchbTimeHint),
      validator: (String? v) =>
          RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v ?? '') ? null : t.merchbTimeHint,
      onChanged: onChanged,
    );
  }

  Widget _number(DeliveryStrings t, TextEditingController controller, {bool decimals = false}) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimals),
      style: _cardValueStyle,
      cursorColor: DeliveryColors.brand,
      decoration: _cardBoxDecoration(),
      validator: (String? v) {
        final num? parsed = decimals ? double.tryParse(v ?? '') : int.tryParse(v ?? '');
        if (parsed == null) return t.aNumber;
        if (parsed < 0) return t.cannotBeNegative;
        return null;
      },
    );
  }

  // ------------------------------------------------------------------- save

  Widget _saveButton(DeliveryStrings t) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _saving ? null : _saveProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: DeliveryColors.brand,
          foregroundColor: DeliveryColors.white,
          disabledBackgroundColor: DeliveryColors.brandLine,
          disabledForegroundColor: DeliveryColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.md)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        child: _saving
            ? const SizedBox.square(
                dimension: 19,
                child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.white),
              )
            : Text(t.merchbSaveShopSettings),
      ),
    );
  }

  // ----------------------------------------------------------------- upload

  /// Opens the picker and runs the three-step upload.
  ///
  /// Uses `file_selector` rather than `image_picker`, matching the product form — it is the one
  /// that works cleanly on Flutter Web, which is where this portal actually runs.
  Future<void> _pickAndUpload(Store store, String slot) async {
    // Mirrors the service's allow-list. It re-checks and returns 422 regardless, so this only
    // saves the merchant a pointless round trip.
    final XTypeGroup images = XTypeGroup(
      label: DeliveryStrings.of(context).images,
      extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: <String>['image/jpeg', 'image/png', 'image/webp'],
    );

    // Guarded, for the same reason as the product form: an unguarded openFile that throws leaves
    // this method as an unhandled async error and the shop sees nothing happen at all, which reads
    // as a dead button rather than as a failure worth reporting.
    final XFile? picked;
    try {
      picked = await openFile(acceptedTypeGroups: <XTypeGroup>[images]);
    } catch (e, stack) {
      debugPrint('SHOP PICTURE PICKER FAILED: $e');
      debugPrintStack(stackTrace: stack, label: 'shop-picture-picker');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(DeliveryStrings.of(context).couldNotOpenPicker(e.toString()))));
      return;
    }
    if (picked == null) {
      // Cancelled, which is not a failure.
      return;
    }
    // Rebound non-null: a local assigned inside a try is not promoted by the null check above.
    final XFile file = picked;
    final Uint8List bytes = await file.readAsBytes();
    // The file dialog and the read are both async gaps; this State can be gone by now.
    if (!mounted) return;

    await _run(
      () => widget.api
          .uploadImage(
            storeId: store.id,
            slot: slot,
            bytes: bytes,
            contentType: _contentTypeFor(file),
          )
          .then((_) {}),
      DeliveryStrings.of(context).pictureUpdated,
    );
  }

  /// `XFile.mimeType` is null on several platforms, so fall back to the extension.
  static String _contentTypeFor(XFile file) {
    final String? declared = file.mimeType;
    if (declared != null && declared.startsWith('image/')) {
      return declared;
    }
    final String name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  static DeliveryStoreState _stateOf(StoreAvailability availability) => switch (availability) {
        StoreAvailability.open => DeliveryStoreState.open,
        StoreAvailability.busy => DeliveryStoreState.busy,
        StoreAvailability.closingSoon => DeliveryStoreState.closingSoon,
        StoreAvailability.closed => DeliveryStoreState.closed,
      };
}

/// The frame's in-card input value: Regular 13 in ink.
const TextStyle _cardValueStyle = TextStyle(
  fontSize: 13,
  color: DeliveryColors.ink,
  height: 1.35,
);

/// The frame's in-card input box: the background token as a fill, no border, radius 10, 12px
/// padding. Distinct on purpose from the add-product frame's white bordered box — the design uses
/// the quieter fill wherever a field sits *inside* a card that already has an outline.
InputDecoration _cardBoxDecoration({String? hint}) {
  OutlineInputBorder border([Color? color, double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(DeliveryRadius.sm + 2),
        borderSide: color == null ? BorderSide.none : BorderSide(color: color, width: width),
      );

  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: DeliveryColors.background,
    counterText: '',
    hintText: hint,
    contentPadding:
        const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
    border: border(),
    enabledBorder: border(),
    focusedBorder: border(DeliveryColors.brand, 1.5),
    errorBorder: border(DeliveryAccent.critical.color),
    focusedErrorBorder: border(DeliveryAccent.critical.color, 1.5),
    hintStyle: const TextStyle(fontSize: 13, color: DeliveryColors.faint),
    errorStyle: TextStyle(fontSize: 11, color: DeliveryAccent.critical.color),
  );
}

/// The SemiBold 14 ink label that heads a block on the page background.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: DeliveryColors.ink,
          height: 1.25,
        ),
      );
}

/// The Bold 14 title inside a card, with the muted line the existing screen used to explain it.
class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title, {this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.25,
          ),
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: const TextStyle(fontSize: 12, color: DeliveryColors.faint, height: 1.3),
          ),
        ],
      ],
    );
  }
}

/// A Regular 12 muted label six pixels above its field — the frame's in-card `input-field` group.
class _CardField extends StatelessWidget {
  const _CardField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: DeliveryColors.faint, height: 1.25),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// The frame's paired action button: radius 10, 12px padding, filled brand or the quiet
/// background-token fill with muted text.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  /// Already localised by the caller.
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final Color background = primary
        ? (enabled ? DeliveryColors.brand : DeliveryColors.brandLine)
        : DeliveryColors.background;
    final Color foreground = primary
        ? DeliveryColors.white
        : (enabled ? DeliveryColors.muted : DeliveryColors.faint);
    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.sm + 2);

    return Semantics(
      button: true,
      child: Material(
        color: background,
        borderRadius: corners,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: DeliverySpacing.md - DeliverySpacing.xs,
              vertical: 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The design's brand-tinted chip used as a button — the `Edit` badge, borrowed for "Change Logo".
class _ChipButton extends StatelessWidget {
  const _ChipButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.md);
    return Semantics(
      button: true,
      child: Material(
        color: DeliveryColors.brandSoft,
        borderRadius: corners,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: DeliverySpacing.md - DeliverySpacing.xs,
              vertical: 6,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: onPressed == null ? DeliveryColors.brandLine : DeliveryColors.brand,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

