/// The pieces of the carrier payroll page (Figma 112:1162): how its figures, periods and statuses are
/// written, the payslip drawer, the confirmations and forms it asks through, and the CSV export.
///
/// Kept apart from the screen so the screen reads as what the page does, and so a payslip, a status
/// and a refusal are worded the same way wherever they appear — the approval confirmation especially,
/// because it is the last thing somebody reads before a period's pay is frozen and riders' cash is
/// kept from their pay for good.
library;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';
import 'cash_parts.dart';

/// A calendar day as the reader's language writes it, like "Oct 1, 2026". Unknown is a dash.
String payDay(BuildContext context, DateTime? day) =>
    day == null ? '—' : MaterialLocalizations.of(context).formatShortDate(day);

/// A moment in the reader's own clock: the day and the time.
String payStamp(BuildContext context, DateTime? when) {
  if (when == null) return '—';
  final MaterialLocalizations words = MaterialLocalizations.of(context);
  return '${words.formatShortDate(when)} ${words.formatTimeOfDay(TimeOfDay.fromDateTime(when))}';
}

/// Hours to two places from exact seconds, for reading only — the pay was worked out from the
/// seconds on the server. Unknown stays a dash.
String hoursText(int? seconds) {
  if (seconds == null) return '—';
  final int hundredths = (seconds * 100 + 1800) ~/ 3600;
  return '${hundredths ~/ 100}.${(hundredths % 100).toString().padLeft(2, '0')}';
}

/// A deduction as the ledger draws it: a minus in front of anything taken, a plain zero otherwise.
String deductionText(Money? money, String currency) {
  if (money == null) return '—';
  return money.isZero || money.isNegative || !money.isReadable
      ? cashText(money, currency)
      : '-${cashText(money, currency)}';
}

/// How many days a period has, counted on the calendar — never through a clock change, which would
/// make the second half of October a day short.
int periodDays(DateTime? from, DateTime? to) {
  if (from == null || to == null) return 0;
  return DateTime.utc(to.year, to.month, to.day)
          .difference(DateTime.utc(from.year, from.month, from.day))
          .inDays +
      1;
}

/// A payslip's status as the table's pill. Only a failed payment is critical; a payment still to
/// make is caution, and a payslip with nothing to pay is neither.
Widget payslipPill(DeliveryStrings t, PayslipStatus status) => switch (status) {
      PayslipStatus.draft => ConsoleStatusPill(label: t.payrollStatusDraft),
      PayslipStatus.due =>
        ConsoleStatusPill(label: t.payrollStatusDue, accent: DeliveryAccent.caution),
      PayslipStatus.nothingDue => ConsoleStatusPill(label: t.payrollStatusNothingDue),
      PayslipStatus.paid =>
        ConsoleStatusPill(label: t.payrollStatusPaid, accent: DeliveryAccent.positive),
      PayslipStatus.failed =>
        ConsoleStatusPill(label: t.payrollStatusFailed, accent: DeliveryAccent.critical),
      PayslipStatus.unknown => const ConsoleStatusPill(label: '—'),
    };

/// Where a period's run is, in a word. Null is a period with no run yet.
String runStateText(DeliveryStrings t, PayRunStatus? status) => switch (status) {
      null => t.payrollNotStarted,
      PayRunStatus.draft => t.payrollStatusDraft,
      PayRunStatus.approved => t.payrollRunApproved,
      PayRunStatus.paid => t.payrollRunPaid,
      PayRunStatus.unknown => '—',
    };

