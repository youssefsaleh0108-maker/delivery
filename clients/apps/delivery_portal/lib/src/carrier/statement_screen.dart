import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../shell/shell.dart';

/// The delivery company's own statement, over a period they choose.
///
/// Read-only, and deliberately so. Everything on this page is the platform's account of what it owes
/// the company; a carrier disputing a figure does it by pointing at an order, which is why the
/// itemised rows are here and not summarised away.
///
/// It sits beside Earnings rather than replacing it, because the two answer different questions.
/// Earnings is a rolling window off the order service — how is the work going. This is the ledger's
/// own arithmetic for a closed period, the same figures the Backoffice sees on the row with this
/// company's name on it, fetched through `/statements/mine`: the route names nobody, and whose
/// statement it returns is decided by the token. A carrier cannot ask this screen for somebody
/// else's.
///
/// The wording is the counterparty's, not the operator's: [NetDirection.selfLabel] — "Owed to you",
/// not "We owe them". The platform's vantage point is fixed in the contract so all three apps agree
/// on the sign; the label is what translates it for whoever is reading.
class CarrierStatementScreen extends StatefulWidget {
  const CarrierStatementScreen({super.key, required this.api});

  final StatementsApi api;

  @override
  State<CarrierStatementScreen> createState() => _CarrierStatementScreenState();
}

class _CarrierStatementScreenState extends State<CarrierStatementScreen> {
  late DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late DateTime _to = DateTime.now();

  Statement? _statement;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final Statement loaded = await widget.api.mine(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _statement = loaded;
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

  Future<void> _pickPeriod() async {
    final DateTime today = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 3),
      lastDate: today,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: 'Statement period',
      saveText: 'Use period',
    );
    if (picked == null || !mounted) return;

