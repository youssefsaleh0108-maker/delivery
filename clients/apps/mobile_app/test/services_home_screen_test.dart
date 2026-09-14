import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/delivery_address.dart';
import 'package:mobile_app/src/service_provider_screen.dart';
import 'package:mobile_app/src/service_results_screen.dart';
import 'package:mobile_app/src/services_home_screen.dart';
import 'package:mobile_app/src/services_kit.dart';

import 'service_fixtures.dart';
import 'widget_test.dart' show sessionWith;

/// The Services tab (Figma 126:285) and the results it opens.
///
/// What the frame could not show: the grid is the server's open categories and nothing else, the
/// heading over the providers claims popularity only when a ranking backs it and nearness only when
/// there is a pin to be near, and a tab that finds nothing — or cannot read anything — says so.
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

  Map<String, dynamic> near(Map<String, dynamic> store, int metres) => <String, dynamic>{
        'store': store,
        'latitude': 33.8959,
        'longitude': 35.5155,
        'distanceMetres': metres,
      };

  FakeServer serve({
    FakeAnswer? categories,
    FakeAnswer? popular,
    FakeAnswer? nearby,
    FakeAnswer? browse,
    FakeAnswer? offers,
  }) =>
      FakeServer()
        ..on('GET', '/api/stores/service-categories',
            categories ?? (_) => <String>['PRINTING', 'TAILORING', 'REPAIRS', 'PHOTOGRAPHY'])
        ..on('GET', '/api/stores/services/popular', popular ?? (_) => <dynamic>[])
        ..on('GET', '/api/stores/nearby',
            nearby ?? (_) => pageJson(<Map<String, dynamic>>[near(storeJson(), 1200)]))
        ..on('GET', '/api/stores', browse ?? (_) => pageJson(<Map<String, dynamic>>[storeJson()]))
        ..on('GET', '/api/products/services',
            offers ?? (_) => pageJson(const <Map<String, dynamic>>[]));

  ServicesKit kit(FakeServer server, {DeliveryAddressStore? addresses}) => ServicesKit(
        storeApi: StoreApi(server.dio),
        orderApi: OrderApi(server.dio),
        catalogApi: CatalogApi(server.dio),
        zoneApi: DeliveryZoneApi(server.dio),
        addresses: addresses ?? DeliveryAddressStore(ownerId: 'test-user'),
        connectivity: ValueNotifier<bool>(true),
      );

  Future<DeliveryAddressStore> pinned() async {
    final DeliveryAddressStore addresses = DeliveryAddressStore(ownerId: 'test-user');
    await addresses.select(const DeliveryAddress(line: 'Home', latitude: 33.9, longitude: 35.51));
    return addresses;
  }

  final AuthSession session = sessionWith(<DeliveryRole>{DeliveryRole.customer});

  Future<void> pump(
    WidgetTester tester,
    FakeServer server, {
    ServicesKit? with_,
    bool showing = true,
    Locale locale = const Locale('en'),
    Size size = const Size(390, 2400),
  }) async {
    phone(tester, size: size);
    await tester.pumpWidget(svcApp(
      Scaffold(
        body: ServicesHomeScreen(kit: with_ ?? kit(server), session: session, showing: showing),
      ),
      locale: locale,
    ));
    await tester.pumpAndSettle();
  }

  List<RequestOptions> reads(FakeServer server, String path) => server.sent('GET', path);

  testWidgets('reads nothing until the tab is first shown', (WidgetTester tester) async {
    final FakeServer server = serve();
    final ServicesKit services = kit(server);
    await pump(tester, server, with_: services, showing: false);
    expect(server.requests, isEmpty);

    await pump(tester, server, with_: services);
    expect(reads(server, '/api/stores/service-categories'), hasLength(1));
    expect(find.text(en.svcCategoryPrinting), findsOneWidget);
  });

  testWidgets('the grid is the open categories only, and tailoring wears scissors',
      (WidgetTester tester) async {
    await pump(tester, serve(categories: (_) => <String>['PRINTING', 'TAILORING']));

    expect(find.text(en.custHiName(session.displayName.split(' ').first)), findsOneWidget);
    expect(find.text(en.svcBrandPill), findsOneWidget);
    expect(find.text(en.svcSearchHint), findsOneWidget);
    expect(find.text(en.svcCategoryPrinting), findsOneWidget);
    expect(find.text(en.svcCategoryTailoring), findsOneWidget);
    expect(find.text(en.svcCategoryCleaning), findsNothing);
    expect(find.text(en.svcCategoryBeauty), findsNothing);
    expect(find.byIcon(Icons.content_cut_rounded), findsOneWidget);
    expect(find.byIcon(Icons.highlight_off), findsNothing);
    expect(find.byIcon(Icons.cancel_outlined), findsNothing);
  });

  testWidgets('with a pin and a ranking: popular services near the customer, with their distance',
      (WidgetTester tester) async {
    final FakeServer server =
        serve(popular: (_) => <Map<String, dynamic>>[near(storeJson(), 450)]);
    await pump(tester, server, with_: kit(server, addresses: await pinned()));

    expect(find.text(en.svcPopularNearYou), findsOneWidget);
    expect(find.text('${en.svcCategoryPrinting} • ${en.svcDistanceAway(en.distanceM('450'))} • Mar Mikhael'),
        findsOneWidget);
    expect(reads(server, '/api/stores/services/popular').single.queryParameters['latitude'], 33.9);
    expect(reads(server, '/api/stores/nearby'), isEmpty);
  });

  testWidgets('with a pin but no ranking yet: the services nearest the pin',
      (WidgetTester tester) async {
    final FakeServer server = serve();
    await pump(tester, server, with_: kit(server, addresses: await pinned()));

    expect(find.text(en.svcPopularNearYou), findsNothing);
    expect(find.text(en.svcNearYou), findsOneWidget);
    expect(find.text('${en.svcCategoryPrinting} • ${en.svcDistanceAway(en.distanceKm('1.2'))} • Mar Mikhael'),
        findsOneWidget);
    expect(reads(server, '/api/stores/nearby').single.queryParameters['vertical'], 'SERVICES');
  });

  testWidgets('without a pin: the listing, claiming no distance and no nearness',
      (WidgetTester tester) async {
    final FakeServer server = serve();
    await pump(tester, server);

    expect(find.text(en.svcAllProviders), findsOneWidget);
    expect(find.text(en.svcNearYou), findsNothing);
    expect(find.text('${en.svcCategoryPrinting} • Mar Mikhael'), findsOneWidget);
    expect(reads(server, '/api/stores').single.queryParameters['vertical'], 'SERVICES');
    expect(reads(server, '/api/stores/services/popular'), isEmpty);
    expect(reads(server, '/api/stores/nearby'), isEmpty);
  });

  testWidgets('no services to show is an honest empty state', (WidgetTester tester) async {
    await pump(tester, serve(browse: (_) => pageJson(const <Map<String, dynamic>>[])));

    expect(find.text(en.svcNoServicesNearby), findsOneWidget);
    expect(find.text(en.svcCategoriesTitle), findsOneWidget);
  });

  testWidgets('with no category open, the tab says services are not offered here',
      (WidgetTester tester) async {
    await pump(tester, serve(categories: (_) => <String>[]));

    expect(find.text(en.svcServicesNotOffered), findsOneWidget);
    expect(find.text(en.svcCategoriesTitle), findsNothing);
  });

  testWidgets('when nothing can be read, Try again reads it', (WidgetTester tester) async {
    bool failing = true;
    final FakeServer server = serve(
      categories: (_) => failing ? const FakeReply(500) : <String>['PRINTING'],
      browse: (_) => failing ? const FakeReply(500) : pageJson(<Map<String, dynamic>>[storeJson()]),
    );
    await pump(tester, server);
    expect(find.text(en.svcCouldNotLoadServices), findsOneWidget);

    failing = false;
    await tester.tap(find.text(en.tryAgain));
    await tester.pumpAndSettle();
    expect(find.text(en.svcCategoryPrinting), findsOneWidget);
    expect(find.text('Al Fakhry Press'), findsOneWidget);
  });

  testWidgets('a category tile opens that category\'s providers', (WidgetTester tester) async {
    final FakeServer server = serve(
      browse: (RequestOptions r) => r.queryParameters['serviceCategory'] == 'REPAIRS'
          ? pageJson(const <Map<String, dynamic>>[])
          : pageJson(<Map<String, dynamic>>[storeJson()]),
    );
    await pump(tester, server);

    await tester.tap(find.text(en.svcCategoryPrinting));
    await tester.pumpAndSettle();
    expect(find.byType(ServiceCategoryResultsScreen), findsOneWidget);
    expect(reads(server, '/api/stores').last.queryParameters['serviceCategory'], 'PRINTING');
    expect(find.text('Al Fakhry Press'), findsOneWidget);

    await tester.tap(find.byType(YdBackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.svcCategoryRepairs));
    await tester.pumpAndSettle();
    expect(find.text(en.svcCategoryEmpty(en.svcCategoryRepairs)), findsOneWidget);
  });

  testWidgets('a search opens the providers and the offers that match', (WidgetTester tester) async {
    final FakeServer server = serve(
      browse: (RequestOptions r) => r.queryParameters['search'] == 'nothing'
          ? pageJson(const <Map<String, dynamic>>[])
          : pageJson(<Map<String, dynamic>>[storeJson()]),
      offers: (RequestOptions r) => r.queryParameters['search'] == 'nothing'
          ? pageJson(const <Map<String, dynamic>>[])
          : pageJson(<Map<String, dynamic>>[offerJson()]),
    );
    await pump(tester, server);

    await tester.enterText(find.byType(TextField), 'cards');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text(en.svcSearchTitle('cards')), findsOneWidget);
    expect(find.text(en.svcSearchProviders), findsOneWidget);
    expect(find.text(en.svcOffers), findsOneWidget);
    expect(find.text('Business Card Printing'), findsOneWidget);
    expect(reads(server, '/api/stores').last.queryParameters['search'], 'cards');
    expect(reads(server, '/api/products/services').single.queryParameters['search'], 'cards');

    await tester.tap(find.byType(YdBackButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nothing');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text(en.svcNoResults('nothing')), findsOneWidget);
  });

  testWidgets('a provider card opens the provider\'s page', (WidgetTester tester) async {
    await pump(tester, serve());

    await tester.tap(find.text('Al Fakhry Press'));
    await tester.pumpAndSettle();

    expect(find.byType(ServiceProviderScreen), findsOneWidget);
  });

  testWidgets('reads right to left in Arabic', (WidgetTester tester) async {
    await pump(tester, serve(), locale: const Locale('ar'));

    expect(find.text(ar.svcCategoriesTitle), findsOneWidget);
    expect(find.text(ar.svcBrandPill), findsOneWidget);
    expect(Directionality.of(tester.element(find.text(ar.svcCategoriesTitle))), TextDirection.rtl);
    // The greeting leads the header, so in Arabic it sits right of the pill.
    expect(tester.getCenter(find.textContaining(ar.custHiName('').trim())).dx,
        greaterThan(tester.getCenter(find.text(ar.svcBrandPill)).dx));
    // The first category is at the start of its row: the right.
    expect(tester.getCenter(find.text(ar.svcCategoryPrinting)).dx,
        greaterThan(tester.getCenter(find.text(ar.svcCategoryPhotography)).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a 320dp phone with every category open', (WidgetTester tester) async {
    await pump(
      tester,
      serve(
        categories: (_) => ServiceCategory.values.map((ServiceCategory c) => c.wireValue).toList(),
        browse: (_) => pageJson(<Map<String, dynamic>>[
          storeJson(name: 'Al Fakhry Press and Copy Centre of Greater Mar Mikhael'),
        ]),
      ),
      size: const Size(320, 1400),
    );

    expect(find.text(en.svcCategoryPhotography), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
