import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
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
///
/// <strong>Delivery companies hold their riders' cash</strong> (the owner's decision). A company's
/// rider hands the door cash to the company, and the company owes the platform until somebody here
/// records its payment. So the riders on the cash-on-hand list are the platform's own and any
/// company rider still carrying notes, while companies get their own section: what each holds and
/// owes now, with what its riders still hold for it shown beside it and never added to it.
class ReconciliationScreen extends StatefulWidget {
  const ReconciliationScreen({super.key, required this.api, this.providerApi});

  final AccountingApi api;

  /// Where a delivery company's name comes from. The ledger keys a company by its Order Manager id
  /// and knows no name for it, so without this the companies section shows a short id — the same
  /// fallback this screen uses for a rider.
  final DeliveryProviderApi? providerApi;

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

    // Allowed to fail on its own. The companies' section is one panel of a finance screen whose
    // work list must still open when that panel's route is down — it says so in place instead.
    List<CarrierCashHolding>? carriers;
    try {
      carriers = await widget.api.carriersFloat();
    } catch (_) {
      carriers = null;
    }
    final Map<String, String> names = carriers == null || carriers.isEmpty
        ? const <String, String>{}
        : await _companyNames();

    return _ReconciliationData(summary, rows, float, carriers, names);
  }

  /// Company names by provider id, or nothing: a name is a nicety, and an id still identifies them.
  Future<Map<String, String>> _companyNames() async {
    final DeliveryProviderApi? providers = widget.providerApi;
    if (providers == null) return const <String, String>{};
    try {
      final Paged<DeliveryProviderInfo> page = await providers.all(size: 100);
      return <String, String>{
        for (final DeliveryProviderInfo p in page.content) p.id: p.name,
      };
    } catch (_) {
      return const <String, String>{};
    }
  }

  /// Records that a holder has banked everything they were carrying.
  ///
  /// Confirmed first, because there is no way back. The ledger can discharge a collection but not
  /// un-discharge one, so an accidental click here means a rider is shown as square with the
  /// platform while still holding the notes.
  Future<void> _remit(CashHolder holder) async {
    // A shop's till is settled on terms of its own, against what it owes rather than what it holds.
    if (holder.isShop) return _remitShop(holder);

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
      // Which of the account's cash this is: one account can be a rider and a shop at once, and the
      // server will not guess between the bag and the till.
      final Remittance receipt =
          await widget.api.remit(holder.holderRef, holderKind: holder.holderKind);
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

  /// Records that a delivery company has paid the platform everything it holds.
  ///
  /// Against the figure on screen, not "whatever it holds by the time this lands": a company's
  /// balance grows every time one of its riders hands over at its hub, so an operator confirming a
  /// cheque for 485.50 must not clear 525.50. If it moved, the server records nothing and says what
  /// it is now. The key is made once per confirmation, so a double press records one payment.
  Future<void> _remitCarrier(CarrierCashHolding carrier, String company) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final Money? expected = carrier.held;
    if (expected == null || !carrier.holdsCash) return;

    final String requestKey = CarrierCashApi.newRequestKey();
    final _PaymentChoice? choice = await showDialog<_PaymentChoice>(
      context: context,
      builder: (BuildContext context) => _PaymentDialog(
        body: t.carrCashBoConfirmBody(
            company, _cash(expected), t.carrCashOrderCount(carrier.orders)),
      ),
    );
    if (choice == null || !mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    String message;
    try {
      final Remittance receipt = await widget.api.remit(
        carrier.carrierRef,
        expected: expected,
        method: choice.method,
        requestKey: requestKey,
      );
      message = receipt.isEmpty
          ? t.carrCashBoNothing
          // The confirmed figure, which the server has just agreed is exactly what was cleared.
          : t.carrCashBoRecorded(_cash(expected), company);
    } on CashAmountChanged catch (e) {
      message = t.carrCashBoAmountChanged(company, _cash(e.current));
    } catch (e) {
      message = t.carrCashBoFailed('$e');
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
    if (mounted) _reload();
  }

  /// Records that a shop has paid the platform what it owes out of its till (services V52).
  ///
  /// A shop keeps its own share of the cash its counter took for pickups and pays the platform only
  /// its commission, so the figure confirmed is [CashHolder.owed] and never the till, which is mostly
  /// the shop's own money. It goes as the counted amount with a key made once per confirmation, as a
  /// company's payment does: if another pickup was paid at the counter meanwhile the server records
  /// nothing and says what the shop owes now, and a double press records one payment. The Back
  /// Office's full screens for shops are their own slice; this makes the one button right.
  Future<void> _remitShop(CashHolder holder) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final Money? owed = holder.owed;
    if (owed == null) return;

    final String shop = t.svcCashShopName(_shortId(holder.holderRef));
    final String requestKey = CarrierCashApi.newRequestKey();
    final _PaymentChoice? choice = await showDialog<_PaymentChoice>(
      context: context,
      builder: (BuildContext context) => _PaymentDialog(
        body: t.svcCashShopConfirmBody(
            shop, _cash(owed), _money(holder.amount), t.carrCashOrderCount(holder.orders)),
      ),
    );
    if (choice == null || !mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    String message;
    try {
      final Remittance receipt = await widget.api.remit(
        holder.holderRef,
        expected: owed,
        method: choice.method,
        requestKey: requestKey,
        holderKind: holder.holderKind,
      );
      message = receipt.isEmpty ? t.carrCashBoNothing : t.carrCashBoRecorded(_cash(owed), shop);
    } on CashAmountChanged catch (e) {
      message = t.svcCashShopAmountChanged(shop, _cash(e.current));
    } catch (e) {
      message = t.carrCashBoFailed('$e');
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
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
        // Companies are listed in their own section below, with the payment flow that fits them.
        final List<CashHolder> riders =
            data.float.where((CashHolder h) => !h.isCarrier).toList(growable: false);
        final List<CarrierCashHolding>? carriers = data.carriers;

        // What sits above the work list: the heading, the tiles, and who is holding cash.
        final Widget panels = Column(
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
            if (riders.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    DeliverySpacing.lg, 0, DeliverySpacing.lg, DeliverySpacing.lg),
                child: _CashOnHand(holders: riders, onRemit: _remit),
              ),
            // Hidden when no company holds or is owed anything, as cash on hand is; shown with its
            // own sentence when it could not be loaded, because silence would read as "none".
            if (carriers == null || carriers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    DeliverySpacing.lg, 0, DeliverySpacing.lg, DeliverySpacing.lg),
                child: _HeldByCarriers(
                  carriers: carriers,
                  names: data.names,
                  onRecord: _remitCarrier,
                ),
              ),
          ],
        );

        // The panels scroll among themselves once the window is too short for all of them, rather
        // than overflowing: they are context, and the settlement table below is the job, so it
        // always keeps a usable height. On an ordinary window everything fits and nothing
        // scrolls, exactly as before the companies' section was added.
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            const double filtersHeight = 64;
            const double minTableHeight = 200;
            final double room = constraints.maxHeight - filtersHeight - minTableHeight;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: room > 0 ? room : 0),
                  child: SingleChildScrollView(child: panels),
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
      },
    );
  }
}

