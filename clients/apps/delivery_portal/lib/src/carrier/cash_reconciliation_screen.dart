import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/download_file.dart';
import '../shell/shell.dart';
import 'cash_parts.dart';
import 'rider_cash_screen.dart';

/// The delivery company's rider cash reconciliation (Figma 112:9).
///
/// <strong>The company holds its riders' cash</strong> — the owner's decision. A rider owes the door
/// cash they collected on the company's jobs to the company; the company records each hand-over
/// here, the cash then sits in the company's custody, and the company owes YouDrop until the Back
/// Office records its payment. This page is the hub counter's view of the first half of that.
///
/// <strong>What changed from the design, and why.</strong> Every figure here is one the ledger
/// actually holds:
///
///  * The design's "commission (15%)" and "rider earnings" columns assume a rider keeps the cash
///    less a commission. The ledger says otherwise: every note is platform money until it is banked,
///    the platform's cut on a catalog order cannot be separated per order, and what a company pays
///    its riders is its own employment contract. So the table shows what the rider collected on the
///    day, what the platform credited the company for that rider's jobs ("Fees earned for you"), and
///    the cash still to hand over — which is the whole balance, not a commission.
///  * "Disputed amount" has no record behind it anywhere, so that card is "Owed to YouDrop" — the
///    cash the company itself holds, which is the one figure the design has no place for and the
///    custody model makes the most important.
///  * "Pending Match" is "Holding cash": nothing is matched against a bank for rider cash.
///  * The live-riders badge needs a presence feed this area is not given, so it is not drawn.
///
/// Balances are always as of now; the day chip scopes only the collected, earned and handed-over
/// figures, because cash collected on Monday and still held on Wednesday is Wednesday's problem.
class CarrierCashScreen extends StatefulWidget {
  const CarrierCashScreen({
    super.key,
    required this.api,
    this.notificationApi,
    this.orderApi,
    this.saveFile = downloadTextFile,
  });

  final CarrierCashApi api;

  /// The console bell's inbox. Null draws the bell inert, as on a portal built without one.
  final NotificationApi? notificationApi;

  /// For the rider's public rating on their settlement page. Null leaves it off — never a zero.
  final OrderApi? orderApi;

  /// Where the CSV export goes: the browser's download in production, a capture in tests.
  final SaveTextFile saveFile;

  @override
  State<CarrierCashScreen> createState() => _CarrierCashScreenState();
}

class _CarrierCashScreenState extends State<CarrierCashScreen> {
  DateTime _day = _today();
  CarrierCashOverview? _overview;
  bool _loading = true;
  Object? _error;

  /// Riders ticked for "Settle selected". Only riders holding cash can be in it.
  final Set<String> _selected = <String>{};

  /// A hand-over is in flight. Every Settle control is disabled until it answers, which is the
  /// page's half of the double-submit guard; the server's lock and request key are the other.
  bool _busy = false;

  /// The rider whose settlement page is open in place of the list. The page keeps the rail's
  /// Reconciliation item selected, as the design draws it, rather than pushing a route over the
  /// whole console.
  RiderCashLine? _open;

