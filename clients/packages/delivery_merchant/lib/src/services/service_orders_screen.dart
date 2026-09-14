import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../order_detail_screen.dart';
import '../visible_poller.dart';
import 'service_order_detail_screen.dart';
import 'service_order_steps.dart';
import 'service_words.dart';

/// A services shop's order queue — Figma `service-provider-orders` (126:200), "Incoming orders".
///
/// Its own screen rather than a mode of the goods queue, because the two disagree about nearly
/// everything a card says: who ordered (a name, where a basket shows a number), what (1,000 cards in
/// a finish, where a basket lists lines), how it leaves (a counter or a rider), and what a shop may do
/// about it (decline with a reason, collected at the counter, cancel an uncollected pickup after its
/// time). What the two share — polling, buttons strictly from what the server offers, and a 422 meaning
/// another device acted first — is the same here.
///
/// Three tabs, as drawn: New, In progress, Completed. The frame has no place for a READY order; it sits
/// in In progress with the line that says what it is waiting for — the customer, or a rider — because
/// it is still the shop's to hand over. Service orders only: a merchant who also runs a goods shop
/// sees those in the goods queue.
///
/// New and In progress are read by status, every page of them; Completed is read on its own, newest
/// first, a page at a time. Not one newest page split three ways, which is what this screen first did:
/// a job runs for up to a month and a pickup can wait days at the counter, so on a busy shop the orders
/// still in hand were exactly the ones that fell off that page — and their buttons with them.
///
/// No bottom bar here: the shell that mounts it owns navigation. [onBack] draws a back button, for a
/// host that pushes the queue as a page rather than showing it as a tab.
class ServiceOrdersScreen extends StatefulWidget {
  const ServiceOrdersScreen({
    super.key,
    required this.api,
    this.shopChat,
    this.chatSocket,
    this.files,
    this.openLink,
    this.clock,
    this.onBack,
  });

  final OrderApi api;

  /// The shop's customer conversations, behind the order detail's "Chat with customer". Null draws no
  /// such button.
  final ShopChatApi? shopChat;

  /// Handed on to the conversations, so a customer's reply arrives live. Null loses only liveness.
  final UserQueueSocket? chatSocket;

  /// The customers' files, for the order detail: Order Manager's attachment read, which an order's
  /// shop may make. Null draws no files section.
  final OrderAttachmentApi? files;

  /// Opens a file's link; null opens it with the platform. A test's seam.
  final Future<bool> Function(Uri link)? openLink;

  /// The clock the pickup countdowns read. Null is the device's own.
  final DateTime Function()? clock;

  /// Draws a back button that calls this. Null draws none, which is what a tab wants.
  final VoidCallback? onBack;

  @override
  State<ServiceOrdersScreen> createState() => _ServiceOrdersScreenState();
}

/// The frame's three tabs, cut along the order status machine.
///
/// New is an order nobody has answered yet (PLACED). Completed is an order no transition leaves
/// ([OrderStatus.isTerminal]: collected, delivered, declined or cancelled). In progress is everything
/// between — accepted, in production, ready, and out with a rider — so nothing falls between the tabs,
/// and an order a rider has picked up is still in progress to the shop that made it until it is
/// delivered.
enum _Tab {
  fresh,
  inProgress,
  completed;

  static _Tab of(OrderStatus status) {
    if (status == OrderStatus.placed) return _Tab.fresh;
    return status.isTerminal ? _Tab.completed : _Tab.inProgress;
  }

  /// Checked on every order drawn, not only asked of the server: an Order Manager from before the
  /// status filter answers every state, and then this is what keeps each order in its own tab.
  bool holds(DeliveryOrder order) => of(order.status) == this;

  String labelIn(DeliveryStrings t) => switch (this) {
        _Tab.fresh => t.svcTabNew,
        _Tab.inProgress => t.svcTabInProgress,
        _Tab.completed => t.svcTabCompleted,
      };

  String emptyIn(DeliveryStrings t) => switch (this) {
        _Tab.fresh => t.svcNoNewOrders,
        _Tab.inProgress => t.svcNoOrdersInProgress,
        _Tab.completed => t.svcNoCompletedOrders,
      };
}

/// The states New and In progress hold, asked for in one read — so the two tabs' counts come from one
/// answer and cannot disagree with each other.
final List<OrderStatus> _liveStatuses = <OrderStatus>[
  for (final OrderStatus status in OrderStatus.values)
    if (_Tab.of(status) != _Tab.completed) status,
];