class _ReconciliationData {
  const _ReconciliationData(this.summary, this.rows, this.float, this.carriers, this.names);

  final ReconciliationSummary summary;
  final List<AccountingTransaction> rows;
  final List<CashHolder> float;

  /// Null when the companies' figures could not be loaded — not the same as "no company holds any".
  final List<CarrierCashHolding>? carriers;

  /// Company names by provider id; empty when unknown.
  final Map<String, String> names;
}

/// Past this, cash has been out longer than a shift and somebody should be asked about it.
///
/// <strong>A fallback only.</strong> The server decides with its own configured limits and flags
/// every holder: a day for a rider of the platform's own fleet — the rule this screen always applied
/// (`delivery.accounting.float.platform-overdue-after-hours`) — and the carrier-custody limit for a
/// delivery company's cash (`carrier-overdue-after-hours`), the same one the company's own
/// reconciliation page states, so the two cannot disagree about what "late" means. This day is used
/// only against a server that predates the flag.
const Duration _bankItWithin = Duration(hours: 24);

/// Whether a holder's cash is late: the server's call, or the fallback above when it made none.
bool _isLate(CashHolder holder) => holder.overdue ?? holder.age > _bankItWithin;

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
    return float.any(_isLate) ? DeliveryAccent.caution : DeliveryAccent.info;
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
/// This is the only place in the product where a rider's float can be discharged with the
/// platform. Until it existed the balance only ever grew: settlement recorded every collection
/// correctly and nothing could ever record the hand-over, so a working ledger still added up to a
/// number that meant nothing.
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
    final bool anyLate = sorted.any(_isLate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionLabel('Cash on hand'),
        const SizedBox(height: DeliverySpacing.sm),
        if (anyLate)
          Padding(
            padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
            child: SoftNote(
              text: DeliveryStrings.of(context).carrCashBoOverdueNote,
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
    final bool late = _isLate(holder);
    final DeliveryStrings t = DeliveryStrings.of(context);
    final TextStyle? meta =
        Theme.of(context).textTheme.bodySmall?.copyWith(color: DeliveryColors.muted);
    final TextStyle? figure =
        Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    // A shop holding pickup cash (services V52) is a shop, not a rider. It is named as one, and
    // what it is asked for is what it owes out of its till — the platform's commission — with what
    // its counter took beside it, because most of that is the shop's own share.
    final bool shop = holder.isShop;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: DeliverySpacing.sm, vertical: DeliverySpacing.sm),
      child: Row(
        children: <Widget>[
          Icon(shop ? Icons.storefront_outlined : Icons.pedal_bike_outlined,
              size: 18, color: DeliveryColors.muted),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                    shop
                        ? t.svcCashShopName(_shortId(holder.holderRef))
                        : _shortId(holder.holderRef),
                    style: Theme.of(context).textTheme.titleSmall),
                Text(
                  shop
                      ? <String>[
                          t.carrCashOrderCount(holder.orders),
                          t.svcCashShopTakenAtCounter(_money(holder.amount)),
                        ].join(' · ')
                      : '${holder.orders} ${holder.orders == 1 ? 'order' : 'orders'} '
                          '· since ${_ago(holder.oldest)}',
                  style: meta,
                ),
              ],
            ),
          ),
          if (late) ...<Widget>[
            const StatePill(label: 'Overdue', accent: DeliveryAccent.caution),
            const SizedBox(width: DeliverySpacing.sm),
          ],
          if (shop)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(_cash(holder.owed), style: figure),
                Text(t.carrCashBoOwes, style: meta),
              ],
            )
          else
            Text(_money(holder.amount), style: figure),
          const SizedBox(width: DeliverySpacing.md),
          if (shop)
            // Disabled when the server did not say what the shop owes: its payment is recorded
            // against that figure, and there would be none to confirm.
            OutlinedButton.icon(
              onPressed: holder.owed == null ? null : () => onRemit(holder),
              icon: const Icon(Icons.account_balance_outlined, size: 16),
              label: Text(t.carrCashBoRecordPayment),
            )
          else
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

