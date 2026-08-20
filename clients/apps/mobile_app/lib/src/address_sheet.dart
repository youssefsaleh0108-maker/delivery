import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'delivery_address.dart';

/// Picks or enters the delivery address.
///
/// A bottom sheet rather than a route: choosing an address is a decision made *while* looking at
/// the storefront, and pushing a full screen loses that context.
Future<void> showAddressSheet(BuildContext context, DeliveryAddressStore store,
    {DeliveryZoneApi? zoneApi}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DeliveryColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.lg)),
    ),
    builder: (BuildContext context) => _AddressSheet(store: store, zoneApi: zoneApi),
  );
}

class _AddressSheet extends StatefulWidget {
  const _AddressSheet({required this.store, this.zoneApi});

  final DeliveryAddressStore store;

  /// Optional so the sheet still works with no areas configured, and so a test can pump it
  /// without a server.
  final DeliveryZoneApi? zoneApi;

  @override
  State<_AddressSheet> createState() => _AddressSheetState();
}

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

  @override
  void initState() {
    super.initState();
    // In initState rather than a field initialiser: `widget` is not available while fields are
    // being initialised.
    _zoneId = widget.store.selected?.zoneId;
    _loadZones();
  }

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
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lifts the sheet clear of the keyboard, which otherwise covers the field being typed into.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(DeliverySpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: DeliveryColors.border,
                      borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: DeliverySpacing.md),
                Text(DeliveryStrings.of(context).deliverTo,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: DeliverySpacing.xs),
                Text(DeliveryStrings.of(context).whereShouldWeBring,
                    style: const TextStyle(fontSize: 13, color: DeliveryColors.muted)),
                const SizedBox(height: DeliverySpacing.md),

                if (widget.store.recents.isNotEmpty) ...<Widget>[
                  Text(DeliveryStrings.of(context).recent,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: DeliverySpacing.xs),
                  for (final DeliveryAddress address in widget.store.recents)
                    _recentTile(address),
                  const SizedBox(height: DeliverySpacing.md),
                  const Divider(height: 1, color: DeliveryColors.border),
                  const SizedBox(height: DeliverySpacing.md),
                ],

                TextFormField(
                  controller: _line,
                  autofocus: widget.store.recents.isEmpty,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: DeliveryStrings.of(context).address,
                    hintText: DeliveryStrings.of(context).addressHint,
                    prefixIcon: const Icon(Icons.place_outlined),
                  ),
                  validator: (String? v) =>
                      (v == null || v.trim().length < 5) ? DeliveryStrings.of(context).addressTooShort : null,
                ),
                // The area, directly under the street. It is part of the address rather than a
                // setting — and it is what decides whether a shop will come at all, and for how
                // much.
                if (_zones.isNotEmpty) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.md),
                  DropdownButtonFormField<String>(
                    initialValue: _zoneId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: DeliveryStrings.of(context).area,
                      prefixIcon: const Icon(Icons.map_outlined),
                    ),
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
                    // Required once areas exist. An address with no area is priced at the flat fee,
                    // which is right for one saved before areas and wrong for one typed now.
                    validator: (String? v) =>
                        v == null ? DeliveryStrings.of(context).pickYourArea : null,
                  ),
                ],
                const SizedBox(height: DeliverySpacing.md),
                TextFormField(
                  controller: _label,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: DeliveryStrings.of(context).labelOptional,
                    hintText: DeliveryStrings.of(context).labelHint,
                    prefixIcon: const Icon(Icons.bookmark_border_rounded),
                  ),
                ),
                const SizedBox(height: DeliverySpacing.md),
                TextFormField(
                  controller: _notes,
                  decoration: InputDecoration(
                    labelText: DeliveryStrings.of(context).riderNotesOptional,
                    hintText: DeliveryStrings.of(context).riderNotesHint,
                    prefixIcon: const Icon(Icons.sticky_note_2_outlined),
                  ),
                ),
                const SizedBox(height: DeliverySpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: DeliveryColors.brand,
                      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.md),
                    ),
                    child: Text(DeliveryStrings.of(context).deliverHere),
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

  Widget _recentTile(DeliveryAddress address) {
    final bool isSelected = widget.store.selected == address;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
        color: isSelected ? DeliveryColors.brand : DeliveryColors.muted,
        size: 20,
      ),
      title: Text(address.label ?? address.line,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: address.label == null
          ? null
          : Text(address.line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: DeliveryColors.muted)),
      trailing: IconButton(
        tooltip: DeliveryStrings.of(context).forgetThisAddress,
        icon: const Icon(Icons.close_rounded, size: 18),
        onPressed: () async {
          await widget.store.forget(address);
          if (mounted) setState(() {});
        },
      ),
      onTap: () async {
        await widget.store.select(address);
        if (mounted) Navigator.of(context).pop();
      },
    );
  }
}
