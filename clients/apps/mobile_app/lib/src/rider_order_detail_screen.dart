import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'rider_job_card.dart';

/// Everything about one job, on one screen — Figma `rider-order-detail` (3:1344).
///
/// New in the redesign. Before it, a rider's only view of an order was the board card, so the
/// manifest they are meant to check against the bag was nowhere and the step-forward action sat on
/// a card in a scrolling list. This screen takes both: the card in the Active tab now only opens
/// this, and the committing act happens here, once, with the whole order in front of you.
///
/// It performs no API calls of its own. [onAction] is the *same* wiring the board already used —
/// claim / pick-up / deliver go through the screen that owns the refresh timer and the error
/// messages, and this screen pops when one lands.
class RiderOrderDetailScreen extends StatefulWidget {
  const RiderOrderDetailScreen({
    super.key,
    required this.order,
    required this.onAction,
  });

  final DeliveryOrder order;

  /// Completes when the action has been sent and the board refreshed.
  final Future<void> Function(OrderAction) onAction;

  @override
  State<RiderOrderDetailScreen> createState() => _RiderOrderDetailScreenState();
}

class _RiderOrderDetailScreenState extends State<RiderOrderDetailScreen> {
  bool _busy = false;

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
  /// The circular chat button the design puts on the right is not drawn — there is no messaging
  /// between rider and customer anywhere in the platform, and a button that opens nothing is worse
  /// than a header with room in it.
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
        ],
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
        ],
      ),
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
