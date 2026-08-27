import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'rider_chat_screen.dart';
import 'rider_job_card.dart';

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
                  // Turn-by-turn needs coordinates on the addresses and a routing engine; neither
                  // exists. Drawn as designed, and inert.
                  SizedBox(
                    width: double.infinity,
                    child: RiderButton(
                      label: t.riderStartNavigation,
                      style: RiderButtonStyle.outlined,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      verticalPadding: 14,
                      onPressed: null,
                      trailing: YdComingSoon(label: t.riderComingSoon),
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