/// What one payslip line is, in a sentence: "17 deliveries × $2.35".
String payLineText(DeliveryStrings t, PayLine line, String currency) {
  final String quantity = line.quantity ?? '—';
  final String rate = line.rate == null ? '—' : cashText(Money(line.rate!), currency);
  final String label = line.label ?? '—';
  final bool correction = line.source == PayLineSource.adjustment;
  return switch (line.kind) {
    PayLineKind.deliveries => t.payrollLineDeliveries(quantity, rate),
    PayLineKind.hours => t.payrollLineHours(quantity, rate),
    PayLineKind.overtime => t.payrollLineOvertime(quantity, rate),
    PayLineKind.manualHours => line.rate == null
        ? t.payrollLineTypedUnpaid(quantity)
        : t.payrollLineTyped(quantity, rate),
    PayLineKind.lateDeduction => t.payrollLineLate(quantity, rate),
    PayLineKind.absenceDeduction => t.payrollLineAbsence(quantity, rate),
    PayLineKind.cashHeld => t.payrollLineCash,
    PayLineKind.bonus => correction ? t.payrollLineCorrection(label) : t.payrollLineBonus(label),
    PayLineKind.deduction =>
      correction ? t.payrollLineCorrection(label) : t.payrollLineDeduction(label),
    PayLineKind.unknown => t.payrollLineOther,
  };
}

/// Why the server did not do what was asked, in a sentence somebody can act on.
String refusalText(DeliveryStrings t, PayrollRefused refused, String currency) =>
    switch (refused.code) {
      'FIGURES_CHANGED' => t.payrollErrFiguresChanged,
      'NEEDS_ACKNOWLEDGEMENT' => t.payrollErrNeedsHours,
      'CASH_CHANGED' => t.payrollErrCashChanged,
      'TOTAL_CHANGED' => t.payrollErrTotalChanged(cashText(refused.current, currency)),
      'NOT_A_PERIOD_START' ||
      'CALENDAR_CHANGE_NOT_ON_THE_FIRST' ||
      'CONFLICTS_WITH_LATER_RULES' ||
      'PERIOD_APPROVED' =>
        t.payrollErrRulesStart,
      _ => t.payrollErrRefused,
    };

final RegExp _amountShape = RegExp(r'^\d{1,6}(\.\d{1,2})?$');

/// Null when [text] is an amount a person may type here: whole or to the cent, not absurd, and more
/// than nothing unless [zeroAllowed]. The server checks the same and rounds nothing.
String? amountProblem(DeliveryStrings t, String text, {bool zeroAllowed = false}) {
  final String value = text.trim();
  if (!_amountShape.hasMatch(value)) return t.payrollAmountInvalid;
  if (!zeroAllowed && (Money(value).minorUnits ?? 0) <= 0) return t.payrollAmountInvalid;
  return null;
}

// ------------------------------------------------------------------------------ the drawer

enum PayslipActionKind { addBonus, addDeduction, removeLine, markPaid, markFailed, addCorrection }

/// What the payslip drawer was closed to do. The page does it, so one place owns the busy state and
/// what is said afterwards.
typedef PayslipAction = ({PayslipActionKind kind, String? lineId});

/// One rider's payslip, broken down, with only the actions the run allows.
class PayslipPanel extends StatelessWidget {
  const PayslipPanel({super.key, required this.run, required this.slip});

  final PayRun run;
  final Payslip slip;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String currency = run.currency;
    final List<PayLine> earned =
        slip.lines.where((PayLine l) => !l.kind.isDeduction).toList(growable: false);
    final List<PayLine> taken =
        slip.lines.where((PayLine l) => l.kind.isDeduction).toList(growable: false);
    final List<PayCorrection> corrections = run.corrections
        .where((PayCorrection c) => c.riderRef == slip.riderRef)
        .toList(growable: false);
    final bool frozen =
        run.status == PayRunStatus.approved || run.status == PayRunStatus.paid;

    void close(PayslipActionKind kind, [String? lineId]) =>
        Navigator.of(context).pop<PayslipAction>((kind: kind, lineId: lineId));