/// What each delivery company holds and owes the platform, and the button that records it paid.
///
/// A company's own figure is what its riders handed it and it has not yet paid: exactly what a
/// payment clears. What its riders still carry is owed to the company, not yet to the platform, so
/// it is written beside the figure and never added to it — adding it would record a payment for
/// notes still in a rider's pocket.
class _HeldByCarriers extends StatelessWidget {
  const _HeldByCarriers({required this.carriers, required this.names, required this.onRecord});

  /// Null when the figures could not be loaded.
  final List<CarrierCashHolding>? carriers;
  final Map<String, String> names;
  final Future<void> Function(CarrierCashHolding carrier, String company) onRecord;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<CarrierCashHolding>? list = carriers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionLabel(t.carrCashBoTitle),
        const SizedBox(height: DeliverySpacing.sm),
        if (list == null)
          Text(
            t.carrCashBoLoadFailed,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DeliveryColors.muted),
          )
        else
          SoftCard(
            padding: EdgeInsets.zero,
            child: ConstrainedBox(
              // Capped for the reason cash on hand is: the work list below is the job.
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(DeliverySpacing.sm),
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (BuildContext context, int i) => _CarrierRow(
                  carrier: list[i],
                  name: names[list[i].carrierRef] ?? _shortId(list[i].carrierRef),
                  onRecord: onRecord,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CarrierRow extends StatelessWidget {
  const _CarrierRow({required this.carrier, required this.name, required this.onRecord});

  final CarrierCashHolding carrier;
  final String name;
  final Future<void> Function(CarrierCashHolding carrier, String company) onRecord;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final CarrierCashHolding c = carrier;
    final TextStyle? meta =
        Theme.of(context).textTheme.bodySmall?.copyWith(color: DeliveryColors.muted);

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: DeliverySpacing.sm, vertical: DeliverySpacing.sm),
      child: Row(
        children: <Widget>[
          const Icon(Icons.local_shipping_outlined, size: 18, color: DeliveryColors.muted),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
                Text(
                  <String>[
                    if (c.holdsCash) t.carrCashOrderCount(c.orders) else t.carrCashBoHoldsNothing,
                    t.carrCashBoWithRiders(_cash(c.withRiders)),
                    if (c.lastPaidAt == null)
                      t.carrCashBoNeverPaid
                    else
                      t.carrCashBoLastPaid(CarrierCashApi.isoDate(c.lastPaidAt!)),
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: meta,
                ),
              ],
            ),
          ),
          if (c.overdue) ...<Widget>[
            StatePill(label: t.carrCashKpiOverdue, accent: DeliveryAccent.caution),
            const SizedBox(width: DeliverySpacing.sm),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_cash(c.held),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(t.carrCashBoOwes, style: meta),
            ],
          ),
          const SizedBox(width: DeliverySpacing.md),
          // Disabled when the company holds nothing: recording a payment of nothing is not a fact.
          OutlinedButton.icon(
            onPressed: c.holdsCash ? () => onRecord(c, name) : null,
            icon: const Icon(Icons.account_balance_outlined, size: 16),
            label: Text(t.carrCashBoRecordPayment),
          ),
        ],
      ),
    );
  }
}

