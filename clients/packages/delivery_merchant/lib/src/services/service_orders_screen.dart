import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../order_detail_screen.dart';
import '../visible_poller.dart';
import 'service_order_detail_screen.dart';
import 'service_order_files.dart';
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
/// No bottom bar and no back button here: the shell that mounts it owns navigation, and this is a tab.
class ServiceOrdersScreen extends StatefulWidget {
  const ServiceOrdersScreen({
    super.key,
    required this.api,
    this.shopChat,
    this.chatSocket,
    this.files,
    this.openLink,
    this.clock,
  });

  final OrderApi api;

  /// The shop's customer conversations, behind the order detail's "Chat with customer". Null draws no
  /// such button.
  final ShopChatApi? shopChat;

  /// Handed on to the conversations, so a customer's reply arrives live. Null loses only liveness.
  final UserQueueSocket? chatSocket;

  /// The customers' files, for the order detail. Null draws no files section — see
  /// [ServiceOrderFiles].
  final ServiceOrderFiles? files;

  /// Opens a file's link; null opens it with the platform. A test's seam.
  final Future<bool> Function(Uri link)? openLink;

  /// The clock the pickup countdowns read. Null is the device's own.
  final DateTime Function()? clock;

  @override
  State<ServiceOrdersScreen> createState() => _ServiceOrdersScreenState();
}

/// The frame's three tabs.
///
/// Counted from one list rather than fetched per tab, so a tab's count and the cards under it can
/// never disagree. Nothing falls between them: an order a rider has picked up is still in progress to
/// the shop that made it until it is delivered.
enum _Tab {
  fresh(<OrderStatus>[OrderStatus.placed]),
  inProgress(<OrderStatus>[
    OrderStatus.accepted,
    OrderStatus.preparing,
    OrderStatus.ready,
    OrderStatus.pickedUp,
  ]),
  completed(<OrderStatus>[OrderStatus.delivered, OrderStatus.cancelled]);

  const _Tab(this.statuses);

  final List<OrderStatus> statuses;

  bool holds(DeliveryOrder order) => statuses.contains(order.status);

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

class _ServiceOrdersScreenState extends State<ServiceOrdersScreen> {
  /// As often as the goods queue: a new order is a customer waiting to hear whether the shop will do
  /// the job.
  static const Duration _pollEvery = Duration(seconds: 5);

  late final VisiblePoller _poller =
      VisiblePoller(every: _pollEvery, onTick: () => _refresh(silent: true));

  /// Moves the pickup countdowns on between polls that bring no change.
  Timer? _minute;

  List<DeliveryOrder> _orders = const <DeliveryOrder>[];
  Object? _error;
  bool _loading = true;
  String? _busyOrderId;
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

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final Paged<DeliveryOrder> page =
          await widget.api.forMerchant(kind: OrderKind.service, size: 50);
      if (!mounted) return;
      setState(() {
        _orders = page.content;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // A failed background poll must not wipe the queue the shop is looking at.
      setState(() {
        if (!silent) _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _step(DeliveryOrder order, SvcStep step) async {
    final SvcStepResult result = await SvcOrderSteps(widget.api).run(
      context,
      order,
      step,
      onSending: () {
        if (mounted) setState(() => _busyOrderId = order.id);
      },
    );
    if (!mounted) return;
    setState(() => _busyOrderId = null);
    if (result == SvcStepResult.reload) await _refresh(silent: true);
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

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<DeliveryOrder> visible = _orders.where(_tab.holds).toList(growable: false);

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
              _body(t, visible, constraints.maxWidth),
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
    final int count = _orders.where(tab.holds).length;
    // As drawn: "New (3)", "In progress (2)", and a bare "Completed" — a count of everything ever
    // finished is not a number anybody acts on.
    final String label =
        tab == _Tab.completed || count == 0 ? tab.labelIn(t) : '${tab.labelIn(t)} ($count)';

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: selected ? null : () => setState(() => _tab = tab),
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

  Widget _body(DeliveryStrings t, List<DeliveryOrder> visible, double width) {
    final double side =
        width > merchantMaxContentWidth ? (width - merchantMaxContentWidth) / 2 : 0;
    final EdgeInsets pad = EdgeInsets.fromLTRB(
      DeliverySpacing.md + side,
      DeliverySpacing.md,
      DeliverySpacing.md + side,
      DeliverySpacing.xl,
    );

    final Widget? standIn = _standIn(t, visible);
    if (standIn != null) {
      return SliverPadding(padding: pad, sliver: SliverToBoxAdapter(child: standIn));
    }

    final DateTime now = _now();
    return SliverPadding(
      padding: pad,
      sliver: SliverList.separated(
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.md),
        itemBuilder: (BuildContext context, int i) {
          final DeliveryOrder order = visible[i];
          return _ServiceOrderCard(
            order: order,
            now: now,
            busy: _busyOrderId == order.id,
            onStep: (SvcStep step) => _step(order, step),
            onOpen: () => _open(order),
          );
        },
      ),
    );
  }

  /// Loading, failed, or an empty tab — or null when there are cards to draw.
  Widget? _standIn(DeliveryStrings t, List<DeliveryOrder> visible) {
    if (_error != null) {
      return YdEmptyState(
        icon: Icons.cloud_off_rounded,
        title: t.couldNotLoadOrdersShort,
        message: t.thatDidNotGoThrough,
        action: YdPillButton.secondary(
          label: t.tryAgain,
          onPressed: () => _refresh(),
          size: YdPillButtonSize.compact,
          expand: false,
        ),
      );
    }
    if (_loading && _orders.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(DeliverySpacing.xl),
        child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
      );
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
      if (!order.isPickup) return order.fulfilment == Fulfilment.delivery ? t.svcWaitingForRider : null;
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