    Widget lines(List<PayLine> list, {required bool deductions}) {
      if (list.isEmpty) return Text('—', style: ConsoleText.cellMuted);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final PayLine line in list)
            _AmountRow(
              label: payLineText(t, line, currency),
              amount: deductions
                  ? deductionText(line.amount, currency)
                  : cashText(line.amount, currency),
              critical: deductions,
              removeTooltip: t.payrollRemove,
              // Only a named line somebody added, and only while the run is a draft.
              onRemove: run.isDraft && line.removable
                  ? () => close(PayslipActionKind.removeLine, line.id)
                  : null,
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ConsoleDrawerSection(
          first: true,
          title: t.payrollSectionPay,
          child: lines(earned, deductions: false),
        ),
        ConsoleDrawerSection(
          title: t.payrollColDeductions,
          child: lines(taken, deductions: true),
        ),
        ConsoleDrawerSection(
          title: t.payrollSectionSummary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _AmountRow(label: t.payrollColGross, amount: cashText(slip.gross, currency)),
              _AmountRow(
                label: t.payrollColDeductions,
                amount: deductionText(slip.deductions, currency),
              ),
              _AmountRow(
                label: t.payrollColNet,
                amount: cashText(slip.net, currency),
                strong: true,
                critical: slip.owesCompany,
              ),
              if (slip.owesCompany && slip.net != null) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                SoftNote(
                  text: t.payrollOwes(cashText(Money(slip.net!.unsigned), currency)),
                  accent: DeliveryAccent.caution,
                  icon: Icons.info_outline,
                ),
              ],
              if (slip.cashNotNetted) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                SoftNote(
                  text: t.payrollCashKept(cashText(slip.cashHeld, currency)),
                  accent: DeliveryAccent.caution,
                  icon: Icons.payments_outlined,
                ),
              ],
              if ((slip.tips?.minorUnits ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: DeliverySpacing.sm),
                  child: Text(
                    t.payrollTipsInfo(cashText(slip.tips, currency)),
                    style: ConsoleText.meta,
                  ),
                ),
            ],
          ),
        ),
        if (run.policy?.needsAttendance ?? false)
          ConsoleDrawerSection(
            title: t.payrollSectionAttendance,
            child: slip.hoursUnknown
                ? Text(
                    t.payrollHoursUnknown,
                    style: ConsoleText.body.copyWith(color: DeliveryColors.muted),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        t.payrollHoursFacts(hoursText(slip.workedSeconds),
                            hoursText(slip.manualSeconds), hoursText(slip.overtimeSeconds)),
                        style: ConsoleText.body,
                      ),
                      const SizedBox(height: DeliverySpacing.xs),
                      Text(
                        t.payrollDaysFacts(slip.lates ?? 0, slip.absences ?? 0),
                        style: ConsoleText.meta,
                      ),
                    ],
                  ),
          ),
        if (slip.status == PayslipStatus.paid || slip.status == PayslipStatus.failed)
          ConsoleDrawerSection(
            title: t.payrollSectionPayment,
            child: _payment(context, t),
          ),
        if (corrections.isNotEmpty)
          ConsoleDrawerSection(
            title: t.payrollCorrections,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final PayCorrection c in corrections)
                  _AmountRow(
                    label: '${t.payrollLineCorrection(c.reason)} · '
                        '${c.appliedRunId == null ? t.payrollCorrectionWaiting : t.payrollCorrectionPaid}',
                    amount: c.kind.isDeduction
                        ? deductionText(c.amount, currency)
                        : cashText(c.amount, currency),
                    critical: c.kind.isDeduction,
                  ),
              ],
            ),
          ),
        const SizedBox(height: DeliverySpacing.md),
        Wrap(
          spacing: DeliverySpacing.sm,
          runSpacing: DeliverySpacing.sm,
          children: <Widget>[
            if (run.isDraft) ...<Widget>[
              ConsoleButton(
                label: t.payrollAddBonus,
                icon: Icons.add,
                tone: ConsoleButtonTone.outlined,
                onPressed: () => close(PayslipActionKind.addBonus),
              ),
              ConsoleButton(
                label: t.payrollAddDeduction,
                icon: Icons.remove,
                tone: ConsoleButtonTone.outlined,
                onPressed: () => close(PayslipActionKind.addDeduction),
              ),
            ],
            if (frozen && slip.outstanding) ...<Widget>[
              ConsolePrimaryButton(
                label: t.payrollMarkPaid,
                icon: Icons.check,
                onPressed: () => close(PayslipActionKind.markPaid),
              ),
              if (slip.status == PayslipStatus.due)
                ConsoleSoftButton(
                  label: t.payrollMarkFailed,
                  icon: Icons.error_outline,
                  onPressed: () => close(PayslipActionKind.markFailed),
                ),
            ],
            if (frozen)
              ConsoleButton(
                label: t.payrollAddCorrection,
                icon: Icons.edit_note,
                tone: ConsoleButtonTone.outlined,
                onPressed: () => close(PayslipActionKind.addCorrection),
              ),
          ],
        ),
      ],
    );
  }

  Widget _payment(BuildContext context, DeliveryStrings t) {
    if (slip.status == PayslipStatus.failed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.payrollFailedBecause(slip.failureReason ?? '—'),
            style: ConsoleText.body.copyWith(color: DeliveryAccent.critical.onTint),
          ),
          if (slip.failedByName != null)
            Text(t.payrollRecordedBy(slip.failedByName!), style: ConsoleText.meta),
        ],
      );
    }
    final CashMethod? method = slip.paidMethod;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          t.payrollPaidOn(payStamp(context, slip.paidAt), method == null ? '—' : methodLabel(t, method)),
          style: ConsoleText.body,
        ),
        if (slip.paidReference != null) Text(slip.paidReference!, style: ConsoleText.meta),
        if (slip.paidByName != null)
          Text(t.payrollRecordedBy(slip.paidByName!), style: ConsoleText.meta),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    this.strong = false,
    this.critical = false,
    this.onRemove,
    this.removeTooltip,
  });

  final String label;
  final String amount;
  final bool strong;
  final bool critical;
  final VoidCallback? onRemove;
  final String? removeTooltip;

  @override
  Widget build(BuildContext context) {
    final TextStyle base = strong ? ConsoleText.cellStrong : ConsoleText.cell;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: base)),
          if (onRemove != null) ...<Widget>[
            ConsoleIconAction(icon: Icons.close, tooltip: removeTooltip ?? '', onPressed: onRemove),
            const SizedBox(width: DeliverySpacing.xs),
          ],
          Text(
            amount,
            style: base.copyWith(color: critical ? DeliveryAccent.critical.onTint : null),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------- the dialogs

/// A named bonus or deduction: what it is for, and how much.
Future<({String label, String amount})?> askPayLine(BuildContext context,
    {required String title}) {
  return showDialog<({String label, String amount})>(
    context: context,
    builder: (BuildContext context) => _PayLineDialog(title: title),
  );
}

class _PayLineDialog extends StatefulWidget {
  const _PayLineDialog({required this.title});

  final String title;

  @override
  State<_PayLineDialog> createState() => _PayLineDialogState();
}

class _PayLineDialogState extends State<_PayLineDialog> {
  final TextEditingController _label = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  bool _tried = false;

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ConsoleSectionLabel(t.payrollLabelField),
            TextField(
              controller: _label,
              maxLength: 120,
              onChanged: (String _) => setState(() {}),
              decoration: InputDecoration(
                errorText: _tried && _label.text.trim().isEmpty ? t.payrollRequired : null,
              ),
            ),
            ConsoleSectionLabel(t.payrollAmountField),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (String _) => setState(() {}),
              decoration: InputDecoration(
                hintText: '0.00',
                errorText: _tried ? amountProblem(t, _amount.text) : null,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.cancel)),
        FilledButton(onPressed: () => _submit(t), child: Text(t.payrollSave)),
      ],
    );
  }

  void _submit(DeliveryStrings t) {
    setState(() => _tried = true);
    if (_label.text.trim().isEmpty || amountProblem(t, _amount.text) != null) return;
    Navigator.of(context).pop((label: _label.text.trim(), amount: _amount.text.trim()));
  }
}

