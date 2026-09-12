/// The pieces the carrier's two cash pages share: how a figure is written, how a rider's standing is
/// badged, the hand-over confirmation, the CSV export and the "could not load" card.
///
/// Kept apart from both screens so the overview and the rider's settlement page cannot drift into
/// two wordings for the same hand-over — the confirmation in particular has to say the same thing
/// whichever page it was opened from, because it is the last thing the hub reads before a balance
/// is cleared for good.
library;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../shell/console_controls.dart';
import '../shell/shell.dart';

/// Saves a text file through the browser. [downloadTextFile] in production; a capture in tests.
typedef SaveTextFile = void Function(String fileName, String content, {String mimeType});

/// A cash figure as the page shows it: the ledger's own digits, with the currency's mark.
///
/// The digits are never touched — see [Money]. A figure the server did not send is a dash, never a
/// zero: "we were not told" and "nothing is owed" are different statements about somebody's cash.
String cashText(Money? money, String currency) {
  if (money == null) return '—';
  if (currency == 'USD' || currency.isEmpty) {
    return money.isNegative ? '-\$${money.unsigned}' : '\$${money.amount}';
  }
  return '${money.amount} $currency';
}

/// Enough of an id to recognise in conversation — what a rider with no name on file is called.
String shortRef(String id) => id.length <= 8 ? id : id.substring(0, 8).toUpperCase();

/// `yyyy-MM-dd`, the shape the rest of the console writes dates in.
String isoDay(DateTime when) => CarrierCashApi.isoDate(when);

/// `yyyy-MM-dd HH:mm`, in the reader's own clock.
String stamp(DateTime when) => '${isoDay(when)} ${when.hour.toString().padLeft(2, '0')}:'
    '${when.minute.toString().padLeft(2, '0')}';

/// "Today", "Yesterday", "3 days ago" — by calendar day in the reader's clock, not by 24-hour
/// blocks, so a hand-over at 23:50 last night is "Yesterday" at 00:10 this morning.
String relativeDay(DeliveryStrings t, DateTime? when, {DateTime? now}) {
  if (when == null) return t.carrCashNever;
  final DateTime today = _dayOf(now ?? DateTime.now());
  final int days = today.difference(_dayOf(when)).inDays;
  if (days <= 0) return t.carrCashToday;
  if (days == 1) return t.carrCashYesterday;
  return t.carrCashDaysAgo(days);
}

DateTime _dayOf(DateTime when) => DateTime.utc(when.year, when.month, when.day);

/// A rider's standing as the table's badge. Caution for cash held, never critical until it is
/// actually late: holding the day's takings is a working rider, not a problem.
Widget standingPill(DeliveryStrings t, RiderCashStanding standing, int? overdueHours) {
  return switch (standing) {
    RiderCashStanding.holding =>
      ConsoleStatusPill(label: t.carrCashStatusHolding, accent: DeliveryAccent.caution),
    RiderCashStanding.overdue => ConsoleStatusPill(
        label: overdueHours == null
            ? t.carrCashKpiOverdue
            : t.carrCashStatusOverdue(overdueHours),
        accent: DeliveryAccent.critical,
      ),
    RiderCashStanding.settled =>
      ConsoleStatusPill(label: t.carrCashStatusSettled, accent: DeliveryAccent.positive),
    RiderCashStanding.unknown => const ConsoleStatusPill(label: '—'),
  };
}

String methodLabel(DeliveryStrings t, CashMethod method) => switch (method) {
      CashMethod.cash => t.carrCashMethodCash,
      CashMethod.bankDeposit => t.carrCashMethodBank,
      CashMethod.wallet => t.carrCashMethodWallet,
    };

/// How the money moved. Recorded with the hand-over; nothing moves money because of it.
class CashMethodSelect extends StatelessWidget {
  const CashMethodSelect({super.key, required this.value, required this.onChanged});

  final CashMethod value;
  final ValueChanged<CashMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return ConsoleSelect(
      label: methodLabel(t, value),
      icon: Icons.payments_outlined,
      options: <ConsoleOption>[
        for (final CashMethod m in CashMethod.values)
          ConsoleOption(label: methodLabel(t, m), value: m.wire),
      ],
      onSelected: (String? wire) {
        final CashMethod? picked = CashMethod.fromWire(wire);
        if (picked != null) onChanged(picked);
      },
    );
  }
}

/// What the person at the counter chose in the confirmation.
class HandoverChoice {
  const HandoverChoice(this.method, this.note);

  final CashMethod method;
  final String? note;
}

/// Asks before clearing one rider's balance with the company.
///
/// Names the rider, the amount and the order count, because that is what the person at the counter
/// is checking against the notes in their hand, and says it cannot be undone because it cannot: the
/// ledger discharges a collection and never un-discharges one. With a [preset] the method and note
/// were already chosen on the page and the dialog only confirms them.
Future<HandoverChoice?> confirmHandover(
  BuildContext context, {
  required String name,
  required String amount,
  required String orders,
  HandoverChoice? preset,
}) {
  final DeliveryStrings t = DeliveryStrings.of(context);
  return showDialog<HandoverChoice>(
    context: context,
    builder: (BuildContext context) => _HandoverDialog(
      title: t.carrCashConfirmTitle,
      body: <Widget>[Text(t.carrCashConfirmBody(name, amount, orders))],
      preset: preset,
    ),
  );
}

/// One rider in the bulk confirmation.
typedef BulkLine = ({String name, String amount});

