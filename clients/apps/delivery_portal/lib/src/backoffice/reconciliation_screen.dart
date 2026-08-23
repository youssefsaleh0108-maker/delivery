import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

/// Financial reconciliation (Phase 4). BACKOFFICE only.
///
/// Built around one question — <em>what has not settled</em> — rather than around browsing every
/// transaction. A finance screen that lists everything makes the handful of stuck rows the hardest
/// thing on it to find, which is the opposite of its purpose. So the work list is the default tab
/// and "everything" is not offered at all: per-status and per-order are the two ways in.
///
/// The headline number is money, not rows. "14 unsettled" says nothing about whether to worry;
/// "$1,240 at risk" does.
class ReconciliationScreen extends StatefulWidget {
  const ReconciliationScreen({super.key, required this.api});

  final AccountingApi api;

  @override
  State<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends State<ReconciliationScreen> {
  late Future<_ReconciliationData> _data = _load();

  SettlementStatus? _filter;

  Future<_ReconciliationData> _load() async {
    final ReconciliationSummary summary = await widget.api.summary();
    final List<AccountingTransaction> rows = _filter == null
        ? await widget.api.unsettled()
        : await widget.api.byStatus(_filter!);
    // Loaded on every view, not behind the filter: cash somebody is carrying is outstanding no
    // matter which settlement status is being looked at, and it is the one exposure on this screen
    // that no bank statement will ever reveal.
    final List<CashHolder> float = await widget.api.cashFloat();
    return _ReconciliationData(summary, rows, float);
  }

  /// Records that a holder has banked everything they were carrying.
  ///
  /// Confirmed first, because there is no way back. The ledger can discharge a collection but not
  /// un-discharge one, so an accidental click here means a rider is shown as square with the
  /// platform while still holding the notes.
  Future<void> _remit(CashHolder holder) async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Record a hand-over'),
            content: Text(
              'Confirm ${_shortId(holder.holderRef)} has handed over '
              '${_money(holder.amount)} in cash, covering ${holder.orders} '
              '${holder.orders == 1 ? 'order' : 'orders'}.\n\n'
              'This clears their whole balance and cannot be undone.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Yes, they banked it'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    // Captured before the await: this State can be disposed while the request is in flight, and
    // reaching through a dead context afterwards is the usual way that crashes.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final Remittance receipt = await widget.api.remit(holder.holderRef);
      messenger.showSnackBar(SnackBar(
        content: Text(receipt.isEmpty
            ? 'Nothing was outstanding — somebody may have recorded this already.'
            : 'Recorded ${_money(receipt.amount)} from ${_shortId(receipt.holderRef)}.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not record it: $e')));
    }
    if (mounted) _reload();
  }

  void _reload() {
    // Block body, not an arrow — see the note in settings_screen.dart.
    setState(() {
      _data = _load();
    });
  }

  void _selectFilter(SettlementStatus? status) {
    _filter = status;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ReconciliationData>(
      future: _data,
      builder: (BuildContext context, AsyncSnapshot<_ReconciliationData> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Could not load reconciliation: ${snapshot.error}'));
        }

        final _ReconciliationData data = snapshot.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  DeliverySpacing.lg, DeliverySpacing.lg, DeliverySpacing.lg, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Reconciliation',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: DeliverySpacing.xs),
                        Text(
                          'Every movement of money the platform has asked the bank to make.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: DeliveryColors.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(DeliverySpacing.lg),
              child: _SummaryTiles(summary: data.summary, float: data.float),
            ),
            if (data.float.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    DeliverySpacing.lg, 0, DeliverySpacing.lg, DeliverySpacing.lg),
                child: _CashOnHand(holders: data.float, onRemit: _remit),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.lg),
              child: _Filters(selected: _filter, onSelected: _selectFilter),
            ),
            const SizedBox(height: DeliverySpacing.md),
            Expanded(child: _TransactionTable(rows: data.rows, api: widget.api)),
          ],
        );
      },
    );
  }
}

class _ReconciliationData {
  const _ReconciliationData(this.summary, this.rows, this.float);

