import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/download_file.dart';
import '../shell/shell.dart';
import 'cash_parts.dart';
import 'payroll_parts.dart';

/// A delivery company's payroll for the riders it employs (Figma 112:1162).
///
/// <strong>The company's money, not YouDrop's.</strong> What a company pays its riders is its own
/// employment contract, so this page is the company's payroll book: it works each rider's pay out
/// from the company's own rules and the ledger's facts, freezes it when the company approves it, and
/// records what the company then paid. Nothing here moves money.
///
/// <strong>What changed from the design, and why.</strong>
///
///  * "Process All Payments" and the "Failed" pill imply a payment rail, and there is none: the
///    company pays outside YouDrop. So the button is "Record All Payments", behind a confirmation
///    naming the count and the total, and a failed payment is one the company records, with its
///    reason — the pay stays owed.
///  * "Delivery bonus" is "Delivery pay": the per-delivery rate the company set. There is no
///    delivery-speed bonus engine, so the fourth card is the run's named bonuses and corrections,
///    not "Paid out bonuses — based on delivery speeds".
///  * Tips are shown and added to nothing. A tip is the rider's own money — paid by YouDrop, or in
///    their hand — and counting it into what the company pays would pay it twice.
///  * Gross is base pay (hours) plus delivery pay plus bonuses; net is gross less deductions, which
///    include any company cash the rider held that was kept from their pay.
///  * "Processing" is "Awaiting payment". The pay rules, the draft/approve step and the per-payslip
///    breakdown are added: payroll cannot be computed without rules, and cannot be trusted without
///    being frozen before it is paid.
///  * The live-riders badge needs a presence feed this area is not given, so it is not drawn.
class CarrierPayrollScreen extends StatefulWidget {
  const CarrierPayrollScreen({
    super.key,
    required this.api,
    this.notificationApi,
    this.saveFile = downloadTextFile,
  });

  final CarrierPayrollApi api;

  /// The console bell's inbox. Null draws the bell inert, as on a portal built without one.
  final NotificationApi? notificationApi;

  /// Where the CSV export goes: the browser's download in production, a capture in tests.
  final SaveTextFile saveFile;

  @override
  State<CarrierPayrollScreen> createState() => _CarrierPayrollScreenState();
}

class _CarrierPayrollScreenState extends State<CarrierPayrollScreen> {
  PayPeriodsPage? _periods;
  PayPeriod? _period;
  PayRun? _run;
  bool _loading = true;
  Object? _error;

  /// A change is in flight. Every control that writes is disabled until it answers.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Reads the period list and the chosen period's run.
  Future<void> _load({DateTime? keep}) async {
    setState(() => _loading = true);
    try {
      final PayPeriodsPage page = await widget.api.periods();
      final PayPeriod? chosen = _pick(page, keep ?? _period?.from);
      final String? runId = chosen?.runId;
      final PayRun? run = runId == null ? null : await widget.api.run(runId);
      if (!mounted) return;
      setState(() {
        _periods = page;
        _period = chosen;
        _run = run;
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

  /// The period asked for if it is still listed; otherwise the latest one that is over — the one
  /// waiting to be paid — and the current one only when none is.
  static PayPeriod? _pick(PayPeriodsPage page, DateTime? wanted) {
    if (page.periods.isEmpty) return null;
    if (wanted != null) {
      for (final PayPeriod p in page.periods) {
        if (p.from == wanted) return p;
      }
    }
    return page.periods.firstWhere((PayPeriod p) => p.over, orElse: () => page.periods.first);
  }

  Future<void> _select(String? iso) async {
    final PayPeriodsPage? page = _periods;
    if (iso == null || page == null || _busy) return;
    for (final PayPeriod p in page.periods) {
      if (CarrierCashApi.isoDate(p.from) == iso) {
        await _load(keep: p.from);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return ConsolePage(
      header: ConsoleTopbar(
        title: t.payrollTitle,
        subtitle: t.payrollSubtitle,
        actions: <Widget>[
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: t.refresh,
            onPressed: _loading || _busy ? null : () => _load(),
          ),
          ConsoleBell(api: widget.notificationApi),
        ],
      ),
      children: _body(t),
    );
  }

  List<Widget> _body(DeliveryStrings t) {
    if (_loading && _periods == null && _error == null) {
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
      return <Widget>[PayrollProblem(error: _error!, onRetry: _load)];
    }

    final PayPeriodsPage page = _periods!;
    final PayPeriod? period = _period;
    if (!page.hasPolicy || period == null) {
      return <Widget>[_noRules(t)];
    }
    final PayRun? run = _run;
    return <Widget>[
      _toolbar(t, page, period, run),
      if (run == null)
        ConsoleCard(
          title: t.payrollNoRunTitle,
          child: Text(
            t.payrollNoRunBody,
            style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.5),
          ),
        )
      else ...<Widget>[
        ..._notes(t, run),
        _kpis(t, run),
        _ledger(t, run),
      ],
    ];
  }

  Widget _noRules(DeliveryStrings t) {
    return ConsoleCard(
      title: t.payrollNoRulesTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            t.payrollNoRulesBody,
            style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.5),
          ),
          const SizedBox(height: DeliverySpacing.md),
          ConsolePrimaryButton(
            label: t.payrollRulesButton,
            icon: Icons.tune,
            busy: _busy,
            onPressed: _busy ? null : _editRules,
          ),
        ],
      ),
    );
  }

