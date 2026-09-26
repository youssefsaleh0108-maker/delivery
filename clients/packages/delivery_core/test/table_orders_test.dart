import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

/// An order sent from a table in a shop's own room, as the shop's app reads it.
///
/// Two things are pinned here. The first is the wire: a table order reaches a merchant through the
/// same `GET /api/orders/merchant` as a basket, and every field it does *not* have is a field some
/// screen would otherwise draw — an address, a rider, a delivery fee. Those absences are asserted
/// rather than assumed, because the model's own defaults would hide a rename.
///
/// The second is the round, which exists nowhere but here. Nothing on the server records that a
/// ticket is a table's second send; the number is counted from the table's still-open tickets at the
/// moment a queue is drawn. That makes it the one figure on these screens with no server to check it
/// against, so its rules are written out as cases: what a fresh table reads as, what a second send
/// reads as, and what stops being counted.

/// A table order as order-manager serialises one.
///
/// Every field is the value the server actually sends for `kind: TABLE`, including the ones that are
/// present-and-null: `deliveryAddress`, `riderId`, `contactPhone`, `gift` and `checkoutId` are all
/// emitted as null rather than left out (the DTO is a Java record and Jackson writes nulls), and a
/// screen that treats "absent" and "null" differently would pass a test built the other way.
Map<String, dynamic> _tableOrder({
  String id = 'aaaaaaaa-0000-4000-8000-000000000001',
  int table = 7,
  String status = 'PLACED',
  String merchantId = 'merchant-1',
  String? placedAt = '2026-09-23T18:00:00Z',
  List<String> actions = const <String>['ACCEPT', 'CANCEL'],
}) =>
    <String, dynamic>{
      'id': id,
      'kind': 'TABLE',
      // Synthetic and unique per order: there is no account behind a table order, and the server
      // refuses to file every diner in the country under one identity.
      'customerId': 'table:5e00abcd-$table:9f3a1b2c',
      'merchantId': merchantId,
      'riderId': null,
      'status': status,
      'totalAmount': 20.0,
      'subtotal': 20.0,
      'deliveryFee': 0,
      'deliveryFeeCharged': 0,
      'deliveryTier': 'STANDARD',
      'expressSurcharge': 0,
      'deliveryFeeWaived': false,
      'merchantFeeWaived': false,
      'carrierFeeWaived': false,
      'discountAmount': 0,
      'promoCode': null,
      'storeId': 'ffffffff-0000-4000-8000-00000000000f',
      'storeName': 'Dekkanet Al Rawche',
      'deliveryAddress': null,
      'paymentMethod': 'CASH',
      'paymentStatus': 'DUE',
      'contactPhone': null,
      'notes': 'No onions.',
      'gift': null,
      'checkoutId': null,
      'checkoutSize': null,
      'items': <dynamic>[
        <String, dynamic>{
          'productId': 'p1',
          'productName': 'Hummus',
          'unitPrice': 10.0,
          'qty': 2,
          'lineTotal': 20.0,
        },
      ],
      'availableActions': actions,
      'placedAt': placedAt,
      'deliveredAt': null,
      'cancelReason': null,
      'fulfilment': 'DINE_IN',
      // A `Short` on the wire, so a bare JSON number.
      'tableLabel': table,
      'serviceCategory': null,
      'customerDisplayName': null,
      'uncollectedCancellableAt': null,
    };

/// A delivery order, for the assertions that are about a table order *not* changing one.
Map<String, dynamic> _deliveryOrder({
  String id = 'bbbbbbbb-0000-4000-8000-000000000002',
  String status = 'PLACED',
}) =>
    <String, dynamic>{
      'id': id,
      'kind': 'CATALOG',
      'customerId': 'customer-1',
      'merchantId': 'merchant-1',
      'riderId': 'rider-9',
      'status': status,
      'totalAmount': 24.5,
      'subtotal': 21.0,
      'deliveryFee': 3.5,
      'deliveryFeeCharged': 3.5,
      'deliveryAddress': 'Hamra, Beirut',
      'contactPhone': '+96170000000',
      'items': <dynamic>[
        <String, dynamic>{
          'productId': 'p2',
          'productName': 'Manoushe',
          'unitPrice': 10.5,
          'qty': 2,
          'lineTotal': 21.0,
        },
      ],
      'availableActions': const <String>['ACCEPT', 'CANCEL'],
      'placedAt': '2026-09-23T18:05:00Z',
      'deliveredAt': null,
      'cancelReason': null,
      'fulfilment': 'DELIVERY',
      'tableLabel': null,
    };

