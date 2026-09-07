/// Taking the money — Figma `pos-checkout` (94:4462) and its 1440x900 counterpart (94:5328).
///
/// The tender step of a walk-in sale: what is in the basket, how the customer is paying, what they
/// handed over, and what comes back. It is deliberately the *last* screen that can still be
/// abandoned without consequence — nothing here writes until [PosApi.checkout] returns.
///
/// **Money law.** Every figure that came from the server is rendered as the server wrote it
/// ([Money] is a string, never a double, never reformatted). The three figures this screen computes
/// itself — what is still outstanding, the change on a cash tender, and the lira the drawer should
/// physically collect — are computed in **integer cents** and are labelled a preview
/// ([DeliveryStrings.posChangePreview]). The authoritative figures are whatever `checkout` sends
/// back, and the receipt prints those.
///
/// **Lira law.** Lebanese cash is entered as a **USD amount settled in lira**, never as a pile of
/// lira converted back into dollars. The inverse direction is not exact — a tenderable multiple of
/// 1,000 LBP is essentially never a whole number of cents — so this screen never performs it: the
/// cashier types the dollar portion the customer is paying in lira, and the screen derives the note
/// value to collect (`exact` at the sale's own locked rate, rounded to the nearest 1,000 note,
/// which is the smallest note that exists). The gap is the rounding the till books, and it is shown
/// rather than hidden.
///
/// **Rate law.** Every lira figure here is derived from [PosSale.lbpPerUsd] — the rate this sale
/// locked when it opened — and never from `MarketRates`. A sale open across a rate change must
/// still agree with its own receipt. When the sale carries no rate (0), no lira figure is drawn at
/// all and paying in lira is not offered: a converted figure at an invented rate is worse than no
/// figure.
library;

import 'dart:math' as math;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../order_detail_screen.dart';

/// The width at which the sheet stops being one column and puts the basket beside the tender pad.
///
/// Measured against the widget's OWN constraints, not the window: mounted in the portal this
/// screen gets the space beside a navigation rail, and shown as the terminal's dialog it gets 420
/// whatever the monitor is.
const double _twoPaneWidth = 900;

/// The tender pad's width in the two-pane layout. The basket takes the rest.
const double _tenderPaneWidth = 400;

/// The WINDOW width at which [PosCheckoutScreen.show] stops using a bottom sheet and uses a
/// dialog. The terminal's own split is drawn at the same number, so the checkout arrives in the
/// shape the screen behind it is already in.
const double _dialogWindowWidth = 1000;

/// The smallest Lebanese note in circulation. Physical lira move in multiples of this, so an
/// amount to hand over or take in is always rounded to it.
const int _lbpNote = 1000;

/// The tender step of a walk-in sale.
///
/// A sheet rather than a route (see [show]): a half-tendered sale must not be reachable with the
/// browser's Back button. It is still a plain widget, so the portal can also mount it in a panel.
///
/// [api] is nullable because pos-service is not deployed yet. With no client the screen still draws
/// the basket and the tender pad — a cashier can see what they are about to charge — and says
/// plainly that the register is unavailable instead of throwing when Complete is pressed.
class PosCheckoutScreen extends StatefulWidget {
  const PosCheckoutScreen({
    super.key,
    required this.sale,
    this.api,
    this.onCompleted,
    this.onCancelled,
  });

  /// The sale as the terminal has it. Every figure on screen comes from this object until the
  /// server replaces it wholesale at checkout — this screen never merges a basket of its own.
  final PosSale sale;

  /// Null until pos-service ships. Everything reads; only Complete needs it.
  final PosApi? api;

  /// Told once, with the COMPLETED sale, so the terminal can clear its basket and open the
  /// receipt. When null the screen shows its own short confirmation instead.
  final ValueChanged<PosSale>? onCompleted;

  /// The back affordance, when the host wants one that is not `Navigator.pop`.
  final VoidCallback? onCancelled;