  final ReconciliationSummary summary;
  final List<AccountingTransaction> rows;
  final List<CashHolder> float;
}

/// Past this, cash has been out longer than a shift and somebody should be asked about it.
///
/// A day is a judgement, not a rule the ledger enforces — but a number here is what turns "some
/// cash is out" into "this is late", and no number at all means nobody ever chases it.
const Duration _bankItWithin = Duration(hours: 24);

class _SummaryTiles extends StatelessWidget {
  const _SummaryTiles({required this.summary, required this.float});

  final ReconciliationSummary summary;
  final List<CashHolder> float;

  /// When the longest-held cash was collected.
  DateTime get _oldest => float
      .map((CashHolder h) => h.oldest)
      .reduce((DateTime a, DateTime b) => a.isBefore(b) ? a : b);

  /// Held cash is normal; held cash that is <em>old</em> is not.
  ///
  /// The amount alone is a poor signal — a busy Saturday afternoon and a rider who stopped
  /// answering their phone look identical in it. Age is what separates them, so age decides the
  /// colour.
  DeliveryAccent get _floatAccent {
    if (float.isEmpty) return DeliveryAccent.positive;
    return DateTime.now().difference(_oldest) > _bankItWithin
        ? DeliveryAccent.caution
        : DeliveryAccent.info;
  }

  @override
  Widget build(BuildContext context) {
    final int posted = summary.byStatus[SettlementStatus.posted]?.count ?? 0;
    final int failed = summary.byStatus[SettlementStatus.failed]?.count ?? 0;
    final int pending = summary.byStatus[SettlementStatus.pending]?.count ?? 0;

    final int reversed = summary.byStatus[SettlementStatus.compensated]?.count ?? 0;
    final int abandoned = summary.byStatus[SettlementStatus.abandoned]?.count ?? 0;

    return StatRow(tiles: <Widget>[
      // First, because it is the only number that says whether to worry. Its colour is the answer:
      // green on a clean ledger, red the moment money is stuck somewhere.
      StatTile(
        value: _money(summary.amountAtRisk),
        label: 'At risk',
        icon: summary.isClean
            ? Icons.verified_outlined
            : Icons.warning_amber_rounded,
        accent: summary.isClean ? DeliveryAccent.positive : DeliveryAccent.critical,
        footnote: summary.isClean ? 'all settled' : '$pending·$failed',
      ),
      // Second, beside the other exposure. This one is not "at risk" in the same sense — nothing
      // has failed — but it is the money the bank cannot see, so it belongs next to the number
      // that says whether to worry rather than buried among the counts.
      StatTile(
        value: _money(float.fold<double>(0, (double s, CashHolder h) => s + h.amount)),
        label: 'Cash on hand',
        icon: Icons.payments_outlined,
        accent: _floatAccent,
        footnote: float.isEmpty
            ? 'nobody holding'
            : '${float.length} holding · ${_ago(_oldest)}',
      ),
      StatTile(
        value: '$posted',
        label: 'Settled',
        icon: Icons.check_circle_outline_rounded,
        accent: DeliveryAccent.positive,
      ),
      StatTile(
        value: '$pending',
        label: 'In flight',
        icon: Icons.sync_rounded,
        // Pending is normal, not a problem — amber only once something is actually waiting.
        accent: pending == 0 ? DeliveryAccent.positive : DeliveryAccent.info,
      ),
      StatTile(
        value: '$reversed',
        label: 'Reversed',
        icon: Icons.undo_rounded,
        accent: reversed == 0 ? DeliveryAccent.positive : DeliveryAccent.caution,
      ),
      StatTile(
        value: '$abandoned',
        label: 'Abandoned',
        icon: Icons.block_rounded,
        accent: abandoned == 0 ? DeliveryAccent.positive : DeliveryAccent.critical,
      ),
    ]);
  }
}

// The bespoke tile that lived here is gone. StatTile from the design system does the same job in
// every app, and the "tinted only when there is something to act on" idea it carried is now the
// accent: green when a number is fine, red when it is not, decided per tile rather than by a flag.