/// What the operator chose when confirming a company's payment. [method] is null when they did not
/// say — recorded as not said, rather than guessed.
class _PaymentChoice {
  const _PaymentChoice(this.method);

  final CashMethod? method;
}

/// Confirms a payment to the platform — a delivery company's, or a shop's — and asks how it was made.
///
/// [body] says who paid what, and the two are different sentences on purpose: a company clears
/// everything it holds, while a shop pays only what it owes out of its till and keeps its share.
class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.body});

  final String body;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  CashMethod? _method;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return AlertDialog(
      title: Text(t.carrCashBoConfirmTitle),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.body),
            const SizedBox(height: DeliverySpacing.md),
            Text(
              t.carrCashBoMethodLabel,
              style:
                  Theme.of(context).textTheme.labelMedium?.copyWith(color: DeliveryColors.muted),
            ),
            const SizedBox(height: DeliverySpacing.xs),
            Wrap(
              spacing: DeliverySpacing.sm,
              runSpacing: DeliverySpacing.xs,
              children: <Widget>[
                // Only what an operator may record; a pay run's deduction is never a payment.
                for (final CashMethod m in CashMethod.recordable)
                  ChoiceChip(
                    label: Text(_methodLabel(t, m)),
                    selected: _method == m,
                    onSelected: (bool on) => setState(() => _method = on ? m : null),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_PaymentChoice(_method)),
          child: Text(t.carrCashBoConfirmYes),
        ),
      ],
    );
  }
}

String _methodLabel(DeliveryStrings t, CashMethod method) => switch (method) {
      CashMethod.cash => t.carrCashMethodCash,
      CashMethod.bankDeposit => t.carrCashMethodBank,
      CashMethod.wallet => t.carrCashMethodWallet,
      CashMethod.payrollDeduction => t.payrollCashMethodKeptFromPay,
    };

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

/// A company's figure exactly as the ledger wrote it; a dash when it sent none, never a zero.
String _cash(Money? money) => money == null ? '—' : '\$${money.amount}';

String _ago(DateTime time) {
  final Duration d = DateTime.now().difference(time);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}
