import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// Where this shop delivers, and what it charges to get there.
///
/// A shop starts with no areas at all, which is deliberately not "delivers nowhere": it means one
/// flat fee, everywhere, exactly as before areas existed. Adding the first area is the moment that
/// changes — from then on the shop delivers only to the areas listed here, and an order from
/// anywhere else is refused at placement rather than accepted and then abandoned.
///
/// That switch is consequential enough to be stated on screen rather than discovered.
class ZonesScreen extends StatefulWidget {
  const ZonesScreen({super.key, required this.api, required this.storeApi});

  final DeliveryZoneApi api;
  final StoreApi storeApi;

  @override
  State<ZonesScreen> createState() => _ZonesScreenState();
}

class _ZonesScreenState extends State<ZonesScreen> {
  late Future<_Data> _data = _load();
  bool _busy = false;

  Future<_Data> _load() async {
    final Store? store = (await widget.storeApi.mine(size: 20)).content.firstOrNull;
    if (store == null) {
      return const _Data(null, <DeliveryZone>[], <ZoneCoverage>[]);
    }
    final List<Object> results = await Future.wait(<Future<Object>>[
      widget.api.picker(),
      widget.api.coverage(store.id),
    ]);
    return _Data(store, results[0] as List<DeliveryZone>, results[1] as List<ZoneCoverage>);
  }

  void _reload() {
    setState(() {
      _data = _load();
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(DeliveryStrings.of(context).thatDidNotWorkWith('$e')),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(Store store, DeliveryZone zone, ZoneCoverage? existing) async {
    final _Terms? terms = await showDialog<_Terms>(
      context: context,
      builder: (BuildContext context) => _TermsDialog(zone: zone, existing: existing),
    );
    // The dialog is an async gap; this State can be gone before it closes.
    if (terms == null || !mounted) return;

    await _run(
      () => widget.api
          .setCoverage(store.id, zone.id,
              deliveryFee: terms.fee,
              minOrder: terms.minOrder,
              etaExtraMinutes: terms.etaExtra)
          .then((_) {}),
      DeliveryStrings.of(context).saved,
    );
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return FutureBuilder<_Data>(
      future: _data,
      builder: (BuildContext context, AsyncSnapshot<_Data> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
        }
        if (snapshot.hasError || snapshot.data?.store == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(DeliverySpacing.lg),
              child: Text(t.noShopYet, style: Theme.of(context).textTheme.titleMedium),
            ),
          );
        }

        final _Data data = snapshot.data!;
        final Store store = data.store!;
        final Map<String, ZoneCoverage> covered = <String, ZoneCoverage>{
          for (final ZoneCoverage c in data.coverage) c.zoneId: c,
        };

        return ListView(
          padding: const EdgeInsets.all(DeliverySpacing.lg),
          children: <Widget>[
            Text(t.deliveryAreas, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: DeliverySpacing.xs),
            Text(t.whereYouDeliver, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: DeliverySpacing.lg),

            if (data.zones.isEmpty)
              SoftCard(
                child: SoftNote(
                  // Nothing for the merchant to do here until the platform defines areas.
                  text: t.noAreasBlurb,
                  accent: DeliveryAccent.info,
                ),
              )
            else ...<Widget>[
              if (covered.isEmpty)
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(t.flatFeeEverywhere,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: DeliverySpacing.xs),
                      Text(t.flatFeeExplanation,
                          style: const TextStyle(
                              fontSize: 13, color: DeliveryColors.muted, height: 1.35)),
                    ],
                  ),
                )
              else
                SoftNote(
                  // The consequence of having any coverage at all, said before it surprises them.
                  text: t.onlyTheseAreas,
                  accent: DeliveryAccent.caution,
                  icon: Icons.info_outline,
                ),
              const SizedBox(height: DeliverySpacing.lg),
              SectionLabel(t.areasYouServe),
              const SizedBox(height: DeliverySpacing.sm),
              for (final DeliveryZone zone in data.zones)
                _zoneRow(store, zone, covered[zone.id], t),
            ],
          ],
        );
      },
    );
  }

  Widget _zoneRow(Store store, DeliveryZone zone, ZoneCoverage? coverage, DeliveryStrings t) {
    final bool served = coverage != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: SoftCard(
        accent: served ? DeliveryAccent.positive.color : null,
        child: Row(
          children: <Widget>[
            Icon(served ? Icons.check_circle_outline_rounded : Icons.radio_button_off_rounded,
                size: 20,
                color: served ? DeliveryAccent.positive.color : DeliveryColors.muted),
            const SizedBox(width: DeliverySpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(zone.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  Text(
                    served
                        ? '${t.feeToHere} ${coverage.deliveryFee.toStringAsFixed(2)}'
                            ' · ${coverage.minOrder == null ? t.usesShopMinimum : '${t.minimumHere} ${coverage.minOrder!.toStringAsFixed(2)}'}'
                            '${coverage.etaExtraMinutes == 0 ? '' : ' · +${coverage.etaExtraMinutes}m'}'
                        : (zone.region ?? ''),
                    style: const TextStyle(fontSize: 12.5, color: DeliveryColors.muted),
                  ),
                ],
              ),
            ),
            if (served)
              IconButton(
                tooltip: t.stopDelivering,
                onPressed: _busy
                    ? null
                    : () => _run(() => widget.api.dropCoverage(store.id, zone.id),
                        t.saved),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            TextButton(
              onPressed: _busy ? null : () => _edit(store, zone, coverage),
              child: Text(served ? t.edit : t.addAnArea),
            ),
          ],
        ),
      ),
    );
  }
}

