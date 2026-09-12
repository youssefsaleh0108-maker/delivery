import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';
import 'cash_parts.dart';

/// One rider's cash bag, and the hand-over at the hub counter (Figma 112:235).
///
/// Opened in place from the reconciliation list, with the rail's Reconciliation item still
/// selected, as the design draws it.
///
/// <strong>What changed from the design, and why.</strong> The design's summary has the rider
/// keeping the cash less a 15% commission, plus base bonuses and late penalties, and the hub
/// receiving only the commission. The ledger says the opposite: every note the rider took is owed
/// in full — to the company, which owes the platform — and there is no bonus or penalty record
/// anywhere. So the summary shows the cash collected and not yet handed over, what the platform
/// credited the company for those jobs (for information: it is paid to the company, not taken from
/// the cash), and the cash due, which is the whole balance. It says in words that the rider keeps
/// none of it, because the design taught the reader to expect otherwise.
///
/// The design's rider PIN field is not drawn: no PIN exists anywhere on the platform, and a box
/// that accepted any four digits would be a control that cannot work. The customer and YouDrop-cut
/// columns are not drawn either — accounting holds no customer names, and the cut is not separable
/// per order. The hand-over records who pressed Confirm, how the cash moved, and a note.
class RiderCashScreen extends StatefulWidget {
  const RiderCashScreen({
    super.key,
    required this.api,
    required this.riderRef,
    required this.onBack,
    this.name,
    this.orderApi,
    this.notificationApi,
  });

  final CarrierCashApi api;
  final String riderRef;

  /// What the list called them, shown until the page's own answer arrives.
  final String? name;
  final VoidCallback onBack;
  final OrderApi? orderApi;
  final NotificationApi? notificationApi;

  @override
  State<RiderCashScreen> createState() => _RiderCashScreenState();
}

class _RiderCashScreenState extends State<RiderCashScreen> {
  RiderCashSettlement? _settlement;
  bool _loading = true;
  Object? _error;

  /// The rider's public rating. Null until it arrives and forever if it fails — the box is then
  /// left off rather than drawn with a zero, which would be a lie about somebody's livelihood.
  RiderStanding? _rating;

