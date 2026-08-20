import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// One job on the rider's board: where it comes from, where it goes, what is owed at the door,
/// and the one button that moves it on.
///
/// Its own file so it can be pumped on its own. The screen around it runs two periodic timers,
/// which a widget test cannot settle — and the layout risk is all in here.
class RiderJobCard extends StatelessWidget {
  const RiderJobCard({super.key, required this.order, required this.busy, required this.onAction});

  final DeliveryOrder order;
  final bool busy;
  final void Function(OrderAction) onAction;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    // Cancel is not a step forward, and rendering it beside one as an equal-width button is how a
    // rider taps it by accident. It goes below, as text.
    final List<OrderAction> forward = order.availableActions
        .where((OrderAction a) => a != OrderAction.cancel)
        .toList();
    final bool canCancel = order.availableActions.contains(OrderAction.cancel);

    return SoftCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(DeliverySpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                OrderStatusBadge(statusWire: order.status.wire),
                const Spacer(),
                Text('#${order.shortId}',
                    style: const TextStyle(fontSize: 12, color: DeliveryColors.muted)),
              ],
            ),
            // Where it comes from, named. A rider heading out needs the shop before the street.
            if (order.storeName != null && order.storeName!.isNotEmpty) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm + 2),
              _line(
                icon: Icons.storefront_rounded,
                tint: DeliveryAccent.info,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(t.pickUpFrom,
                        style: const TextStyle(fontSize: 11.5, color: DeliveryColors.muted)),
                    Text(order.storeName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: DeliveryColors.ink)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: DeliverySpacing.sm),
            // The largest thing on the card, on purpose: it is the one piece a rider re-reads at
            // every junction.
            _line(
              icon: Icons.place_rounded,
              tint: DeliveryAccent.critical,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(t.dropOffAt,
                      style: const TextStyle(fontSize: 11.5, color: DeliveryColors.muted)),
                  Text(order.deliveryAddress,
                      style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          color: DeliveryColors.ink)),
                ],
              ),
            ),
            const SizedBox(height: DeliverySpacing.sm + 2),
            Wrap(
              spacing: DeliverySpacing.sm,
              runSpacing: DeliverySpacing.xs + 2,
              children: <Widget>[
                _chip(
                  DeliveryAccent.neutral,
                  Icons.shopping_bag_outlined,
                  t.itemCountWithDot(
                      order.items.fold<int>(0, (int a, OrderLine l) => a + l.qty)),
                ),
                // The one fact that changes what happens at the door. A rider who arrives thinking
                // an order is prepaid either leaves without the money or has an argument on a
                // doorstep — so it is a chip, in the colour that means "look at this", not a line
                // of small print.
                if (order.collectsCashOnDelivery)
                  _chip(DeliveryAccent.caution, Icons.payments_rounded,
                      t.collectCash(order.totalAmount.toStringAsFixed(2)))
                else
                  _chip(DeliveryAccent.positive, Icons.check_circle_outline_rounded, t.alreadyPaid),
              ],
            ),
            if (order.contactPhone != null && order.contactPhone!.isNotEmpty) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              Row(
                children: <Widget>[
                  const Icon(Icons.phone_rounded, size: 15, color: DeliveryColors.muted),
                  const SizedBox(width: DeliverySpacing.xs + 2),
                  Expanded(
                    child: Text(order.contactPhone!,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: DeliveryColors.muted)),
                  ),
                ],
              ),
            ],
            if (order.notes != null && order.notes!.isNotEmpty) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(DeliverySpacing.sm),
                decoration: BoxDecoration(
                  color: DeliveryColors.background,
                  borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                ),
                child: Text(order.notes!,
                    style: const TextStyle(
                        fontSize: 12.5, color: DeliveryColors.muted, height: 1.35)),
              ),
            ],

            // Server-supplied actions only - the rider is never offered a step the state machine
            // would refuse, including CLAIM on an order another rider already took.
            if (forward.isNotEmpty) ...<Widget>[
              const SizedBox(height: DeliverySpacing.md),
              for (final OrderAction action in forward)
                Padding(
                  padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: busy ? null : () => onAction(action),
                      style: FilledButton.styleFrom(
                        backgroundColor: DeliveryColors.brand,
                        foregroundColor: DeliveryColors.white,
                        textStyle:
                            const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(DeliveryRadius.md + 2),
                        ),
                      ),
                      icon: Icon(_iconFor(action), size: 19),
                      label: Text(action.labelIn(t)),
                    ),
                  ),
                ),
            ],
            if (canCancel)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: busy ? null : () => onAction(OrderAction.cancel),
                  style: TextButton.styleFrom(
                      foregroundColor: DeliveryAccent.critical.color,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36)),
                  child: Text(OrderAction.cancel.labelIn(t)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// An icon in its own tinted circle, beside its content. Used for the two things a rider
  /// navigates by — the shop and the door.
  Widget _line({required IconData icon, required DeliveryAccent tint, required Widget child}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: tint.tint, shape: BoxShape.circle),
          child: Icon(icon, size: 17, color: tint.color),
        ),
        const SizedBox(width: DeliverySpacing.sm + 2),
        Expanded(child: child),
      ],
    );
  }

  Widget _chip(DeliveryAccent accent, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: DeliverySpacing.sm, vertical: DeliverySpacing.xs + 1),
      decoration: BoxDecoration(
        color: accent.tint,
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
        border: Border.all(color: accent.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: accent.color),
          const SizedBox(width: DeliverySpacing.xs + 1),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: accent.color)),
        ],
      ),
    );
  }

  IconData _iconFor(OrderAction action) => switch (action) {
        OrderAction.claim => Icons.pan_tool_alt_rounded,
        OrderAction.pickUp => Icons.shopping_bag_rounded,
        OrderAction.deliver => Icons.check_circle_rounded,
        OrderAction.accept => Icons.thumb_up_alt_rounded,
        OrderAction.prepare => Icons.soup_kitchen_rounded,
        OrderAction.ready => Icons.done_all_rounded,
        OrderAction.cancel => Icons.close_rounded,
      };
}