  /// Opens the checkout the way the design does: a bottom sheet under a phone's thumb, a 420px
  /// dialog on a desktop window. Completes with the settled [PosSale], or null if it was dismissed.
  ///
  /// Deliberately not a `MaterialPageRoute`: a half-tendered sale that survives in the browser's
  /// history is a sale somebody eventually charges twice.
  static Future<PosSale?> show(
    BuildContext context, {
    required PosSale sale,
    PosApi? api,
  }) {
    final bool wide = MediaQuery.sizeOf(context).width >= _dialogWindowWidth;

    if (wide) {
      return showDialog<PosSale>(
        context: context,
        // A dialog that vanishes on a stray click behind it is not what a cashier holding
        // somebody's cash needs.
        barrierDismissible: false,
        builder: (BuildContext ctx) => Dialog(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DeliveryRadius.lg),
          ),
          child: ConstrainedBox(
            // The spec's own measure. Narrow on purpose: the tender pad is a column of one-line
            // rows and stretching it across a monitor does not make it faster to read.
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 720),
            child: PosCheckoutScreen(
              sale: sale,
              api: api,
              onCompleted: (PosSale done) => Navigator.of(ctx).pop(done),
              onCancelled: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<PosSale>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: DeliveryColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
      ),
      builder: (BuildContext ctx) => Padding(
        // The keyboard, which the amount field will raise on every single sale.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: PosCheckoutScreen(
            sale: sale,
            api: api,
            onCompleted: (PosSale done) => Navigator.of(ctx).pop(done),
            onCancelled: () => Navigator.of(ctx).pop(),
          ),
        ),
      ),
    );
  }

  @override
  State<PosCheckoutScreen> createState() => _PosCheckoutScreenState();
}

/// The name the spec's screen inventory uses for this file's widget.
///
/// Both names resolve to the same class so neither the terminal nor a test has to know which one
/// the file was called on the day it was written.
typedef PosCheckoutSheet = PosCheckoutScreen;

class _PosCheckoutScreenState extends State<PosCheckoutScreen> {
  /// Generated ONCE, here, and reused on every retry.
  ///
  /// This is the whole defence against charging a customer twice: a replayed key returns the sale
  /// the first attempt created instead of creating a second one. Regenerating it on retry — which
  /// is what a key built inside the button handler would do — is exactly how a timeout that
  /// actually succeeded becomes two receipts.
  late final String _idempotencyKey = _uuidV4();

  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reference = TextEditingController();

  late PosSale _sale = widget.sale;

  /// Tenders the cashier has explicitly added, in the order they will be applied.
  final List<_StagedTender> _staged = <_StagedTender>[];

  PosTenderMethod _method = PosTenderMethod.cashUsd;
  ChangeCurrency _changeIn = ChangeCurrency.usd;

  bool _busy = false;

  /// The server's own words about why the last attempt failed, rendered inline under the tender
  /// list rather than as a snackbar — a 422 says which figure is wrong and the cashier has to read
  /// it while fixing it, not watch it slide away.
  String? _failure;

  /// Non-null once the money is taken. Only ever shown when the host gave no [onCompleted].
  PosSale? _settled;