/// A correction to an approved payslip: which way, how much, and why.
Future<({PayLineKind kind, String amount, String reason})?> askCorrection(BuildContext context,
    {required String name}) {
  return showDialog<({PayLineKind kind, String amount, String reason})>(
    context: context,
    builder: (BuildContext context) => _CorrectionDialog(name: name),
  );
}

class _CorrectionDialog extends StatefulWidget {
  const _CorrectionDialog({required this.name});

  final String name;

  @override
  State<_CorrectionDialog> createState() => _CorrectionDialogState();
}

class _CorrectionDialogState extends State<_CorrectionDialog> {
  PayLineKind _kind = PayLineKind.bonus;
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  bool _tried = false;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return AlertDialog(
      title: Text(t.payrollCorrectionTitle(widget.name)),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(t.payrollCorrectionBody),
            const SizedBox(height: DeliverySpacing.md),
            ConsoleSelect(
              label: _kind == PayLineKind.bonus ? t.payrollCorrectionMore : t.payrollCorrectionLess,
              icon: Icons.swap_vert,
              options: <ConsoleOption>[
                ConsoleOption(label: t.payrollCorrectionMore, value: PayLineKind.bonus.wire),
                ConsoleOption(label: t.payrollCorrectionLess, value: PayLineKind.deduction.wire),
              ],
              onSelected: (String? wire) => setState(() => _kind =
                  wire == PayLineKind.deduction.wire ? PayLineKind.deduction : PayLineKind.bonus),
            ),
            const SizedBox(height: DeliverySpacing.md),
            ConsoleSectionLabel(t.payrollAmountField),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (String _) => setState(() {}),
              decoration: InputDecoration(
                hintText: '0.00',
                errorText: _tried ? amountProblem(t, _amount.text) : null,
              ),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            ConsoleSectionLabel(t.payrollReasonField),
            TextField(
              controller: _reason,
              maxLength: 500,
              onChanged: (String _) => setState(() {}),
              decoration: InputDecoration(
                errorText: _tried && _reason.text.trim().isEmpty ? t.payrollRequired : null,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.cancel)),
        FilledButton(onPressed: () => _submit(t), child: Text(t.payrollSave)),
      ],
    );
  }

  void _submit(DeliveryStrings t) {
    setState(() => _tried = true);
    if (amountProblem(t, _amount.text) != null || _reason.text.trim().isEmpty) return;
    Navigator.of(context)
        .pop((kind: _kind, amount: _amount.text.trim(), reason: _reason.text.trim()));
  }
}