  static DateTime _today() {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _isToday => _day == _today();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final CarrierCashOverview loaded = await widget.api.overview(day: _day);
      if (!mounted) return;
      setState(() {
        _overview = loaded;
        _error = null;
        _loading = false;
        // Somebody square since the last load cannot stay ticked for a hand-over.
        _selected.retainAll(loaded.riders
            .where((RiderCashLine l) => l.hasCash)
            .map((RiderCashLine l) => l.riderRef));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _pickDay() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DateTime today = _today();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(today.year - 1, today.month, today.day),
      lastDate: today,
      helpText: t.carrCashPickDay,
    );
    if (picked == null || !mounted) return;
    setState(() => _day = DateTime(picked.year, picked.month, picked.day));
    await _refresh();
  }

  void _openRider(RiderCashLine line) => setState(() => _open = line);

  void _closeRider() {
    setState(() => _open = null);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final RiderCashLine? open = _open;
    if (open != null) {
      return RiderCashScreen(
        api: widget.api,
        riderRef: open.riderRef,
        name: open.name,
        orderApi: widget.orderApi,
        notificationApi: widget.notificationApi,
        onBack: _closeRider,
      );
    }

    return ConsolePage(
      header: ConsoleTopbar(
        title: t.carrCashTitle,
        subtitle: t.carrCashSubtitle,
        actions: <Widget>[
          ConsoleFilterButton(
            label: _isToday ? t.carrCashTodayChip(isoDay(_day)) : t.carrCashDayChip(isoDay(_day)),
            icon: Icons.calendar_today_outlined,
            onPressed: _loading ? null : _pickDay,
          ),
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: t.refresh,
            onPressed: _loading ? null : _refresh,
          ),
          ConsoleBell(api: widget.notificationApi),
        ],
      ),
      children: _body(t),
    );
  }

  List<Widget> _body(DeliveryStrings t) {
    if (_loading && _overview == null && _error == null) {
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
      return <Widget>[CarrierCashProblem(error: _error!, onRetry: _refresh)];
    }

    final CarrierCashOverview o = _overview!;
    return <Widget>[
      _kpis(t, o),
      if (o.totals.overdueRiders > 0)
        SoftNote(
          text: t.carrCashOverdueSoftNote(o.overdueAfterHours),
          accent: DeliveryAccent.caution,
          icon: Icons.schedule_rounded,
        ),
      _balances(t, o),
    ];
  }

  Widget _kpis(DeliveryStrings t, CarrierCashOverview o) {
    final CarrierCashTotals s = o.totals;
    return ConsoleKpiRow(
      cards: <Widget>[
        ConsoleKpiCard(
          label: t.carrCashKpiWithRiders,
          value: cashText(s.withRiders, o.currency),
          icon: Icons.pedal_bike_outlined,
          footnote: _foot(t.carrCashKpiWithRidersNote(s.ridersHolding),
              s.ridersHolding > 0 ? DeliveryAccent.caution : null),
        ),
        ConsoleKpiCard(
          label: t.carrCashKpiHandedOver,
          value: cashText(s.handedOver, o.currency),
          icon: Icons.check_circle_outline,
          footnote: _foot(t.carrCashKpiHandedOverNote(s.handovers),
              s.handovers > 0 ? DeliveryAccent.positive : null),
        ),
        ConsoleKpiCard(
          label: t.carrCashKpiOwed,
          value: cashText(s.held, o.currency),
          icon: Icons.account_balance_outlined,
          footnote: _foot(t.carrCashKpiOwedNote(s.heldOrders), null),
        ),
        ConsoleKpiCard(
          label: t.carrCashKpiOverdue,
          value: cashText(s.overdue, o.currency),
          icon: Icons.schedule,
          footnote: _foot(t.carrCashKpiOverdueNote(s.overdueRiders, o.overdueAfterHours),
              s.overdueRiders > 0 ? DeliveryAccent.critical : null),
        ),
      ],
    );
  }

