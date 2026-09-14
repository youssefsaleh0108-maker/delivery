import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart' show ShopThreadScreen;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'order_tracking_panel.dart';
import 'service_order_words.dart';

/// Tracking one service order (Figma 126:507): straight after placing it, or from the Orders tab.
///
/// What the frame draws, corrected where it drew something the platform does not have:
///
/// * **The order's own reference.** The frame's "Order #8842" is a number nothing produces; order
///   ids are UUIDs and every screen of the app names an order by its eight-character short id.
/// * **A timeline by kind and fulfilment** ([serviceTimeline]) rather than the frame's five fixed
///   rows: a pickup ends "Collected", a delivery passes "Out for delivery", and an order that ended
///   early says how — declined with the provider's reason, never collected, or cancelled.
/// * **A promise only when there is one.** Once accepted, the server's `estimatedReadyAt`; before
///   that, the offer's turnaround "confirmed once the provider accepts"; after the work is ready, or
///   once the order has ended, no card at all.
/// * **The shop, not "Support Representative".** The card is the provider's. Its chat button opens
///   the customer's existing thread with that shop, and is drawn only when this app has the shop
///   chat client — a button that cannot open anything is not drawn.
/// * **Pickup is not a delivery.** A pickup shows where to collect and the shop's hours today, and
///   never a rider map: nobody is riding. A delivery mounts the rider tracking panel once it is out.
///
/// The order is read again every [refreshEvery] while it is still moving, so a provider's accept
/// arrives without the customer pulling to refresh.
class ServiceOrderTrackingScreen extends StatefulWidget {
  const ServiceOrderTrackingScreen({
    super.key,
    required this.orderApi,
    required this.storeApi,
    required this.orderId,
    this.preview,
    this.shopChatApi,
    this.chatSocket,
    this.trackingApi,
    this.trackingSocket,
    this.chatApi,
    this.refreshEvery = const Duration(seconds: 20),
  });

  final OrderApi orderApi;

  /// The shop's address and hours for a pickup, and its logo.
  final StoreApi storeApi;
  final String orderId;

  /// The order as the screen that opened this one already had it — the placement's answer, or the
  /// Orders list's row — drawn at once instead of a spinner. Replaced by the server's copy.
  final DeliveryOrder? preview;

  /// The customer's conversations with shops. Null draws no chat button.
  final ShopChatApi? shopChatApi;

  /// App Notification's socket, for a live thread. Null loses only liveness.
  final UserQueueSocket? chatSocket;

  /// Handed to the rider tracking panel of a delivery that is out. Each optional, as the panel's own.
  final TrackingApi? trackingApi;
  final UserQueueSocket? trackingSocket;
  final ChatApi? chatApi;

  final Duration refreshEvery;

  @override
  State<ServiceOrderTrackingScreen> createState() => _ServiceOrderTrackingScreenState();
}

class _ServiceOrderTrackingScreenState extends State<ServiceOrderTrackingScreen> {
  DeliveryOrder? _order;
  List<OrderStatusChange> _history = const <OrderStatusChange>[];

  /// The shop behind the order, for its logo, address and hours. Null until read, and for good when
  /// it cannot be: the card then carries the order's own snapshot of the shop's name.
  Store? _shop;
  List<OpeningWindow>? _hours;
  bool _askedShop = false;

  bool _failed = false;
  bool _cancelling = false;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _order = widget.preview;
    unawaited(_load());
    _refresh = Timer.periodic(widget.refreshEvery, (_) {
      if (_order?.status.isTerminal ?? false) return;
      unawaited(_load(silent: true));
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && _failed) setState(() => _failed = false);
    // Asked beside the order rather than after it; a timeline without its history still draws from
    // the order's status, so a history that cannot be read is not a failure of the screen.
    final Future<List<OrderStatusChange>> history = _readHistory();
    try {
      final DeliveryOrder order = await widget.orderApi.read(widget.orderId);
      final List<OrderStatusChange> steps = await history;
      if (!mounted) return;
      setState(() {
        _order = order;
        _history = steps;
        _failed = false;
      });
      final String? storeId = order.storeId;
      if (!_askedShop && storeId != null) {
        _askedShop = true;
        unawaited(_loadShop(storeId, pickup: order.isPickup));
      }
    } catch (_) {
      if (!mounted) return;
      // Only when there is nothing to show: an order already on screen is still the best answer the
      // phone has, and swapping it for an error would take it away.
      if (_order == null) setState(() => _failed = true);
    }
  }

