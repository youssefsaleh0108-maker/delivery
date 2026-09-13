import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/offline_store.dart';

import 'widget_test.dart' show sessionWith;

/// The profile menu's doors to selling services, through the real customer shell.
///
/// A customer with no partner role is offered the services signup (Figma 126:11); a customer who
/// already runs a shop is offered the switch to it instead — never both; and a host that hands over
/// neither draws neither. Which account gets which is the host's decision (main.dart); what is pinned
/// here is that the shell passes each door through to the menu, where one that is not handed over is
/// absent rather than dead.
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

  /// The real shell with its profile menu open, for an account holding [roles].
  Future<void> openMenu(
    WidgetTester tester, {
    Set<DeliveryRole> roles = const <DeliveryRole>{DeliveryRole.customer},
    VoidCallback? onOfferServices,
    VoidCallback? onSwitchToShop,
  }) async {
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
        session: sessionWith(roles),
        locale: LocaleController(read: () async => 'en', write: (String _) async {}),
        onSignOut: () async {},
        onOfferServices: onOfferServices,
        onSwitchToShop: onSwitchToShop,
      ),
    ));
    await tester.pumpAndSettle();
    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();
  }

  testWidgets('a customer with no partner role is offered the services signup',
      (WidgetTester tester) async {
    int offered = 0;
    await openMenu(tester, onOfferServices: () => offered++);

    expect(find.text(en.svcSwitchToShop), findsNothing);
    expect(find.text(en.svcOfferYourServicesSub), findsOneWidget);
    await tester.ensureVisible(find.text(en.svcOfferYourServices));
    await tester.tap(find.text(en.svcOfferYourServices));
    await tester.pumpAndSettle();

    expect(offered, 1);
  });

  testWidgets('a customer who runs a shop is offered the switch to it, and not the signup',
      (WidgetTester tester) async {
    int switched = 0;
    int offered = 0;
    await openMenu(
      tester,
      roles: const <DeliveryRole>{DeliveryRole.customer, DeliveryRole.merchant},
      onSwitchToShop: () => switched++,
      onOfferServices: () => offered++,
    );

    expect(find.text(en.svcOfferYourServices), findsNothing);
    await tester.ensureVisible(find.text(en.svcSwitchToShop));
    await tester.tap(find.text(en.svcSwitchToShop));
    await tester.pumpAndSettle();

    expect(switched, 1);
    expect(offered, 0);
  });

  testWidgets('draws neither door when the host hands over neither', (WidgetTester tester) async {
    await openMenu(tester);

    expect(find.text(en.custMyAddresses), findsOneWidget, reason: 'the menu is open');
    expect(find.text(en.svcOfferYourServices), findsNothing);
    expect(find.text(en.svcSwitchToShop), findsNothing);
  });
}
