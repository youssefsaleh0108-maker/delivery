import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mobile_app/src/butler_screen.dart';
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/delivery_address.dart';
import 'package:mobile_app/src/product_options_sheet.dart';

/// The role branch is the whole point of a single mobile codebase serving two users (Section 9),
/// and the cart carries the one business rule the client enforces locally.
AuthSession sessionWith(Set<DeliveryRole> roles) => AuthSession(
      accessToken: 'token',
      refreshToken: null,
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      roles: roles,
      subject: 'user-1',
    );

/// [storeId] doubles as the merchant id: a store belongs to exactly one merchant, so in a fixture
/// the two never usefully differ.
Product product(String id, String storeId, double price) => Product(
      id: id,
      merchantId: storeId,
      storeId: storeId,
      name: 'Item $id',
      description: null,
      price: price,
      categoryId: null,
      imageRefs: const <String>[],
      imageUrls: const <String>[],
      status: ProductStatus.active,
    );

StoreCard storeCard(String id, {double deliveryFee = 0, double minOrder = 0}) => StoreCard(
      id: id,
      slug: id,
      name: 'Shop $id',
      vertical: StoreVertical.restaurant,
      availability: StoreAvailability.open,
      deliveryFee: deliveryFee,
      minOrder: minOrder,
    );