/// Who is holding platform cash, and the button that says they have banked it.
///
/// This is the only place in the product where the float can be discharged. Until it existed the
/// balance only ever grew: settlement recorded every collection correctly and nothing could ever
/// record the hand-over, so a working ledger still added up to a number that meant nothing.
///
/// Sorted oldest-first rather than largest-first. The biggest balance is usually just the busiest
/// rider; the oldest one is the question worth asking.
class _CashOnHand extends StatelessWidget {
  const _CashOnHand({required this.holders, required this.onRemit});

  final List<CashHolder> holders;
  final Future<void> Function(CashHolder) onRemit;

  @override
  Widget build(BuildContext context) {
    final List<CashHolder> sorted = holders.toList()
      ..sort((CashHolder a, CashHolder b) => a.oldest.compareTo(b.oldest));
    final bool anyLate =
        DateTime.now().difference(sorted.first.oldest) > _bankItWithin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionLabel('Cash on hand'),
        const SizedBox(height: DeliverySpacing.sm),
        if (anyLate)
          const Padding(
            padding: EdgeInsets.only(bottom: DeliverySpacing.sm),
            child: SoftNote(
              text: 'Cash has been out longer than a day. Nothing is wrong with the ledger — '
                  'this is money the bank has not seen yet.',
              accent: DeliveryAccent.caution,
              icon: Icons.schedule_rounded,
            ),
          ),
        SoftCard(
          padding: EdgeInsets.zero,
          child: ConstrainedBox(
            // Capped so a long shift's worth of riders cannot push the settlement work list off
            // the screen: this panel is context, the table below is the job.
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(DeliverySpacing.sm),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int i) =>
                  _HolderRow(holder: sorted[i], onRemit: onRemit),
            ),
          ),
        ),
      ],
    );
  }
}

class _HolderRow extends StatelessWidget {
  const _HolderRow({required this.holder, required this.onRemit});

  final CashHolder holder;
  final Future<void> Function(CashHolder) onRemit;

  @override
  Widget build(BuildContext context) {
    final bool late = holder.age > _bankItWithin;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: DeliverySpacing.sm, vertical: DeliverySpacing.sm),
      child: Row(
        children: <Widget>[
          Icon(
            // A rider today; a delivery company once carriers collect their own cash.
            holder.holderKind == 'PROVIDER'
                ? Icons.local_shipping_outlined
                : Icons.pedal_bike_outlined,
            size: 18,
            color: DeliveryColors.muted,
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_shortId(holder.holderRef),
                    style: Theme.of(context).textTheme.titleSmall),
                Text(
                  '${holder.orders} ${holder.orders == 1 ? 'order' : 'orders'} '
                  '· since ${_ago(holder.oldest)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: DeliveryColors.muted),
                ),
              ],
            ),
          ),
          if (late) ...<Widget>[
            const StatePill(label: 'Overdue', accent: DeliveryAccent.caution),
            const SizedBox(width: DeliverySpacing.sm),
          ],
          Text(_money(holder.amount),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: DeliverySpacing.md),
          OutlinedButton.icon(
            onPressed: () => onRemit(holder),
            icon: const Icon(Icons.account_balance_outlined, size: 16),
            label: const Text('Banked'),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.selected, required this.onSelected});

  final SettlementStatus? selected;
  final ValueChanged<SettlementStatus?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: DeliverySpacing.sm,
      children: <Widget>[
        // The default, and deliberately first: this screen exists for the work list.
        ChoiceChip(
          label: const Text('Needs attention'),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final SettlementStatus status in <SettlementStatus>[
          SettlementStatus.posted,
          SettlementStatus.failed,
          SettlementStatus.pending,
          SettlementStatus.compensated,
          SettlementStatus.abandoned,
        ])
          ChoiceChip(
            label: Text(status.label),
            selected: selected == status,
            onSelected: (_) => onSelected(status),
          ),
      ],
    );
  }
}

class _TransactionTable extends StatelessWidget {
  const _TransactionTable({required this.rows, required this.api});