  @override
  void initState() {
    super.initState();
    // Prefilled BEFORE the listener is attached: writing to the controller notifies synchronously,
    // and a setState during initState is a build-phase error rather than a redraw.
    _prefillAmount();
    _amount.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amount.removeListener(_onAmountChanged);
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  void _onAmountChanged() => setState(() {});

  /// Puts what is still owed in the amount box, which is what a cashier types nine times in ten.
  void _prefillAmount() {
    final int? remaining = _remainingCents;
    _amount.text = remaining == null || remaining <= 0 ? '' : _usdText(remaining);
  }

  // ------------------------------------------------------------------ derived money

  /// The sale total in cents, or null when this build cannot read the figure the server sent.
  ///
  /// Null is not zero. An unreadable total disables Complete rather than being treated as a free
  /// sale — see [Money.minorUnits].
  int? get _totalCents => _sale.total.minorUnits;

  int get _stagedCents =>
      _staged.fold(0, (int sum, _StagedTender t) => sum + t.appliedCents);

  /// What is left after the tenders already added — before the one being typed.
  int? get _remainingCents {
    final int? total = _totalCents;
    return total == null ? null : total - _stagedCents;
  }

  /// The amount currently in the box, in cents, or null when it is empty or not a figure.
  int? get _draftCents {
    final String text = _amount.text.trim();
    if (text.isEmpty) return null;
    final int? cents = Money(text).minorUnits;
    return cents == null || cents <= 0 ? null : cents;
  }

  /// The tender the box currently describes, or null when there is nothing valid to add.
  _StagedTender? get _draft {
    final int? remaining = _remainingCents;
    final int? typed = _draftCents;
    if (remaining == null || remaining <= 0 || typed == null) return null;
    if (_method == PosTenderMethod.wallet) return null;
    if (_method == PosTenderMethod.cashLbp && _sale.lbpPerUsd <= 0) return null;

    // A tender never settles more than is outstanding: the overage on cash is change, and on a
    // card it is an amount nobody authorised.
    final int applied = math.min(typed, remaining);

    switch (_method) {
      case PosTenderMethod.cashUsd:
        return _StagedTender(
          method: PosTenderMethod.cashUsd,
          appliedCents: applied,
          tenderedCents: typed,
          changeIn: _changeIn,
        );
      case PosTenderMethod.cashLbp:
        // The dollar portion settled in lira. The lira themselves are DERIVED, never typed.
        return _StagedTender(
          method: PosTenderMethod.cashLbp,
          appliedCents: applied,
          lbpFace: _lbpFace(_lbpExact(applied, _sale.lbpPerUsd)),
        );
      case PosTenderMethod.card:
        return _StagedTender(
          method: PosTenderMethod.card,
          appliedCents: applied,
          reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        );
      case PosTenderMethod.wallet:
        return null;
    }
  }

  /// Everything that would be sent if Complete were pressed now: what was added, plus what is in
  /// the box. One tap settles the ordinary single-tender sale without an "Add" step first.
  List<_StagedTender> get _effective {
    final _StagedTender? draft = _draft;
    return <_StagedTender>[..._staged, if (draft != null) draft];
  }

  /// What would still be owed after [_effective]. Null when the total is unreadable.
  int? get _shortfall {
    final int? total = _totalCents;
    if (total == null) return null;
    return total - _effective.fold(0, (int sum, _StagedTender t) => sum + t.appliedCents);
  }

  bool get _canComplete =>
      widget.api != null && !_busy && _shortfall == 0 && !_sale.isEmpty;

  // ------------------------------------------------------------------ actions

  void _addTender() {
    final _StagedTender? draft = _draft;
    if (draft == null) return;
    setState(() {
      _staged.add(draft);
      _failure = null;
      _reference.clear();
    });
    _prefillAmount();
  }

  void _removeTender(int index) {
    setState(() {
      _staged.removeAt(index);
      _failure = null;
    });
    _prefillAmount();
  }

  void _pickMethod(PosTenderMethod method) {
    if (method == _method) return;
    setState(() {
      _method = method;
      _failure = null;
      if (method != PosTenderMethod.card) _reference.clear();
    });
  }

  Future<void> _complete() async {
    final PosApi? api = widget.api;
    final List<_StagedTender> tenders = _effective;
    if (api == null || tenders.isEmpty || _busy) return;

    final DeliveryStrings t = DeliveryStrings.of(context);
    setState(() {
      _busy = true;
      _failure = null;
    });

    try {
      final PosSale done = await api.checkout(
        _sale.id,
        tenders: tenders.map((_StagedTender x) => x.toRequest()).toList(),
        // The receipt is chosen on the receipt screen, which owns that decision and the contact
        // field that goes with it. Asking twice is how a cashier sends two.
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;
      setState(() {
        _sale = done;
        _settled = done;
        _busy = false;
      });
      widget.onCompleted?.call(done);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = _messageFor(error, t, fallback: t.somethingWentWrong);
        _busy = false;
      });
    }
  }

  /// Whether there is anywhere to go back to. False when the portal mounted this in a panel, in
  /// which case the header draws no back arrow at all rather than a dead one.
  bool get _closable =>
      widget.onCancelled != null || (Navigator.maybeOf(context)?.canPop() ?? false);