class _Data {
  const _Data(this.store, this.zones, this.coverage);

  final Store? store;
  final List<DeliveryZone> zones;
  final List<ZoneCoverage> coverage;
}

class _Terms {
  const _Terms(this.fee, this.minOrder, this.etaExtra);

  final double fee;
  final double? minOrder;
  final int etaExtra;
}

/// What this shop charges to reach one area.
class _TermsDialog extends StatefulWidget {
  const _TermsDialog({required this.zone, this.existing});

  final DeliveryZone zone;
  final ZoneCoverage? existing;

  @override
  State<_TermsDialog> createState() => _TermsDialogState();
}

class _TermsDialogState extends State<_TermsDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _fee =
      TextEditingController(text: widget.existing?.deliveryFee.toStringAsFixed(2) ?? '');
  late final TextEditingController _minOrder =
      TextEditingController(text: widget.existing?.minOrder?.toStringAsFixed(2) ?? '');
  late final TextEditingController _eta =
      TextEditingController(text: '${widget.existing?.etaExtraMinutes ?? 0}');

  @override
  void dispose() {
    _fee.dispose();
    _minOrder.dispose();
    _eta.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return AlertDialog(
      title: Text(widget.zone.name),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextFormField(
              controller: _fee,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: t.feeToHere),
              validator: (String? v) {
                final double? parsed = double.tryParse((v ?? '').trim());
                if (parsed == null) return t.aNumber;
                if (parsed < 0) return t.cannotBeNegative;
                return null;
              },
            ),
            const SizedBox(height: DeliverySpacing.sm),
            TextFormField(
              controller: _minOrder,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: t.minimumHere,
                // Blank is meaningful, so it is spelled out rather than left to be guessed.
                helperText: t.usesShopMinimum,
              ),
              validator: (String? v) {
                if ((v ?? '').trim().isEmpty) return null;
                final double? parsed = double.tryParse(v!.trim());
                if (parsed == null) return t.aNumber;
                if (parsed < 0) return t.cannotBeNegative;
                return null;
              },
            ),
            const SizedBox(height: DeliverySpacing.sm),
            TextFormField(
              controller: _eta,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: t.extraMinutes),
              validator: (String? v) {
                final int? parsed = int.tryParse((v ?? '').trim());
                if (parsed == null) return t.aNumber;
                if (parsed < 0) return t.cannotBeNegative;
                return null;
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (!(_form.currentState?.validate() ?? false)) return;
            final String min = _minOrder.text.trim();
            Navigator.of(context).pop(_Terms(
              double.parse(_fee.text.trim()),
              min.isEmpty ? null : double.parse(min),
              int.parse(_eta.text.trim()),
            ));
          },
          style: FilledButton.styleFrom(backgroundColor: DeliveryColors.brand),
          child: Text(t.save),
        ),
      ],
    );
  }
}