final List<OrderStatus> _finishedStatuses = <OrderStatus>[
  for (final OrderStatus status in OrderStatus.values)
    if (_Tab.of(status) == _Tab.completed) status,
];

class _ServiceOrdersScreenState extends State<ServiceOrdersScreen> {
  /// As often as the goods queue: a new order is a customer waiting to hear whether the shop will do
  /// the job.
  static const Duration _pollEvery = Duration(seconds: 5);

  /// A page of the live queue. Most shops' whole queue fits in one.
  static const int _livePageSize = 50;

  /// The most pages of live orders one read takes. Only a stop for a read that would not end: a
  /// thousand jobs in hand at once is not a shop this screen was drawn for.
  static const int _maxLivePages = 20;

  /// A page of finished orders: the first read, and what each Load more adds.
  static const int _completedPageSize = 20;

  late final VisiblePoller _poller =
      VisiblePoller(every: _pollEvery, onTick: () => _refresh(silent: true));

  /// Moves the pickup countdowns on between polls that bring no change.
  Timer? _minute;

  /// Every service order in a live state: New's and In progress's.
  List<DeliveryOrder> _live = const <DeliveryOrder>[];
  Object? _error;
  bool _loading = true;

  /// Completed's orders, newest first, as many pages as have been read. Null until the tab is first
  /// opened: a shop that never looks back does not pay for reading its history on every visit.
  List<DeliveryOrder>? _completed;
  int _completedPages = 0;
  bool _completedHasMore = false;
  bool _completedLoading = false;
  Object? _completedError;
  bool _completedMoreFailed = false;

  /// The orders with a step on its way. Their buttons spin and take no second tap until the order has
  /// been read back — not merely until the step answered, which would leave a moment where the card
  /// still offers the step it has just taken.
  final Set<String> _busy = <String>{};

  /// Moves on each time a step is sent and each time one answers. A read begun before the latest move
  /// may show an order as it stood before the step, so it is not drawn: without this, a poll that left
  /// before an Accept and landed after it put the Accept button back on an accepted order.
  int _generation = 0;

  /// Numbers the live reads, so one that lands after a newer read has been drawn is dropped.
  int _liveRead = 0;
  int _liveDrawn = 0;

  /// Numbers Completed's reads, so an older one never lands on top of a newer one.
  int _completedRead = 0;