/// How a payment was made, recorded after the company made it. Used for one rider and for all.
Future<({CashMethod method, String? reference})?> askPayment(
  BuildContext context, {
  required String title,
  required String body,
}) {
  return showDialog<({CashMethod method, String? reference})>(
    context: context,
    builder: (BuildContext context) => _PaymentDialog(title: title, body: body),
  );
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.title, required this.body});

  final String title;
  final String body;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  CashMethod _method = CashMethod.cash;
  final TextEditingController _reference = TextEditingController();

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.body),
            const SizedBox(height: DeliverySpacing.md),
            ConsoleSectionLabel(t.carrCashMethodLabel),
            const SizedBox(height: 6),
            CashMethodSelect(
              value: _method,
              onChanged: (CashMethod m) => setState(() => _method = m),
            ),
            const SizedBox(height: DeliverySpacing.md),
            ConsoleSectionLabel(t.payrollReferenceField),
            TextField(controller: _reference, maxLength: 120),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.cancel)),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((
            method: _method,
            reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
          )),
          child: Text(t.payrollRecordYes),
        ),
      ],
    );
  }
}

/// Why a payment did not go through.
Future<String?> askFailure(BuildContext context, {required String name}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => _FailureDialog(name: name),
  );
}

class _FailureDialog extends StatefulWidget {
  const _FailureDialog({required this.name});

  final String name;

  @override
  State<_FailureDialog> createState() => _FailureDialogState();
}

class _FailureDialogState extends State<_FailureDialog> {
  final TextEditingController _reason = TextEditingController();
  bool _tried = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return AlertDialog(
      title: Text(t.payrollFailedTitle(widget.name)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(t.payrollFailedBody),
            const SizedBox(height: DeliverySpacing.md),
            ConsoleSectionLabel(t.payrollReasonField),
            TextField(
              controller: _reason,
              maxLength: 500,
              onChanged: (String _) => setState(() {}),
              decoration: InputDecoration(
                errorText: _tried && _reason.text.trim().isEmpty ? t.payrollRequired : null,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.cancel)),
        FilledButton(
          onPressed: () {
            setState(() => _tried = true);
            if (_reason.text.trim().isEmpty) return;
            Navigator.of(context).pop(_reason.text.trim());
          },
          child: Text(t.payrollRecordYes),
        ),
      ],
    );
  }
}