  void _close() {
    if (widget.onCancelled != null) {
      widget.onCancelled!.call();
      return;
    }
    final NavigatorState? navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) navigator.pop(_settled);
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return PopScope(
      // Not while the money is in flight: a dismissed sheet mid-checkout leaves a cashier with no
      // idea whether the card was charged.
      canPop: !_busy,
      child: ColoredBox(
        color: DeliveryColors.background,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool twoPane = constraints.maxWidth >= _twoPaneWidth;

            final Widget header = MerchantScreenHeader(
              title: t.posCheckout,
              subtitle: _sale.receiptLabel ?? t.posLinesCount(_sale.itemCount),
              onBack: _busy || !_closable ? null : _close,
              backSemanticLabel: t.back,
              trailing: _sale.status.isSettled
                  ? YdBadge(
                      label: _sale.status.labelIn(t),
                      color: DeliveryAccent.positive.color,
                      background: DeliveryAccent.positive.tint,
                      uppercase: false,
                    )
                  : null,
            );

            if (_settled != null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[header, Expanded(child: _settledBody(t))],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                header,
                Expanded(
                  child: twoPane ? _twoPaneBody(t) : _singleColumnBody(t),
                ),
                _bottomBar(t),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Basket on the left, tender pad on the right — the portal's shape.
  Widget _twoPaneBody(DeliveryStrings t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
            children: <Widget>[_basketCard(t)],
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1, color: DeliveryColors.border),
        SizedBox(
          width: _tenderPaneWidth,
          child: ListView(
            padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
            children: <Widget>[_tenderCard(t)],
          ),
        ),
      ],
    );
  }

