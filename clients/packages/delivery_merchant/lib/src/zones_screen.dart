import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// Below this width the screen lays itself out in one column and edits terms in a sheet.
///
/// 600 rather than a phone's 360: an area row stops being readable long before it overflows —
/// name, fee line and two controls on one line leaves the fee line about a third of the width,
/// and "Fee 15.00 · uses your shop minimum" then wraps to four lines beside a button. A portal in
/// a half-width browser window is in that state too, and gets the same layout for the same reason.
const double _oneColumnBelow = 600;

/// A control tall enough to hit with a thumb.
///
/// The button themes are padded for a mouse, which lands a few px short of the 48 a touch target
/// wants. Only the phone layout needs this — a pointer hits a 36px button fine.
///
/// A minimum rather than a fixed height. Android scales text system-wide, and at the larger
/// settings "Stop delivering here" wraps to a second line; a fixed 48 clips it instead of growing.
Widget _thumbSized(Widget child) =>
    ConstrainedBox(constraints: const BoxConstraints(minHeight: 48), child: child);

/// Where this shop delivers, and what it charges to get there.
///
/// A shop starts with no areas at all, which is deliberately not "delivers nowhere": it means one
/// flat fee, everywhere, exactly as before areas existed. Adding the first area is the moment that
/// changes — from then on the shop delivers only to the areas listed here, and an order from
/// anywhere else is refused at placement rather than accepted and then abandoned.
///
/// That switch is consequential enough to be stated on screen rather than discovered.
///
/// Rendered by the web portal beside a nav rail and by the Android app on a 360dp phone. One
/// widget: the shape changes with the width it is given, not with which app is asking.
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

  /// Pull to refresh.
  ///
  /// The portal can re-tap the rail to rebuild this page; a phone that has landed on a failed load
  /// has no equivalent, so without this the only way back to the server is to leave the screen.
  Future<void> _refresh() {
    final Future<_Data> next = _load();
    setState(() => _data = next);
    // The FutureBuilder renders whatever this settles as, a failure included. The spinner only
    // needs to know when it stopped, so the error is swallowed here rather than left unhandled.
    return next.then<void>((_) {}, onError: (Object _) {});
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

  Future<void> _edit(
    Store store,
    DeliveryZone zone,
    ZoneCoverage? existing, {
    required bool narrow,
  }) async {
    final _Terms? terms = await _askTerms(zone, existing, narrow: narrow);
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

  /// The same form, in the chrome the window can carry.
  ///
  /// A centred dialog on a phone is half under the keyboard the moment the fee field takes focus,
  /// and there is nowhere for it to move to. A sheet rides on top of the keyboard instead.
  Future<_Terms?> _askTerms(
    DeliveryZone zone,
    ZoneCoverage? existing, {
    required bool narrow,
  }) {
    if (!narrow) {
      return showDialog<_Terms>(
        context: context,
        builder: (BuildContext context) =>
            _TermsForm(zone: zone, existing: existing, asSheet: false),
      );
    }
    return showModalBottomSheet<_Terms>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: DeliveryColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.lg)),
      ),
      builder: (BuildContext context) =>
          _TermsForm(zone: zone, existing: existing, asSheet: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // The width this widget was handed, not the window's: in the portal the rail has already
        // taken its share, and that is the room the rows actually get.
        final bool narrow = constraints.maxWidth < _oneColumnBelow;
        final double gutter = narrow ? DeliverySpacing.md : DeliverySpacing.lg;

        return FutureBuilder<_Data>(
          future: _data,
          builder: (BuildContext context, AsyncSnapshot<_Data> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
            }
            if (snapshot.hasError || snapshot.data?.store == null) {
              return _refreshable(
                gutter: gutter,
                children: <Widget>[
                  const SizedBox(height: DeliverySpacing.xxl),
                  Text(
                    t.noShopYet,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              );
            }

            final _Data data = snapshot.data!;
            final Store store = data.store!;
            final Map<String, ZoneCoverage> covered = <String, ZoneCoverage>{
              for (final ZoneCoverage c in data.coverage) c.zoneId: c,
            };

            return _refreshable(
              gutter: gutter,
              children: <Widget>[
                Text(
                  t.deliveryAreas,
                  style: narrow
                      ? Theme.of(context).textTheme.titleLarge
                      : Theme.of(context).textTheme.headlineMedium,
                ),
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
                    _zoneRow(store, zone, covered[zone.id], t, narrow),
                ],
              ],
            );
          },
        );
      },
    );
  }

  /// The page body. Always a scrollable, even when it holds one sentence, so the pull gesture is
  /// there on the states a phone most needs it on.
  Widget _refreshable({required double gutter, required List<Widget> children}) {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: DeliveryColors.brand,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(gutter),
        children: children,
      ),
    );
  }

  /// One area: whether this shop serves it, on what terms, and the two things you can do about it.
  ///
  /// Wide puts the controls on the name's line; narrow puts them underneath, full width. One card
  /// with two arrangements rather than two cards — the state icon, the fee wording and the
  /// add-versus-edit distinction are decided once and read the same on both.
  Widget _zoneRow(
    Store store,
    DeliveryZone zone,
    ZoneCoverage? coverage,
    DeliveryStrings t,
    bool narrow,
  ) {
    final bool served = coverage != null;
    final String detail = served
        ? '${t.feeToHere} ${coverage.deliveryFee.toStringAsFixed(2)}'
            ' · ${coverage.minOrder == null ? t.usesShopMinimum : '${t.minimumHere} ${coverage.minOrder!.toStringAsFixed(2)}'}'
            '${coverage.etaExtraMinutes == 0 ? '' : ' · +${coverage.etaExtraMinutes}m'}'
        : (zone.region ?? '');

    final VoidCallback? edit =
        _busy ? null : () => _edit(store, zone, coverage, narrow: narrow);
    final VoidCallback? drop = _busy
        ? null
        : () => _run(() => widget.api.dropCoverage(store.id, zone.id), t.saved);

    final Widget heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(served ? Icons.check_circle_outline_rounded : Icons.radio_button_off_rounded,
            size: 20, color: served ? DeliveryAccent.positive.color : DeliveryColors.muted),
        const SizedBox(width: DeliverySpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(zone.name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              if (detail.isNotEmpty)
                Text(detail,
                    style: const TextStyle(fontSize: 12.5, color: DeliveryColors.muted)),
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: SoftCard(
        accent: served ? DeliveryAccent.positive.color : null,
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  heading,
                  const SizedBox(height: DeliverySpacing.sm),
                  _thumbSized(OutlinedButton.icon(
                    onPressed: edit,
                    icon: Icon(served ? Icons.tune_rounded : Icons.add_rounded, size: 18),
                    label: Text(served ? t.edit : t.addAnArea),
                  )),
                  if (served) ...<Widget>[
                    // Wider than the usual xs. Stacking full-width buttons puts a destructive
                    // action directly under the one they came here to press, and 4px between two
                    // thumb-sized targets is a mis-tap waiting to happen.
                    const SizedBox(height: DeliverySpacing.sm),
                    // Named rather than left as the bare X of the wide layout. That X says what it
                    // does in a tooltip, and a tooltip on a phone is a control you have to press to
                    // find out what it was — which is the wrong way round for the one action here
                    // that throws away a price the shop set.
                    _thumbSized(TextButton.icon(
                      onPressed: drop,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: Text(t.stopDelivering),
                      style: TextButton.styleFrom(
                          foregroundColor: DeliveryAccent.critical.color),
                    )),
                  ],
                ],
              )
            : Row(
                children: <Widget>[
                  Expanded(child: heading),
                  if (served)
                    IconButton(
                      tooltip: t.stopDelivering,
                      onPressed: drop,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  TextButton(
                    onPressed: edit,
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
///
/// One form in two chromes — a dialog on a wide window, a bottom sheet on a phone. The fields, the
/// validation and the blank-minimum rule are written once: a second copy of a pricing form is a
/// second place for the rules to go wrong.
class _TermsForm extends StatefulWidget {
  const _TermsForm({required this.zone, required this.asSheet, this.existing});

  final DeliveryZone zone;
  final ZoneCoverage? existing;
  final bool asSheet;

  @override
  State<_TermsForm> createState() => _TermsFormState();
}

class _TermsFormState extends State<_TermsForm> {
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

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final String min = _minOrder.text.trim();
    Navigator.of(context).pop(_Terms(
      double.parse(_fee.text.trim()),
      min.isEmpty ? null : double.parse(min),
      int.parse(_eta.text.trim()),
    ));
  }

  Widget _fields(DeliveryStrings t) {
    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextFormField(
            controller: _fee,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
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
            textInputAction: TextInputAction.next,
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
            // The last field, so the phone keyboard offers done rather than another next.
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    if (!widget.asSheet) {
      return AlertDialog(
        title: Text(widget.zone.name),
        // Scrollable: three fields, each of which can grow a validation message, do not fit a
        // laptop window that also has a browser toolbar, and a dialog that cannot scroll overflows
        // rather than shrinking.
        scrollable: true,
        content: _fields(t),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: _submit,
            style: FilledButton.styleFrom(backgroundColor: DeliveryColors.brand),
            child: Text(t.save),
          ),
        ],
      );
    }

    return Padding(
      // The keyboard. Without this the sheet holds its place and types into a field underneath it.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        // The sheet is already clear of the status bar; this is for the gesture bar under Save.
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(DeliverySpacing.md, DeliverySpacing.sm,
              DeliverySpacing.md, DeliverySpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              Text(widget.zone.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: DeliverySpacing.md),
              _fields(t),
              const SizedBox(height: DeliverySpacing.lg),
              PrimaryAction(label: t.save, onPressed: _submit),
              const SizedBox(height: DeliverySpacing.xs),
              _thumbSized(TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t.cancel),
              )),
            ],
          ),
        ),
      ),
    );
  }
}