  final List<AccountingTransaction> rows;
  final AccountingApi api;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(DeliverySpacing.xl),
          child: Text('Nothing here — every settlement in this view has completed.'),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.lg),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const <DataColumn>[
            DataColumn(label: Text('Order')),
            DataColumn(label: Text('Leg')),
            DataColumn(label: Text('Account')),
            DataColumn(label: Text('Amount'), numeric: true),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Bank reference')),
            DataColumn(label: Text('')),
          ],
          rows: <DataRow>[
            for (final AccountingTransaction t in rows)
              DataRow(
                cells: <DataCell>[
                  DataCell(Text(_shortId(t.orderId))),
                  DataCell(Text(t.leg.label)),
                  DataCell(Text(t.accountRef)),
                  DataCell(Text('${t.isDebit ? '−' : '+'}${_money(t.amount)}')),
                  DataCell(_StatusChip(status: t.status, reason: t.failureReason)),
                  // Missing on anything the bank never accepted, which is itself the signal.
                  DataCell(Text(t.coreBankingRef ?? '—')),
                  DataCell(
                    IconButton(
                      tooltip: 'What the bank was told',
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (BuildContext context) =>
                            _SyncLogDialog(transaction: t, api: api),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, this.reason});

  final SettlementStatus status;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final DeliveryStatusColor colour = switch (status) {
      SettlementStatus.posted => DeliveryStatusColor.delivered,
      SettlementStatus.failed => DeliveryStatusColor.inTransit,
      SettlementStatus.pending => DeliveryStatusColor.preparing,
      _ => DeliveryStatusColor.offline,
    };

    final Widget badge = DeliveryStatusBadge(status: colour, label: status.label);

    // The failure reason is the first thing anyone wants after seeing FAILED, so it is one hover
    // away rather than one dialog away.
    return reason == null ? badge : Tooltip(message: reason!, child: badge);
  }
}

class _SyncLogDialog extends StatelessWidget {
  const _SyncLogDialog({required this.transaction, required this.api});

  final AccountingTransaction transaction;
  final AccountingApi api;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${transaction.leg.label} · ${_money(transaction.amount)}'),
      content: SizedBox(
        width: 700,
        child: FutureBuilder<List<SyncLogEntry>>(
          future: api.syncLog(transaction.id),
          builder: (BuildContext context, AsyncSnapshot<List<SyncLogEntry>> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                  height: 120, child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError) {
              return Text('Could not load the sync log: ${snapshot.error}');
            }
            final List<SyncLogEntry> entries = snapshot.data!;
            if (entries.isEmpty) {
              // Means the connector never reported anything — the leg is still in flight, or the
              // result was lost. Worth saying, rather than showing an empty box.
              return const Text('The bank has not been asked about this yet.');
            }

            return ListView(
              shrinkWrap: true,
              children: <Widget>[
                for (final SyncLogEntry e in entries) ...<Widget>[
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${e.outcome} · ${e.provider ?? 'unknown provider'}'),
                    subtitle: Text(_ago(e.syncedAt)),
                  ),
                  _Payload(label: 'Sent', body: e.requestPayload),
                  _Payload(label: 'Received', body: e.responsePayload),
                  const Divider(),
                ],
              ],
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _Payload extends StatelessWidget {
  const _Payload({required this.label, required this.body});

  final String label;
  final String? body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label,
            style:
                Theme.of(context).textTheme.labelSmall?.copyWith(color: DeliveryColors.muted)),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: DeliverySpacing.sm),
          padding: const EdgeInsets.all(DeliverySpacing.sm),
          decoration: BoxDecoration(
            color: DeliveryColors.background,
            border: Border.all(color: DeliveryColors.border),
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          ),
          // Selectable, because the next thing anyone does with a bank payload is paste it into an
          // email to the bank.
          child: SelectableText(
            body ?? 'nothing recorded',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// Enough of a UUID to identify an order in conversation, which is all a table column needs.
String _shortId(String id) => id.length <= 8 ? id : id.substring(0, 8).toUpperCase();

String _money(double amount) => '\$${amount.toStringAsFixed(2)}';

String _ago(DateTime time) {
  final Duration d = DateTime.now().difference(time);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}