  /// One column, basket first — the phone's shape, and the dialog's.
  Widget _singleColumnBody(DeliveryStrings t) {
    return Align(
      alignment: AlignmentDirectional.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
        child: ListView(
          padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
          children: <Widget>[
            _basketCard(t),
            const SizedBox(height: DeliverySpacing.md),
            _tenderCard(t),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ basket

  Widget _basketCard(DeliveryStrings t) {
    if (_sale.isEmpty) {
      return YdCard.bordered(
        child: YdEmptyState(
          icon: Icons.shopping_basket_outlined,
          title: t.posCartEmpty,
          message: t.posCartEmptyHint,
        ),
      );
    }

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: _sectionTitle(t.posCart)),
              Text(
                t.posLinesCount(_sale.itemCount),
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 12,
                  color: DeliveryColors.faint,
                  height: 1.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          for (final PosSaleLine line in _sale.lines) _line(t, line),
          const SizedBox(height: DeliverySpacing.sm),
          const MerchantDivider(),
          const SizedBox(height: DeliverySpacing.sm),
          _totalRow(t.posSubtotal, _sale.subtotal),
          if (!_sale.discount.isZero) _totalRow(t.posDiscount, _sale.discount),
          if (!_sale.tax.isZero) _totalRow(t.posTax, _sale.tax),
          if (!_sale.paid.isZero) _totalRow(t.posPaid, _sale.paid),
          if (!_sale.refunded.isZero) _totalRow(t.posRefundedAmount, _sale.refunded),
          const SizedBox(height: DeliverySpacing.xs),
          const MerchantDivider(),
          const SizedBox(height: DeliverySpacing.sm),
          _totalRow(t.posTotal, _sale.total, strong: true),
          // The sale's OWN rate and its OWN lira figure — never the market rate, never recomputed.
          if (_sale.lbpPerUsd > 0 && _sale.totalLbpExact > 0) ...<Widget>[
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Flexible(
                  child: Text(
                    t.posRate(_group(_sale.lbpPerUsd)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: DeliveryColors.faint,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(width: DeliverySpacing.sm),
                Text(
                  t.posLbp(_group(_sale.totalLbpExact)),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.muted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(DeliveryStrings t, PosSaleLine line) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  // "2 × Latte" — the quantity and the name in one translated phrase, so RTL puts
                  // the multiplier where Arabic puts it.
                  t.lineQuantity(line.qty, line.productName),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                if (line.optionsSummary.isNotEmpty)
                  Text(
                    // The SERVER's rendering of the options, so the till and the receipt agree.
                    line.optionsSummary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DeliveryColors.muted,
                      height: 1.35,
                    ),
                  ),
                if (line.sku != null && line.sku!.isNotEmpty)
                  Text(
                    t.invSku(line.sku!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: DeliveryColors.faint,
                      height: 1.35,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Text(
            t.posUsd(line.lineTotal.amount),
            maxLines: 1,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.ink,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  /// One "label ......... $12.34" row. The figure is the server's string, untouched.
  Widget _totalRow(String label, Money value, {bool strong = false}) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: strong ? 15 : 13,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
                color: strong ? DeliveryColors.ink : DeliveryColors.muted,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Text(
            t.posUsd(value.amount),
            maxLines: 1,
            style: TextStyle(
              fontSize: strong ? 18 : 13,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
              color: strong ? DeliveryColors.brand : DeliveryColors.ink,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ tender pad

  Widget _tenderCard(DeliveryStrings t) {
    final int? remaining = _remainingCents;
    final bool settled = _sale.status.isSettled;

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _sectionTitle(t.posTenderMethod),
          const SizedBox(height: DeliverySpacing.sm),
          _methodChips(t),
          if (_staged.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            _sectionTitle(t.posSplitPayment),
            const SizedBox(height: DeliverySpacing.sm),
            for (int i = 0; i < _staged.length; i++) _stagedRow(t, i),
          ],
          if (!settled && remaining != null && remaining > 0) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            _amountField(t),
            if (_method == PosTenderMethod.cashUsd) ...<Widget>[
              const SizedBox(height: DeliverySpacing.md),
              _changeCurrencyPicker(t),
            ],
            if (_method == PosTenderMethod.card) ...<Widget>[
              const SizedBox(height: DeliverySpacing.md),
              _referenceField(t),
            ],
            const SizedBox(height: DeliverySpacing.md),
            _preview(t),
            const SizedBox(height: DeliverySpacing.md),
            // Only offered when a second tender could actually be needed — a split is the
            // exception, and a button that stages a tender covering the whole total is a way to
            // press Complete twice.
            if (_draft != null && (_shortfall ?? 0) > 0)
              MerchantActionButton(
                label: t.posAddTender,
                onPressed: _busy ? null : _addTender,
                primary: false,
                outlined: true,
              ),
          ],
          if (widget.api == null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            _notice(t.posTerminalUnavailable, DeliveryAccent.caution),
          ],
          if (_totalCents == null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            _notice(t.posCouldNotLoadSale, DeliveryAccent.critical),
          ],
          if (_failure != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            _notice(_failure!, DeliveryAccent.critical),
          ],
        ],
      ),
    );
  }

  Widget _methodChips(DeliveryStrings t) {
    // Wrap, not a Row: four translated method names do not fit 380dp in either language, and a
    // horizontal scroller would hide the card option off the edge with nothing to say so.
    return Wrap(
      spacing: DeliverySpacing.sm,
      runSpacing: DeliverySpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final PosTenderMethod method in PosTenderMethod.values) ...<Widget>[
          _methodChip(t, method),
          // The "Soon" marker is its own Wrap item rather than the chip's trailing slot: inside
          // the chip it makes one pill wider than a 400px tender pane, and a chip's Row cannot
          // ellipsise its way out of that.
          if (method == PosTenderMethod.wallet)
            YdComingSoon(label: t.posWalletComingSoon, icon: Icons.schedule),
        ],
      ],
    );
  }

  Widget _methodChip(DeliveryStrings t, PosTenderMethod method) {
    // The wallet has no ledger behind it yet, and lira cannot be quoted on a sale that carries no
    // rate — both stay visible and inert rather than disappearing, so nobody hunts for them.
    final bool wallet = method == PosTenderMethod.wallet;
    final bool noRate = method == PosTenderMethod.cashLbp && _sale.lbpPerUsd <= 0;
    final bool enabled = !wallet && !noRate && !_busy && !_sale.status.isSettled;

    final Widget chip = YdChip(
      label: method.labelIn(t),
      icon: switch (method) {
        PosTenderMethod.cashUsd => Icons.payments_outlined,
        PosTenderMethod.cashLbp => Icons.account_balance_wallet_outlined,
        PosTenderMethod.card => Icons.credit_card,
        PosTenderMethod.wallet => Icons.phone_iphone,
      },
      selected: enabled && _method == method,
      onTap: enabled ? () => _pickMethod(method) : null,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      selected: _method == method,
      child: Opacity(opacity: enabled ? 1 : 0.5, child: chip),
    );
  }

  Widget _stagedRow(DeliveryStrings t, int index) {
    final _StagedTender tender = _staged[index];
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  tender.method.labelIn(t),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                if (tender.method == PosTenderMethod.cashLbp && tender.lbpFace > 0)
                  Text(
                    t.posLbp(_group(tender.lbpFace)),
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 11,
                      color: DeliveryColors.faint,
                      height: 1.35,
                    ),
                  ),
                if (tender.reference != null && tender.reference!.isNotEmpty)
                  Text(
                    tender.reference!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: DeliveryColors.faint,
                      height: 1.35,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Text(
            t.posUsd(_usdText(tender.appliedCents)),
            maxLines: 1,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.ink,
              height: 1.3,
            ),
          ),
          IconButton(
            onPressed: _busy ? null : () => _removeTender(index),
            icon: const Icon(Icons.close_rounded, size: 18),
            color: DeliveryColors.faint,
            tooltip: t.posRemoveLine,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _amountField(DeliveryStrings t) {
    // The symbol comes out of the money key, never a hardcoded '$' — and which side of the digits
    // it sits on follows the reading direction, because Arabic writes "10.55 $".
    final String symbol = t.posUsd('').trim();
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    const TextStyle affix = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: DeliveryColors.faint,
    );

    return _Field(
      // For lira this is the DOLLAR portion being settled in lira, not a pile of lira: the note
      // value to hand over is derived below and shown, never typed.
      label: t.posAmountTendered,
      child: TextField(
        controller: _amount,
        enabled: !_busy,
        autofocus: false,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        inputFormatters: <TextInputFormatter>[
          // Digits and at most two decimals — the exact shape Money can read, so nothing the
          // cashier types can produce an amount this screen would silently drop.
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          _TwoDecimalFormatter(),
        ],
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.ink,
        ),
        cursorColor: DeliveryColors.brand,
        decoration: _boxDecoration().copyWith(
          prefixText: rtl ? null : symbol,
          prefixStyle: affix,
          suffixText: rtl ? symbol : null,
          suffixStyle: affix,
        ),
        onSubmitted: (_) {
          if (_canComplete) _complete();
        },
      ),
    );
  }

  Widget _referenceField(DeliveryStrings t) {
    return _Field(
      label: t.posCardReference,
      child: TextField(
        controller: _reference,
        enabled: !_busy,
        maxLength: 64,
        style: const TextStyle(fontSize: 14, color: DeliveryColors.ink),
        cursorColor: DeliveryColors.brand,
        decoration: _boxDecoration(),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  /// "Change in: USD | LBP" — cash in dollars is the only tender where the drawer has a choice.
  Widget _changeCurrencyPicker(DeliveryStrings t) {
    return _Field(
      label: t.posChangeIn,
      child: Wrap(
        spacing: DeliverySpacing.sm,
        children: <Widget>[
          for (final ChangeCurrency currency in ChangeCurrency.values)
            YdChip(
              label: switch (currency) {
                // The currency words themselves live in the money keys, which already carry them.
                ChangeCurrency.usd => t.posUsd(''),
                ChangeCurrency.lbp => t.posLbp('').trim(),
              },
              selected: _changeIn == currency,
              onTap: _busy || (currency == ChangeCurrency.lbp && _sale.lbpPerUsd <= 0)
                  ? null
                  : () => setState(() => _changeIn = currency),
            ),
        ],
      ),
    );
  }

  /// What the cashier does next: how much lira to collect, or how much change to give.
  ///
  /// Every figure here is this client's arithmetic on integer cents, which is why the block is
  /// labelled a preview. The till's own numbers arrive with the completed sale.
  Widget _preview(DeliveryStrings t) {
    final _StagedTender? draft = _draft;
    if (draft == null) return const SizedBox.shrink();

    final List<Widget> rows = <Widget>[];

    if (draft.method == PosTenderMethod.cashLbp && draft.lbpFace > 0) {
      final int exact = _lbpExact(draft.appliedCents, _sale.lbpPerUsd);
      final int rounding = draft.lbpFace - exact;
      rows.add(_previewRow(t.posCashLbp, t.posLbp(_group(draft.lbpFace)), strong: true));
      if (rounding != 0) {
        rows.add(_previewRow(
          t.posRoundingLbp,
          t.posLbp(_group(rounding.abs())),
        ));
      }
    }

    if (draft.method == PosTenderMethod.cashUsd && draft.changeCents > 0) {
      if (draft.changeIn == ChangeCurrency.lbp && _sale.lbpPerUsd > 0) {
        final int exact = _lbpExact(draft.changeCents, _sale.lbpPerUsd);
        final int face = _lbpFace(exact);
        rows.add(_previewRow(t.posChangeDue, t.posLbp(_group(face)), strong: true));
        if (face != exact) {
          rows.add(_previewRow(t.posRoundingLbp, t.posLbp(_group((face - exact).abs()))));
        }
      } else {
        rows.add(_previewRow(
          t.posChangeDue,
          t.posUsd(_usdText(draft.changeCents)),
          strong: true,
        ));
      }
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryColors.background,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        border: Border.all(color: DeliveryColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ...rows,
          const SizedBox(height: DeliverySpacing.xs),
          Text(
            t.posChangePreview,
            style: const TextStyle(
              fontSize: 11,
              color: DeliveryColors.faint,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewRow(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 12,
                color: DeliveryColors.muted,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: strong ? 16 : 12,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
              color: strong ? DeliveryColors.ink : DeliveryColors.muted,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ bottom bar

  Widget _bottomBar(DeliveryStrings t) {
    final int? shortfall = _shortfall;
    final bool short = shortfall != null && shortfall > 0;

    return Container(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(top: BorderSide(color: DeliveryColors.border)),
      ),
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      short
                          ? t.posRemainingAmount(t.posUsd(_usdText(shortfall)))
                          : t.posOutstanding,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: short ? DeliveryAccent.caution.color : DeliveryColors.muted,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: DeliverySpacing.sm),
                  Text(
                    short ? t.posUsd(_sale.total.amount) : t.posUsd(_usdText(0)),
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.ink,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
              if (short) ...<Widget>[
                const SizedBox(height: DeliverySpacing.xs),
                Text(
                  t.posTendersShort,
                  style: const TextStyle(
                    fontSize: 11,
                    color: DeliveryColors.faint,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: DeliverySpacing.sm),
              YdPillButton(
                label: t.posCompleteSale,
                // Disabled until the tenders settle the total EXACTLY. The server refuses anything
                // else with a 422 and writes nothing, so offering the button would only teach a
                // cashier that Complete sometimes does nothing.
                onPressed: _canComplete ? _complete : null,
                busy: _busy,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ settled

  Widget _settledBody(DeliveryStrings t) {
    final PosSale done = _settled!;
    return ListView(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.lg),
      children: <Widget>[
        YdEmptyState(
          icon: Icons.check_circle_outline,
          title: t.posSaleCompleted,
          message: done.receiptLabel ?? t.posUsd(done.total.amount),
          // Only where there is somewhere to go: a Done button that does nothing reads as a
          // screen that has hung on the one action that already succeeded.
          action: _closable
              ? YdPillButton.secondary(
                  label: t.done,
                  onPressed: _close,
                  size: YdPillButtonSize.compact,
                  expand: false,
                )
              : null,
        ),
        const SizedBox(height: DeliverySpacing.lg),
        _basketCard(t),
      ],
    );
  }

  // ------------------------------------------------------------------ small parts

  Widget _sectionTitle(String label) => Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.ink,
          height: 1.3,
        ),
      );

  /// An inline band, in the accent's own tint. Not a snackbar: a 422 says which figure is wrong
  /// and the cashier has to read it while fixing it.
  Widget _notice(String message, DeliveryAccent accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: accent.tint,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 16, color: accent.color),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
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

/// One tender the cashier has composed but the server has not seen.
///
/// A small class rather than a bag of nullable fields on the state: the three methods genuinely
/// differ, and the moment "tendered" and "reference" live in the same two variables a card payment
/// starts claiming to have given change.
class _StagedTender {
  const _StagedTender({
    required this.method,
    required this.appliedCents,
    this.tenderedCents,
    this.changeIn = ChangeCurrency.usd,
    this.reference,
    this.lbpFace = 0,
  });

  final PosTenderMethod method;

  /// How much of the sale total this tender settles, in cents. Never more than is outstanding.
  final int appliedCents;

  /// Cash in dollars only: what the customer physically handed over.
  final int? tenderedCents;

  final ChangeCurrency changeIn;

  /// Card only.
  final String? reference;

  /// Cash in lira only: the note value the drawer actually takes in, DERIVED from [appliedCents]
  /// at the sale's own rate and rounded to the nearest 1,000. Never typed by the cashier — the
  /// lira→dollar direction is not exact and this screen never performs it.
  final int lbpFace;

  int get changeCents => (tenderedCents ?? appliedCents) - appliedCents;

  PosTender toRequest() => switch (method) {
        PosTenderMethod.cashUsd => PosTender.cashUsd(
            tendered: Money(_usdText(tenderedCents ?? appliedCents)),
            changeIn: changeIn,
          ),
        // The contract's CASH_LBP tender carries the lira the drawer received; the dollars it
        // settles are the server's to derive from the rate the sale locked.
        PosTenderMethod.cashLbp => PosTender.cashLbp(tenderedLbp: lbpFace),
        PosTenderMethod.card => PosTender.card(
            amount: Money(_usdText(appliedCents)),
            reference: reference,
          ),
        PosTenderMethod.wallet => PosTender.wallet(
            amount: Money(_usdText(appliedCents)),
            reference: reference ?? '',
          ),
      };
}

/// The label-over-input pairing the merchant forms use.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  /// Already localised by the caller.
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
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: DeliveryColors.muted,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// Keeps the amount box in the shape [Money] can read: one dot, at most two decimals.
///
/// A formatter rather than a validator, because the failure it prevents is silent — a third
/// decimal makes [Money.minorUnits] null, which would read on screen as "this amount is not a
/// figure" while the cashier is looking at digits they just typed.
class _TwoDecimalFormatter extends TextInputFormatter {
  static final RegExp _shape = RegExp(r'^\d*(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      _shape.hasMatch(newValue.text) ? newValue : oldValue;
}

/// The bordered input the merchant forms draw.
InputDecoration _boxDecoration() {
  const EdgeInsetsGeometry padding =
      EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs);
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: DeliveryColors.white,
    counterText: '',
    contentPadding: padding,
    border: border(DeliveryColors.border),
    enabledBorder: border(DeliveryColors.border),
    focusedBorder: border(DeliveryColors.brand, 1.5),
    hintStyle: const TextStyle(fontSize: 14, color: DeliveryColors.faint),
  );
}

// ---------------------------------------------------------------------- money arithmetic
//
// The only arithmetic this screen does, all of it in integer cents and integer lira, none of it
// authoritative. A double never touches a figure here: it cannot hold 0.10, and the error compounds
// the moment two of them are added.

/// Cents as the two-decimal text this client will show and send.
///
/// This is the ONE place a money string is built rather than passed through, and it exists because
/// the outstanding balance and the change are figures the server has not computed yet. Everything
/// that came down the wire is rendered from [Money.amount] untouched.
String _usdText(int cents) {
  final bool negative = cents < 0;
  final int magnitude = negative ? -cents : cents;
  final String minor = (magnitude % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}${magnitude ~/ 100}.$minor';
}

/// The exact lira value of a cent figure at a given rate.
///
/// Exact by construction on the platform's own rate: 90,000 is a multiple of 100, so this is a
/// multiplication and no division happens at all. The half-up branch is there only so an odd rate
/// configured in future rounds predictably rather than truncating.
int _lbpExact(int cents, int rate) {
  if (rate <= 0 || cents <= 0) return 0;
  if (rate % 100 == 0) return cents * (rate ~/ 100);
  return (cents * rate + 50) ~/ 100;
}

/// The nearest note that physically exists — lira come in multiples of 1,000 and nothing smaller
/// can be handed over. The gap between this and [_lbpExact] is the rounding the till books.
int _lbpFace(int lbp) {
  if (lbp <= 0) return 0;
  return ((lbp + _lbpNote ~/ 2) ~/ _lbpNote) * _lbpNote;
}

/// "949,500". Thousands separators, done here rather than through `intl` so this package does not
/// take a dependency for one helper — the same reason `MarketRates` has its own.
String _group(int amount) {
  final String digits = amount.abs().toString();
  final StringBuffer out = StringBuffer(amount < 0 ? '-' : '');
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// A version-4 UUID for the idempotency key.
///
/// Hand-rolled rather than pulling in `uuid`: this is the package's only use, and the property that
/// matters is that two checkout attempts in one shop never collide, which 122 random bits from
/// [math.Random.secure] gives comfortably.
String _uuidV4() {
  final math.Random random = math.Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  final String hex =
      bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
      '-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Pulls the human-readable half out of an RFC 9457 problem response.
///
/// A copy of `product_list_screen.dart`'s helper rather than a call to it: that one is file-private
/// and the spec's plan to promote it into the shared vocabulary file touches a file this screen
/// must not edit. The 422 this exists for — "Tenders leave 1.25 outstanding" — is the single most
/// useful sentence on this screen.
String _messageFor(Object error, DeliveryStrings t, {required String fallback}) {
  if (error is DioException) {
    final Object? body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final String? detail = body['detail'] as String?;
      final String? correlationId = body['correlationId'] as String?;
      if (detail != null && detail.isNotEmpty) {
        return correlationId == null ? detail : t.detailWithRef(detail, correlationId);
      }
    }
  }
  return fallback;
}
