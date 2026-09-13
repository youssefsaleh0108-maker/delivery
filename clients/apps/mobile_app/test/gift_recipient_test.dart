import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/delivery_address.dart';

import 'widget_test.dart' show product, storeCard;

/// The gift state the phone keeps: who a recipient is, remembered with their address, and whether
/// the basket is a gift — which decides the checkout Proceed opens.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  group('a recipient remembered with their address', () {
    test('an address saved before gifting still reads, with nobody recorded', () {
      final DeliveryAddress old = DeliveryAddress.fromJson(<String, dynamic>{
        'line': 'Achrafieh, Sassine Square',
        'label': 'Teta Layla',
        'zoneId': 'zone-1',
      });

      expect(old.recipientName, isNull);
      expect(old.recipientPhone, isNull);
      expect(old.personName(en), 'Teta Layla');
    });

    test('survives storage, and a new area, once a gift has named them', () {
      final DeliveryAddress remembered = const DeliveryAddress(line: 'Mar Mikhael', label: 'Mom')
          .withRecipient('Mona (Mom)', '+96171234567');
      final DeliveryAddress restored = DeliveryAddress.fromJson(remembered.toJson());

      expect(restored.recipientName, 'Mona (Mom)');
      expect(restored.recipientPhone, '+96171234567');
      expect(restored.withZone('zone-2', 'Gemmayze').recipientPhone, '+96171234567');
      expect(restored.personName(en), 'Mona (Mom)');
    });

    test('a place is not a person, in either language', () {
      expect(const DeliveryAddress(line: 'x', label: 'Home').personName(en), isNull);
      expect(const DeliveryAddress(line: 'x', label: 'work').personName(en), isNull);
      expect(DeliveryAddress(line: 'x', label: ar.custLabelHome).personName(ar), isNull);
      expect(const DeliveryAddress(line: 'x').personName(en), isNull);
    });
  });

  group('a gift basket', () {
    Cart basket() => Cart()..add(product('a', 's1', 10), from: storeCard('s1'));

    test('stays a gift when another shop\'s items join it, and ends when it is emptied', () {
      final Cart cart = basket()..startGift();

      cart.add(product('b', 's2', 4), from: storeCard('s2'));
      expect(cart.isGift, isTrue);

      cart.giftNote = 'Love you';
      cart.giftWrap = true;
      cart.clear();
      expect(cart.isGift, isFalse);
      expect(cart.giftNote, isNull);
      expect(cart.giftWrap, isFalse);
    });

    test('"not a gift" forgets the card and the wrap that only a gift carries', () {
      final Cart cart = basket()..startGift();
      cart.giftNote = 'Love you';
      cart.giftWrap = true;

      cart.stopGift();

      expect(cart.isGift, isFalse);
      expect(cart.giftNote, isNull);
      expect(cart.giftWrap, isFalse);
      expect(cart.isNotEmpty, isTrue);
    });
  });
}