  _Tab _tab = _Tab.fresh;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _refresh();
    _poller.start();
    _minute = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _poller.dispose();
    _minute?.cancel();
    super.dispose();
  }

  /// Reads the live queue again — and Completed with it, once that tab has been opened, when the shop
  /// asked ([silent] false) or an order just left the live queue, finished and so Completed's now.
  Future<void> _refresh({bool silent = false}) async {
    final bool finished = await _readLive(silent: silent);
    if (!mounted || _completed == null) return;
    if (finished || !silent) await _readCompleted();
  }

  /// Reads every live order, and answers whether an order the screen held has left the live states.
  Future<bool> _readLive({bool silent = false}) async {
    final int generation = _generation;
    final int read = ++_liveRead;
    if (!silent) setState(() => _loading = true);
    try {
      final List<DeliveryOrder> live = await _allLive();
      if (!mounted || generation != _generation || read < _liveDrawn) {
        // Begun before a step moved an order, or overtaken by a newer read: the read that step began,
        // or that newer read, says what is true now.
        return false;
      }
      _liveDrawn = read;
      final Set<String> still = <String>{for (final DeliveryOrder order in live) order.id};
      final bool finished = _live.any((DeliveryOrder order) => !still.contains(order.id));
      setState(() {
        _live = live;
        _error = null;
        _loading = false;
      });
      return finished;
    } catch (e) {
      if (!mounted) return false;
      // A failed background poll must not wipe the queue the shop is looking at.
      setState(() {
        if (!silent && generation == _generation) _error = e;
        _loading = false;
      });
      return false;
    }
  }

  /// The live orders, newest first, page after page to the last.
  ///
  /// An Order Manager from before the status filter answers every state, and its later pages would be
  /// the shop's whole history. A page holding a finished order says that is what answered, and the
  /// read stops there: the newest page, split by [_Tab.holds], which is what this screen always drew.
  Future<List<DeliveryOrder>> _allLive() async {
    final List<DeliveryOrder> found = <DeliveryOrder>[];
    final Set<String> seen = <String>{};
    for (int page = 0; page < _maxLivePages; page++) {
      final Paged<DeliveryOrder> answer = await widget.api.forMerchant(
        kind: OrderKind.service,
        statuses: _liveStatuses,
        page: page,
        size: _livePageSize,
      );
      // An order placed while the pages are read pushes the rest down a place: each is kept once.
      for (final DeliveryOrder order in answer.content) {
        if (seen.add(order.id)) found.add(order);
      }
      final bool unfiltered = answer.content.any((DeliveryOrder order) => order.status.isTerminal);
      if (unfiltered || answer.content.isEmpty || page + 1 >= answer.totalPages) break;
    }
    return found;
  }

  /// Completed's newest page, put in front of what was read before — or, with [more], the page after
  /// the last one read.
  ///
  /// In front of, rather than instead of: a finished order never changes again, so nothing read before
  /// is wrong, and a shop that has loaded three pages keeps them when one more order finishes.
  Future<void> _readCompleted({bool more = false}) async {
    final int read = ++_completedRead;
    final int page = more ? _completedPages : 0;
    setState(() {
      _completedLoading = true;
      _completedMoreFailed = false;
    });
    try {
      final Paged<DeliveryOrder> answer = await widget.api.forMerchant(
        kind: OrderKind.service,
        statuses: _finishedStatuses,
        page: page,
        size: _completedPageSize,
      );
      if (!mounted || read != _completedRead) return;
      final List<DeliveryOrder> held = _completed ?? const <DeliveryOrder>[];
      final Set<String> heldIds = <String>{for (final DeliveryOrder order in held) order.id};
      final Set<String> answered = <String>{
        for (final DeliveryOrder order in answer.content) order.id,
      };
      setState(() {
        _completed = more
            ? <DeliveryOrder>[
                ...held,
                for (final DeliveryOrder order in answer.content)
                  if (!heldIds.contains(order.id)) order,
              ]
            : <DeliveryOrder>[
                ...answer.content,
                for (final DeliveryOrder order in held)
                  if (!answered.contains(order.id)) order,
              ];
        if (more || _completedPages == 0) _completedPages = page + 1;
        _completedHasMore = _completedPages < answer.totalPages;
        _completedLoading = false;
        _completedError = null;
      });
    } catch (e) {
      if (!mounted || read != _completedRead) return;
      setState(() {
        _completedLoading = false;
        if (more) {
          _completedMoreFailed = true;
        } else if (_completed == null) {
          _completedError = e;
        }
      });
    }
  }

  Future<void> _step(DeliveryOrder order, SvcStep step) async {
    // A second tap while the step is out, or while its order is read back, does nothing.
    if (_busy.contains(order.id)) return;
    final SvcStepResult result = await SvcOrderSteps(widget.api).run(
      context,
      order,
      step,
      onSending: () {
        _generation++;
        if (mounted) setState(() => _busy.add(order.id));
      },
    );
    if (!mounted || result == SvcStepResult.dismissed) return;
    // The step has answered, so what it did is on the server: every read begun before now is stale.
    _generation++;
    await _refresh(silent: true);
    if (mounted) setState(() => _busy.remove(order.id));
  }

  void _open(DeliveryOrder order) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ServiceOrderDetailScreen(
        api: widget.api,
        order: order,
        shopChat: widget.shopChat,
        chatSocket: widget.chatSocket,
        files: widget.files,
        openLink: widget.openLink,
        clock: widget.clock,
        // The detail moves orders on too, so the queue behind it reads them again.
        onChanged: (_) => _refresh(silent: true),
      ),
    ));
  }

  void _select(_Tab tab) {
    setState(() => _tab = tab);
    if (tab == _Tab.completed && _completed == null && !_completedLoading) _readCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<DeliveryOrder> source =
        _tab == _Tab.completed ? (_completed ?? const <DeliveryOrder>[]) : _live;
    final List<DeliveryOrder> visible = source.where(_tab.holds).toList(growable: false);

    return ColoredBox(
      color: DeliveryColors.background,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) => RefreshIndicator(
          onRefresh: () => _refresh(),
          color: DeliveryColors.brand,
          // One scroll for the page: the header and the tabs scroll away with the queue, so a phone
          // held sideways still shows cards rather than a pinned title.
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: MerchantScreenHeader(
                  title: t.svcIncomingOrders,
                  onBack: widget.onBack,
                  backSemanticLabel: widget.onBack == null ? null : t.back,
                  // The frame's overflow has no defined actions; the portal needs a refresh a mouse can
                  // reach, and a dead "…" would be a control that does nothing.
                  trailing: IconButton(
                    onPressed: () => _refresh(),
                    icon: const Icon(Icons.refresh, size: 20),
                    color: DeliveryColors.muted,
                    tooltip: t.refresh,
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _tabs(t)),
              ..._body(t, visible, constraints.maxWidth),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabs(DeliveryStrings t) {
    return Container(
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          for (final _Tab tab in _Tab.values) Expanded(child: _tabButton(tab, t)),
        ],
      ),
    );
  }

  Widget _tabButton(_Tab tab, DeliveryStrings t) {
    final bool selected = tab == _tab;
    // As drawn: "New (3)", "In progress (2)", and a bare "Completed" — a count of everything ever
    // finished is not a number anybody acts on.
    final int count = tab == _Tab.completed ? 0 : _live.where(tab.holds).length;
    final String label = count == 0 ? tab.labelIn(t) : '${tab.labelIn(t)} ($count)';

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: selected ? null : () => _select(tab),
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
          padding: const EdgeInsetsDirectional.symmetric(horizontal: DeliverySpacing.xs),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? DeliveryColors.brand : const Color(0x00000000),
                width: 3,
              ),
            ),
          ),
          // Scaled down rather than cut: "In progress (12)" in Arabic on a 320dp phone is wider than a
          // third of it, and a count that loses its last digit is a wrong number.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? DeliveryColors.brand : DeliveryColors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(DeliveryStrings t, List<DeliveryOrder> visible, double width) {
    final double side =
        width > merchantMaxContentWidth ? (width - merchantMaxContentWidth) / 2 : 0;
    final EdgeInsets pad = EdgeInsets.fromLTRB(
      DeliverySpacing.md + side,
      DeliverySpacing.md,
      DeliverySpacing.md + side,
      DeliverySpacing.xl,
    );

    final Widget? standIn = _standIn(t, visible);
    final Widget? footer =
        _tab == _Tab.completed && _completed != null ? _completedFooter(t) : null;
    final DateTime now = _now();

    return <Widget>[
      SliverPadding(
        padding: footer == null ? pad : pad.copyWith(bottom: DeliverySpacing.md),
        sliver: standIn != null
            ? SliverToBoxAdapter(child: standIn)
            : SliverList.separated(
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.md),
                itemBuilder: (BuildContext context, int i) {
                  final DeliveryOrder order = visible[i];
                  return _ServiceOrderCard(
                    order: order,
                    now: now,
                    busy: _busy.contains(order.id),
                    onStep: (SvcStep step) => _step(order, step),
                    onOpen: () => _open(order),
                  );
                },
              ),
      ),
      if (footer != null)
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad.left, 0, pad.right, DeliverySpacing.xl),
          sliver: SliverToBoxAdapter(child: footer),
        ),
    ];
  }

  /// Loading, failed, or an empty tab — or null when there are cards to draw.
  Widget? _standIn(DeliveryStrings t, List<DeliveryOrder> visible) {
    if (_tab == _Tab.completed) {
      if (_completed == null) {
        return _completedError != null ? _failed(t, _readCompleted) : _spinner();
      }
    } else {
      if (_error != null) return _failed(t, _refresh);
      if (_loading && _live.isEmpty) return _spinner();
    }
    if (visible.isEmpty) {
      return YdEmptyState(
        icon: Icons.receipt_long_outlined,
        title: _tab.emptyIn(t),
        message: t.svcOrdersEmptyBody,
      );
    }
    return null;
  }

  Widget _spinner() => const Padding(
        padding: EdgeInsets.all(DeliverySpacing.xl),
        child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
      );

  Widget _failed(DeliveryStrings t, Future<void> Function() retry) {
    return YdEmptyState(
      icon: Icons.cloud_off_rounded,
      title: t.couldNotLoadOrdersShort,
      message: t.thatDidNotGoThrough,
      action: YdPillButton.secondary(
        label: t.tryAgain,
        onPressed: () => retry(),
        size: YdPillButtonSize.compact,
        expand: false,
      ),
    );
  }

  /// Under Completed: Load more while the server holds more, a spinner while a page is read, and a line
  /// that says so when one could not be. Null when everything has been read.
  Widget? _completedFooter(DeliveryStrings t) {
    if (_completedLoading) {
      return const Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
        ),
      );
    }
    if (!_completedHasMore) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_completedMoreFailed) ...<Widget>[
          Text(
            t.couldNotLoadMore,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: DeliveryColors.muted),
          ),
          const SizedBox(height: DeliverySpacing.xs),
        ],
        YdPillButton.secondary(
          label: t.svcLoadMore,
          onPressed: () => _readCompleted(more: true),
          size: YdPillButtonSize.compact,
          expand: false,
        ),
      ],
    );
  }
}

