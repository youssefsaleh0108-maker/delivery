import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'order_details_screen.dart' show CustomerStatusPill;

/// One order as the dispatch desk reads it (Figma 87:450).
///
/// <p>Everything on it is the order the carrier already holds — no second fetch: the stepper is
/// the order's status told in carrier words, the addresses and items are the order's own, and the
/// money card derives the platform's cut from the delivery fee and the standing commission rate.
///
/// <p>What the frame draws that the wire cannot answer stays off: the assigned rider's name,
/// photo and phone (the wire carries a ref), and the Reassign Rider button (dispatch has no
/// reassignment endpoint yet). The rider ref is shown when there is one, because an honest
/// handle beats an invented person.
class CarrierOrderDetailsScreen extends StatelessWidget {
  const CarrierOrderDetailsScreen({
    super.key,
    required this.order,
    required this.cutPercentage,
  });

  final DeliveryOrder order;

  /// The platform's standing cut, from the earnings surface — 15 when nothing better is known.
  final double cutPercentage;

  /// Where this order stands on the carrier's five-step journey (87:450): Received, Assigned,
  /// Picking Up, En Route, Delivered. -1 for a cancelled order, which has no place on it.
  int _stage() => switch (order.status) {
        OrderStatus.placed => 0,
        OrderStatus.accepted => order.riderId == null ? 0 : 1,
        OrderStatus.preparing || OrderStatus.ready => 2,
        OrderStatus.pickedUp => 3,
        OrderStatus.delivered => 4,
        OrderStatus.cancelled => -1,
      };

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final int stage = _stage();
    final double lbpPerUsd = MarketRates.instance.lbpPerUsd;
    final double fee = order.deliveryFee;
    final double cut = fee * cutPercentage / 100;

    final List<String> stepLabels = <String>[
      t.carrStepReceived,
      t.carrStepAssigned,
      t.carrStepPickingUp,
      t.carrStepEnRoute,
      t.carrStepDelivered,
    ];

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: '#${order.shortId}',
        onBack: () => Navigator.of(context).pop(),
        backSemanticLabel: t.back,
        trailing: CustomerStatusPill(
          statusWire: order.status.wire,
          label: order.status.labelIn(t),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(DeliverySpacing.md),
        children: <Widget>[
          // The five-step carrier stepper. A cancelled order shows the pill above instead.
          if (stage >= 0)
            YdCard.bordered(
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < stepLabels.length; i++) ...<Widget>[
                    if (i > 0)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.only(bottom: 18),
                          color: i <= stage
                              ? DeliveryColors.brand
                              : DeliveryColors.border,
                        ),
                      ),
                    _StepNode(
                      label: stepLabels[i],
                      number: i + 1,
                      state: i < stage
                          ? _NodeState.done
                          : (i == stage ? _NodeState.current : _NodeState.next),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: DeliverySpacing.md),

          // Order details: who it is, where it is picked up, where it goes.
          YdCard.bordered(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    StoreMonogram(
                        name: order.storeName ?? t.tabShop,
                        size: 40,
                        radius: 20),
                    const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(order.storeName ?? t.tabShop,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w800)),
                          Text(
                            t.itemCount(order.items.length),
                            style: const TextStyle(
                                fontSize: 12, color: DeliveryColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(
                    height: DeliverySpacing.lg, color: DeliveryColors.borderFaint),
                _addressRow(t.carrPickupFrom.toUpperCase(),
                    order.storeName ?? t.tabShop, DeliveryColors.brand),
                const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                _addressRow(t.carrDeliverTo.toUpperCase(),
                    order.deliveryAddress, DeliveryColors.faint),
              ],
            ),
          ),

          // The rider, by their honest handle. No card at all while nobody is assigned.
          if (order.riderId != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            YdCard.bordered(
              child: Row(
                children: <Widget>[
                  StoreMonogram(name: order.riderId!, size: 40, radius: 20),
                  const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
                  Expanded(
                    child: Text(
                      order.riderId!.length > 12
                          ? '${order.riderId!.substring(0, 12).toUpperCase()}…'
                          : order.riderId!.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          fontFeatures: <FontFeature>[
                            FontFeature.tabularFigures()
                          ]),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Payment & commission (87:450's money card), derived from the order itself.
          const SizedBox(height: DeliverySpacing.md),
          YdCard.bordered(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(t.carrPaymentCommission,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                _moneyRow(t.carrDeliveryFee, '\$${fee.toStringAsFixed(2)}'),
                if (lbpPerUsd > 0)
                  _moneyRow(
                    t.carrLbpRate(_thousands(lbpPerUsd)),
                    '${_thousands(fee * lbpPerUsd)} LBP',
                  ),
                _moneyRow(
                  t.carrPlatformFee(cutPercentage.round()),
                  '-\$${cut.toStringAsFixed(2)}',
                  color: DeliveryColors.brand,
                ),
                const Divider(
                    height: DeliverySpacing.lg,
                    color: DeliveryColors.borderFaint),
                _moneyRow(
                  t.total,
                  '\$${order.totalAmount.toStringAsFixed(2)}',
                  bold: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: DeliverySpacing.lg),
        ],
      ),
    );
  }

  static String _thousands(double value) {
    final String raw = value.round().toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      if (i > 0 && (raw.length - i) % 3 == 0) out.write(',');
      out.write(raw[i]);
    }
    return out.toString();
  }

  Widget _addressRow(String eyebrow, String value, Color pin) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.place, size: 16, color: pin),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(eyebrow,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.faint,
                    letterSpacing: 0.5,
                  )),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _moneyRow(String label, String value,
      {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: bold ? DeliveryColors.ink : DeliveryColors.muted,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          ),
          Text(value,
              style: TextStyle(
                fontSize: bold ? 15 : 13,
                fontWeight: FontWeight.w800,
                color: color ?? DeliveryColors.ink,
              )),
        ],
      ),
    );
  }
}

enum _NodeState { done, current, next }

/// One node of the stepper: a filled check for done, a numbered crimson circle for the current
/// step, a numbered grey circle for what has not happened yet.
class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.label,
    required this.number,
    required this.state,
  });

  final String label;
  final int number;
  final _NodeState state;

  @override
  Widget build(BuildContext context) {
    const Color green = Color(0xFF10B981);
    final Color fill = switch (state) {
      _NodeState.done => green,
      _NodeState.current => DeliveryColors.brand,
      _NodeState.next => DeliveryColors.border,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          child: state == _NodeState.done
              ? const Icon(Icons.check, size: 14, color: DeliveryColors.white)
              : Text('$number',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: state == _NodeState.next
                        ? DeliveryColors.muted
                        : DeliveryColors.white,
                  )),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight:
                state == _NodeState.current ? FontWeight.w800 : FontWeight.w600,
            color: state == _NodeState.current
                ? DeliveryColors.brand
                : DeliveryColors.muted,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}
