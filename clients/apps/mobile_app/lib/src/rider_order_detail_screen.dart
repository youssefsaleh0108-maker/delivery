import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'rider_chat_screen.dart';
import 'rider_job_card.dart';
import 'split_labels.dart';

/// Everything about one job, on one screen — Figma `rider-order-detail` (3:1344).
///
/// New in the redesign. Before it, a rider's only view of an order was the board card, so the
/// manifest they are meant to check against the bag was nowhere and the step-forward action sat on
/// a card in a scrolling list. This screen takes both: the card in the Active tab now only opens
/// this, and the committing act happens here, once, with the whole order in front of you.
///
/// The committing acts perform no API calls of their own. [onAction] is the *same* wiring the
/// board already used — claim / pick-up / deliver go through the screen that owns the refresh
/// timer and the error messages, and this screen pops when one lands. What this screen *does*
/// call for itself is read-only and new: the tracking API's ETA, refreshed on a slow timer, and
/// the chat conversation behind the header's chat button.
class RiderOrderDetailScreen extends StatefulWidget {
  const RiderOrderDetailScreen({
    super.key,
    required this.order,
    required this.onAction,
    this.trackingApi,
    this.chatApi,
    this.socket,
    this.splitApi,
  });

  final DeliveryOrder order;

  /// Completes when the action has been sent and the board refreshed.
  final Future<void> Function(OrderAction) onAction;

  /// The ETA half of the tracking service. Null draws the route card exactly as before — no panel
  /// at all, never a fabricated number.
  final TrackingApi? trackingApi;

  /// The order chat and its live socket. Null keeps the header without a chat button, which is
  /// how it looked before the backend existed.
  final ChatApi? chatApi;
  final UserQueueSocket? socket;

  /// The group-split ledger. When a cash order is a split, the cash-collection checklist
  /// (Figma `rider-cash-checklist` 83:769) draws under the items: whose cash — and how much of it —
  /// the door owes, adding up to the order's total. Null, a card or wallet order, or an order with
  /// no split behind it, draws nothing.
  final SplitApi? splitApi;

  @override
  State<RiderOrderDetailScreen> createState() => _RiderOrderDetailScreenState();
}

class _RiderOrderDetailScreenState extends State<RiderOrderDetailScreen> {
  /// How often the ETA re-asks. Slower than the board's 5s on purpose: the estimate moves at the
  /// speed of the 10s ping, and this screen holds one order, not a fleet.
  static const Duration _etaInterval = Duration(seconds: 30);

  bool _busy = false;

  /// The tracking API's last answer. Null until it has answered once — the panel renders nothing
  /// rather than a spinner or an invented figure.
  OrderEta? _eta;

  /// The split plan behind this order, or null for the overwhelming majority that have none.
  SplitPlan? _split;

  Future<void> _loadSplit() async {
    final SplitApi? api = widget.splitApi;
    if (api == null) return;
    try {
      final SplitPlan plan = await api.forOrder(widget.order.id);
      if (!mounted) return;
      setState(() => _split = plan);
    } catch (_) {
      // 404 is the normal answer: not a split order.
    }
  }

  static int _cents(double amount) => (amount * 100).round();

  static String _usd(int cents) => '\$${(cents.abs() / 100).toStringAsFixed(2)}';