DeliveryOrder _table({
  String id = 'aaaaaaaa-0000-4000-8000-000000000001',
  int table = 7,
  String status = 'PLACED',
  String merchantId = 'merchant-1',
  String? placedAt = '2026-09-23T18:00:00Z',
}) =>
    DeliveryOrder.fromJson(_tableOrder(
      id: id,
      table: table,
      status: status,
      merchantId: merchantId,
      placedAt: placedAt,
    ));

void main() {
  group('a table order on the wire', () {
    test('carries its table, and says it is nobody\'s delivery', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(_tableOrder());

      expect(order.kind, OrderKind.table);
      expect(order.kind.wire, 'TABLE');
      expect(order.fulfilment, Fulfilment.dineIn);
      expect(order.fulfilment.wire, 'DINE_IN');
      expect(order.tableLabel, 7);
      expect(order.isTableOrder, isTrue);

      // Nobody carries it, so nothing may offer or wait for a rider.
      expect(order.isCarried, isFalse);
      expect(order.riderId, isNull);

      // No address and no phone, because the diner is in the room and has no account. The model reads
      // the server's null as an empty address rather than throwing, which is what lets the card's
      // address row simply not draw.
      expect(order.deliveryAddress, isEmpty);
      expect(order.contactPhone, isNull);

      // The note the diner left on the order is theirs and is kept: it is the one free-text field a
      // table order has, and it is what the kitchen reads.
      expect(order.notes, 'No onions.');
      expect(order.items.single.productName, 'Hummus');
    });

    test('books nothing: no delivery fee, no waiver, no commission to claim', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(_tableOrder());

      expect(order.settles, isFalse, reason: 'the platform is not a party to this money');
      expect(order.deliveryFee, 0);
      expect(order.deliveryFeeCharged, 0);
      expect(order.expressSurcharge, 0);
      // A waiver is a charge the platform dropped. Nothing was charged here, so nothing was waived —
      // a screen that read these as true would claim a favour that was never granted.
      expect(order.deliveryFeeWaived, isFalse);
      expect(order.merchantFeeWaived, isFalse);
      expect(order.carrierFeeWaived, isFalse);
      // The whole total is the food, which is what the diner settles with the restaurant directly.
      expect(order.totalAmount, 20.0);
      expect(order.goodsSubtotal, 20.0);
    });

    test('a delivery order is untouched by any of it', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(_deliveryOrder());

      expect(order.kind, OrderKind.catalog);
      expect(order.fulfilment, Fulfilment.delivery);
      expect(order.tableLabel, isNull);
      expect(order.isTableOrder, isFalse);
      expect(order.isCarried, isTrue);
      expect(order.settles, isTrue);
      expect(order.deliveryAddress, 'Hamra, Beirut');
      expect(order.deliveryFeeCharged, 3.5);
    });

    test('only the table kind fails to settle', () {
      for (final OrderKind kind in OrderKind.values) {
        expect(kind.settles, kind != OrderKind.table, reason: kind.name);
      }
    });

    test('a table label sent as a widened number still reads as an int', () {
      // A `Short` reaches Dart as whatever the JSON codec made of it. A cast straight to int would
      // throw on a decoder that widened it, on the one field a table order cannot do without.
      final DeliveryOrder order =
          DeliveryOrder.fromJson(_tableOrder()..['tableLabel'] = 7.0);

      expect(order.tableLabel, 7);
    });

    test('a build that has not heard of table orders is not the one guessing', () {
      // The other direction of the same contract: an order whose kind this build does not know reads
      // as unknown rather than as a basket, so it cannot be handed a basket's screens.
      final DeliveryOrder order = DeliveryOrder.fromJson(_tableOrder()..['kind'] = 'BANQUET');

      expect(order.kind, OrderKind.unknown);
      expect(order.isTableOrder, isFalse);
    });
  });

  group('which round a table is on', () {
    test('a table with one ticket open is on round one, and says so to nobody', () {
      final DeliveryOrder only = _table();
      final TableRound? round = tableRoundOf(only, <DeliveryOrder>[only]);

      expect(round, isNotNull);
      expect(round!.round, 1, reason: 'a newly seated party starts at one by itself');
      expect(round.openTickets, 1);
      // The number is true and not worth printing: there is nothing to tell it apart from.
      expect(round.isOnlyTicket, isTrue);
    });

    test('sending again from one table reads as round one and round two', () {
      final DeliveryOrder first = _table(id: 'aaaa-1', placedAt: '2026-09-23T18:00:00Z');
      final DeliveryOrder second = _table(id: 'aaaa-2', placedAt: '2026-09-23T18:40:00Z');
      final List<DeliveryOrder> queue = <DeliveryOrder>[second, first];

      expect(tableRoundOf(first, queue)!.round, 1);
      expect(tableRoundOf(second, queue)!.round, 2);
      // Both are marked once there are two, because that is when the number does work.
      expect(tableRoundOf(first, queue)!.isOnlyTicket, isFalse);
      expect(tableRoundOf(second, queue)!.isOnlyTicket, isFalse);
      expect(tableRoundOf(second, queue)!.openTickets, 2);
    });

    test('the count does not depend on the order the queue happens to be in', () {
      final DeliveryOrder first = _table(id: 'aaaa-1', placedAt: '2026-09-23T18:00:00Z');
      final DeliveryOrder second = _table(id: 'aaaa-2', placedAt: '2026-09-23T18:40:00Z');
      final DeliveryOrder third = _table(id: 'aaaa-3', placedAt: '2026-09-23T19:10:00Z');

      for (final List<DeliveryOrder> queue in <List<DeliveryOrder>>[
        <DeliveryOrder>[first, second, third],
        <DeliveryOrder>[third, second, first],
        <DeliveryOrder>[second, third, first],
      ]) {
        expect(tableRoundOf(first, queue)!.round, 1);
        expect(tableRoundOf(second, queue)!.round, 2);
        expect(tableRoundOf(third, queue)!.round, 3);
      }
    });

    test('a fresh table starts at round one once the last meal is closed', () {
      // The party that was at table 7 has paid: both their tickets are done. The next party's first
      // send must not read as round three, and nothing told the app anybody left — the count of *open*
      // tickets is what notices.
      final DeliveryOrder servedFirst =
          _table(id: 'aaaa-1', status: 'DELIVERED', placedAt: '2026-09-23T18:00:00Z');
      final DeliveryOrder servedSecond =
          _table(id: 'aaaa-2', status: 'DELIVERED', placedAt: '2026-09-23T18:40:00Z');
      final DeliveryOrder newParty =
          _table(id: 'aaaa-3', status: 'PLACED', placedAt: '2026-09-23T20:30:00Z');

      final TableRound? round = tableRoundOf(
          newParty, <DeliveryOrder>[servedFirst, servedSecond, newParty]);

      expect(round!.round, 1);
      expect(round.openTickets, 1);
      expect(round.isOnlyTicket, isTrue);
    });

    test('a cancelled ticket stops being counted, exactly as a served one does', () {
      final DeliveryOrder rejected =
          _table(id: 'aaaa-1', status: 'CANCELLED', placedAt: '2026-09-23T18:00:00Z');
      final DeliveryOrder open =
          _table(id: 'aaaa-2', status: 'PLACED', placedAt: '2026-09-23T18:40:00Z');

      expect(tableRoundOf(open, <DeliveryOrder>[rejected, open])!.round, 1);
    });

    test('a closed ticket is given no round at all', () {
      // It cannot be placed among tickets that have since closed too, so any number would be a guess.
      // Its table is still shown; only the round is withheld.
      final DeliveryOrder served = _table(status: 'DELIVERED');

      expect(tableRoundOf(served, <DeliveryOrder>[served]), isNull);
      expect(tableRoundOf(_table(status: 'CANCELLED'), <DeliveryOrder>[]), isNull);
    });

    test('another table, another shop and another kind are all somebody else\'s count', () {
      final DeliveryOrder mine = _table(id: 'aaaa-1', table: 7);
      final TableRound? round = tableRoundOf(mine, <DeliveryOrder>[
        mine,
        _table(id: 'aaaa-2', table: 8),
        _table(id: 'aaaa-3', merchantId: 'merchant-2'),
        DeliveryOrder.fromJson(_deliveryOrder()),
      ]);

      expect(round!.round, 1);
      expect(round.openTickets, 1);
    });

    test('an order that is not a table order has no round', () {
      final DeliveryOrder delivery = DeliveryOrder.fromJson(_deliveryOrder());

      expect(tableRoundOf(delivery, <DeliveryOrder>[delivery]), isNull);
    });

    test('a ticket counts itself even when the caller was not holding it', () {
      // The detail screen holds one order and re-reads it from the server, so the instance it is
      // drawing is not the one in the list it came from.
      final DeliveryOrder earlier = _table(id: 'aaaa-1', placedAt: '2026-09-23T18:00:00Z');
      final DeliveryOrder reread = _table(id: 'aaaa-2', placedAt: '2026-09-23T18:40:00Z');

      final TableRound? round = tableRoundOf(reread, <DeliveryOrder>[earlier]);

      expect(round!.round, 2);
      expect(round.openTickets, 2);
    });

    test('two tickets sent in the same second keep their places between rebuilds', () {
      // One party, two phones, one tap each. Whatever order they come back in, the pair must not swap
      // numbers under the staff's eyes on the next poll.
      final DeliveryOrder a = _table(id: 'aaaa-1', placedAt: '2026-09-23T18:00:00Z');
      final DeliveryOrder b = _table(id: 'aaaa-2', placedAt: '2026-09-23T18:00:00Z');

      expect(tableRoundOf(a, <DeliveryOrder>[a, b])!.round, 1);
      expect(tableRoundOf(b, <DeliveryOrder>[a, b])!.round, 2);
      expect(tableRoundOf(a, <DeliveryOrder>[b, a])!.round, 1);
      expect(tableRoundOf(b, <DeliveryOrder>[b, a])!.round, 2);
    });

    test('a ticket the server could not date sorts last rather than renumbering the rest', () {
      final DeliveryOrder dated = _table(id: 'aaaa-1', placedAt: '2026-09-23T18:00:00Z');
      final DeliveryOrder undated = _table(id: 'aaaa-2', placedAt: null);

      expect(tableRoundOf(dated, <DeliveryOrder>[dated, undated])!.round, 1);
      expect(tableRoundOf(undated, <DeliveryOrder>[dated, undated])!.round, 2);
    });

    test('a table order with no table on it claims no round', () {
      // The database will not allow it (V40: a table label if and only if the kind is TABLE), which is
      // exactly why a client must not invent one if it ever arrives.
      final DeliveryOrder order =
          DeliveryOrder.fromJson(_tableOrder()..['tableLabel'] = null);

      expect(order.tableLabel, isNull);
      expect(tableRoundOf(order, <DeliveryOrder>[order]), isNull);
    });
  });

  group('the words a table order is read in', () {
    final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
    final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

    test('READY and DELIVERED are said as a restaurant says them', () {
      final DeliveryOrder ready = _table(status: 'READY');
      final DeliveryOrder served = _table(status: 'DELIVERED');

      // "Ready for pickup" tells a kitchen somebody is coming for the food, and "Delivered" says it
      // left the building. Neither happened.
      expect(ready.statusLabelIn(en), en.merchTableStatusReady);
      expect(ready.statusLabelIn(en), isNot(OrderStatus.ready.labelIn(en)));
      expect(served.statusLabelIn(en), en.merchTableStatusServed);
      expect(served.statusLabelIn(en), isNot(OrderStatus.delivered.labelIn(en)));

      // Arabic is a real translation, not the English string.
      expect(ready.statusLabelIn(ar), isNotEmpty);
      expect(ready.statusLabelIn(ar), isNot(ready.statusLabelIn(en)));
      expect(served.statusLabelIn(ar), isNot(served.statusLabelIn(en)));
    });

    test('every other status reads exactly as it does on a delivery', () {
      for (final String status in <String>['PLACED', 'ACCEPTED', 'PREPARING', 'CANCELLED']) {
        final DeliveryOrder order = _table(status: status);
        expect(order.statusLabelIn(en), order.status.labelIn(en), reason: status);
        expect(order.statusLabelIn(ar), order.status.labelIn(ar), reason: status);
      }
    });

    test('a delivery order keeps every word it had', () {
      for (final String status in <String>['READY', 'DELIVERED', 'PICKED_UP']) {
        final DeliveryOrder order =
            DeliveryOrder.fromJson(_deliveryOrder(status: status));
        expect(order.statusLabelIn(en), order.status.labelIn(en), reason: status);
      }
    });

    test('the hand-over is served to a table, not collected by a customer', () {
      final DeliveryOrder ready = _table(status: 'READY');
      final DeliveryOrder pickup = DeliveryOrder.fromJson(_deliveryOrder(status: 'READY'));

      expect(ready.actionLabelIn(OrderAction.collected, en), en.merchTableActionServed);
      expect(ready.actionLabelIn(OrderAction.collected, en),
          isNot(OrderAction.collected.labelIn(en)));
      expect(ready.actionLabelIn(OrderAction.collected, ar),
          isNot(ready.actionLabelIn(OrderAction.collected, en)));
      // The same transition on an order nobody dines in at keeps the counter's words.
      expect(pickup.actionLabelIn(OrderAction.collected, en),
          OrderAction.collected.labelIn(en));
      // Every other action is the same word on both.
      for (final OrderAction action in <OrderAction>[
        OrderAction.accept,
        OrderAction.prepare,
        OrderAction.ready,
        OrderAction.cancel,
      ]) {
        expect(ready.actionLabelIn(action, en), action.labelIn(en), reason: action.name);
      }
    });

    test('the mark is the table, and the round only once there are two', () {
      final DeliveryOrder first = _table(id: 'aaaa-1', placedAt: '2026-09-23T18:00:00Z');
      final DeliveryOrder second = _table(id: 'aaaa-2', placedAt: '2026-09-23T18:40:00Z');

      expect(tableMarkFor(first, <DeliveryOrder>[first], en), en.merchTableTicket(7));
      expect(tableMarkFor(first, <DeliveryOrder>[first], en), contains('7'));

      final List<DeliveryOrder> both = <DeliveryOrder>[first, second];
      expect(tableMarkFor(second, both, en), en.merchTableTicketRound(7, 2));
      expect(tableMarkFor(second, both, en), contains('2'));
      expect(tableMarkFor(first, both, en), en.merchTableTicketRound(7, 1));

      // Arabic carries both figures too, in Arabic words.
      expect(tableMarkFor(second, both, ar), contains('7'));
      expect(tableMarkFor(second, both, ar), isNot(tableMarkFor(second, both, en)));
    });

    test('a served ticket still says which table it was, without a round', () {
      final DeliveryOrder served = _table(status: 'DELIVERED');

      expect(tableMarkFor(served, <DeliveryOrder>[served], en), en.merchTableTicket(7));
    });

    test('nothing is marked on an order that did not come from a table', () {
      final DeliveryOrder delivery = DeliveryOrder.fromJson(_deliveryOrder());

      expect(tableMarkFor(delivery, <DeliveryOrder>[delivery], en), isNull);
      expect(tableMarkFor(DeliveryOrder.fromJson(_tableOrder()..['tableLabel'] = null),
          <DeliveryOrder>[], en),
          isNull);
    });
  });
}