/// Asks before a period's pay is frozen. Null when cancelled; otherwise whether the approver said to
/// go ahead without missing hours — which is required, not offered, when hours are missing.
Future<bool?> confirmApproval(BuildContext context, {required PayRun run}) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) => _ApprovalDialog(run: run),
  );
}

class _ApprovalDialog extends StatefulWidget {
  const _ApprovalDialog({required this.run});

  final PayRun run;

  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  bool _withoutHours = false;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final PayRun run = widget.run;
    final bool netsCash = (run.totals.cashNetted?.minorUnits ?? 0) > 0;
    return AlertDialog(
      title: Text(t.payrollApproveTitle(payDay(context, run.from), payDay(context, run.to))),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(t.payrollApproveBody(run.totals.riders, cashText(run.totals.payable, run.currency))),
            if (netsCash) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              Text(t.payrollApproveCash(cashText(run.totals.cashNetted, run.currency))),
            ],
            if (run.needsAcknowledgement) ...<Widget>[
              const SizedBox(height: DeliverySpacing.md),
              SoftNote(
                text: t.payrollHoursMissing,
                accent: DeliveryAccent.caution,
                icon: Icons.timer_off_outlined,
              ),
              CheckboxListTile(
                value: _withoutHours,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (bool? on) => setState(() => _withoutHours = on ?? false),
                title: Text(t.payrollApproveWithoutHours),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.cancel)),
        FilledButton(
          onPressed: run.needsAcknowledgement && !_withoutHours
              ? null
              : () => Navigator.of(context).pop(_withoutHours),
          child: Text(t.payrollApproveYes),
        ),
      ],
    );
  }
}

/// Asks before a draft is thrown away.
Future<bool> confirmDiscard(BuildContext context) async {
  final DeliveryStrings t = DeliveryStrings.of(context);
  final bool? yes = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(t.payrollDiscardTitle),
      content: Text(t.payrollDiscardBody),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t.cancel)),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t.payrollDiscardYes),
        ),
      ],
    ),
  );
  return yes ?? false;
}

/// The rules form as it was saved: amounts exactly as typed.
typedef PayRulesDraft = ({
  DateTime effectiveFrom,
  PayCycle cycle,
  String perDelivery,
  String? hourly,
  bool payTyped,
  String overtime,
  String late,
  String absence,
});

/// The company's pay rules, starting from what is in force (or the defaults) and offering only the
/// start days the server said are open.
Future<PayRulesDraft?> editPayRules(BuildContext context, {required PayPolicyPage page}) {
  return showDialog<PayRulesDraft>(
    context: context,
    builder: (BuildContext context) => _RulesDialog(page: page),
  );
}

class _RulesDialog extends StatefulWidget {
  const _RulesDialog({required this.page});

  final PayPolicyPage page;

  @override
  State<_RulesDialog> createState() => _RulesDialogState();
}