  Future<List<OrderStatusChange>> _readHistory() async {
    try {
      return await widget.orderApi.statusHistory(widget.orderId);
    } catch (_) {
      return _history;
    }
  }

  Future<void> _loadShop(String storeId, {required bool pickup}) async {
    try {
      final Store shop = await widget.storeApi.read(storeId);
      if (!mounted) return;
      setState(() => _shop = shop);
      if (!pickup) return;
      final List<OpeningWindow> hours = await widget.storeApi.hours(storeId);
      if (mounted) setState(() => _hours = hours);
    } catch (_) {
      // The card keeps the order's own shop name; the address and hours are simply not drawn.
    }
  }

  Future<void> _cancel(DeliveryOrder order) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(t.cancelThisOrder),
        content: Text(t.cancelBeforeAccepted),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.keepIt)),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.cancelOrder)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      // Not translated: the audit reason stored on the order for the shop and support, as the Orders
      // list's cancel sends it.
      final DeliveryOrder updated =
          await widget.orderApi.act(order.id, OrderAction.cancel, reason: 'Cancelled by customer');
      if (!mounted) return;
      setState(() {
        _order = updated;
        _cancelling = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.response?.statusCode == 422 ? t.tooLateToCancel : t.couldNotCancelOrder)));
    }
    unawaited(_load(silent: true));
  }

  void _openChat(DeliveryOrder order) {
    final ShopChatApi? api = widget.shopChatApi;
    final String? storeId = order.storeId;
    if (api == null || storeId == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ShopThreadScreen(
        api: api,
        open: () => api.openWithStore(storeId),
        title: order.storeName ?? _shop?.name,
        socket: widget.chatSocket,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SafeArea(
            bottom: false,
            child: YdScreenHeader(
              title: t.svcTrackTitle,
              onBack: () => Navigator.of(context).maybePop(),
              backSemanticLabel: t.back,
            ),
          ),
          Expanded(child: _body(t)),
        ],
      ),
    );
  }

  Widget _body(DeliveryStrings t) {
    final DeliveryOrder? order = _order;
    if (order == null) {
      if (_failed) {
        return YdEmptyState(
          icon: Icons.cloud_off_rounded,
          title: t.couldNotLoadOrder,
          action: YdPillButton(
            label: t.tryAgain,
            expand: false,
            size: YdPillButtonSize.compact,
            onPressed: () => _load(),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }

    final Widget? estimate = _estimateCard(order, t);
    final String? instructions = order.serviceLine?.instructions;
    final bool canCancel =
        order.status == OrderStatus.placed && order.availableActions.contains(OrderAction.cancel);
    const SizedBox gap = SizedBox(height: DeliverySpacing.md);

    return RefreshIndicator(
      color: DeliveryColors.brand,
      onRefresh: () => _load(silent: true),
      child: ListView(
        padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
        children: <Widget>[
          _heading(order, t),
          if (estimate != null) ...<Widget>[gap, estimate],
          const SizedBox(height: DeliverySpacing.md + 4),
          _caption(t.svcOrderStatusTitle),
          const SizedBox(height: DeliverySpacing.sm),
          YdCard.bordered(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final (int i, ServiceTimelineStep step)
                    in serviceTimeline(order, _history, t).indexed) ...<Widget>[
                  if (i > 0) const SizedBox(height: DeliverySpacing.md - 2),
                  ServiceTimelineRow(step: step),
                ],
              ],
            ),
          ),
          gap,
          _providerCard(order, t),
          gap,
          _fulfilmentCard(order, t),
          if (instructions != null) ...<Widget>[gap, _instructionsCard(instructions, t)],
          gap,
          _summaryCard(order, t),
          if (canCancel) ...<Widget>[
            gap,
            YdPillButton.secondary(
              label: t.cancelOrder,
              busy: _cancelling,
              onPressed: _cancelling ? null : () => _cancel(order),
            ),
          ],
          const SizedBox(height: DeliverySpacing.lg),
        ],
      ),
    );
  }

  Widget _heading(DeliveryOrder order, DeliveryStrings t) {
    final List<String> about = <String>[
      if ((order.storeName ?? '').isNotEmpty) order.storeName!,
      if (order.serviceCategory != null) order.serviceCategory!.labelIn(t),
    ];
    final DeliveryAccent? accent = switch (order.status) {
      OrderStatus.delivered => DeliveryAccent.positive,
      OrderStatus.cancelled => DeliveryAccent.critical,
      _ => null,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                t.svcOrderNumber(order.shortId),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: DeliveryColors.ink, height: 1.25),
              ),
              if (about.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  about.join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: DeliveryColors.muted, height: 1.3),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        YdBadge(
          label: serviceStatusLabel(order, t),
          color: accent?.onTint ?? DeliveryColors.brand,
          background: accent?.tint ?? DeliveryColors.brandSoft,
        ),
      ],
    );
  }

  /// The frame's estimated-completion card, only while there is a promise to show.
  Widget? _estimateCard(DeliveryOrder order, DeliveryStrings t) {
    String? value;
    switch (order.status) {
      case OrderStatus.accepted:
      case OrderStatus.preparing:
        final DateTime? at = order.estimatedReadyAt;
        if (at != null) value = serviceWhenLabel(context, at);
      case OrderStatus.placed:
        final ServiceOrderLine? line = order.serviceLine;
        final String? range = line == null
            ? null
            : serviceTurnaroundLabel(line.turnaroundMinHours, line.turnaroundMaxHours, t);
        if (range != null) value = t.svcEstimateAfterAccept(range);
      case OrderStatus.ready:
      case OrderStatus.pickedUp:
      case OrderStatus.delivered:
      case OrderStatus.cancelled:
        break;
    }
    if (value == null) return null;
    // For a delivery the promise is when the work is ready, not when it arrives — said so.
    final String caption = order.isPickup ? t.svcEstimatedCompletion : t.svcReadyBy;
    return YdCard.bordered(
      child: Row(
        children: <Widget>[
          const Icon(Icons.schedule_rounded, size: 24, color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.md - 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _caption(caption),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: DeliveryColors.ink, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _providerCard(DeliveryOrder order, DeliveryStrings t) {
    final String name = order.storeName ?? _shop?.name ?? t.tabShop;
    final bool canChat = widget.shopChatApi != null && order.storeId != null;
    return YdCard.bordered(
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - 4),
      child: Row(
        children: <Widget>[
          ClipOval(child: StoreAvatar(name: name, logoUrl: _shop?.listLogoUrl, size: 40)),
          const SizedBox(width: DeliverySpacing.md - 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: DeliveryColors.ink),
                ),
                const SizedBox(height: 2),
                Text(t.svcProviderRole,
                    style: const TextStyle(fontSize: 11.5, color: DeliveryColors.muted)),
              ],
            ),
          ),
          if (canChat)
            Semantics(
              container: true,
              button: true,
              label: t.chatShopWith(name),
              child: Material(
                color: DeliveryColors.brandSoft,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _openChat(order),
                  child: const SizedBox.square(
                    dimension: 38,
                    child: Icon(Icons.chat_bubble_outline_rounded,
                        size: 18, color: DeliveryColors.brand),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fulfilmentCard(DeliveryOrder order, DeliveryStrings t) {
    if (order.isPickup) {
      final String name = order.storeName ?? _shop?.name ?? '';
      final String? address = _shop?.address;
      final String? today = _hoursToday(t);
      return YdCard.bordered(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _iconLine(Icons.storefront_outlined, t.svcPickupFrom(name)),
            if (address != null && address.trim().isNotEmpty) _detailLine(address),
            if (today != null) _detailLine(today),
            if (!order.status.isTerminal) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 28),
                child: Text(
                  t.svcShowNumberAtPickup,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: DeliveryColors.brand),
                ),
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        YdCard.bordered(
            child: _iconLine(Icons.location_on_outlined, t.svcDeliveringTo(order.deliveryAddress))),
        // The rider's map only while a rider has the work: before that nobody is moving, and after it
        // the panel has nothing left to show.
        if (order.status == OrderStatus.pickedUp && order.fulfilment == Fulfilment.delivery) ...<Widget>[
          const SizedBox(height: DeliverySpacing.md),
          OrderTrackingPanel(
            api: widget.orderApi,
            order: order,
            trackingApi: widget.trackingApi,
            liveSocket: widget.trackingSocket,
            chatApi: widget.chatApi,
          ),
        ],
      ],
    );
  }

  /// The shop's hours today, as its opening windows give them; null until they are known.
  String? _hoursToday(DeliveryStrings t) {
    final List<OpeningWindow>? hours = _hours;
    if (hours == null) return null;
    final int weekday = DateTime.now().weekday;
    final List<String> spans = <String>[
      for (final OpeningWindow window in hours.where((OpeningWindow w) => w.dayOfWeek == weekday))
        if ((serviceClockLabel(context, window.opensAt), serviceClockLabel(context, window.closesAt))
            case (final String opens, final String closes))
          '$opens – $closes',
    ];
    return t.svcTodayAt(spans.isEmpty ? t.statusClosed : spans.join(', '));
  }

  Widget _instructionsCard(String words, DeliveryStrings t) {
    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(t.svcYourInstructions,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: DeliveryColors.ink)),
          const SizedBox(height: DeliverySpacing.xs),
          Text(words,
              style: const TextStyle(fontSize: 13, color: DeliveryColors.ink, height: 1.4)),
        ],
      ),
    );
  }

  Widget _summaryCard(DeliveryOrder order, DeliveryStrings t) {
    final OrderLine? line = order.items.isEmpty ? null : order.items.first;
    final ServiceOrderLine? terms = order.serviceLine;
    final String detail = <String>[
      if (terms?.unitLabel case final String unit) t.svcUnitsLine(svcCount(terms!.units), unit),
      if ((line?.optionsSummary ?? '').isNotEmpty) line!.optionsSummary!,
    ].join(' · ');
    final double discount = order.discountAmount ?? 0;
    final String? lbp = MarketRates.instance.lbp(order.totalAmount);

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(t.svcSummary,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: DeliveryColors.ink)),
          if (line != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Text(line.productName,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: DeliveryColors.ink)),
            if (detail.isNotEmpty)
              Text(detail, style: const TextStyle(fontSize: 12, color: DeliveryColors.muted)),
          ],
          const SizedBox(height: DeliverySpacing.sm),
          _moneyRow(t.subtotal, svcUsd(order.goodsSubtotal)),
          _moneyRow(
            t.svcDeliveryFee,
            order.isPickup || order.deliveryFeeCharged == 0 ? t.free : svcUsd(order.deliveryFeeCharged),
          ),
          if (discount > 0) _moneyRow(t.svcDiscount, '-${svcUsd(discount)}'),
          const Divider(height: DeliverySpacing.md, color: DeliveryColors.borderFaint),
          _moneyRow(t.total, svcUsd(order.totalAmount), strong: true),
          if (lbp != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(lbp, style: const TextStyle(fontSize: 11, color: DeliveryColors.muted)),
            ),
          const SizedBox(height: DeliverySpacing.sm),
          _iconLine(
            Icons.payments_outlined,
            order.paymentMethod == PaymentMethod.cash
                ? (order.isPickup ? t.svcPayCashPickup : t.svcPayCashDelivery)
                : order.paymentMethod.labelIn(t),
          ),
        ],
      ),
    );
  }

  static Widget _caption(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: DeliveryColors.muted, letterSpacing: 0.3),
      );

  static Widget _iconLine(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.sm + 2),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600, color: DeliveryColors.ink, height: 1.35)),
          ),
        ],
      );

  static Widget _detailLine(String text) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 28, top: 2),
        child: Text(text, style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.35)),
      );

  static Widget _moneyRow(String label, String value, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: strong ? 15 : 12.5,
                      fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                      color: strong ? DeliveryColors.ink : DeliveryColors.muted)),
            ),
            Text(value,
                style: TextStyle(
                    fontSize: strong ? 17 : 12.5,
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                    color: strong ? DeliveryColors.brand : DeliveryColors.ink)),
          ],
        ),
      );
}

