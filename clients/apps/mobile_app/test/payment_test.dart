import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the rider is told to do at the door.
///
/// [DeliveryOrder.collectsCashOnDelivery] is the only piece of payment logic on the client, and it
/// drives a chip that either sends a rider to ask for money or tells them not to. Both mistakes are
/// arguments on a doorstep, so all four combinations are pinned down here.
Map<String, dynamic> orderJson({String? method, String? status}) => <String, dynamic>{
      'id': 'order-1',
      'customerId': 'user-1',
      'merchantId': 'm1',
      'riderId': null,
      'status': 'PICKED_UP',
      'totalAmount': 24.50,
      'deliveryAddress': '12 Rose Street',
      if (method != null) 'paymentMethod': method,
      if (status != null) 'paymentStatus': status,
      'items': <dynamic>[],
      'availableActions': <dynamic>[],
    };

void main() {
  group('payment on an order', () {
    test('cash that has not been taken yet is cash to collect', () {
      final DeliveryOrder order =
          DeliveryOrder.fromJson(orderJson(method: 'CASH', status: 'DUE'));

      expect(order.paymentMethod, PaymentMethod.cash);
      expect(order.collectsCashOnDelivery, isTrue);
    });

    test('cash already collected is not collectable twice', () {
      final DeliveryOrder order =
          DeliveryOrder.fromJson(orderJson(method: 'CASH', status: 'COLLECTED'));

      expect(order.paymentStatus.isSettled, isTrue);
      expect(order.collectsCashOnDelivery, isFalse);
    });

    test('a card order is never cash, however unpaid it is', () {
      // The state every card order sits in today: recorded, and waiting on a provider that is not
      // wired up. Unpaid — but not the rider's problem, and not money owed at the door.
      final DeliveryOrder order = DeliveryOrder.fromJson(
          orderJson(method: 'CARD', status: 'AUTHORIZATION_PENDING'));

      expect(order.paymentStatus.isSettled, isFalse);
      expect(order.collectsCashOnDelivery, isFalse);
    });

    test('an order that says nothing about payment is a cash order', () {
      // Matches the server, which defaults a request with no method to CASH — and covers orders
      // placed before either field was sent at all.
      final DeliveryOrder order = DeliveryOrder.fromJson(orderJson());

      expect(order.paymentMethod, PaymentMethod.cash);
      expect(order.paymentStatus, PaymentStatus.due);
      expect(order.collectsCashOnDelivery, isTrue);
    });

    test('a method the client has never heard of does not crash the order list', () {
      // WALLET stopped being the example the day it became a real method; the test's point —
      // an unknown wire falls back to cash rather than crashing — needs a wire that stays
      // unknown.
      final DeliveryOrder order = DeliveryOrder.fromJson(
          orderJson(method: 'BARTER_GOATS', status: 'SOMETHING_NEW'));

      expect(order.paymentMethod, PaymentMethod.cash);
      expect(order.paymentStatus, PaymentStatus.due);
    });

    test('a wallet order parses as the wallet method it is', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(orderJson(method: 'WALLET'));

      expect(order.paymentMethod, PaymentMethod.wallet);
      // Never cash at the door: a wallet order is not money for a rider to collect.
      expect(order.collectsCashOnDelivery, isFalse);
    });

    test('only cash is offered at checkout', () {
      // The guard on the one thing that must not quietly change: CARD parks at
      // AUTHORIZATION_PENDING and never becomes money, so offering it would be selling a way to
      // pay that does not work.
      expect(PaymentMethod.offered, <PaymentMethod>[PaymentMethod.cash]);
    });
  });
}
