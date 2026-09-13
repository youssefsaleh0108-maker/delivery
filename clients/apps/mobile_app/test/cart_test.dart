import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/product_options_sheet.dart';

import 'widget_test.dart' show product, storeCard;

/// One basket, several shops (Figma 121:358): the rules the basket keeps while it holds them.
///
/// A second shop used to be refused outright — "one basket, one store, one order". Now each shop is
/// a group of its own, measured against its own minimum and checked out as its own order, and the
/// only thing an add can be refused for is going past [Cart.maxShops].
void main() {
  group('a basket from several shops', () {
    test('a second shop becomes a second group, and nothing is refused or thrown away', () {
      final Cart cart = Cart()
        ..add(product('shawarma', 's1', 9.00), from: storeCard('s1', deliveryFee: 3))
        ..add(product('panadol', 's2', 5.00), from: storeCard('s2', deliveryFee: 2));

      expect(cart.storeIds, <String>['s1', 's2']);
      expect(cart.isMultiShop, isTrue);
      expect(cart.itemCount, 2);
      expect(cart.subtotal, closeTo(14.00, 0.001));
      expect(cart.linesFor('s1').single.product.id, 'shawarma');
      expect(cart.linesFor('s2').single.storeId, 's2');
      expect(cart.storeFor('s2')?.name, 'Shop s2');
      // "The basket's shop" is no longer a question with one answer, so nothing pretends it is.
      expect(cart.storeId, isNull);
      expect(cart.store, isNull);
    });

    test('each shop is measured against its own minimum, never helped by another\'s goods', () {
      final Cart cart = Cart()
        ..add(product('a', 's1', 8.00), from: storeCard('s1', minOrder: 10))
        ..add(product('b', 's2', 5.00), from: storeCard('s2', minOrder: 4));

      expect(cart.shortfallAt('s1'), closeTo(2.00, 0.001));
      expect(cart.shortfallAt('s2'), 0);
      expect(cart.meetsMinimum, isFalse);

      cart.add(product('c', 's1', 2.00), from: storeCard('s1', minOrder: 10));
      expect(cart.meetsMinimum, isTrue);
    });

    test('removing a shop\'s last line drops that shop and keeps the other', () {
      final Cart cart = Cart()
        ..add(product('a', 's1', 8), from: storeCard('s1'))
        ..add(product('b', 's2', 5), from: storeCard('s2'));

      cart.remove('a');

      expect(cart.storeIds, <String>['s2']);
      expect(cart.storeId, 's2');
      expect(cart.isEmpty, isFalse);
    });

    test('a whole shop can be taken out, leaving the rest of the basket as it was', () {
      final Cart cart = Cart()
        ..add(product('a', 's1', 8), from: storeCard('s1'))
        ..add(product('b', 's1', 2), from: storeCard('s1'))
        ..add(product('c', 's2', 5), from: storeCard('s2'));

      cart.removeStore('s1');

      expect(cart.storeIds, <String>['s2']);
      expect(cart.itemCount, 1);
      expect(cart.subtotal, closeTo(5, 0.001));
    });

    test('a shop past the limit is refused at the tap, and room comes back when a shop leaves', () {
      final Cart cart = Cart();
      for (final String shop in <String>['s1', 's2', 's3']) {
        cart.add(product('p-$shop', shop, 1), from: storeCard(shop));
      }
      final Product fourth = product('p-s4', 's4', 1);

      expect(Cart.maxShops, 3);
      expect(cart.exceedsShopLimit(fourth), isTrue);
      expect(() => cart.add(fourth), throwsStateError);
      // More from a shop already in the basket is always fine.
      expect(cart.exceedsShopLimit(product('more', 's2', 1)), isFalse);

      cart.removeStore('s1');
      expect(cart.exceedsShopLimit(fourth), isFalse);
    });

    test('every shop\'s lines go in the order lines, and differently configured lines stay apart',
        () {
      final Product pizza = product('pizza', 's1', 10);
      final Cart cart = Cart()
        ..addConfigured(
            ConfiguredProduct(
                product: pizza, optionIds: <String>['large'], unitPrice: 12, summary: 'Large'),
            from: storeCard('s1'))
        ..addConfigured(
            ConfiguredProduct(
                product: pizza, optionIds: <String>['medium'], unitPrice: 10, summary: 'Medium'),
            from: storeCard('s1'))
        ..add(product('panadol', 's2', 5), from: storeCard('s2'));

      expect(cart.toOrderLines(), hasLength(3));
      expect(cart.linesFor('s1'), hasLength(2));
      expect(cart.qtyOf('pizza'), 2);
    });

    test('one checkout key covers the whole basket, through shops joining and leaving it', () {
      final Cart cart = Cart()..add(product('a', 's1', 2), from: storeCard('s1'));
      final String key = cart.checkoutKey;

      cart.add(product('b', 's2', 3), from: storeCard('s2'));
      expect(cart.checkoutKey, key);
      cart.removeStore('s1');
      expect(cart.checkoutKey, key);

      // Emptied: that attempt is over, and the next basket is a new one.
      cart.removeStore('s2');
      expect(cart.checkoutKey, isNot(key));
    });

    test('a later add from a screen without the shop\'s card keeps the card an earlier add brought',
        () {
      final Cart cart = Cart()
        ..add(product('a', 's1', 8), from: storeCard('s1', minOrder: 10))
        ..add(product('b', 's1', 1));

      expect(cart.storeFor('s1')?.minOrder, 10);
      expect(cart.shortfallAt('s1'), closeTo(1, 0.001));
    });
  });
}