/// One step of the tracking timeline: the frame's 16px dot — filled green when done, a brand ring
/// where the order is, a grey outline ahead, red where it stopped — beside its label.
class ServiceTimelineRow extends StatelessWidget {
  const ServiceTimelineRow({super.key, required this.step});

  final ServiceTimelineStep step;

  @override
  Widget build(BuildContext context) {
    final Widget dot = switch (step.state) {
      ServiceStepState.done => Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: DeliveryAccent.positive.color, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, size: 11, color: DeliveryColors.white),
        ),
      ServiceStepState.current => Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: DeliveryColors.white,
            shape: BoxShape.circle,
            border: Border.all(color: DeliveryColors.brand, width: 4),
          ),
        ),
      ServiceStepState.pending => Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: DeliveryColors.border, width: 1.5),
          ),
        ),
      ServiceStepState.stopped => Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(color: DeliveryAccent.critical.color, shape: BoxShape.circle),
          child: const Icon(Icons.close_rounded, size: 11, color: DeliveryColors.white),
        ),
    };
    final Color color = switch (step.state) {
      ServiceStepState.pending => DeliveryColors.faint,
      ServiceStepState.stopped => DeliveryAccent.critical.onTint,
      ServiceStepState.done || ServiceStepState.current => DeliveryColors.ink,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(padding: const EdgeInsets.only(top: 2), child: dot),
        const SizedBox(width: DeliverySpacing.md - 4),
        Expanded(
          child: Text(
            step.label,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color, height: 1.3),
          ),
        ),
      ],
    );
  }
}