/// Asks before clearing several riders' balances at once, listing each and the total.
Future<HandoverChoice?> confirmBulkHandover(
  BuildContext context, {
  required List<BulkLine> lines,
  required String total,
}) {
  final DeliveryStrings t = DeliveryStrings.of(context);
  return showDialog<HandoverChoice>(
    context: context,
    builder: (BuildContext context) => _HandoverDialog(
      title: t.carrCashConfirmBulkTitle(lines.length),
      body: <Widget>[
        Text(t.carrCashConfirmBulkBody),
        const SizedBox(height: DeliverySpacing.md),
        for (final BulkLine line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: DeliverySpacing.xs),
            child: Row(
              children: <Widget>[
                Expanded(child: Text(line.name, overflow: TextOverflow.ellipsis)),
                Text(line.amount, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        const Divider(),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Text(t.carrCashConfirmBulkTotal(total),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
      preset: null,
    ),
  );
}

class _HandoverDialog extends StatefulWidget {
  const _HandoverDialog({required this.title, required this.body, required this.preset});

  final String title;
  final List<Widget> body;
  final HandoverChoice? preset;

  @override
  State<_HandoverDialog> createState() => _HandoverDialogState();
}

class _HandoverDialogState extends State<_HandoverDialog> {
  late CashMethod _method = widget.preset?.method ?? CashMethod.cash;
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final HandoverChoice? preset = widget.preset;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ...widget.body,
              if (preset == null) ...<Widget>[
                const SizedBox(height: DeliverySpacing.md),
                ConsoleSectionLabel(t.carrCashMethodLabel),
                const SizedBox(height: 6),
                CashMethodSelect(
                  value: _method,
                  onChanged: (CashMethod m) => setState(() => _method = m),
                ),
                const SizedBox(height: DeliverySpacing.md),
                ConsoleSectionLabel(t.carrCashNoteLabel),
                TextField(
                  controller: _note,
                  maxLength: 500,
                  decoration: InputDecoration(hintText: t.carrCashNoteHint),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            preset ?? HandoverChoice(_method, _note.text.trim().isEmpty ? null : _note.text),
          ),
          child: Text(t.carrCashConfirmYes),
        ),
      ],
    );
  }
}

/// The exact total of several amounts, or null when any of them is unknown.
///
/// Summed in cents, which is exact, and only because the bulk confirmation needs one figure no
/// server response carries. Unknown anywhere makes the total unknown rather than a smaller number.
Money? sumMoney(Iterable<Money?> amounts) {
  int cents = 0;
  for (final Money? m in amounts) {
    final int? units = m?.minorUnits;
    if (units == null) return null;
    cents += units;
  }
  final String sign = cents < 0 ? '-' : '';
  final int whole = cents.abs() ~/ 100;
  final int fraction = cents.abs() % 100;
  return Money('$sign$whole.${fraction.toString().padLeft(2, '0')}');
}

/// The rider balances as CSV: one header line, one line per rider, amounts exactly as the ledger
/// wrote them.
String carrierCashCsv(DeliveryStrings t, CarrierCashOverview overview) {
  String standing(RiderCashLine l) => switch (l.standing) {
        RiderCashStanding.holding => t.carrCashStatusHolding,
        RiderCashStanding.overdue => t.carrCashKpiOverdue,
        RiderCashStanding.settled => t.carrCashStatusSettled,
        RiderCashStanding.unknown => '',
      };

  final List<List<String>> rows = <List<String>>[
    <String>[
      t.carrCashColRider,
      t.carrCashCsvRiderId,
      t.carrCashColCollected,
      t.carrCashColEarned,
      t.carrCashColHolding,
      t.carrCashCsvOrdersHeld,
      t.carrCashCsvOldest,
      t.carrCashColLastHandover,
      t.carrCashColStatus,
    ],
    for (final RiderCashLine l in overview.riders)
      <String>[
        l.name ?? '',
        l.riderRef,
        l.collected?.amount ?? '',
        l.earned?.amount ?? '',
        l.holding?.amount ?? '',
        '${l.orders}',
        l.oldest == null ? '' : l.oldest!.toUtc().toIso8601String(),
        l.lastHandoverAt == null ? '' : l.lastHandoverAt!.toUtc().toIso8601String(),
        standing(l),
      ],
  ];
  return '${rows.map((List<String> r) => r.map(_csvField).join(',')).join('\r\n')}\r\n';
}

/// Quoted when it has to be, with quotes doubled — RFC 4180, which every spreadsheet reads.
String _csvField(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n') ||
      value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

/// Why a cash page could not be shown, said plainly.
///
/// A company that is not attached yet is told so in the words the rest of the carrier console
/// uses; a rider who never carried cash for this company gets [notFound]; anything else is the
/// platform failing to answer, which is never rendered as an empty page — "nobody is holding cash"
/// on a day the service simply did not reply is the one wrong answer here.
class CarrierCashProblem extends StatelessWidget {
  const CarrierCashProblem({
    super.key,
    required this.error,
    required this.onRetry,
    this.notFound,
  });

  final Object error;
  final VoidCallback onRetry;
  final String? notFound;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final Response<dynamic>? response =
        error is DioException ? (error as DioException).response : null;
    final int? status = response?.statusCode;
    final Object? data = response?.data;
    final bool noCompany =
        status == 403 && data is Map<String, dynamic> && data['code'] == 'NO_COMPANY';

    if (noCompany || (status == 404 && notFound == null)) {
      return ConsoleCard(
        title: t.noCompanyYet,
        child: Text(
          t.askThePlatformToAttachYou,
          style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.5),
        ),
      );
    }
    if (status == 404) {
      return ConsoleCard(
        child: Text(
          notFound!,
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
            t.carrCashLoadFailed,
            style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.5),
          ),
          const SizedBox(height: DeliverySpacing.md),
          ConsoleButton(
            label: t.carrCashTryAgain,
            icon: Icons.refresh,
            tone: ConsoleButtonTone.outlined,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}