void main() {
  group('role branch', () {
    test('a customer session does not carry the rider role', () {
      final AuthSession customer = sessionWith(<DeliveryRole>{DeliveryRole.customer});

      expect(customer.hasRole(DeliveryRole.customer), isTrue);
      expect(customer.hasRole(DeliveryRole.delivery), isFalse);
    });

    test('a staff account holding both roles is treated as a rider', () {
      // main.dart checks hasRole(delivery) first, so this session lands on the rider surface.
      final AuthSession both =
          sessionWith(<DeliveryRole>{DeliveryRole.customer, DeliveryRole.delivery});

      expect(both.hasRole(DeliveryRole.delivery), isTrue);
    });
  });

  group('cart', () {
    test('totals multiply by quantity', () {
      final Cart cart = Cart();
      cart.add(product('a', 'm1', 9.75));
      cart.add(product('a', 'm1', 9.75));
      cart.add(product('b', 'm1', 3.50));

      expect(cart.itemCount, 3);
      expect(cart.subtotal, closeTo(23.00, 0.001));
      expect(cart.qtyOf('a'), 2);
    });

    test('adding a second shop is refused', () {
      final Cart cart = Cart();
      cart.add(product('a', 'm1', 5.00));

      final Product other = product('b', 'm2', 5.00);
      expect(cart.conflictsWith(other), isTrue);
      // Order Manager rejects this too; failing here just means the customer hears about it at
      // the moment of the tap rather than at checkout.
      expect(() => cart.add(other), throwsStateError);
    });

    test('emptying the basket releases the store lock', () {
      final Cart cart = Cart();
      cart.add(product('a', 'm1', 5.00));
      expect(cart.storeId, 'm1');

      cart.remove('a');

      expect(cart.isEmpty, isTrue);
      expect(cart.storeId, isNull);
      // Which means a different shop is now addable without an explicit "clear basket".
      expect(cart.conflictsWith(product('b', 'm2', 5.00)), isFalse);
    });

    test('switching shops discards the old basket and re-locks in one step', () {
      final Cart cart = Cart();
      cart.add(product('a', 'm1', 5.00), from: storeCard('m1'));

      cart.switchTo(storeCard('m2'));

      expect(cart.isEmpty, isTrue);
      expect(cart.storeId, 'm2');
      // Re-locked immediately, so the product that triggered the switch goes straight in.
      expect(cart.conflictsWith(product('b', 'm2', 5.00)), isFalse);
    });

    test('the delivery fee is added to the total but not to the subtotal', () {
      final Cart cart = Cart();
      cart.add(product('a', 'm1', 10.00), from: storeCard('m1', deliveryFee: 2.50));

      expect(cart.subtotal, closeTo(10.00, 0.001));
      expect(cart.deliveryFee, closeTo(2.50, 0.001));
      expect(cart.total, closeTo(12.50, 0.001));
    });

    test('a minimum order is measured against the subtotal, not the total', () {
      // Otherwise the delivery fee would help a basket clear the shop's own minimum, which is
      // the one number the minimum exists to exclude.
      final Cart cart = Cart();
      cart.add(product('a', 'm1', 8.00),
          from: storeCard('m1', deliveryFee: 5.00, minOrder: 10.00));

      expect(cart.meetsMinimum, isFalse);
      expect(cart.amountBelowMinimum, closeTo(2.00, 0.001));

      cart.add(product('b', 'm1', 2.00));

      expect(cart.meetsMinimum, isTrue);
      expect(cart.amountBelowMinimum, 0);
    });

    test('a basket with no known store has no fee and no minimum', () {
      final Cart cart = Cart();
      cart.add(product('a', 'm1', 5.00));

      expect(cart.deliveryFee, 0);
      expect(cart.meetsMinimum, isTrue);
    });

    test('removing decrements before it deletes the line', () {
      final Cart cart = Cart();
      cart.add(product('a', 'm1', 5.00));
      cart.add(product('a', 'm1', 5.00));

      cart.remove('a');
      expect(cart.qtyOf('a'), 1);

      cart.remove('a');
      expect(cart.qtyOf('a'), 0);
      expect(cart.isEmpty, isTrue);
    });

    test('order lines carry ids and quantities only, never prices', () {
      final Cart cart = Cart();
      cart.add(product('a', 'm1', 9.75));
      cart.add(product('a', 'm1', 9.75));

      final List<({String productId, int qty, List<String> optionIds})> lines =
          cart.toOrderLines();

      expect(lines, hasLength(1));
      expect(lines.first.productId, 'a');
      expect(lines.first.qty, 2);
      expect(lines.first.optionIds, isEmpty);
    });

    test('the same product with different options is two lines', () {
      // Mirrors OrderService.LineKey on the server. If these two disagreed, a basket showing two
      // lines would place an order with one.
      final Cart cart = Cart();
      final Product pizza = product('a', 'm1', 11.00);
      cart.addConfigured(ConfiguredProduct(
          product: pizza, optionIds: <String>['large'], unitPrice: 14.00, summary: 'Size: Large'));
      cart.addConfigured(ConfiguredProduct(
          product: pizza, optionIds: <String>['small'], unitPrice: 9.50, summary: 'Size: Small'));

      expect(cart.lines, hasLength(2));
      // The badge on the shelf tile counts the product, however it is configured.
      expect(cart.qtyOf('a'), 2);
      expect(cart.subtotal, closeTo(23.50, 0.001));
    });

    test('the identical configuration twice merges to quantity two', () {
      final Cart cart = Cart();
      final Product pizza = product('a', 'm1', 11.00);
      for (int i = 0; i < 2; i++) {
        cart.addConfigured(ConfiguredProduct(
            product: pizza, optionIds: <String>['large'], unitPrice: 14.00,
            summary: 'Size: Large'));
      }

      expect(cart.lines, hasLength(1));
      expect(cart.lines.first.qty, 2);
      expect(cart.subtotal, closeTo(28.00, 0.001));
    });

    test('option order does not create a duplicate line', () {
      final Cart cart = Cart();
      final Product pizza = product('a', 'm1', 11.00);
      cart.addConfigured(ConfiguredProduct(product: pizza,
          optionIds: <String>['cheese', 'olives'], unitPrice: 12.75, summary: 'Extras'));
      cart.addConfigured(ConfiguredProduct(product: pizza,
          optionIds: <String>['olives', 'cheese'], unitPrice: 12.75, summary: 'Extras'));

      expect(cart.lines, hasLength(1));
      expect(cart.lines.first.qty, 2);
    });

    test('a configured line is priced by the catalog, not the base price', () {
      final Cart cart = Cart();
      cart.addConfigured(ConfiguredProduct(
          product: product('a', 'm1', 11.00),
          optionIds: <String>['large'],
          unitPrice: 14.00,
          summary: 'Choose Size: Large'));

      // 14.00, not the product's 11.00 — the deltas are already in the unit price.
      expect(cart.subtotal, closeTo(14.00, 0.001));
      expect(cart.toOrderLines().first.optionIds, <String>['large']);
    });
  });

  group('Butler request state', () {
    ButlerRequest at(ButlerStatus status, {ButlerMode mode = ButlerMode.buy}) => ButlerRequest(
          id: 'r1',
          mode: mode,
          status: status,
          what: 'Two litres of milk',
          dropoffAddress: '12 Test Street',
          deliveryFee: 3.50,
          payableTotal: 16.25,
          overBudget: false,
          createdAt: DateTime.now(),
        );

    test('only a quoted request is waiting on the customer', () {
      // This is what pulls a card to the top of the customer's list and rings it. If it were true
      // of any other state the list would nag about errands nobody can act on.
      for (final ButlerStatus s in ButlerStatus.values) {
        expect(at(s).awaitingApproval, s == ButlerStatus.quoted, reason: '$s');
      }
    });

    test('a request stays actionable until it is resolved', () {
      // The rider board drops terminal ones: a declined errand is not work, and leaving it makes
      // the list grow forever with things nobody can act on.
      expect(at(ButlerStatus.requested).status.isTerminal, isFalse);
      expect(at(ButlerStatus.claimed).status.isTerminal, isFalse);
      expect(at(ButlerStatus.quoted).status.isTerminal, isFalse);

      expect(at(ButlerStatus.approved).status.isTerminal, isTrue);
      expect(at(ButlerStatus.declined).status.isTerminal, isTrue);
      expect(at(ButlerStatus.cancelled).status.isTerminal, isTrue);
      expect(at(ButlerStatus.expired).status.isTerminal, isTrue);
    });

    test('an unknown status from a newer server does not crash the client', () {
      // Enums decoded from the wire are the classic place a client breaks on a server it did not
      // ship with. Falling back beats throwing inside a list builder.
      expect(ButlerStatus.fromWire('SOMETHING_NEW'), ButlerStatus.requested);
      expect(ButlerMode.fromWire(null), ButlerMode.buy);
    });

    test('a pickup carries no goods cost, because nothing was bought', () {
      final ButlerRequest pickup = at(ButlerStatus.claimed, mode: ButlerMode.send);

      expect(pickup.goodsCost, isNull);
      expect(pickup.mode, ButlerMode.send);
    });
  });

  group('Butler', () {
    /// The store is never `load()`ed, so it stays empty and touches no platform channel.
    ///
    /// The view is made tall enough for the whole form: the default 800x600 leaves the submit
    /// button outside the viewport, where a lazy ListView never builds it and no finder can reach
    /// it. Sizing the view is steadier than scrolling by a guessed offset.
    ///
    /// The APIs point at a Dio with no server behind it. That is deliberate rather than lazy: these
    /// tests are about which questions each mode asks, and a request that fails simply leaves the
    /// fee showing as a dash and the list empty — neither of which any assertion here depends on.
    Future<void> pumpButler(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
      await tester.pumpWidget(MaterialApp(
        theme: DeliveryTheme.light(),
        // Required now that the screen reads its labels from the string table: without the
        // delegates the lookup throws and every finder below reports nothing found, which reads
        // like a missing widget rather than a missing dependency.
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          DeliveryStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: LocaleController.supported,
        home: ButlerScreen(
          addresses: DeliveryAddressStore(ownerId: 'test-user'),
          api: ButlerApi(dio),
          orderApi: OrderApi(dio),
          storeApi: StoreApi(dio),
          zoneApi: DeliveryZoneApi(dio),
          cart: Cart(),
        ),
      ));
      // Lets the terms request fail and settle, so the tree is stable before anything is asserted.
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('opens on buy, and buying asks what to buy and for a budget',
        (WidgetTester tester) async {
      await pumpButler(tester);

      expect(find.text('What do you need?'), findsOneWidget);
      expect(find.text('Budget cap (optional)'), findsOneWidget);
      // The pickup address belongs to the other job.
      expect(find.text('Pick up from'), findsNothing);
    });

    testWidgets('switching to delivering your own things swaps the questions',
        (WidgetTester tester) async {
      await pumpButler(tester);

      await tester.tap(find.text('Deliver your stuff'));
      await tester.pumpAndSettle();

      expect(find.text('Pick up from'), findsOneWidget);
      expect(find.text('What are we moving?'), findsOneWidget);
      // Nothing is bought, so there is no goods price to cap — this is the difference that makes
      // the two modes worth keeping apart.
      expect(find.text('Budget cap (optional)'), findsNothing);
      expect(find.text('What do you need?'), findsNothing);
    });

    testWidgets('a pickup will not submit without somewhere to collect from',
        (WidgetTester tester) async {
      await pumpButler(tester);
      await tester.tap(find.text('Deliver your stuff'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'A4 envelope of documents');
      await tester.tap(find.text('Request a pickup'));
      await tester.pumpAndSettle();

      expect(find.text('Where should the rider collect it?'), findsOneWidget);
    });

    testWidgets('switching modes clears errors raised against fields that are now gone',
        (WidgetTester tester) async {
      await pumpButler(tester);

      // Fail validation in buy mode...
      await tester.tap(find.text('Request a Butler'));
      await tester.pumpAndSettle();
      expect(find.text('A bit more detail so the shopper knows what to buy'), findsOneWidget);

      // ...then leave it. The complaint was about a field this mode does not have.
      await tester.tap(find.text('Deliver your stuff'));
      await tester.pumpAndSettle();
      expect(find.text('A bit more detail so the shopper knows what to buy'), findsNothing);
    });
  });
}
