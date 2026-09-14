import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/delivery_address.dart';
import 'package:mobile_app/src/order_placement.dart';
import 'package:mobile_app/src/service_order_files.dart';
import 'package:mobile_app/src/service_order_screen.dart';
import 'package:mobile_app/src/service_provider_screen.dart';
import 'package:mobile_app/src/service_widgets.dart';
import 'package:mobile_app/src/services_kit.dart';

import 'service_fixtures.dart';

/// A service provider's page (Figma 126:371).
///
/// Pinned: the frame's meta row said only what is true (a distance needs two pins, "Open until" needs
/// a closing time, "New" stands in for a score nobody gave), "From" only where the price does start
/// there, no Share button with nothing behind it, no Order button while the shop is closed or while an
/// offer needs a file this app cannot send — and the two tabs the frame never drew, backed by the
/// shop's real reviews and hours.
void main() {
  const MethodChannel storageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (MethodCall call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  FakeServer serve({
    FakeAnswer? store,
    List<Map<String, dynamic>>? offers,
  }) =>
      FakeServer()
        ..on('GET', '/api/stores/s1', store ?? (_) => storeJson(description: 'We print anything.'))
        ..on('GET', '/api/stores/s1/products', (_) => pageJson(offers ?? <Map<String, dynamic>>[
              offerJson(),
              offerJson(id: 'p2', name: 'Banner Printing', price: 8, pricingType: 'PER_UNIT',
                  unitSize: 1, unitLabel: 'sqm', fulfilment: 'DELIVERY'),
              offerJson(id: 'p3', name: 'Photo Restoration', price: 25, pricingType: 'FROM',
                  unitLabel: null, unitSize: 1, fulfilment: 'PICKUP'),
              offerJson(id: 'p4', name: 'Flyer Design + Print', price: 15, fromPrice: 17.5,
                  unitLabel: null, unitSize: 1),
            ]))
        ..on('GET', '/api/products/p1/options', (_) => <dynamic>[])
        ..on('GET', '/api/stores/s1/hours', (_) => <Map<String, dynamic>>[
              for (int day = 1; day <= 6; day++)
                <String, dynamic>{'dayOfWeek': day, 'opensAt': '09:00:00', 'closesAt': '18:00:00'},
            ]);

  ServicesKit kit(FakeServer server, {DeliveryAddressStore? addresses, ServiceOrderFiles? files}) =>
      ServicesKit(
        storeApi: StoreApi(server.dio),
        orderApi: OrderApi(server.dio),
        zoneApi: DeliveryZoneApi(server.dio),
        addresses: addresses ?? DeliveryAddressStore(ownerId: 'test-user'),
        connectivity: ValueNotifier<bool>(true),
        files: files,
      );

  Future<void> pump(
    WidgetTester tester,
    FakeServer server, {
    ServicesKit? with_,
    Locale locale = const Locale('en'),
    Size size = const Size(390, 2400),
    bool settle = true,
  }) async {
    phone(tester, size: size);
    await tester.pumpWidget(svcApp(
      ServiceProviderScreen(
        kit: with_ ?? kit(server),
        storeId: 's1',
        preview: StoreCard.fromJson(storeJson()),
      ),
      locale: locale,
    ));
    if (settle) await tester.pumpAndSettle();
  }

  String clock(WidgetTester tester, int hour) =>
      MaterialLocalizations.of(tester.element(find.byType(ServiceProviderScreen)))
          .formatTimeOfDay(TimeOfDay(hour: hour, minute: 0));

  testWidgets('waits on the shop, and offers to try again when it cannot be read',
      (WidgetTester tester) async {
    final Completer<Object?> first = Completer<Object?>();
    int reads = 0;
    final FakeServer server =
        serve(store: (_) => ++reads == 1 ? first.future : storeJson());
    await pump(tester, server, settle: false);
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Al Fakhry Press'), findsOneWidget, reason: 'the tapped card names the page');

    first.complete(const FakeReply(500));
    await tester.pumpAndSettle();
    expect(find.text(en.couldNotLoadShop), findsOneWidget);

    await tester.tap(find.text(en.tryAgain));
    await tester.pumpAndSettle();
    expect(find.text(en.svcOffers), findsOneWidget);
  });

  testWidgets('says what is true about the shop: badge, tagline, rating, hours — and no Share',
      (WidgetTester tester) async {
    await pump(tester, serve());

    expect(find.text('Al Fakhry Press'), findsOneWidget);
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    expect(find.text('Printing & Copywriting Services'), findsOneWidget);
    expect(find.text('4.8'), findsOneWidget);
    expect(find.text(' (${en.svcReviewsCount(56)})'), findsOneWidget);
    expect(find.text(en.svcOpenUntil(clock(tester, 18))), findsOneWidget);
    expect(find.byIcon(Icons.share), findsNothing);
    expect(find.byIcon(Icons.share_outlined), findsNothing);
    expect(find.byIcon(Icons.ios_share), findsNothing);
    // No pin on the customer's side, so no distance is claimed.
    expect(
        find.byWidgetPredicate(
            (Widget w) => w is Text && RegExp(r'^[0-9.,]+ k?m$').hasMatch(w.data ?? '')),
        findsNothing);
  });

  testWidgets('a shop nobody has rated is New, and an unverified one wears no badge',
      (WidgetTester tester) async {
    await pump(tester,
        serve(store: (_) => storeJson(rating: null, ratingCount: 0, verifiedLocal: false)));

    expect(find.text(en.ratingNew), findsOneWidget);
    expect(find.text('0.0'), findsNothing);
    expect(find.byIcon(Icons.verified_rounded), findsNothing);
  });

  testWidgets('the distance appears once the customer\'s address has a pin',
      (WidgetTester tester) async {
    final DeliveryAddressStore addresses = DeliveryAddressStore(ownerId: 'test-user');
    final FakeServer server = serve();
    await pump(tester, server, with_: kit(server, addresses: addresses));

    await addresses.select(
        const DeliveryAddress(line: 'Home', latitude: 33.9004, longitude: 35.5155));
    await tester.pumpAndSettle();

    final int metres = distanceMetres(33.9004, 35.5155, 33.8959, 35.5155).round();
    expect(find.text(serviceDistanceLabel(metres, en)), findsOneWidget);
  });

  testWidgets('prices say "From" only where they start there, with what a pack is',
      (WidgetTester tester) async {
    await pump(tester, serve());

    expect(find.text('\$15.00'), findsOneWidget, reason: 'a fixed offer is its price');
    expect(find.text(en.svcFromPrice('\$15.00')), findsNothing);
    expect(find.text('\$8.00'), findsOneWidget, reason: 'a price per unit is that price');
    expect(find.text(en.svcFromPrice('\$25.00')), findsOneWidget, reason: 'FROM pricing');
    expect(find.text(en.svcFromPrice('\$17.50')), findsOneWidget,
        reason: 'required options raise where the price starts');
    expect(find.text(en.svcPackOf('500', 'cards')), findsOneWidget);
    expect(find.text(en.svcPerUnit('sqm')), findsOneWidget);
    expect(find.text(en.svcOrderCta), findsNWidgets(4));
  });

  testWidgets('Order opens the order screen for that offer', (WidgetTester tester) async {
    await pump(tester, serve());

    await tester.tap(find.text(en.svcOrderCta).first);
    await tester.pumpAndSettle();

    expect(find.byType(ServiceOrderScreen), findsOneWidget);
    expect(find.text('Business Card Printing'), findsOneWidget);
  });

  testWidgets('a closed shop\'s offers still browse, but nothing offers to order them',
      (WidgetTester tester) async {
    await pump(tester, serve(store: (_) => storeJson(availability: 'CLOSED')));

    expect(find.text(en.statusClosed), findsOneWidget);
    expect(find.text(en.svcClosedNoOrders), findsOneWidget);
    expect(find.text('Business Card Printing'), findsOneWidget);
    expect(find.text(en.svcOrderCta), findsNothing);
    expect(find.textContaining('Open until'), findsNothing);
  });

  testWidgets('an offer that needs a file is ordered only once files can be sent',
      (WidgetTester tester) async {
    final List<Map<String, dynamic>> offers = <Map<String, dynamic>>[
      offerJson(attachmentPolicy: 'REQUIRED'),
    ];
    final FakeServer server = serve(offers: offers);
    await pump(tester, server);
    expect(find.text(en.svcNeedsFileUnavailable), findsOneWidget);
    expect(find.text(en.svcOrderCta), findsNothing);

    await pump(tester, server, with_: kit(server, files: _NoFiles()));
    expect(find.text(en.svcNeedsFileUnavailable), findsNothing);
    expect(find.text(en.svcOrderCta), findsOneWidget);
  });

  testWidgets('a provider with no offers says so', (WidgetTester tester) async {
    await pump(tester, serve(offers: const <Map<String, dynamic>>[]));

    expect(find.text(en.svcNoOffers), findsOneWidget);
  });

  group('reviews', () {
    Map<String, dynamic> review(String id, String comment) => <String, dynamic>{
          'id': id,
          'rating': 4,
          'comment': comment,
          'createdAt': '2026-09-01T10:00:00Z',
        };

    testWidgets('are read when the tab opens, a page at a time', (WidgetTester tester) async {
      final FakeServer server = serve()
        ..on('GET', '/api/stores/s1/reviews', (RequestOptions r) => <String, dynamic>{
              'content': <Map<String, dynamic>>[
                if (r.queryParameters['page'] == 0) review('r1', 'Crisp cards, on time')
                else review('r2', 'Friendly and fast'),
              ],
              'page': r.queryParameters['page'],
              'totalElements': 2,
              'totalPages': 2,
            });
      await pump(tester, server);
      expect(server.sent('GET', '/api/stores/s1/reviews'), isEmpty);

      await tester.tap(find.text(en.reviews));
      await tester.pumpAndSettle();
      expect(find.text('Crisp cards, on time'), findsOneWidget);
      expect(find.text('Friendly and fast'), findsNothing);

      await tester.tap(find.text(en.svcLoadMore));
      await tester.pumpAndSettle();
      expect(find.text('Friendly and fast'), findsOneWidget);
      expect(find.text(en.svcLoadMore), findsNothing);
      expect(server.sent('GET', '/api/stores/s1/reviews').map((RequestOptions r) => r.queryParameters['page']),
          <int>[0, 1]);
    });

    testWidgets('none yet, or none readable, is said plainly', (WidgetTester tester) async {
      bool fail = true;
      final FakeServer server = serve()
        ..on('GET', '/api/stores/s1/reviews',
            (_) => fail ? const FakeReply(500) : pageJson(const <Map<String, dynamic>>[]));
      await pump(tester, server);

      await tester.tap(find.text(en.reviews));
      await tester.pumpAndSettle();
      expect(find.text(en.svcCouldNotLoadReviews), findsOneWidget);

      fail = false;
      await tester.tap(find.text(en.tryAgain));
      await tester.pumpAndSettle();
      expect(find.text(en.noReviewsYet), findsOneWidget);
    });
  });

  testWidgets('About: the description, the address, the week\'s hours and how the work reaches you',
      (WidgetTester tester) async {
    await pump(tester,
        serve(store: (_) => storeJson(description: 'We print anything.', address: '12 Armenia Street')));

    await tester.tap(find.text(en.svcTabAbout));
    await tester.pumpAndSettle();

    expect(find.text('We print anything.'), findsOneWidget);
    expect(find.text('12 Armenia Street'), findsOneWidget);
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('Sunday'), findsOneWidget);
    expect(find.text('${clock(tester, 9)} – ${clock(tester, 18)}'), findsNWidgets(6));
    expect(find.text(en.statusClosed), findsOneWidget, reason: 'Sunday has no hours');
    expect(find.text(en.svcPickupAtShop), findsOneWidget);
    expect(find.text(en.svcYouDropDelivery), findsOneWidget);
  });

  testWidgets('reads right to left in Arabic', (WidgetTester tester) async {
    await pump(tester, serve(), locale: const Locale('ar'));

    expect(find.text(ar.svcOffers), findsOneWidget);
    expect(find.text(ar.svcOrderCta), findsNWidgets(4));
    expect(Directionality.of(tester.element(find.text(ar.svcOffers))), TextDirection.rtl);
    // The back button sits at the start, which in Arabic is the right.
    expect(tester.getCenter(find.byType(YdBackButton)).dx, greaterThan(195));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(ar.svcTabAbout));
    await tester.pumpAndSettle();
    expect(find.text(ar.svcAboutHours), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a 320dp phone', (WidgetTester tester) async {
    await pump(
      tester,
      serve(
        store: (_) => storeJson(
            name: 'Al Fakhry Press and Copy Centre of Greater Mar Mikhael',
            tagline: 'Printing, copywriting, binding, lamination and large-format banners'),
        offers: <Map<String, dynamic>>[
          offerJson(
              name: 'Business Card Printing — Premium Heavyweight Stock, Double Sided',
              description: 'Premium matte finish cards with rounded corners and a spot gloss.'),
        ],
      ),
      size: const Size(320, 1400),
    );

    expect(tester.takeException(), isNull);
  });
}

/// An attachment client that is wired but never used — enough for a page to offer ordering.
class _NoFiles implements ServiceOrderFiles {
  @override
  Future<String> upload({
    required Uint8List bytes,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async =>
      'unused';

  @override
  Future<void> remove(String fileId) async {}

  @override
  Future<List<OrderAttachment>> forOrder(String orderId) async => const <OrderAttachment>[];
}
