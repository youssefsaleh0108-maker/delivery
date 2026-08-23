import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// The platform's list of delivery areas.
///
/// Owned here rather than by merchants, because two shops calling the same neighbourhood by
/// different names would make "do you deliver to me" unanswerable — the customer picks one name
/// from one list, and every shop prices against that same list.
///
/// Until an area exists, every shop charges one delivery fee and delivers anywhere. Adding the
/// first area does not change that on its own: a shop only starts pricing by area once it sets its
/// own coverage.
class ZonesScreen extends StatefulWidget {
  const ZonesScreen({super.key, required this.api});

  final DeliveryZoneApi api;

  @override
  State<ZonesScreen> createState() => _ZonesScreenState();
}

class _ZonesScreenState extends State<ZonesScreen> {
  late Future<List<DeliveryZone>> _zones = widget.api.all();
  bool _busy = false;

  void _reload() {
    setState(() {
      _zones = widget.api.all();
    });
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_messageFor(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _messageFor(Object error) {
    if (error is DioException) {
      final dynamic body = error.response?.data;
      if (body is Map && body['detail'] is String) return body['detail'] as String;
    }
    return 'That did not work: $error';
  }

  Future<void> _edit([DeliveryZone? existing]) async {
    final _Draft? draft = await showDialog<_Draft>(
      context: context,
      builder: (BuildContext context) => _ZoneDialog(existing: existing),
    );
    if (draft == null || !mounted) return;

    await _run(
      () => (existing == null
              ? widget.api.create(
                  name: draft.name, region: draft.region, sortOrder: draft.sortOrder)
              : widget.api.rename(existing.id,
                  name: draft.name, region: draft.region, sortOrder: draft.sortOrder))
          .then((_) {}),
      existing == null ? 'Area added' : 'Area updated',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _edit(),
        backgroundColor: DeliveryColors.brand,
        foregroundColor: DeliveryColors.white,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('New area'),
      ),
      body: FutureBuilder<List<DeliveryZone>>(
        future: _zones,
        builder: (BuildContext context, AsyncSnapshot<List<DeliveryZone>> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load areas: ${snapshot.error}'));
          }

          final List<DeliveryZone> zones = snapshot.data!;
          final int live = zones.where((DeliveryZone z) => z.active).length;
          final int retired = zones.length - live;

          return ListView(
            padding: const EdgeInsets.all(DeliverySpacing.lg),
            children: <Widget>[
              Text('Delivery areas', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: DeliverySpacing.xs),
              Text(
                'The list customers pick from when they enter an address. Shops price their '
                'delivery per area.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: DeliverySpacing.md),

              StatRow(tiles: <Widget>[
                StatTile(
                  value: '$live',
                  label: 'In the picker',
                  icon: Icons.map_outlined,
                  accent: live == 0 ? DeliveryAccent.caution : DeliveryAccent.positive,
                  footnote: live == 0 ? 'flat fees everywhere' : null,
                ),
                StatTile(
                  value: '$retired',
                  label: 'Retired',
                  icon: Icons.visibility_off_outlined,
                  accent: DeliveryAccent.neutral,
                ),
              ]),
              const SizedBox(height: DeliverySpacing.lg),

              if (zones.isEmpty)
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('No areas yet',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: DeliverySpacing.xs),
                      Text(
                        'Until you add areas, every shop charges one delivery fee and delivers '
                        'anywhere. Adding areas lets a shop say where it will go and what it '
                        'charges to get there.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                )
              else ...<Widget>[
                const SectionLabel('Areas'),
                const SizedBox(height: DeliverySpacing.sm),
                for (final DeliveryZone zone in zones) _card(zone),
                const SizedBox(height: DeliverySpacing.md),
                const SoftNote(
                  // The reason retiring exists at all, said where somebody is about to press it.
                  text: 'Retired areas leave the picker but keep working for addresses that '
                      'already name them, and shops keep their prices for them.',
                  accent: DeliveryAccent.info,
                ),
              ],
              const SizedBox(height: DeliverySpacing.xl * 2),
            ],
          );
        },
      ),
    );
  }

  Widget _card(DeliveryZone zone) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: SoftCard(
        accent: zone.active ? null : DeliveryAccent.neutral.color,
        child: Row(
          children: <Widget>[
            Icon(zone.active ? Icons.place_outlined : Icons.visibility_off_outlined,
                size: 20,
                color: zone.active ? DeliveryColors.brand : DeliveryColors.muted),
            const SizedBox(width: DeliverySpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(zone.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  Text(
                    <String>[
                      if (zone.region != null && zone.region!.isNotEmpty) zone.region!,
                      'order ${zone.sortOrder}',
                    ].join('  ·  '),
                    style: const TextStyle(fontSize: 12.5, color: DeliveryColors.muted),
                  ),
                ],
              ),
            ),
            if (!zone.active) ...<Widget>[
              const StatePill(label: 'Retired', accent: DeliveryAccent.neutral),
              const SizedBox(width: DeliverySpacing.xs),
            ],
            TextButton(
              onPressed: _busy ? null : () => _edit(zone),
              child: const Text('Edit'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => (zone.active
                              ? widget.api.retire(zone.id)
                              : widget.api.reinstate(zone.id))
                          .then((_) {}),
                      zone.active ? '${zone.name} retired' : '${zone.name} is back'),
              child: Text(zone.active ? 'Retire' : 'Reinstate'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Draft {
  const _Draft(this.name, this.region, this.sortOrder);

  final String name;
  final String? region;
  final int sortOrder;
}

class _ZoneDialog extends StatefulWidget {
  const _ZoneDialog({this.existing});

  final DeliveryZone? existing;

  @override
  State<_ZoneDialog> createState() => _ZoneDialogState();
}

class _ZoneDialogState extends State<_ZoneDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _region =
      TextEditingController(text: widget.existing?.region ?? '');
  late final TextEditingController _sort =
      TextEditingController(text: '${widget.existing?.sortOrder ?? 100}');

  @override
  void dispose() {
    _name.dispose();
    _region.dispose();
    _sort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New area' : widget.existing!.name),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Area name',
                // The name a customer picks from a list, so it has to read like the place they
                // would say out loud rather than an administrative district.
                helperText: 'What a customer would call it — "Hamra", not "District 4"',
              ),
              validator: (String? v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: DeliverySpacing.sm),
            TextFormField(
              controller: _region,
              decoration: const InputDecoration(
                labelText: 'Region (optional)',
                helperText: 'Groups areas in the picker — "Beirut", "Mount Lebanon"',
              ),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            TextFormField(
              controller: _sort,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Order in the list',
                helperText: 'Lower comes first; ties fall back to the name',
              ),
              validator: (String? v) =>
                  int.tryParse((v ?? '').trim()) == null ? 'A number' : null,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_form.currentState?.validate() ?? false)) return;
            final String region = _region.text.trim();
            Navigator.of(context).pop(_Draft(
              _name.text.trim(),
              region.isEmpty ? null : region,
              int.parse(_sort.text.trim()),
            ));
          },
          style: FilledButton.styleFrom(backgroundColor: DeliveryColors.brand),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