  /// The frame's cash-collection checklist, drawn for a cash order with a split behind it.
  ///
  /// The total is the ORDER's cash, not a sum of chosen shares. The ledger books the whole of a
  /// cash order as collected at this door (CASH_COLLECTED = the order's total), however the group
  /// divided it, so that is what the rider must bring back. The checklist used to add up only the
  /// CASH_AT_DOOR shares: on a 19.50 order split with one guest it asked for 5.00, while the host's
  /// 14.50 — which travels with the order, so on a cash order it is cash at this door too — sat
  /// under "Already paid digitally", and so did every wallet share, though nothing had taken that
  /// money (RECON-01). No share of a cash order is paid anywhere else, so every one is listed here
  /// as what the door owes: the host's own slice, cash promises, a simulated wallet (labelled as
  /// one), and a share nobody answered or somebody declined, which the host now carries.
  Widget _splitChecklist(DeliveryStrings t, DeliveryOrder order) {
    final SplitPlan plan = _split!;
    final int totalCents = _cents(order.totalAmount);
    final int sharesCents =
        plan.shares.fold(0, (int sum, SplitShare s) => sum + _cents(s.amountUsd));
    // A plan made before the order was priced can differ from it (EXPRESS, a zone fee, a code):
    // the order's total still governs, and the gap is shown rather than silently absorbed.
    final int differenceCents = totalCents - sharesCents;

    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  t.riderCashChecklist,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: DeliveryColors.brandSoft,
                  borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                ),
                child: Text(
                  t.riderSplitOrderTag.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: DeliveryColors.brand,
                    letterSpacing: 0.5,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          for (final SplitShare share in plan.shares)
            _checklistLine(
              name: share.name,
              caption: _checklistCaption(t, share),
              amount: _usd(_cents(share.amountUsd)),
            ),
          if (differenceCents != 0)
            _checklistLine(
              name: t.riderSplitOrderDifference,
              amount: '${differenceCents < 0 ? '−' : '+'}${_usd(differenceCents)}',
            ),
          const Divider(
              height: DeliverySpacing.md * 1.5, color: DeliveryColors.borderFaint),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  t.riderTotalCashCollect,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
              ),
              Text(
                _usd(totalCents),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: DeliveryColors.brand,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// What the rider should know about one share at the door, beyond its name and amount: that a
  /// wallet "payment" was only simulated, or that nobody has answered, somebody declined, or the
  /// host took the share on. How a promise travels is not said — at this door it is all cash.
  static String? _checklistCaption(DeliveryStrings t, SplitShare share) {
    if (share.simulated && share.method != null) {
      return t.splitSimulatedPayment(splitMethodLabel(t, share.method!));
    }
    return switch (share.status) {
      'PENDING' => t.custPendingChip,
      'DECLINED' => t.custDeclinedChip,
      'COVERED' => t.custCoveredChip,
      _ => null,
    };
  }

  Widget _checklistLine({required String name, String? caption, required String amount}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          const Icon(Icons.payments_outlined, size: 16, color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.sm),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
                if (caption != null)
                  Text(
                    caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: DeliveryColors.muted, height: 1.3),
                  ),
              ],
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Text(
            amount,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: DeliveryColors.brand,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Timer? _etaTimer;

  /// The conversation behind the chat button, and its badge. Null while the server has not
  /// answered, and null for good on an order with no conversation (one opens when a rider is
  /// assigned; a 404 here is an order that never got that far or is not this rider's).
  ChatConversation? _conversation;
  int _unread = 0;
  StreamSubscription<ChatFrame>? _chatLive;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSplit());
    if (widget.trackingApi != null && !widget.order.status.isTerminal) {
      unawaited(_loadEta());
      _etaTimer = Timer.periodic(_etaInterval, (_) => _loadEta());
    }
    if (widget.chatApi != null) {
      unawaited(_loadConversation());
      final UserQueueSocket? socket = widget.socket;
      if (socket != null) {
        // A message arriving while this screen is up bumps the badge live. The durable count is
        // re-read whenever the conversation reloads.
        _chatLive = ChatApi.live(socket).listen((ChatFrame frame) {
          if (!mounted || frame.orderId != widget.order.id) return;
          setState(() => _unread++);
        });
      }
    }
  }

  @override
  void dispose() {
    _etaTimer?.cancel();
    _chatLive?.cancel();
    super.dispose();
  }

  Future<void> _loadEta() async {
    final TrackingApi? tracking = widget.trackingApi;
    if (tracking == null) return;
    try {
      final OrderEta eta = await tracking.eta(widget.order.id);
      if (!mounted) return;
      setState(() => _eta = eta);
    } catch (_) {
      // The panel keeps the last honest answer; the timer retries.
    }
  }

  Future<void> _loadConversation() async {
    final ChatApi? chat = widget.chatApi;
    if (chat == null) return;
    try {
      final ChatConversation conversation =
          await chat.conversationForOrder(widget.order.id);
      if (!mounted) return;
      setState(() {
        _conversation = conversation;
        _unread = conversation.unread;
      });
    } catch (_) {
      // 404: no conversation on this order (yet). The button simply is not drawn.
    }
  }

  Future<void> _openChat() async {
    final ChatConversation? conversation = _conversation;
    final ChatApi? chat = widget.chatApi;
    if (conversation == null || chat == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => RiderChatScreen(
        api: chat,
        socket: widget.socket,
        conversation: conversation,
        orderShortId: widget.order.shortId,
      ),
    ));
    // The chat screen marked the thread read; re-ask rather than assume.
    await _loadConversation();
  }

  Future<void> _run(OrderAction action) async {
    setState(() => _busy = true);
    try {
      await widget.onAction(action);
      if (!mounted) return;
      // The board behind this screen has already refreshed and this order has moved on, so the
      // page we are looking at is stale by definition. Going back is the honest end of the act.
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmCancel() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(t.cancelThisOrder),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: DeliveryAccent.critical.color),
            child: Text(t.cancelOrder),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _run(OrderAction.cancel);
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DeliveryOrder order = widget.order;

    final List<OrderAction> forward = order.availableActions
        .where((OrderAction a) => a != OrderAction.cancel)
        .toList();
    final bool canCancel = order.availableActions.contains(OrderAction.cancel);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _header(context, t, order),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  _payoutCard(t, order),
                  const SizedBox(height: DeliverySpacing.md),
                  _routeCard(t, order),
                  const SizedBox(height: DeliverySpacing.md),
                  _itemsCard(t, order),
                  const SizedBox(height: DeliverySpacing.md),
                  // Only where this door collects cash. On a card or wallet order the ledger books
                  // the whole total as paid by the customer, the payout card says so, and how the
                  // group settles up among themselves is nothing the rider collects.
                  if (_split != null && order.collectsCashOnDelivery) ...<Widget>[
                    _splitChecklist(t, order),
                    const SizedBox(height: DeliverySpacing.md),
                  ],
                  for (final OrderAction action in forward) ...<Widget>[
                    SizedBox(
                      width: double.infinity,
                      child: RiderButton(
                        label: action.labelIn(t),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        verticalPadding: 14,
                        busy: _busy,
                        onPressed: _busy ? null : () => _run(action),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  // Real, and honest about what it is: the platform has no routing engine and the
                  // order carries no coordinates, so this hands the door — the address the
                  // customer actually typed — to whatever the phone uses for maps. That
                  // application does know about roads. Nothing is invented on the way across:
                  // the search query is the delivery address verbatim.
                  //
                  // While the rider still has to collect, the shop is the stop that matters, so
                  // the button navigates there first and to the door once the goods are aboard.
                  SizedBox(
                    width: double.infinity,
                    child: RiderButton(
                      label: t.riderStartNavigation,
                      style: RiderButtonStyle.outlined,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      verticalPadding: 14,
                      onPressed: _navigationTarget(order).isEmpty
                          ? null
                          : () => riderNavigateTo(context, _navigationTarget(order)),
                    ),
                  ),
                  // Not in the design, and kept anyway: cancel is a real transition the server
                  // offers a rider on some orders, and a step the state machine allows but the app
                  // hides is a rider stuck on a doorstep with no way out. Text, below the CTAs,
                  // where it cannot be hit by accident.
                  if (canCancel) ...<Widget>[
                    const SizedBox(height: DeliverySpacing.sm),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: _busy ? null : _confirmCancel,
                        style: TextButton.styleFrom(
                          foregroundColor: DeliveryAccent.critical.color,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 36),
                        ),
                        child: Text(OrderAction.cancel.labelIn(t)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Which stop Navigate should open.
  ///
  /// Before pick-up the rider is going to the shop, after it to the door — sending them to the
  /// customer while the bag is still on the counter is the one way this button can waste a
  /// journey. The shop is only ever named, never addressed, so its name is what the maps app is
  /// asked to find; the customer's address is a real address.
  ///
  /// Empty when there is nothing to hand over, which disables the button rather than opening a
  /// maps application on an empty search.
  static String _navigationTarget(DeliveryOrder order) {
    final bool collected = order.status == OrderStatus.pickedUp ||
        order.status == OrderStatus.delivered;
    final String? shop = order.storeName;
    if (!collected && shop != null && shop.trim().isNotEmpty) return shop.trim();
    return order.deliveryAddress.trim();
  }

  /// The design's `back-header`: 20/12 padding, a chevron and a 16px bold title.
  ///
  /// The circular chat button the design puts on the right is real now — drawn once the order has
  /// a conversation (the server opens one when a rider is assigned), with the unread count on its
  /// shoulder. Until then the header keeps its room, exactly as it did before chat existed.
  Widget _header(BuildContext context, DeliveryStrings t, DeliveryOrder order) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 20,
        vertical: DeliverySpacing.md - DeliverySpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          YdBackButton(
            onPressed: () => Navigator.of(context).maybePop(),
            semanticLabel: t.back,
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Text(
              t.riderOrderRef(order.shortId),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
              ),
            ),
          ),
          if (_conversation != null) ...<Widget>[
            const SizedBox(width: DeliverySpacing.sm),
            _chatButton(t),
          ],
        ],
      ),
    );
  }

  /// The header's circular chat button with its unread badge.
  Widget _chatButton(DeliveryStrings t) {
    return Semantics(
      button: true,
      label: t.riderChatTitle,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _openChat,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: DeliveryColors.brandSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chat_bubble_outline_rounded,
                    size: 18, color: DeliveryColors.brand),
              ),
              if (_unread > 0)
                PositionedDirectional(
                  top: 0,
                  end: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: DeliveryColors.brand,
                      borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                    ),
                    child: Text(
                      '$_unread',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.white,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// `earnings-card`: the caption over a 24px green figure.
  ///
  /// The design calls it GUARANTEED EARNINGS. Nothing guarantees it — there is no minimum-pay
  /// model — so it is labelled for what the number actually is: this order's delivery fee, which
  /// is the rider's payout for the job.
  Widget _payoutCard(DeliveryStrings t, DeliveryOrder order) {
    return YdCard(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  t.riderYourPayout.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    color: DeliveryColors.faint,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  order.deliveryFee.toStringAsFixed(2),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: DeliveryAccent.positive.color,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          // The design puts a circular call button here. There is no telephony integration, but the
          // slot holds the one fact that changes what happens at the door.
          if (order.collectsCashOnDelivery)
            RiderTag(
              label: t.collectCash(order.totalAmount.toStringAsFixed(2)),
              color: DeliveryAccent.caution.color,
              background: DeliveryAccent.caution.tint,
            )
          else
            RiderTag(
              label: t.alreadyPaid,
              color: DeliveryAccent.positive.color,
              background: DeliveryAccent.positive.tint,
            ),
        ],
      ),
    );
  }

  /// `addresses-card`: the route as two marked nodes with a rule between them.
  Widget _routeCard(DeliveryStrings t, DeliveryOrder order) {
    return YdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _cardTitle(t.riderRouteTimeline),
          const SizedBox(height: DeliverySpacing.md),
          if (order.storeName != null && order.storeName!.isNotEmpty) ...<Widget>[
            _routeNode(
              tint: DeliveryColors.brandSoft,
              iconColour: DeliveryColors.brand,
              captionColour: DeliveryColors.brand,
              caption: t.riderPickupAddress,
              name: order.storeName!,
            ),
            const SizedBox(height: DeliverySpacing.md),
            const RiderHairline(),
            const SizedBox(height: DeliverySpacing.md),
          ],
          _routeNode(
            tint: DeliveryColors.background,
            iconColour: DeliveryColors.ink,
            captionColour: DeliveryColors.muted,
            caption: t.riderDeliveryAddress,
            name: order.deliveryAddress,
            detail: order.contactPhone,
          ),
          if (order.gift != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            _giftPanel(t, order.gift!),
          ],
          if (_eta != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            const RiderHairline(),
            const SizedBox(height: DeliverySpacing.md),
            _etaPanel(t, _eta!),
          ],
        ],
      ),
    );
  }

  /// Who to hand a gift to. The rider carrying it is the one person besides the customer and
  /// support the server gives the recipient's phone to, because they ring it at the door; the card
  /// is shown so it goes over with the goods. On the job board the server withholds the name and the
  /// card — the rider is browsing work, not carrying it — so the panel says only that it is a gift.
  Widget _giftPanel(DeliveryStrings t, OrderGift gift) {
    final String? message = gift.message?.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryColors.brandSoft,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.card_giftcard_rounded, size: 16, color: DeliveryColors.brand),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                child: Text(
                  gift.recipientName == null
                      ? t.giftUnnamed
                      : t.giftForName(gift.recipientName!),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          if (gift.recipientPhone != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Text(
              '${t.giftRecipientPhoneLabel}: ${gift.recipientPhone}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.ink,
                height: 1.3,
              ),
            ),
          ],
          if (gift.wrap) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Text(
              t.giftWrapRequested,
              style: const TextStyle(fontSize: 12, color: DeliveryColors.brand, height: 1.3),
            ),
          ],
          if (message != null && message.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              t.giftCardMessage.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.muted,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '“$message”',
              style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }

  /// The ETA block at the foot of the route card: the tracking API's answer, rendered as far as
  /// it goes and no further.
  ///
  /// Available: which leg, then distance and expected arrival, then who computed it — with the
  /// straight-line caveat when the dev estimator did. Unavailable: the server's reason, in the
  /// design's muted caption style, never a spinner and never a number the server did not send.
  Widget _etaPanel(DeliveryStrings t, OrderEta eta) {
    final List<Widget> lines = <Widget>[
      Text(
        t.riderEtaCaption.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: DeliveryColors.faint,
          height: 1.3,
        ),
      ),
      const SizedBox(height: DeliverySpacing.xs),
    ];

    if (!eta.available) {
      lines.add(Text(
        riderEtaReasonLabel(t, eta.reason ?? EtaUnavailableReason.unknown),
        style: const TextStyle(
          fontSize: 12,
          color: DeliveryColors.muted,
          height: 1.4,
        ),
      ));
    } else {
      final List<String> facts = <String>[
        if (eta.remainingMetres != null)
          t.riderEtaAway(riderDistanceLabel(t, eta.remainingMetres!)),
        if (eta.estimatedArrival != null)
          t.riderEtaArrivingAt(
            MaterialLocalizations.of(context).formatTimeOfDay(
              TimeOfDay.fromDateTime(eta.estimatedArrival!),
              alwaysUse24HourFormat:
                  MediaQuery.of(context).alwaysUse24HourFormat,
            ),
          ),
      ];
      if (eta.leg != null) {
        lines.add(Text(
          riderEtaLegLabel(t, eta.leg!),
          style: const TextStyle(
            fontSize: 12,
            color: DeliveryColors.muted,
            height: 1.4,
          ),
        ));
      }
      if (facts.isNotEmpty) {
        lines.add(Text(
          facts.join(' · '),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.ink,
            height: 1.3,
          ),
        ));
      }
      lines.add(const SizedBox(height: 2));
      lines.add(Text(
        // Which provider computed it — and, for the dev straight-line estimator, that the
        // number knows nothing about roads.
        eta.isStraightLine
            ? '${t.riderEtaComputedBy(eta.provider)} — ${t.etaStraightLineNote}'
            : t.riderEtaComputedBy(eta.provider),
        style: const TextStyle(
          fontSize: 11,
          color: DeliveryColors.faint,
          height: 1.4,
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines,
    );
  }

  Widget _routeNode({
    required Color tint,
    required Color iconColour,
    required Color captionColour,
    required String caption,
    required String name,
    String? detail,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          child: Icon(Icons.place_outlined, size: 16, color: iconColour),
        ),
        const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                caption.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: captionColour,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                  height: 1.3,
                ),
              ),
              if (detail != null && detail.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.muted,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// `items-card`: the manifest a rider checks against the bag, then the customer's own words.
  Widget _itemsCard(DeliveryStrings t, DeliveryOrder order) {
    final bool hasNotes = order.notes != null && order.notes!.isNotEmpty;

    return YdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _cardTitle(t.riderItemsToCollect),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          if (order.items.isEmpty)
            Text(
              t.riderNoItemsListed,
              style: const TextStyle(
                fontSize: 13,
                color: DeliveryColors.muted,
                height: 1.4,
              ),
            )
          else
            for (final OrderLine line in order.items)
              Padding(
                padding: const EdgeInsets.only(
                    bottom: DeliverySpacing.md - DeliverySpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        t.riderItemLine(line.qty, line.productName),
                        style: const TextStyle(
                          fontSize: 13,
                          color: DeliveryColors.muted,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: DeliverySpacing.sm),
                    Text(
                      line.lineTotal.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.ink,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
          if (hasNotes) ...<Widget>[
            const RiderHairline(),
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            Text(
              t.riderDeliveryInstructions.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: DeliveryAccent.caution.color,
                height: 1.3,
              ),
            ),
            const SizedBox(height: DeliverySpacing.xs),
            Text(
              order.notes!,
              style: const TextStyle(
                fontSize: 12,
                color: DeliveryColors.muted,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardTitle(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.ink,
          height: 1.3,
        ),
      );
}