  Widget _toolbar(DeliveryStrings t, PayPeriodsPage page, PayPeriod period, PayRun? run) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: DeliverySpacing.md,
      runSpacing: DeliverySpacing.sm,
      children: <Widget>[
        ConsoleSelect(
          label: t.payrollPeriodLabel(payDay(context, period.from), payDay(context, period.to)),
          icon: Icons.calendar_today_outlined,
          tooltip: t.payrollPeriodTooltip,
          options: <ConsoleOption>[
            for (final PayPeriod p in page.periods)
              ConsoleOption(
                label: t.payrollPeriodOption(
                    payDay(context, p.from), payDay(context, p.to), runStateText(t, p.status)),
                value: CarrierCashApi.isoDate(p.from),
              ),
          ],
          onSelected: _select,
        ),
        Wrap(
          spacing: DeliverySpacing.sm,
          runSpacing: DeliverySpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            ConsoleButton(
              label: t.payrollRulesButton,
              icon: Icons.tune,
              tone: ConsoleButtonTone.outlined,
              onPressed: _busy ? null : _editRules,
            ),
            if (run != null)
              ConsoleButton(
                label: t.payrollExport,
                icon: Icons.download_outlined,
                tone: ConsoleButtonTone.outlined,
                onPressed: run.payslips.isEmpty ? null : () => _export(t, run),
              ),
            ..._primary(t, period, run),
          ],
        ),
      ],
    );
  }

  /// What can be done with the period now, and nothing else: start, then recompute and approve,
  /// then record payments. Approve stays drawn but disabled while the period is open or empty; the
  /// note above the cards says why.
  List<Widget> _primary(DeliveryStrings t, PayPeriod period, PayRun? run) {
    if (run == null) {
      return <Widget>[
        ConsolePrimaryButton(
          label: t.payrollStart,
          icon: Icons.play_arrow_rounded,
          busy: _busy,
          onPressed: _busy ? null : () => _start(period),
        ),
      ];
    }
    switch (run.status) {
      case PayRunStatus.draft:
        return <Widget>[
          if (run.periodChanged)
            ConsoleSoftButton(
              label: t.payrollDiscard,
              icon: Icons.delete_outline,
              busy: _busy,
              onPressed: _busy ? null : () => _discard(run),
            )
          else
            ConsoleButton(
              label: t.payrollRecompute,
              icon: Icons.refresh,
              tone: ConsoleButtonTone.outlined,
              onPressed: _busy ? null : () => _recompute(run),
            ),
          ConsolePrimaryButton(
            label: t.payrollApprove,
            icon: Icons.check,
            busy: _busy,
            onPressed: !_busy && run.periodOver && run.payslips.isNotEmpty && !run.periodChanged
                ? () => _approve(run)
                : null,
          ),
        ];
      case PayRunStatus.approved:
        return <Widget>[
          ConsolePrimaryButton(
            label: t.payrollPayAll,
            icon: Icons.check,
            busy: _busy,
            onPressed: !_busy && run.totals.due > 0 ? () => _payAll(run) : null,
          ),
        ];
      case PayRunStatus.paid:
      case PayRunStatus.unknown:
        return const <Widget>[];
    }
  }

  List<Widget> _notes(DeliveryStrings t, PayRun run) {
    return <Widget>[
      if (run.periodChanged)
        SoftNote(
          text: t.payrollPeriodChanged,
          accent: DeliveryAccent.critical,
          icon: Icons.warning_amber_rounded,
        )
      else if (run.isDraft && !run.periodOver)
        SoftNote(
          text: t.payrollPeriodOpen(payDay(context, run.to)),
          accent: DeliveryAccent.caution,
          icon: Icons.schedule_rounded,
        ),
      if (run.attendance == PayrollAttendance.unavailable)
        SoftNote(
          text: switch (run.attendanceReason) {
            'NOT_DEPLOYED' => t.payrollHoursNotDeployed,
            'NOT_READ' => t.payrollHoursNotRead,
            _ => t.payrollHoursMissing,
          },
          accent: DeliveryAccent.caution,
          icon: Icons.timer_off_outlined,
        ),
      if (run.jobsSinceComputed > 0)
        SoftNote(
          text: run.isDraft
              ? t.payrollJobsLateDraft(run.jobsSinceComputed)
              : t.payrollJobsLateApproved(run.jobsSinceComputed),
          accent: DeliveryAccent.caution,
          icon: Icons.local_shipping_outlined,
        ),
    ];
  }

  Widget _kpis(DeliveryStrings t, PayRun run) {
    final PayRunTotals s = run.totals;
    return ConsoleKpiRow(
      cards: <Widget>[
        ConsoleKpiCard(
          label: t.payrollKpiPool,
          value: cashText(s.payable, run.currency),
          icon: Icons.account_balance_wallet_outlined,
          footnote: _foot(t.payrollKpiPoolNote(payDay(context, run.from), payDay(context, run.to))),
        ),
        ConsoleKpiCard(
          label: t.payrollKpiRiders,
          value: t.payrollKpiRidersValue(s.riders),
          icon: Icons.groups_outlined,
          footnote: _foot(t.payrollKpiRidersNote),
        ),
        ConsoleKpiCard(
          label: t.payrollKpiAverage,
          value: cashText(s.average, run.currency),
          icon: Icons.person_outline,
          footnote: _foot(t.payrollKpiAverageNote(periodDays(run.from, run.to))),
        ),
        ConsoleKpiCard(
          label: t.payrollKpiBonuses,
          value: cashText(s.bonuses, run.currency),
          icon: Icons.card_giftcard_outlined,
          footnote: _foot(t.payrollKpiBonusesNote),
        ),
      ],
    );
  }

  Widget _foot(String text) => Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: ConsoleText.meta.copyWith(color: DeliveryColors.faint),
      );

  Widget _ledger(DeliveryStrings t, PayRun run) {
    final String state =
        run.isDraft ? t.payrollRunRevision(run.revision) : runStateText(t, run.status);
    final List<String> meta = <String>[
      t.payrollRunMeta(state, payStamp(context, run.computedAt)),
      if (run.attendance == PayrollAttendance.included)
        t.payrollHoursAsOf(payStamp(context, run.attendanceAt)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: DeliverySpacing.md,
          runSpacing: DeliverySpacing.xs,
          children: <Widget>[
            Text(t.payrollLedgerTitle, style: ConsoleText.cardTitle),
            Text(meta.join(' · '), style: ConsoleText.meta),
          ],
        ),
        const SizedBox(height: DeliverySpacing.md),
        ConsoleTable(
          minWidth: 1240,
          columns: <ConsoleColumn>[
            ConsoleColumn(label: t.payrollColRider, flex: 1),
            ConsoleColumn(label: t.payrollColBase, width: 105),
            ConsoleColumn(label: t.payrollColDelivery, width: 110),
            ConsoleColumn(label: t.payrollKpiBonuses, width: 100),
            ConsoleColumn(label: t.payrollColTips, width: 90),
            ConsoleColumn(label: t.payrollColDeductions, width: 110),
            ConsoleColumn(label: t.payrollColGross, width: 105),
            ConsoleColumn(label: t.payrollColNet, width: 110),
            ConsoleColumn(label: t.payrollColStatus, width: 150),
            ConsoleColumn(label: t.payrollColActions, width: 110, alignRight: true),
          ],
          empty: Text(t.payrollNobody, style: ConsoleText.cellMuted),
          rows: <ConsoleTableRow>[
            for (final Payslip slip in run.payslips) _row(t, run, slip),
          ],
          footer: Text(
            t.payrollTableNote,
            style: ConsoleText.meta.copyWith(color: DeliveryColors.faint),
          ),
        ),
      ],
    );
  }

  ConsoleTableRow _row(DeliveryStrings t, PayRun run, Payslip slip) {
    final String who = slip.name ?? shortRef(slip.riderRef);
    final String currency = run.currency;
    final bool bonus = (slip.bonuses?.minorUnits ?? 0) > 0;
    return ConsoleTableRow(
      onTap: () => _openPayslip(run, slip),
      cells: <Widget>[
        Row(
          children: <Widget>[
            ConsoleAvatar(name: who, size: 28),
            const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
            Flexible(
              child: Text(who, overflow: TextOverflow.ellipsis, style: ConsoleText.cellStrong),
            ),
          ],
        ),
        // Hours that were not read are unknown, not an hour's pay of nothing.
        if (slip.hoursUnknown)
          Tooltip(
            message: t.payrollHoursUnknown,
            child: Text('—', style: ConsoleText.cellMuted),
          )
        else
          Text(cashText(slip.basePay, currency), style: ConsoleText.cell),
        Text(cashText(slip.deliveryPay, currency), style: ConsoleText.cell),
        Text(
          cashText(slip.bonuses, currency),
          style: ConsoleText.cell.copyWith(color: bonus ? DeliveryAccent.positive.onTint : null),
        ),
        Tooltip(
          message: t.payrollTipsNote,
          child: Text(cashText(slip.tips, currency), style: ConsoleText.cellMuted),
        ),
        Text(
          deductionText(slip.deductions, currency),
          style: ConsoleText.cell.copyWith(color: DeliveryAccent.critical.onTint),
        ),
        Text(cashText(slip.gross, currency), style: ConsoleText.cell),
        Text(
          cashText(slip.net, currency),
          style: ConsoleText.cellStrong.copyWith(
            color: slip.owesCompany ? DeliveryAccent.critical.onTint : null,
          ),
        ),
        payslipPill(t, slip.status),
        ConsoleButton(
          label: t.payrollPayslip,
          tone: ConsoleButtonTone.outlined,
          onPressed: () => _openPayslip(run, slip),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------------- actions

  /// Sends one change and says what happened. Never throws. The page is read again afterwards
  /// either way: after a refusal the run is not what it was when the button was pressed.
  Future<void> _change(Future<PayRun> Function() call, {String? done}) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String currency = _run?.currency ?? _periods?.currency ?? '';
    setState(() => _busy = true);
    String? message = done;
    DateTime? keep = _period?.from;
    try {
      final PayRun run = await call();
      keep = run.from ?? keep;
    } on PayrollRefused catch (refused) {
      message = refusalText(t, refused, currency);
    } catch (_) {
      message = t.payrollErrFailed;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (message != null) messenger.showSnackBar(SnackBar(content: Text(message)));
    await _load(keep: keep);
  }

  Future<void> _start(PayPeriod period) => _change(() => widget.api.start(period.from));

  Future<void> _recompute(PayRun run) =>
      _change(() => widget.api.recompute(run.id), done: DeliveryStrings.of(context).payrollDone);

  Future<void> _approve(PayRun run) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool? withoutHours = await confirmApproval(context, run: run);
    if (withoutHours == null || !mounted) return;
    await _change(
      () => widget.api.approve(run.id, revision: run.revision, acknowledgeMissingHours: withoutHours),
      done: t.payrollApproved,
    );
  }

  Future<void> _payAll(PayRun run) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<Payslip> due =
        run.payslips.where((Payslip s) => s.status == PayslipStatus.due).toList(growable: false);
    // The server's own figures, summed in cents, and sent back as the total confirmed: if anything
    // was recorded meanwhile the server refuses rather than paying a total nobody saw.
    final Money? total = sumMoney(due.map((Payslip s) => s.net));
    if (due.isEmpty || total == null) return;
    final ({CashMethod method, String? reference})? choice = await askPayment(
      context,
      title: t.payrollPayAllTitle(due.length, cashText(total, run.currency)),
      body: t.payrollPayAllBody,
    );
    if (choice == null || !mounted) return;
    await _change(
      () => widget.api.payAll(run.id,
          expectedTotal: total, method: choice.method, reference: choice.reference),
      done: t.payrollDone,
    );
  }

  Future<void> _discard(PayRun run) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (!await confirmDiscard(context) || !mounted) return;
    setState(() => _busy = true);
    String message = t.payrollDone;
    try {
      await widget.api.discard(run.id);
    } on PayrollRefused catch (refused) {
      message = refusalText(t, refused, run.currency);
    } catch (_) {
      message = t.payrollErrFailed;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(content: Text(message)));
    await _load(keep: run.from);
  }

  Future<void> _editRules() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final PayPolicyPage page;
    try {
      page = await widget.api.policy();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(t.payrollLoadFailed)));
      return;
    }
    if (!mounted) return;
    final PayRulesDraft? draft = await editPayRules(context, page: page);
    if (draft == null || !mounted) return;

    setState(() => _busy = true);
    String message = t.payrollDone;
    try {
      await widget.api.savePolicy(
        effectiveFrom: draft.effectiveFrom,
        payCycle: draft.cycle,
        perDeliveryRate: draft.perDelivery,
        hourlyRate: draft.hourly,
        payManualHours: draft.payTyped,
        overtimeMultiplier: draft.overtime,
        lateDeduction: draft.late,
        absenceDeduction: draft.absence,
      );
    } on PayrollRefused catch (refused) {
      message = refusalText(t, refused, page.currency);
    } catch (_) {
      message = t.payrollErrFailed;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.showSnackBar(SnackBar(content: Text(message)));
    await _load();
  }

  Future<void> _openPayslip(PayRun run, Payslip slip) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String who = slip.name ?? shortRef(slip.riderRef);
    final PayslipAction? action = await showConsoleDrawer<PayslipAction>(
      context: context,
      title: who,
      subtitle: t.payrollPayslipSubtitle(payDay(context, run.from), payDay(context, run.to)),
      badge: payslipPill(t, slip.status),
      width: 520,
      builder: (BuildContext context) => PayslipPanel(run: run, slip: slip),
    );
    if (action == null || !mounted || _busy) return;

    switch (action.kind) {
      case PayslipActionKind.addBonus:
      case PayslipActionKind.addDeduction:
        final PayLineKind kind =
            action.kind == PayslipActionKind.addBonus ? PayLineKind.bonus : PayLineKind.deduction;
        final ({String label, String amount})? line = await askPayLine(
          context,
          title: kind == PayLineKind.bonus
              ? t.payrollLineDialogBonus(who)
              : t.payrollLineDialogDeduction(who),
        );
        if (line == null || !mounted) return;
        await _change(
          () => widget.api.addLine(run.id,
              riderRef: slip.riderRef, kind: kind, label: line.label, amount: line.amount),
          done: t.payrollDone,
        );
      case PayslipActionKind.removeLine:
        final String? lineId = action.lineId;
        if (lineId == null) return;
        await _change(() => widget.api.removeLine(run.id, lineId), done: t.payrollDone);
      case PayslipActionKind.markPaid:
        final ({CashMethod method, String? reference})? paid = await askPayment(
          context,
          title: t.payrollPaidTitle(who, cashText(slip.net, run.currency)),
          body: t.payrollPaidBody,
        );
        if (paid == null || !mounted) return;
        await _change(
          () => widget.api.markPaid(run.id, slip.id, method: paid.method, reference: paid.reference),
          done: t.payrollDone,
        );
      case PayslipActionKind.markFailed:
        final String? reason = await askFailure(context, name: who);
        if (reason == null || !mounted) return;
        await _change(() => widget.api.markFailed(run.id, slip.id, reason: reason),
            done: t.payrollDone);
      case PayslipActionKind.addCorrection:
        final ({PayLineKind kind, String amount, String reason})? correction =
            await askCorrection(context, name: who);
        if (correction == null || !mounted) return;
        await _change(
          () => widget.api.addCorrection(run.id,
              riderRef: slip.riderRef,
              kind: correction.kind,
              amount: correction.amount,
              reason: correction.reason),
          done: t.payrollDone,
        );
    }
  }

  void _export(DeliveryStrings t, PayRun run) {
    final DateTime? from = run.from;
    final String file = 'payroll-${from == null ? run.id : CarrierCashApi.isoDate(from)}.csv';
    widget.saveFile(file, payrollCsv(t, run));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.payrollExported(file))));
  }
}
