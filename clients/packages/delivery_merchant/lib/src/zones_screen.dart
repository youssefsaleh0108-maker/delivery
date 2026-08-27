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
/// The 2026-08 Figma redesign has no frame of its own for this page — `merchant-shop-config`
/// (3:2039) covers the shop's single fee and minimum, not the per-area overrides. So it is drawn
/// in that frame's language instead: the same screen header, the same bordered cards with a 32px
/// icon tile, the same tinted alert banner and the same brand button at radius 12.
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
        // The redesign's sheet top.
        borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
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

        return Scaffold(
          backgroundColor: DeliveryColors.background,
          body: Column(
            children: <Widget>[
              YdScreenHeader(title: t.deliveryAreas, subtitle: t.whereYouDeliver),
              Expanded(
                child: FutureBuilder<_Data>(
                  future: _data,
                  builder: (BuildContext context, AsyncSnapshot<_Data> snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: CircularProgressIndicator(color: DeliveryColors.brand),
                      );
                    }
                    if (snapshot.hasError || snapshot.data?.store == null) {
                      return _refreshable(children: <Widget>[
                        const SizedBox(height: DeliverySpacing.xxl),
                        YdEmptyState(
                          icon: Icons.storefront_outlined,
                          title: t.noShopYet,
                          message: t.shopCreatedAutomatically,
                        ),
                      ]);
                    }

                    final _Data data = snapshot.data!;
                    final Store store = data.store!;
                    final Map<String, ZoneCoverage> covered = <String, ZoneCoverage>{
                      for (final ZoneCoverage c in data.coverage) c.zoneId: c,
                    };

                    return _refreshable(children: <Widget>[
                      if (data.zones.isEmpty)
                        _Banner(
                          // Nothing for the merchant to do here until the platform defines areas.
                          text: t.noAreasBlurb,
                          accent: DeliveryAccent.info,
                          icon: Icons.info_outline,
                        )
                      else ...<Widget>[
                        if (covered.isEmpty)
                          YdCard.bordered(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  t.flatFeeEverywhere,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: DeliveryColors.ink,
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: DeliverySpacing.xs),
                                Text(
                                  t.flatFeeExplanation,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: DeliveryColors.muted,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          _Banner(
                            // The consequence of having any coverage at all, said before it
                            // surprises them.
                            text: t.onlyTheseAreas,
                            accent: DeliveryAccent.caution,
                            icon: Icons.info_outline,
                          ),
                        const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                        Text(
                          t.areasYouServe,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: DeliveryColors.ink,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                        for (final DeliveryZone zone in data.zones)
                          _zoneRow(store, zone, covered[zone.id], t, narrow),
                      ],
                    ]);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The page body. Always a scrollable, even when it holds one sentence, so the pull gesture is
  /// there on the states a phone most needs it on.
  Widget _refreshable({required List<Widget> children}) {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: DeliveryColors.brand,
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              DeliverySpacing.lg - DeliverySpacing.xs,
              DeliverySpacing.lg - DeliverySpacing.xs,
              DeliverySpacing.lg - DeliverySpacing.xs,
              DeliverySpacing.lg - DeliverySpacing.xs + MediaQuery.paddingOf(context).bottom,
            ),
            children: children,
          ),
        ),
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

    // The frame's menu row: a 32px tile on the background token holding a 16px glyph, then the
    // name over its detail line.
    final Widget heading = Row(
      children: <Widget>[
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: served ? DeliveryAccent.positive.tint : DeliveryColors.background,
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          ),
          child: Icon(
            served ? Icons.check_circle_outline_rounded : Icons.place_outlined,
            size: 16,
            color: served ? DeliveryAccent.positive.color : DeliveryColors.faint,
          ),
        ),
        const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                zone.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.ink,
                  height: 1.25,
                ),
              ),
              if (detail.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(fontSize: 12, color: DeliveryColors.faint, height: 1.3),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.md - DeliverySpacing.xs),
      child: YdCard.bordered(
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  heading,
                  const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                  _thumbSized(_WideButton(
                    label: served ? t.edit : t.addAnArea,
                    icon: served ? Icons.tune_rounded : Icons.add_rounded,
                    primary: !served,
                    onPressed: edit,
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
                    _thumbSized(_WideButton(
                      label: t.stopDelivering,
                      icon: Icons.close_rounded,
                      destructive: true,
                      onPressed: drop,
                    )),
                  ],
                ],
              )
            : Row(
                children: <Widget>[
                  Expanded(child: heading),
                  if (served) ...<Widget>[
                    IconButton(
                      tooltip: t.stopDelivering,
                      onPressed: drop,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: DeliveryAccent.critical.color,
                      ),
                    ),
                    const SizedBox(width: DeliverySpacing.xs),
                  ],
                  _ChipButton(label: served ? t.edit : t.addAnArea, onPressed: edit),
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

/// The redesign's alert banner: a 12% accent tint, a 1px line in the same accent at 28%, radius 12,
/// a 16px glyph and Medium 12 copy.
class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.accent, required this.icon});

  /// Already localised by the caller.
  final String text;
  final DeliveryAccent accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
      decoration: BoxDecoration(
        color: accent.tint,
        border: Border.all(color: accent.line),
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16, color: accent.color),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: DeliveryColors.ink,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The frame's brand-tinted `Edit` chip, used here as the row's action.
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

/// The full-width action the phone layout stacks: radius 12, 12px padding, three dialects —
/// filled brand, the quiet background-token fill, and the soft destructive tint.
class _WideButton extends StatelessWidget {
  const _WideButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.destructive = false,
  });

  /// Already localised by the caller.
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;

    late final Color background;
    late final Color foreground;
    Color? line;

    if (destructive) {
      background = DeliveryAccent.critical.tint;
      foreground = DeliveryAccent.critical.color;
      line = DeliveryAccent.critical.line;
    } else if (primary) {
      background = enabled ? DeliveryColors.brand : DeliveryColors.brandLine;
      foreground = DeliveryColors.white;
    } else {
      background = DeliveryColors.background;
      foreground = enabled ? DeliveryColors.muted : DeliveryColors.faint;
    }

    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.md);

    return Semantics(
      button: true,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: corners,
          side: line == null ? BorderSide.none : BorderSide(color: line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: DeliverySpacing.sm),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                      height: 1.2,
                    ),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Field(
            label: t.feeToHere,
            child: TextFormField(
              controller: _fee,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              style: _valueStyle,
              cursorColor: DeliveryColors.brand,
              decoration: _boxDecoration(),
              validator: (String? v) {
                final double? parsed = double.tryParse((v ?? '').trim());
                if (parsed == null) return t.aNumber;
                if (parsed < 0) return t.cannotBeNegative;
                return null;
              },
            ),
          ),
          const SizedBox(height: 14),
          _Field(
            label: t.minimumHere,
            // Blank is meaningful, so it is spelled out rather than left to be guessed.
            hint: t.usesShopMinimum,
            child: TextFormField(
              controller: _minOrder,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              style: _valueStyle,
              cursorColor: DeliveryColors.brand,
              decoration: _boxDecoration(),
              validator: (String? v) {
                if ((v ?? '').trim().isEmpty) return null;
                final double? parsed = double.tryParse(v!.trim());
                if (parsed == null) return t.aNumber;
                if (parsed < 0) return t.cannotBeNegative;
                return null;
              },
            ),
          ),
          const SizedBox(height: 14),
          _Field(
            label: t.extraMinutes,
            child: TextFormField(
              controller: _eta,
              keyboardType: TextInputType.number,
              // The last field, so the phone keyboard offers done rather than another next.
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              style: _valueStyle,
              cursorColor: DeliveryColors.brand,
              decoration: _boxDecoration(),
              validator: (String? v) {
                final int? parsed = int.tryParse((v ?? '').trim());
                if (parsed == null) return t.aNumber;
                if (parsed < 0) return t.cannotBeNegative;
                return null;
              },
            ),
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
        backgroundColor: DeliveryColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DeliveryRadius.lg)),
        title: Text(
          widget.zone.name,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
          ),
        ),
        // Scrollable: three fields, each of which can grow a validation message, do not fit a
        // laptop window that also has a browser toolbar, and a dialog that cannot scroll overflows
        // rather than shrinking.
        scrollable: true,
        content: SizedBox(width: 360, child: _fields(t)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: DeliveryColors.muted),
            child: Text(t.cancel),
          ),
          _WideButton(
            label: t.save,
            icon: Icons.check_rounded,
            primary: true,
            onPressed: _submit,
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
          padding: const EdgeInsets.fromLTRB(
            DeliverySpacing.lg - DeliverySpacing.xs,
            DeliverySpacing.sm,
            DeliverySpacing.lg - DeliverySpacing.xs,
            DeliverySpacing.lg - DeliverySpacing.xs,
          ),
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
              Text(
                widget.zone.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                ),
              ),
              const SizedBox(height: DeliverySpacing.md),
              _fields(t),
              const SizedBox(height: DeliverySpacing.lg),
              _WideButton(
                label: t.save,
                icon: Icons.check_rounded,
                primary: true,
                onPressed: _submit,
              ),
              const SizedBox(height: DeliverySpacing.sm),
              _thumbSized(TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: DeliveryColors.muted),
                child: Text(t.cancel),
              )),
            ],
          ),
        ),
      ),
    );
  }
}

/// The redesign's input value: Regular 14 in ink.
const TextStyle _valueStyle = TextStyle(
  fontSize: 14,
  color: DeliveryColors.ink,
  height: 1.3,
);

/// The redesign's white bordered input box: radius 12, 12px padding all round.
InputDecoration _boxDecoration() {
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: DeliveryColors.white,
    contentPadding:
        const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
    border: border(DeliveryColors.border),
    enabledBorder: border(DeliveryColors.border),
    focusedBorder: border(DeliveryColors.brand, 1.5),
    errorBorder: border(DeliveryAccent.critical.color),
    focusedErrorBorder: border(DeliveryAccent.critical.color, 1.5),
    errorStyle: TextStyle(fontSize: 11, color: DeliveryAccent.critical.color),
  );
}

/// A SemiBold 13 muted label over its field, with room for the one-line explanation the minimum
/// field needs.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.hint});

  final String label;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: DeliveryColors.muted,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 6),
        child,
        if (hint != null) ...<Widget>[
          const SizedBox(height: DeliverySpacing.xs),
          Text(
            hint!,
            style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.3),
          ),
        ],
      ],
    );
  }
}
