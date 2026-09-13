import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/category_strip.dart';
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/store_state_mapping.dart';

import 'widget_test.dart' show sessionWith;

/// The Home storefront once the SERVICES vertical exists: unchanged.
///
/// Adding `StoreVertical.services` reached every goods picker, because they iterated
/// `StoreVertical.values`. Left that way, Home would have grown an eighth chip — Services — filtering a
/// storefront that never lists a service shop. These pin Home as it was before: the same seven chips
/// in the same order, a storefront read that names no vertical, and no Services chip even if the
/// server sent one.
///
/// The same holds for the "Your favourites" rail. The server leaves service shops out of that read;
/// a service shop that arrived in it anyway is still not drawn on Home.
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

  /// Home's strip before services existed: `StoreVertical.values` as it then was.
  const List<StoreVertical> homeAsItWas = <StoreVertical>[
    StoreVertical.restaurant,
    StoreVertical.coffee,
    StoreVertical.grocery,
    StoreVertical.convenience,
    StoreVertical.pharmacy,
    StoreVertical.electronics,
    StoreVertical.flowersGifts,
  ];

  late List<RequestOptions> requests;
  late List<Map<String, dynamic>> chips;
  late List<Map<String, dynamic>> favourites;

  setUp(() {
    requests = <RequestOptions>[];
    chips = <Map<String, dynamic>>[];
    favourites = <Map<String, dynamic>>[];
  });

  Map<String, dynamic> page(List<Map<String, dynamic>> content) => <String, dynamic>{
        'content': content,
        'page': 0,
        'totalElements': content.length,
        'totalPages': 1,
      };

  final Map<String, dynamic> grocer = <String, dynamic>{
    'id': 's1',
    'slug': 's1',
    'name': 'Abu Hassan Mini Market',
    'vertical': 'GROCERY',
    'availability': 'OPEN',
    'rating': 4.6,
    'ratingCount': 12,
  };

  /// A shop the customer starred, which the favourites rail draws.
  final Map<String, dynamic> starredBakery = <String, dynamic>{
    'id': 's2',
    'slug': 's2',
    'name': 'Rose & Crust Bakery',
    'vertical': 'RESTAURANT',
    'availability': 'OPEN',
    'rating': 4.8,
    'ratingCount': 30,
    'favorite': true,
  };

  /// A print shop the customer also starred. Service shops are never on Home.
  final Map<String, dynamic> starredPrintShop = <String, dynamic>{
    'id': 's3',
    'slug': 's3',
    'name': 'Al Fakhry Press',
    'vertical': 'SERVICES',
    'serviceCategory': 'PRINTING',
    'availability': 'OPEN',
    'rating': 4.9,
    'ratingCount': 51,
    'favorite': true,
  };

  Object? answer(RequestOptions options) {
    if (options.path.startsWith('/api/orders')) return page(const <Map<String, dynamic>>[]);
    return switch (options.path) {
      '/api/stores' => page(<Map<String, dynamic>>[grocer]),
      '/api/stores/favorites' => page(favourites),
      '/api/banners' => const <dynamic>[],
      '/api/categories/chips' => chips,
      '/api/delivery-zones' => const <dynamic>[],
      '/api/notifications/unread-count' => const <String, dynamic>{'unread': 0},
      '/api/butler/mine' => page(const <Map<String, dynamic>>[]),
      _ => null,
    };
  }

  Dio fakeServer() {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        requests.add(options);
        final Object? body = options.method == 'GET' ? answer(options) : null;
        if (body == null) {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(requestOptions: options, statusCode: 404),
          ));
          return;
        }
        handler.resolve(Response<dynamic>(requestOptions: options, statusCode: 200, data: body));
      },
    ));
    return dio;
  }

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final Dio dio = fakeServer();
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supported,
      home: CustomerShell(
        storeApi: StoreApi(dio),
        orderApi: OrderApi(dio),
        notificationApi: NotificationApi(dio),
        butlerApi: ButlerApi(dio),
        zoneApi: DeliveryZoneApi(dio),
        offerApi: OfferApi(dio),
        session: sessionWith(<DeliveryRole>{DeliveryRole.customer}),
        locale: LocaleController(read: () async => 'en', write: (String _) async {}),
        onSignOut: () async {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder servicesOnTheStrip() => find.descendant(
      of: find.byType(CategoryStrip), matching: find.text(en.svcVerticalServices));

  testWidgets('with no curated chips, Home shows the same seven goods verticals in the same order',
      (WidgetTester tester) async {
    await pumpHome(tester);

    final CategoryStrip strip = tester.widget(find.byType(CategoryStrip));
    expect(strip.verticals, homeAsItWas);
    expect(servicesOnTheStrip(), findsNothing);
  });

  testWidgets("Home's storefront read names no vertical and no service category",
      (WidgetTester tester) async {
    await pumpHome(tester);

    final List<RequestOptions> browse =
        requests.where((RequestOptions r) => r.path == '/api/stores').toList();
    expect(browse, isNotEmpty);
    for (final RequestOptions request in browse) {
      expect(request.queryParameters.containsKey('vertical'), isFalse);
      expect(request.queryParameters.containsKey('serviceCategory'), isFalse);
    }
  });

  testWidgets('a Services chip from the server is not drawn on Home', (WidgetTester tester) async {
    chips = <Map<String, dynamic>>[
      <String, dynamic>{'id': 'c1', 'name': 'Groceries', 'vertical': 'GROCERY'},
      <String, dynamic>{'id': 'c2', 'name': 'Services', 'vertical': 'SERVICES'},
    ];

    await pumpHome(tester);

    final CategoryStrip strip = tester.widget(find.byType(CategoryStrip));
    expect(strip.verticals, <StoreVertical>[StoreVertical.grocery]);
    expect(servicesOnTheStrip(), findsNothing);
  });

  testWidgets("a starred service shop in the favourites response is not drawn on Home's rail",
      (WidgetTester tester) async {
    favourites = <Map<String, dynamic>>[starredPrintShop, starredBakery];

    await pumpHome(tester);

    expect(find.text(en.yourFavourites), findsOneWidget);
    expect(find.text('Rose & Crust Bakery'), findsOneWidget);
    expect(find.text('Al Fakhry Press'), findsNothing);
  });

  testWidgets('favourites that are all service shops draw no favourites rail at all',
      (WidgetTester tester) async {
    favourites = <Map<String, dynamic>>[starredPrintShop];

    await pumpHome(tester);

    expect(find.text(en.yourFavourites), findsNothing);
    expect(find.text('Al Fakhry Press'), findsNothing);
  });

  test('the services vertical has an icon of its own, so the switch over verticals is complete', () {
    expect(iconForVertical(StoreVertical.services), Icons.work_outline_rounded);
    for (final StoreVertical goods in StoreVertical.pickerVerticals) {
      expect(iconForVertical(goods), isNot(Icons.work_outline_rounded));
    }
  });
}