    final int days = picked.end.difference(picked.start).inDays + 1;
    if (days > StatementsApi.maxRangeDays) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('A statement covers at most ${StatementsApi.maxRangeDays} days and that '
            'period is $days. The period is unchanged.'),
        backgroundColor: DeliveryAccent.critical.color,
      ));
      return;
    }

    setState(() {
      _from = picked.start;
      _to = picked.end;
    });
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ConsolePage(
      header: ConsoleTopbar(
        title: 'Statement',
        subtitle: 'What the platform owes you for the jobs your riders carried in this period',
        actions: <Widget>[
          ConsoleFilterButton(
            label: '${_date(_from)} → ${_date(_to)}',
            icon: Icons.date_range_outlined,
            onPressed: _loading ? null : _pickPeriod,
          ),
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
          ),
          // FINISH-WAVE NOTE: the console bell's slot, matching the other five carrier screens.
          // Wiring it needs a NotificationApi threaded to the carrier area, which no carrier page
          // has yet; a greyed control is a truer picture than an empty corner.
          const ConsoleIconAction(
            icon: Icons.notifications_none,
            tooltip: 'Notifications',
          ),
        ],
      ),
      children: _body(),
    );
  }

  List<Widget> _body() {
    if (_loading && _statement == null) {
      return <Widget>[
        const ConsoleCard(
          child: SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
          ),
        ),
      ];
    }

    if (_error != null) return <Widget>[_ErrorCard(error: _error!)];

    final Statement s = _statement!;
    if (s.isEmpty) {
      return <Widget>[
        ConsoleCard(
          title: 'Nothing in this period',
          child: Text(
            'No jobs of yours settled between ${_date(_from)} and ${_date(_to)}. That is an '
            'answer, not a failure — widen the period to look further back.',
            style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.5),
          ),
        ),
      ];
    }

    return <Widget>[
      _kpis(s),
      if (s.note != null)
        ConsoleCard(
          title: 'What the figures do not say',
          child: Text(
            s.note!,
            style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.5),
          ),
        ),
      _entries(s),
    ];
  }

  /// Jobs, what was earned, what the platform kept, and the bottom line.
  ///
  /// The middle two cards are built from the statement's own lines rather than from any rule this
  /// screen knows: their labels and their percentages are the server's words, because the commission
  /// rate lives where the rate lives and a client that formatted its own would go stale the day it
  /// changed for one company.
  ///
  /// When the ledger sends no debit line at all — which is the ordinary case for a carrier, because
  /// a catalog order always has a merchant on it too and the platform's cut cannot be split out of
  /// the residue — the cut card is drawn holding a dash and the statement's own note explains it. A
  /// zero there would be a claim that the platform kept nothing.
  Widget _kpis(Statement s) {
    final List<StatementLine> credits = s.lines
        .where((StatementLine l) => l.direction != LedgerDirection.debit)
        .toList(growable: false);
    final List<StatementLine> debits = s.lines
        .where((StatementLine l) => l.direction == LedgerDirection.debit)
        .toList(growable: false);

    return ConsoleKpiRow(
      cards: <Widget>[
        // Deliberately NOT a "Jobs" count.
        //
        // It used to read `entries.length`, which is the number of rows that happened to come
        // back — and the server trims that list. A company whose riders carried 61 jobs was shown
        // "Jobs 2" beside a credit line whose own words said "61 jobs", and the invented number
        // was given the same weight as the money next to it. The statement contract carries no
        // order count for this route, so the honest thing is to say how many are itemised, which
        // is a fact about the list rather than a claim about the month.
        ConsoleKpiCard(
          label: 'Itemised below',
          value: '${s.entries.length}',
          icon: Icons.receipt_long_outlined,
          footnote: Text(
            s.entries.isEmpty ? 'not itemised for this period' : 'of the jobs in this period',
            style: ConsoleText.meta.copyWith(color: DeliveryColors.faint),
          ),
        ),
        for (final StatementLine line in credits)
          ConsoleKpiCard(
            label: line.label,
            value: line.amount?.amount ?? '—',
            icon: Icons.payments_outlined,
            footnote: Text(
              line.note ?? 'as the ledger recorded it',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ConsoleText.meta.copyWith(color: DeliveryColors.faint),
            ),
          ),
        if (debits.isEmpty)
          ConsoleKpiCard(
            label: 'Platform\'s cut',
            value: '—',
            icon: Icons.percent_outlined,
            footnote: Text(
              'not itemised for this period',
              style: ConsoleText.meta.copyWith(color: DeliveryColors.faint),
            ),
          )
        else
          for (final StatementLine line in debits)
            ConsoleKpiCard(
              label: line.label,
              value: line.signedAmount ?? '—',
              icon: Icons.percent_outlined,
              footnote: Text(
                line.note ?? 'taken off the figures above',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ConsoleText.meta.copyWith(color: DeliveryColors.faint),
              ),
            ),
        ConsoleKpiCard(
          label: s.currency.isEmpty ? 'Net' : 'Net (${s.currency})',
          value: s.net.amount?.amount ?? '—',
          icon: Icons.account_balance_wallet_outlined,
          footnote: Text(
            // The counterparty's wording, not the operator's. See the class note.
            s.net.direction.selfLabel,
            style: ConsoleText.meta.copyWith(
              color: _accentFor(s.net.direction).color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _entries(Statement s) {
    return ConsoleTable(
      minWidth: 900,
      columns: const <ConsoleColumn>[
        ConsoleColumn(label: 'Order', flex: 1),
        ConsoleColumn(label: 'Settled', width: 170),
        ConsoleColumn(label: 'Gross', width: 110, alignRight: true),
        ConsoleColumn(label: 'Commission', width: 130, alignRight: true),
        ConsoleColumn(label: 'Net', width: 110, alignRight: true),
        ConsoleColumn(label: 'Paid by', width: 110),
      ],
      empty: const Text(
        'The totals above are not itemised for this period.',
        style: ConsoleText.cellMuted,
      ),
      rows: <ConsoleTableRow>[
        for (final StatementEntry e in s.entries)
          ConsoleTableRow(
            cells: <Widget>[
              Text('#${_shortId(e.orderId)}', style: ConsoleText.cellLink),
              Text(e.at == null ? '—' : _stamp(e.at!), style: ConsoleText.cellMuted),
              Text(e.gross?.amount ?? '—', style: ConsoleText.cell),
              Text(e.commission?.amount ?? '—', style: ConsoleText.cellMuted),
              Text(e.net?.amount ?? '—', style: ConsoleText.cellStrong),
              Text(e.paymentMethod ?? '—', style: ConsoleText.cellMuted),
            ],
          ),
      ],
      footer: Text(
        'Every figure is the ledger\'s own. A dash means the platform sent no number for that '
        'field, which is not the same as a zero.',
        style: ConsoleText.meta.copyWith(color: DeliveryColors.faint),
      ),
    );
  }
}

/// A 403 here is not a fault: the route resolves the caller's kind from their realm role, and a role
/// with no statement gets a correct refusal. Saying so plainly beats a stack trace.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final int? status = error is DioException
        ? (error as DioException).response?.statusCode
        : null;

    final String message = switch (status) {
      403 => 'This account has no statement of its own. Statements are kept for shops, riders and '
          'delivery companies; ask the platform team if you expected one here.',
      404 => 'You are not attached to a delivery company yet, so there is nothing to state.',
      _ => 'The statement could not be loaded. Nothing is wrong with your account — this is the '
          'platform failing to answer.\n\n$error',
    };

    return ConsoleCard(
      title: 'No statement to show',
      child: Text(
        message,
        style: ConsoleText.body.copyWith(color: DeliveryColors.muted, height: 1.5),
      ),
    );
  }
}

DeliveryAccent _accentFor(NetDirection direction) => switch (direction) {
      // Money coming to the company.
      NetDirection.weOwe => DeliveryAccent.positive,
      // Money the company owes back — cash its riders are still carrying, typically.
      NetDirection.theyOwe => DeliveryAccent.caution,
      NetDirection.settled => DeliveryAccent.info,
      NetDirection.unknown => DeliveryAccent.neutral,
    };

/// `yyyy-MM-dd`, the shape the contract uses on the wire.
String _date(DateTime when) => '${when.year.toString().padLeft(4, '0')}'
    '-${when.month.toString().padLeft(2, '0')}'
    '-${when.day.toString().padLeft(2, '0')}';

String _stamp(DateTime when) => '${_date(when)} ${when.hour.toString().padLeft(2, '0')}:'
    '${when.minute.toString().padLeft(2, '0')}';

String _shortId(String id) => id.length <= 8 ? id : id.substring(0, 8).toUpperCase();