class _RulesDialogState extends State<_RulesDialog> {
  late PayCycle _cycle;
  DateTime? _start;
  late bool _payTyped;
  late final TextEditingController _perDelivery;
  late final TextEditingController _hourly;
  late final TextEditingController _overtime;
  late final TextEditingController _late;
  late final TextEditingController _absence;
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    final PayPolicy? now = widget.page.current;
    final PayPolicyDefaults defaults = widget.page.defaults;
    final PayCycle cycle = now?.payCycle ?? defaults.payCycle;
    _cycle = cycle == PayCycle.unknown ? PayCycle.semiMonthly : cycle;
    _start = _starts.isEmpty ? null : _starts.first;
    _payTyped = now?.payManualHours ?? defaults.payManualHours;
    _perDelivery = TextEditingController(text: now?.perDeliveryRate?.amount ?? '');
    _hourly = TextEditingController(text: now?.hourlyRate?.amount ?? '');
    _overtime =
        TextEditingController(text: now?.overtimeMultiplier ?? defaults.overtimeMultiplier ?? '1.00');
    _late = TextEditingController(
        text: (now?.lateDeduction ?? defaults.lateDeduction)?.amount ?? '0.00');
    _absence = TextEditingController(
        text: (now?.absenceDeduction ?? defaults.absenceDeduction)?.amount ?? '0.00');
  }

  @override
  void dispose() {
    _perDelivery.dispose();
    _hourly.dispose();
    _overtime.dispose();
    _late.dispose();
    _absence.dispose();
    super.dispose();
  }

  List<DateTime> get _starts => widget.page.startOptions[_cycle] ?? const <DateTime>[];

  String? _overtimeProblem(DeliveryStrings t) {
    final String value = _overtime.text.trim();
    final int? cents =
        RegExp(r'^\d(\.\d{1,2})?$').hasMatch(value) ? Money(value).minorUnits : null;
    return cents == null || cents < 100 || cents > 500 ? t.payrollMultiplierInvalid : null;
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final PayPolicy? now = widget.page.current;
    return AlertDialog(
      title: Text(t.payrollRulesButton),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                now == null ? t.payrollRulesNone : t.payrollRulesNow(payDay(context, now.effectiveFrom)),
                style: ConsoleText.meta,
              ),
              for (final PayPolicy next in widget.page.scheduled)
                Text(t.payrollRulesNext(payDay(context, next.effectiveFrom)), style: ConsoleText.meta),
              const SizedBox(height: DeliverySpacing.md),
              ConsoleSectionLabel(t.payrollRulesCycle),
              const SizedBox(height: 6),
              ConsoleSelect(
                label: _cycle == PayCycle.monthly ? t.payrollCycleMonthly : t.payrollCycleSemiMonthly,
                icon: Icons.event_repeat,
                options: <ConsoleOption>[
                  ConsoleOption(label: t.payrollCycleSemiMonthly, value: PayCycle.semiMonthly.wire),
                  ConsoleOption(label: t.payrollCycleMonthly, value: PayCycle.monthly.wire),
                ],
                onSelected: (String? wire) => setState(() {
                  _cycle = PayCycle.fromWire(wire) == PayCycle.monthly
                      ? PayCycle.monthly
                      : PayCycle.semiMonthly;
                  _start = _starts.isEmpty ? null : _starts.first;
                }),
              ),
              const SizedBox(height: DeliverySpacing.md),
              ConsoleSectionLabel(t.payrollRulesStart),
              const SizedBox(height: 6),
              if (_starts.isEmpty)
                Text(t.payrollRulesNoStart, style: ConsoleText.meta)
              else
                ConsoleSelect(
                  label: payDay(context, _start),
                  icon: Icons.calendar_today_outlined,
                  options: <ConsoleOption>[
                    for (final DateTime day in _starts)
                      ConsoleOption(label: payDay(context, day), value: CarrierCashApi.isoDate(day)),
                  ],
                  onSelected: (String? iso) => setState(() {
                    for (final DateTime day in _starts) {
                      if (CarrierCashApi.isoDate(day) == iso) _start = day;
                    }
                  }),
                ),
              const SizedBox(height: DeliverySpacing.md),
              _field(t.payrollRulesPerDelivery, _perDelivery,
                  _tried ? amountProblem(t, _perDelivery.text, zeroAllowed: true) : null),
              _field(
                t.payrollRulesHourly,
                _hourly,
                _tried && _hourly.text.trim().isNotEmpty
                    ? amountProblem(t, _hourly.text, zeroAllowed: true)
                    : null,
                hint: t.payrollRulesHourlyHint,
              ),
              Row(
                children: <Widget>[
                  Expanded(child: Text(t.payrollRulesTyped, style: ConsoleText.body)),
                  Switch(
                    value: _payTyped,
                    onChanged: (bool on) => setState(() => _payTyped = on),
                  ),
                ],
              ),
              _field(t.payrollRulesOvertime, _overtime, _tried ? _overtimeProblem(t) : null),
              _field(t.payrollRulesLate, _late,
                  _tried ? amountProblem(t, _late.text, zeroAllowed: true) : null),
              _field(t.payrollRulesAbsence, _absence,
                  _tried ? amountProblem(t, _absence.text, zeroAllowed: true) : null),
              const SizedBox(height: DeliverySpacing.sm),
              Text(t.payrollRulesNote, style: ConsoleText.meta),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.cancel)),
        FilledButton(onPressed: _start == null ? null : () => _save(t), child: Text(t.payrollRulesSave)),
      ],
    );
  }

  Widget _field(String label, TextEditingController controller, String? error, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ConsoleSectionLabel(label),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (String _) => setState(() {}),
            decoration: InputDecoration(hintText: hint, errorText: error),
          ),
        ],
      ),
    );
  }

  void _save(DeliveryStrings t) {
    setState(() => _tried = true);
    final DateTime? start = _start;
    final String hourly = _hourly.text.trim();
    if (start == null ||
        amountProblem(t, _perDelivery.text, zeroAllowed: true) != null ||
        (hourly.isNotEmpty && amountProblem(t, hourly, zeroAllowed: true) != null) ||
        _overtimeProblem(t) != null ||
        amountProblem(t, _late.text, zeroAllowed: true) != null ||
        amountProblem(t, _absence.text, zeroAllowed: true) != null) {
      return;
    }
    Navigator.of(context).pop((
      effectiveFrom: start,
      cycle: _cycle,
      perDelivery: _perDelivery.text.trim(),
      hourly: hourly.isEmpty ? null : hourly,
      payTyped: _payTyped,
      overtime: _overtime.text.trim(),
      late: _late.text.trim(),
      absence: _absence.text.trim(),
    ));
  }
}

