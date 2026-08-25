import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// "My Shop" — everything a merchant needs to get their store listed and keep it accurate.
///
/// This screen exists because the storefront made a store mandatory but left no way to manage one.
/// A merchant's first product auto-provisions a DRAFT store called "My Store" with no opening
/// hours, and `publish` refuses a store without hours — so without this page a real merchant is
/// stuck in DRAFT with no way out.
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key, required this.api});

  final StoreApi api;

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
        SnackBar(content: Text(_message(e, DeliveryStrings.of(context))), backgroundColor: DeliveryColors.brandDark),
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    if (_error != null) {
      return _centred(Icons.cloud_off_rounded, DeliveryStrings.of(context).couldNotLoadYourShop, '$_error',
          action: FilledButton(onPressed: _load, child: Text(DeliveryStrings.of(context).tryAgain)));
    }
    if (_store == null) {
      return _centred(Icons.storefront_outlined, DeliveryStrings.of(context).noShopYet,
          DeliveryStrings.of(context).shopCreatedAutomatically);
    }

    final Store store = _store!;
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DeliverySpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _header(store),
              const SizedBox(height: DeliverySpacing.lg),
              _card(DeliveryStrings.of(context).profile, DeliveryStrings.of(context).howYourShopAppears, <Widget>[
                _text(_name, DeliveryStrings.of(context).shopName, required: true),
                _text(_tagline, DeliveryStrings.of(context).tagline, hint: DeliveryStrings.of(context).taglineHint),
                DropdownButtonFormField<StoreVertical>(
                  initialValue: _vertical,
                  decoration: InputDecoration(labelText: DeliveryStrings.of(context).categoryLabel),
                  items: StoreVertical.values
                      .map((StoreVertical v) => DropdownMenuItem<StoreVertical>(
                          value: v, child: Text(v.label)))
                      .toList(),
                  onChanged: (StoreVertical? v) =>
                      setState(() => _vertical = v ?? _vertical),
                ),
                const SizedBox(height: DeliverySpacing.md),
                _text(_tags, DeliveryStrings.of(context).tags, hint: DeliveryStrings.of(context).tagsHint),
                _text(_description, DeliveryStrings.of(context).descriptionLabel, maxLines: 3),
                _text(_address, DeliveryStrings.of(context).addressLabel),
              ]),
              _card(DeliveryStrings.of(context).pictures,
                  DeliveryStrings.of(context).logoRecognisedBy, <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _imageSlot(
                      store: store,
                      slot: 'logo',
                      label: DeliveryStrings.of(context).logo,
                      hint: DeliveryStrings.of(context).logoHint,
                      url: store.logoUrl,
                      preview: StoreAvatar(
                          name: store.name, logoUrl: store.logoUrl, size: 88),
                    ),
                    const SizedBox(width: DeliverySpacing.lg),
                    _imageSlot(
                      store: store,
                      slot: 'cover',
                      label: DeliveryStrings.of(context).cover,
                      hint: DeliveryStrings.of(context).coverHint,
                      url: store.coverUrl,
                      preview: SizedBox(
                        width: 176,
                        height: 88,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(DeliveryRadius.md),
                          child: store.coverUrl == null || store.coverUrl!.isEmpty
                              ? StoreMonogram(name: store.name, radius: 0)
                              : Image.network(store.coverUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      StoreMonogram(name: store.name, radius: 0)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DeliverySpacing.sm),
                Text(
                    DeliveryStrings.of(context).generatedTileBlurb,
                  style: TextStyle(fontSize: 12.5, color: DeliveryColors.muted),
                ),
              ]),
              _card(DeliveryStrings.of(context).navDelivery, DeliveryStrings.of(context).whatCustomersAreCharged, <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child: _number(_fee, DeliveryStrings.of(context).deliveryFeeLabelMerchant, decimals: true)),
                    const SizedBox(width: DeliverySpacing.md),
                    Expanded(child: _number(_minOrder, DeliveryStrings.of(context).minimumOrder, decimals: true)),
                  ],
                ),
                const SizedBox(height: DeliverySpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(child: _number(_etaMin, DeliveryStrings.of(context).etaFromMin)),
                    const SizedBox(width: DeliverySpacing.md),
                    Expanded(child: _number(_etaMax, DeliveryStrings.of(context).etaToMin)),
                  ],
                ),
                const SizedBox(height: DeliverySpacing.sm),
                Text(
            DeliveryStrings.of(context).serverAppliesTerms,
                  style: TextStyle(fontSize: 12.5, color: DeliveryColors.muted),
                ),
              ]),
              _card(DeliveryStrings.of(context).openingHours,
                  DeliveryStrings.of(context).openingHoursBlurb, <Widget>[
                for (int i = 0; i < _hours.length; i++) _hoursRow(i),
                const SizedBox(height: DeliverySpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _hours = <OpeningWindow>[
                          ..._hours,
                          OpeningWindow(dayOfWeek: 1, opensAt: '14:00', closesAt: '19:00'),
                        ]),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(DeliveryStrings.of(context).addASecondWindow),
                    style: TextButton.styleFrom(foregroundColor: DeliveryColors.brand),
                  ),
                ),
                Text(
              DeliveryStrings.of(context).secondWindowBlurb,
                  style: TextStyle(fontSize: 12.5, color: DeliveryColors.muted),
                ),
              ]),
              const SizedBox(height: DeliverySpacing.md),
              FilledButton.icon(
                onPressed: _saving ? null : _saveProfile,
                style: FilledButton.styleFrom(backgroundColor: DeliveryColors.brand),
                icon: _saving
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text(DeliveryStrings.of(context).saveChanges),
              ),
              const SizedBox(height: DeliverySpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(Store store) {
    final bool listed = store.availability != StoreAvailability.closed ||
        store.closesAt != null;
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.md),
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        // Lifted rather than ringed, matching every other card in the platform.
        boxShadow: DeliveryShadows.card,
      ),
      child: Row(
        children: <Widget>[
          StoreAvatar(name: store.name, logoUrl: store.logoUrl, size: 56),
          const SizedBox(width: DeliverySpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(store.name,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: DeliverySpacing.xs),
                Row(
                  children: <Widget>[
                    StoreStatePill(state: _stateOf(store.availability)),
                    const SizedBox(width: DeliverySpacing.sm),
                    Text(
                      listed ? DeliveryStrings.of(context).listedOnStorefront : DeliveryStrings.of(context).notListedYet,
                      style: const TextStyle(fontSize: 12.5, color: DeliveryColors.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _publishControls(store),
        ],
      ),
    );
  }

  Widget _publishControls(Store store) {
    return Wrap(
      spacing: DeliverySpacing.sm,
      children: <Widget>[
        // Busy is a 30-minute flag that clears itself, so it is safe to offer as one tap.
        OutlinedButton.icon(
          onPressed: _saving
              ? null
              : () => _run(
                  () => widget.api.setBusy(store.id, minutes: 30).then((_) {}),
                  DeliveryStrings.of(context).markedBusy30),
          icon: const Icon(Icons.timelapse_rounded, size: 17),
          label: Text(DeliveryStrings.of(context).busy30m),
        ),
        OutlinedButton.icon(
          onPressed: _saving
              ? null
              : () => _run(() => widget.api.clearBusy(store.id).then((_) {}),
                  DeliveryStrings.of(context).noLongerBusy),
          icon: const Icon(Icons.check_circle_outline_rounded, size: 17),
          label: Text(DeliveryStrings.of(context).notBusy),
        ),
        FilledButton.icon(
          onPressed: _saving
              ? null
              : () => _run(() => widget.api.publish(store.id).then((_) {}),
                  DeliveryStrings.of(context).yourShopIsLive),
          style: FilledButton.styleFrom(backgroundColor: DeliveryColors.brand),
          icon: const Icon(Icons.rocket_launch_rounded, size: 17),
          label: Text(DeliveryStrings.of(context).publish),
        ),
      ],
    );
  }

  Widget _hoursRow(int index) {
    final OpeningWindow window = _hours[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<int>(
              initialValue: window.dayOfWeek,
              decoration: const InputDecoration(isDense: true, labelText: 'Day'),
              items: <DropdownMenuItem<int>>[
                for (int d = 1; d <= 7; d++)
                  DropdownMenuItem<int>(
                      value: d, child: Text(OpeningWindow.dayNames[d - 1])),
              ],
              onChanged: (int? d) => setState(() => _hours[index] = OpeningWindow(
                  dayOfWeek: d ?? window.dayOfWeek,
                  opensAt: window.opensAt,
                  closesAt: window.closesAt)),
            ),
          ),
          const SizedBox(width: DeliverySpacing.md),
          Expanded(child: _timeField(window.opensAtLabel, DeliveryStrings.of(context).opens,
              (String v) => setState(() => _hours[index] = window.copyWith(opensAt: v)))),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(child: _timeField(window.closesAtLabel, DeliveryStrings.of(context).closes,
              (String v) => setState(() => _hours[index] = window.copyWith(closesAt: v)))),
          IconButton(
            tooltip: DeliveryStrings.of(context).removeThisWindow,
            onPressed: () => setState(() => _hours.removeAt(index)),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  /// A plain HH:mm field rather than a time picker: a merchant setting seven days of hours types
  /// far faster than they tap through fourteen dialogs.
  Widget _timeField(String value, String label, ValueChanged<String> onChanged) {
    return TextFormField(
      initialValue: value,
      decoration: InputDecoration(labelText: label, isDense: true, hintText: 'HH:mm'),
      validator: (String? v) =>
          RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v ?? '') ? null : 'HH:mm',
      onChanged: onChanged,
    );
  }

  /// One picture slot: what it looks like now, and the controls to change it.
  Widget _imageSlot({
    required Store store,
    required String slot,
    required String label,
    required String hint,
    required String? url,
    required Widget preview,
  }) {
    final bool hasImage = url != null && url.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        const SizedBox(height: DeliverySpacing.xs),
        preview,
        const SizedBox(height: DeliverySpacing.sm),
        SizedBox(
          width: 176,
          child: Text(hint,
              style: const TextStyle(fontSize: 11.5, color: DeliveryColors.muted)),
        ),
        const SizedBox(height: DeliverySpacing.xs),
        Row(
          children: <Widget>[
            TextButton.icon(
              onPressed: _saving ? null : () => _pickAndUpload(store, slot),
              icon: const Icon(Icons.upload_rounded, size: 17),
              label: Text(hasImage ? DeliveryStrings.of(context).replace : DeliveryStrings.of(context).upload),
              style: TextButton.styleFrom(foregroundColor: DeliveryColors.brand),
            ),
            if (hasImage)
              TextButton(
                onPressed: _saving
                    ? null
                    : () => _run(
                        () => widget.api
                            .removeImage(storeId: store.id, slot: slot)
                            .then((_) {}),
                        DeliveryStrings.of(context).labelRemoved(label)),
                style: TextButton.styleFrom(foregroundColor: DeliveryColors.muted),
                child: Text(DeliveryStrings.of(context).remove),
              ),
          ],
        ),
      ],
    );
  }

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

    final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[images]);
    if (file == null) {
      return;
    }
    final Uint8List bytes = await file.readAsBytes();
    // The file dialog and the read are both async gaps; this State can be gone by now.
    if (!mounted) return;

    await _run(
      () => widget.api
          .uploadImage(
              storeId: store.id,
              slot: slot,
              bytes: bytes,
              contentType: _contentTypeFor(file))
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

  Widget _card(String title, String subtitle, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(top: DeliverySpacing.md),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(DeliverySpacing.lg),
        decoration: BoxDecoration(
          color: DeliveryColors.white,
          borderRadius: BorderRadius.circular(DeliveryRadius.lg),
          // Lifted rather than ringed, matching every other card in the platform.
          boxShadow: DeliveryShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(subtitle,
                style: const TextStyle(fontSize: 12.5, color: DeliveryColors.muted)),
            const SizedBox(height: DeliverySpacing.md),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _text(TextEditingController controller, String label,
      {String? hint, int maxLines = 1, bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.md),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: required
            ? (String? v) => (v == null || v.trim().isEmpty) ? DeliveryStrings.of(context).requiredField : null
            : null,
      ),
    );
  }

  Widget _number(TextEditingController controller, String label, {bool decimals = false}) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimals),
      decoration: InputDecoration(labelText: label),
      validator: (String? v) {
        final num? parsed = decimals ? double.tryParse(v ?? '') : int.tryParse(v ?? '');
        if (parsed == null) return DeliveryStrings.of(context).aNumber;
        if (parsed < 0) return DeliveryStrings.of(context).cannotBeNegative;
        return null;
      },
    );
  }

  Widget _centred(IconData icon, String title, String body, {Widget? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DeliverySpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(DeliverySpacing.md),
              decoration:
                  const BoxDecoration(color: DeliveryColors.brandSoft, shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: DeliveryColors.brand),
            ),
            const SizedBox(height: DeliverySpacing.md),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: DeliverySpacing.xs),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: DeliveryColors.muted)),
            if (action != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.md),
              action,
            ],
          ],
        ),
      ),
    );
  }

  static DeliveryStoreState _stateOf(StoreAvailability availability) => switch (availability) {
        StoreAvailability.open => DeliveryStoreState.open,
        StoreAvailability.busy => DeliveryStoreState.busy,
        StoreAvailability.closingSoon => DeliveryStoreState.closingSoon,
        StoreAvailability.closed => DeliveryStoreState.closed,
      };
}