  CashMethod _method = CashMethod.cash;
  final TextEditingController _note = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadRating();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final RiderCashSettlement loaded = await widget.api.rider(widget.riderRef);
      if (!mounted) return;
      setState(() {
        _settlement = loaded;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadRating() async {
    final OrderApi? api = widget.orderApi;
    if (api == null) return;
    try {
      final RiderStanding rating = await api.riderRating(widget.riderRef);
      if (mounted) setState(() => _rating = rating);
    } catch (_) {
      // Left off. See [_rating].
    }
  }

  String get _who => _settlement?.name ?? widget.name ?? shortRef(widget.riderRef);

  Future<void> _confirm(DeliveryStrings t) async {
    final RiderCashSettlement? s = _settlement;
    final Money? expected = s?.holding;
    if (s == null || expected == null || !s.hasCash) return;

    final String requestKey = CarrierCashApi.newRequestKey();
    final HandoverChoice? choice = await confirmHandover(
      context,
      name: _who,
      amount: cashText(expected, s.currency),
      orders: t.carrCashOrderCount(s.held.length),
      preset: HandoverChoice(_method, _note.text.trim().isEmpty ? null : _note.text),
    );
    if (choice == null || !mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    String message;
    try {
      final HandoverReceipt receipt = await widget.api.recordHandover(
        widget.riderRef,
        expected: expected,
        requestKey: requestKey,
        method: choice.method,
        note: choice.note,
      );
      message = receipt.replayed
          ? t.carrCashReplayed
          : t.carrCashRecorded(cashText(receipt.amount, s.currency), _who);
      _note.clear();
    } on CashAmountChanged catch (e) {
      message = e.current == null
          ? t.carrCashAmountChangedUnknown(_who)
          : t.carrCashAmountChanged(_who, cashText(e.current, s.currency));
    } catch (_) {
      message = t.carrCashRecordFailed;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(content: Text(message)));
    // Reloaded whatever happened: on success the bag is empty and the history has a new line; on
    // a refusal the page must show the figure the server now holds, not the one that was refused.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return ConsolePage(
      header: ConsoleTopbar(
        title: t.carrCashRiderTitle,
        subtitle: t.carrCashRiderSubtitle(_who),
        actions: <Widget>[
          ConsoleButton(
            label: t.carrCashBack,
            icon: Icons.arrow_back,
            tone: ConsoleButtonTone.outlined,
            onPressed: widget.onBack,
          ),
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: t.refresh,
            onPressed: _loading ? null : _load,
          ),
          ConsoleBell(api: widget.notificationApi),
        ],
      ),
      children: _body(t),
    );
  }

  List<Widget> _body(DeliveryStrings t) {
    if (_loading && _settlement == null && _error == null) {
      return <Widget>[
        const ConsoleCard(
          child: SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
          ),
        ),
      ];
    }
    if (_error != null) {
      return <Widget>[
        CarrierCashProblem(error: _error!, onRetry: _load, notFound: t.carrCashRiderNotFound),
      ];
    }

    final RiderCashSettlement s = _settlement!;
    return <Widget>[
      _header(t, s),
      LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget held = _held(t, s);
          final Widget summary = _summary(t, s);
          if (constraints.maxWidth >= 960) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 3, child: held),
                const SizedBox(width: ConsoleMetrics.pageGap),
                Expanded(flex: 2, child: summary),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[held, const SizedBox(height: ConsoleMetrics.pageGap), summary],
          );
        },
      ),
      _history(t, s),
    ];
  }

  Widget _header(DeliveryStrings t, RiderCashSettlement s) {
    final RiderStanding? rating = _rating;
    return ConsoleCard(
      child: Row(
        children: <Widget>[
          ConsoleAvatar(name: _who, size: 54),
          const SizedBox(width: DeliverySpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Wrap(
                  spacing: DeliverySpacing.sm,
                  runSpacing: DeliverySpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(_who, style: ConsoleText.cardTitle.copyWith(fontSize: 18)),
                    ConsoleSmallBadge(
                      label: s.hasCash ? t.carrCashBadgeUnsettled : t.carrCashStatusSettled,
                      accent: s.hasCash ? DeliveryAccent.caution : DeliveryAccent.positive,
                    ),
                  ],
                ),
                if (s.firstSeenAt != null) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.xs),
                  Text(t.carrCashRiderSince(isoDay(s.firstSeenAt!)),
                      style: ConsoleText.pageSubtitle),
                ],
              ],
            ),
          ),
          if (rating != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.star_border_rounded, size: 18, color: DeliveryAccent.caution.color),
                const SizedBox(width: DeliverySpacing.xs),
                if (rating.average == null)
                  Text(t.carrCashRatingNew, style: ConsoleText.cellStrong)
                else ...<Widget>[
                  Text(rating.average!.toStringAsFixed(1), style: ConsoleText.cellStrong),
                  const SizedBox(width: DeliverySpacing.xs),
                  Text(t.carrCashRatings(rating.ratings), style: ConsoleText.cellMuted),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _held(DeliveryStrings t, RiderCashSettlement s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(t.carrCashHeldTitle, style: ConsoleText.cardTitle),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        ConsoleTable(
          minWidth: 560,
          columns: <ConsoleColumn>[
            ConsoleColumn(label: t.carrCashColOrder, flex: 1),
            ConsoleColumn(label: t.carrCashColCollected, width: 150),
            ConsoleColumn(label: t.carrCashColCash, width: 110, alignRight: true),
            ConsoleColumn(label: t.carrCashColFee, width: 140, alignRight: true),
          ],
          empty: Text(t.carrCashHeldEmpty, style: ConsoleText.cellMuted),
          rows: <ConsoleTableRow>[
            for (final HeldCollection h in s.held)
              ConsoleTableRow(
                cells: <Widget>[
                  Text('#${shortRef(h.orderId ?? '')}', style: ConsoleText.cellLink),
                  // The design's "(Today)" is not a promise the bag keeps: cash can be days old,
                  // so every line says when it was taken, and a late one says so in red.
                  Text(
                    h.collectedAt == null ? '—' : stamp(h.collectedAt!),
                    style: ConsoleText.cellMuted.copyWith(
                      color: h.overdue ? DeliveryAccent.critical.onTint : null,
                    ),
                  ),
                  Text(cashText(h.amount, s.currency), style: ConsoleText.cellStrong),
                  Text(cashText(h.earned, s.currency), style: ConsoleText.cellMuted),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _summary(DeliveryStrings t, RiderCashSettlement s) {
    // "No figure" rather than 0.00 when the ledger credited none of these jobs: a job with no
    // delivery fee writes no row, and that is not the same as the company earning nothing.
    final bool feesKnown = s.held.any((HeldCollection h) => h.earned != null);

    return ConsoleCard(
      title: t.carrCashSummaryTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _SummaryLine(
            label: t.carrCashSummaryCollected,
            value: cashText(s.holding, s.currency),
            note: t.carrCashOrderCount(s.held.length),
          ),
          _SummaryLine(
            label: t.carrCashSummaryFees,
            value: feesKnown ? cashText(s.earnedOnHeld, s.currency) : '—',
            muted: true,
          ),
          const Divider(height: DeliverySpacing.lg, color: DeliveryColors.border),
          _SummaryLine(
            label: t.carrCashSummaryDue,
            value: cashText(s.holding, s.currency),
            strong: true,
          ),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            t.carrCashSummaryKeeps,
            style: ConsoleText.meta.copyWith(color: DeliveryColors.muted, height: 1.4),
          ),
          const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
          ConsoleSectionLabel(t.carrCashMethodLabel),
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: CashMethodSelect(
              value: _method,
              onChanged: (CashMethod m) => setState(() => _method = m),
            ),
          ),
          const SizedBox(height: DeliverySpacing.md),
          ConsoleSectionLabel(t.carrCashNoteLabel),
          TextField(
            controller: _note,
            maxLength: 500,
            decoration: InputDecoration(hintText: t.carrCashNoteHint, isDense: true),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          ConsolePrimaryButton(
            wide: true,
            label: s.hasCash ? t.carrCashConfirmSettlement : t.carrCashNothingToSettle,
            busy: _busy,
            onPressed: s.hasCash ? () => _confirm(t) : null,
          ),
        ],
      ),
    );
  }

  Widget _history(DeliveryStrings t, RiderCashSettlement s) {
    return ConsoleCard(
      title: t.carrCashHistoryTitle,
      child: s.handovers.isEmpty
          ? Text(t.carrCashHistoryEmpty,
              style: ConsoleText.body.copyWith(color: DeliveryColors.muted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final CashHandover h in s.handovers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: DeliverySpacing.md),
                    child: ConsoleActivityRow(
                      message: t.carrCashHistoryItem(h.at == null ? '—' : stamp(h.at!)),
                      when: _detail(t, s, h),
                      accent: DeliveryAccent.positive,
                    ),
                  ),
              ],
            ),
    );
  }

  String _detail(DeliveryStrings t, RiderCashSettlement s, CashHandover h) {
    final String amount = cashText(h.amount, s.currency);
    final String orders = t.carrCashOrderCount(h.collections);
    return <String>[
      h.recordedByName == null
          ? t.carrCashHistoryDetailAnon(amount, orders)
          : t.carrCashHistoryDetail(amount, orders, h.recordedByName!),
      if (h.method != null) methodLabel(t, h.method!),
      if (h.note != null) h.note!,
    ].join(' · ');
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    this.note,
    this.strong = false,
    this.muted = false,
  });

  final String label;
  final String value;
  final String? note;
  final bool strong;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: strong
                      ? ConsoleText.cellStrong.copyWith(fontSize: 15)
                      : ConsoleText.body.copyWith(color: DeliveryColors.muted),
                ),
                if (note != null) Text(note!, style: ConsoleText.meta),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Text(
            value,
            style: strong
                ? ConsoleText.kpiValue.copyWith(fontSize: 18, color: DeliveryAccent.positive.onTint)
                : (muted ? ConsoleText.cellMuted : ConsoleText.cellStrong),
          ),
        ],
      ),
    );
  }
}