  Widget _foot(String text, DeliveryAccent? accent) => Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: ConsoleText.meta.copyWith(
          color: accent?.onTint ?? DeliveryColors.faint,
          fontWeight: accent == null ? null : FontWeight.w600,
        ),
      );

  Widget _balances(DeliveryStrings t, CarrierCashOverview o) {
    final List<RiderCashLine> withCash =
        o.riders.where((RiderCashLine l) => l.hasCash).toList(growable: false);
    final bool allSelected = withCash.isNotEmpty &&
        withCash.every((RiderCashLine l) => _selected.contains(l.riderRef));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: DeliverySpacing.md,
          runSpacing: DeliverySpacing.sm,
          children: <Widget>[
            Text(t.carrCashBalancesTitle, style: ConsoleText.cardTitle),
            Wrap(
              spacing: DeliverySpacing.md - DeliverySpacing.xs,
              runSpacing: DeliverySpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                if (withCash.isNotEmpty)
                  Tooltip(
                    message: t.carrCashSelectAll,
                    child: Checkbox(
                      value: allSelected,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      onChanged: _busy
                          ? null
                          : (bool? on) => setState(() {
                                if (on ?? false) {
                                  _selected.addAll(withCash.map((RiderCashLine l) => l.riderRef));
                                } else {
                                  _selected.clear();
                                }
                              }),
                    ),
                  ),
                Text(t.carrCashSelectedCount(_selected.length), style: ConsoleText.meta),
                ConsoleButton(
                  label: t.carrCashExportCsv,
                  icon: Icons.download_outlined,
                  tone: ConsoleButtonTone.outlined,
                  onPressed: o.riders.isEmpty ? null : () => _export(t, o),
                ),
                ConsolePrimaryButton(
                  label: t.carrCashSettleSelected,
                  icon: Icons.check,
                  busy: _busy,
                  onPressed: _selected.isEmpty ? null : () => _settleSelected(t, o),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: DeliverySpacing.md),
        ConsoleTable(
          minWidth: 1150,
          columns: <ConsoleColumn>[
            const ConsoleColumn(label: '', width: 44),
            ConsoleColumn(label: t.carrCashColRider, flex: 1),
            ConsoleColumn(label: t.carrCashColCollected, width: 120),
            ConsoleColumn(label: t.carrCashColEarned, width: 150),
            ConsoleColumn(label: t.carrCashColHolding, width: 140),
            ConsoleColumn(label: t.carrCashColLastHandover, width: 130),
            ConsoleColumn(label: t.carrCashColStatus, width: 140),
            // Wide enough for Settle and View side by side, which is what the design draws and
            // what a fixed column must hold without clipping either button.
            ConsoleColumn(label: t.carrCashColActions, width: 200, alignRight: true),
          ],
          empty: Text(t.carrCashNobodyYet, style: ConsoleText.cellMuted),
          rows: <ConsoleTableRow>[
            for (final RiderCashLine line in o.riders) _row(t, o, line),
          ],
          footer: Text(
            t.carrCashTableNote,
            style: ConsoleText.meta.copyWith(color: DeliveryColors.faint),
          ),
        ),
      ],
    );
  }

  ConsoleTableRow _row(DeliveryStrings t, CarrierCashOverview o, RiderCashLine l) {
    final String who = l.name ?? shortRef(l.riderRef);
    final bool late = l.standing == RiderCashStanding.overdue;

    return ConsoleTableRow(
      onTap: () => _openRider(l),
      cells: <Widget>[
        Semantics(
          label: t.carrCashSelectRider(who),
          child: Checkbox(
            value: _selected.contains(l.riderRef),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            // Somebody holding nothing cannot be settled, so they cannot be ticked either.
            onChanged: l.hasCash && !_busy
                ? (bool? on) => setState(() {
                      if (on ?? false) {
                        _selected.add(l.riderRef);
                      } else {
                        _selected.remove(l.riderRef);
                      }
                    })
                : null,
          ),
        ),
        Row(
          children: <Widget>[
            ConsoleAvatar(name: who, size: 28),
            const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
            Flexible(
              child: Text(who, overflow: TextOverflow.ellipsis, style: ConsoleText.cellStrong),
            ),
          ],
        ),
        Text(cashText(l.collected, o.currency), style: ConsoleText.cell),
        Text(cashText(l.earned, o.currency), style: ConsoleText.cellMuted),
        Text(
          cashText(l.holding, o.currency),
          style: ConsoleText.cellStrong.copyWith(
            color: late ? DeliveryAccent.critical.onTint : null,
          ),
        ),
        Text(relativeDay(t, l.lastHandoverAt), style: ConsoleText.cellMuted),
        standingPill(t, l.standing, l.overdueHours),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Drawn on every row, as designed, and disabled where there is nothing to settle —
            // the design shows it live on a 0.00 row, which would record a hand-over of nothing.
            ConsoleTintButton(
              label: t.carrCashActionSettle,
              onPressed: l.hasCash && !_busy ? () => _settleOne(t, o, l) : null,
            ),
            const SizedBox(width: DeliverySpacing.sm),
            ConsoleButton(
              label: t.carrCashActionView,
              tone: ConsoleButtonTone.outlined,
              onPressed: () => _openRider(l),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _settleOne(DeliveryStrings t, CarrierCashOverview o, RiderCashLine l) async {
    final String who = l.name ?? shortRef(l.riderRef);
    // One key per confirmation, made before the dialog: whatever happens after this press, the
    // server sees one hand-over for it.
    final String requestKey = CarrierCashApi.newRequestKey();
    final HandoverChoice? choice = await confirmHandover(
      context,
      name: who,
      amount: cashText(l.holding, o.currency),
      orders: t.carrCashOrderCount(l.orders),
    );
    if (choice == null || !mounted) return;

    // Captured before the await: this State can be disposed while the request is in flight.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final ({bool ok, String message}) result = await _record(t, o, l, requestKey, choice);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected.remove(l.riderRef);
    });
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
    await _refresh();
  }

  Future<void> _settleSelected(DeliveryStrings t, CarrierCashOverview o) async {
    final List<RiderCashLine> lines = o.riders
        .where((RiderCashLine l) => l.hasCash && _selected.contains(l.riderRef))
        .toList(growable: false);
    if (lines.isEmpty) return;

    final Map<String, String> keys = <String, String>{
      for (final RiderCashLine l in lines) l.riderRef: CarrierCashApi.newRequestKey(),
    };
    final HandoverChoice? choice = await confirmBulkHandover(
      context,
      lines: <BulkLine>[
        for (final RiderCashLine l in lines)
          (name: l.name ?? shortRef(l.riderRef), amount: cashText(l.holding, o.currency)),
      ],
      total: cashText(sumMoney(lines.map((RiderCashLine l) => l.holding)), o.currency),
    );
    if (choice == null || !mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    int done = 0;
    final List<String> problems = <String>[];
    // One at a time, each against the amount its own row showed. A hand-over that is refused —
    // somebody collected more since the page loaded — does not stop the others, and says so.
    for (final RiderCashLine l in lines) {
      final ({bool ok, String message}) result =
          await _record(t, o, l, keys[l.riderRef]!, choice);
      if (result.ok) {
        done++;
      } else {
        problems.add(result.message);
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected.clear();
    });
    messenger.showSnackBar(SnackBar(
      content: Text(<String>[t.carrCashBulkDone(done, lines.length), ...problems].join('\n')),
    ));
    await _refresh();
  }

  /// Records one hand-over and says what happened, in a sentence. Never throws.
  Future<({bool ok, String message})> _record(DeliveryStrings t, CarrierCashOverview o,
      RiderCashLine l, String requestKey, HandoverChoice choice) async {
    final String who = l.name ?? shortRef(l.riderRef);
    final Money? expected = l.holding;
    if (expected == null) return (ok: false, message: t.carrCashRecordFailed);
    try {
      final HandoverReceipt receipt = await widget.api.recordHandover(
        l.riderRef,
        expected: expected,
        requestKey: requestKey,
        method: choice.method,
        note: choice.note,
      );
      return (
        ok: true,
        message: receipt.replayed
            ? t.carrCashReplayed
            : t.carrCashRecorded(cashText(receipt.amount, o.currency), who),
      );
    } on CashAmountChanged catch (e) {
      return (
        ok: false,
        message: e.current == null
            ? t.carrCashAmountChangedUnknown(who)
            : t.carrCashAmountChanged(who, cashText(e.current, o.currency)),
      );
    } catch (_) {
      return (ok: false, message: t.carrCashRecordFailed);
    }
  }

  void _export(DeliveryStrings t, CarrierCashOverview o) {
    final String file = 'rider-cash-${o.day}.csv';
    widget.saveFile(file, carrierCashCsv(t, o));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.carrCashExported(file))));
  }
}