/// One order in the queue — the frame's card: who, when, the chip, the job, what it earns, and the
/// steps the server offers.
class _ServiceOrderCard extends StatelessWidget {
  const _ServiceOrderCard({
    required this.order,
    required this.now,
    required this.busy,
    required this.onStep,
    required this.onOpen,
  });

  final DeliveryOrder order;
  final DateTime now;
  final bool busy;
  final void Function(SvcStep step) onStep;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String age = merchantTimeAgo(order.placedAt, t);
    final OrderLine? line = order.items.isEmpty ? null : order.items.first;
    final double amount = svcShopAmount(order);
    final String? lbp = svcLbp(amount, t);
    final Widget? fulfilment = svcFulfilmentChip(order, t);
    final String? note = svcOrderNote(context, order, now);

    return YdCard.bordered(
      onTap: onOpen,
      padding: const EdgeInsets.all(DeliverySpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              SvcCustomerAvatar(name: order.customerDisplayName),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      order.customerDisplayName ?? t.chatShopCustomer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                      ),
                    ),
                    if (age.isNotEmpty)
                      Text(
                        age,
                        maxLines: 1,
                        style: const TextStyle(fontSize: 11, color: DeliveryColors.faint),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              SvcOrderChip(order: order),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          const MerchantDivider(),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          if (line != null) ...<Widget>[
            Text(
              svcJobTitle(line, t),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.ink,
                height: 1.3,
              ),
            ),
            if (svcJobDetail(line, t) case final String detail)
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.35),
              ),
            const SizedBox(height: DeliverySpacing.xs),
          ],
          Row(
            children: <Widget>[
              Expanded(
                child: Wrap(
                  spacing: DeliverySpacing.xs + 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      svcUsd(amount, t),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.brand,
                      ),
                    ),
                    if (lbp != null)
                      Text(
                        lbp,
                        style: const TextStyle(fontSize: 11, color: DeliveryColors.faint),
                      ),
                  ],
                ),
              ),
              if (fulfilment != null) ...<Widget>[
                const SizedBox(width: DeliverySpacing.sm),
                fulfilment,
              ],
            ],
          ),
          if (note != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Text(
              note,
              style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.35),
            ),
          ],
          if (svcStepsFor(order) case final List<SvcStep> steps when steps.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            SvcStepRow(steps: steps, busy: busy, onStep: onStep),
          ],
        ],
      ),
    );
  }
}

