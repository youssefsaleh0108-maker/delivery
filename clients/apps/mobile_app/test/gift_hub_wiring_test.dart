import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/gift_hub_screen.dart';
import 'package:mobile_app/src/offline_store.dart';

import 'widget_test.dart' show sessionWith;

/// That a customer can actually REACH the gift hub from the app they are holding.
///
/// Written because the screen it replaces could not. DiasporaScreen was built, translated and
/// tested, and shipped with no call site at all: its own tests constructed it directly, so nothing
/// failed while no route in the app led to it. What is pinned here is not what the hub renders —
/// `gift_hub_test.dart` does that — but that the real shell hands it over, from both doors.
class _MemoryStore implements OfflineStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  const MethodChannel storageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (MethodCall call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  Map<String, dynamic> page(List<Map<String, dynamic>> content) => <String, dynamic>{
        'content': content,
        'page': 0,
        'totalElements': content.length,
        'totalPages': 1,
      };

  /// GETs answered from [answers]; any other order read is an empty page, anything else a 404.
  Dio serve(Map<String, Object> answers) {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        final Object? body = o.method != 'GET'
            ? null
            : answers[o.path] ??
                (o.path.startsWith('/api/orders') ? page(const <Map<String, dynamic>>[]) : null);
        if (body == null) {
          h.reject(DioException(
            requestOptions: o,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(requestOptions: o, statusCode: 404),
          ));
          return;
        }
        h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: body));
      },
    ));
    return dio;
  }

  /// The real shell, over a gateway whose gift terms accept [giftMethods].
  Future<void> pumpShell(WidgetTester tester,
      {List<String> giftMethods = const <String>['CARD']}) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final Dio dio = serve(<String, Object>{
      '/api/stores': page(const <Map<String, dynamic>>[]),
      '/api/stores/favorites': page(const <Map<String, dynamic>>[]),
      '/api/banners': const <dynamic>[],
      '/api/categories/chips': const <dynamic>[],
      '/api/notifications/unread-count': const <String, dynamic>{'unread': 0},
      '/api/butler/mine': page(const <Map<String, dynamic>>[]),
      '/api/gift-bundles': const <dynamic>[],
      '/api/orders/gift-terms': <String, dynamic>{'wrapFee': 3.0, 'paymentMethods': giftMethods},
    });
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
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
        offlineStore: _MemoryStore(),
        session: sessionWith(<DeliveryRole>{DeliveryRole.customer}),
        locale: LocaleController(read: () async => 'en', write: (String _) async {}),
        onSignOut: () async {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Home\'s gift card opens the gift hub over the shell', (WidgetTester tester) async {
    await pumpShell(tester);

    expect(find.byType(GiftHubScreen), findsNothing);
    await tester.tap(find.text(en.giftHomeEntryTitle));
    await tester.pumpAndSettle();

    expect(find.byType(GiftHubScreen), findsOneWidget);
    expect(find.text(en.giftHubBannerTitle), findsOneWidget);
  });

  testWidgets('the profile menu opens it too', (WidgetTester tester) async {
    await pumpShell(tester);

    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.giftHubTitle));
    await tester.pumpAndSettle();

    expect(find.byType(GiftHubScreen), findsOneWidget);
  });

  testWidgets('while no method can pay for a gift, neither door is drawn', (WidgetTester tester) async {
    // What Order Manager answers today: cash alone, and a gift is never paid in cash.
    await pumpShell(tester, giftMethods: const <String>['CASH']);

    expect(find.text(en.giftHomeEntryTitle), findsNothing);

    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
    // The menu is open, and has no gift row in it.
    expect(find.text(en.custMyAddresses), findsOneWidget);
    expect(find.text(en.giftHubTitle), findsNothing);
  });
}