// -------------------------------------------------------------------------------- the export

/// The run's payslips as CSV: one header line, one line per rider, amounts exactly as the server
/// wrote them, and every text cell through [csvText] so a rider's name never runs as a formula.
/// Base pay is blank where hours were not read, as the table shows a dash.
String payrollCsv(DeliveryStrings t, PayRun run) {
  String status(Payslip s) => switch (s.status) {
        PayslipStatus.draft => t.payrollStatusDraft,
        PayslipStatus.due => t.payrollStatusDue,
        PayslipStatus.nothingDue => t.payrollStatusNothingDue,
        PayslipStatus.paid => t.payrollStatusPaid,
        PayslipStatus.failed => t.payrollStatusFailed,
        PayslipStatus.unknown => '',
      };

  final List<List<String>> rows = <List<String>>[
    <String>[
      for (final String heading in <String>[
        t.payrollColRider,
        t.carrCashCsvRiderId,
        t.payrollColBase,
        t.payrollColDelivery,
        t.payrollKpiBonuses,
        t.payrollColTips,
        t.payrollColDeductions,
        t.payrollColGross,
        t.payrollColNet,
        t.payrollColStatus,
      ])
        csvText(heading),
    ],
    for (final Payslip s in run.payslips)
      <String>[
        csvText(s.name ?? ''),
        csvText(s.riderRef),
        s.hoursUnknown ? '' : csvMoney(s.basePay),
        csvMoney(s.deliveryPay),
        csvMoney(s.bonuses),
        csvMoney(s.tips),
        csvMoney(s.deductions),
        csvMoney(s.gross),
        csvMoney(s.net),
        csvText(status(s)),
      ],
  ];
  return '${rows.map((List<String> r) => r.join(',')).join('\r\n')}\r\n';
}

/// Why the payroll page could not be shown, said plainly — never an empty page, which a company
/// would read as "nobody is owed anything".
class PayrollProblem extends StatelessWidget {
  const PayrollProblem({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final Object failure = error;
    final Response<dynamic>? response = failure is DioException ? failure.response : null;
    final Object? data = response?.data;
    final bool noCompany = response?.statusCode == 403 &&
        data is Map<String, dynamic> &&
        data['code'] == 'NO_COMPANY';

    if (noCompany) {
      return ConsoleCard(
        title: t.noCompanyYet,
        child: Text(
          t.askThePlatformToAttachYou,
          style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.5),
        ),
      );
    }
    return ConsoleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            t.payrollLoadFailed,
            style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.5),
          ),
          const SizedBox(height: DeliverySpacing.md),
          ConsoleButton(
            label: t.payrollTryAgain,
            icon: Icons.refresh,
            tone: ConsoleButtonTone.outlined,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