/// The one line a card adds under the price: when the work is promised, what a ready order waits for,
/// how long before an uncollected pickup may be cancelled, or why the shop declined. Null when there
/// is nothing to add.
String? svcOrderNote(BuildContext context, DeliveryOrder order, DateTime now) {
  final DeliveryStrings t = DeliveryStrings.of(context);
  switch (order.status) {
    case OrderStatus.accepted || OrderStatus.preparing:
      final DateTime? promised = order.estimatedReadyAt;
      return promised == null
          ? null
          : t.svcReadyBy(svcWhenFormatter(context, clock: () => now)(promised));
    case OrderStatus.ready:
      if (!order.isPickup) {
        if (order.fulfilment != Fulfilment.delivery) return null;
        // A rider who has claimed the job is on the way to the counter; until one has, it waits for one.
        return order.riderId != null ? t.svcRiderOnTheWay : t.svcWaitingForRider;
      }
      final Duration? left = order.untilCancellableAsNotCollected(now);
      // The countdown only while the button is still locked: once the server offers the cancel, the
      // button says it.
      if (left != null && left > Duration.zero && !order.canCancelAsNotCollected) {
        return '${t.svcWaitingForPickup} · ${t.svcCancelNotCollectedIn(svcDuration(left, t))}';
      }
      return t.svcWaitingForPickup;
    case OrderStatus.cancelled:
      return order.declineReason?.labelIn(t);
    case OrderStatus.placed || OrderStatus.pickedUp || OrderStatus.delivered:
      return null;
  }
}
