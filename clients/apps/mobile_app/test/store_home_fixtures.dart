import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/store_home_screen.dart';

import 'widget_test.dart' show sessionWith;

/// What the tests of Home's two neighbourhood doors share: the browse (Figma 112:1941) and the
/// chat room (Figma 121:102). Home is pumped through the real shell, over a server that answers
/// in-process, with finders for the doors and the banner rail.
///
/// Not a test file (no `_test` suffix). Two test files import it. store_home_screen_test.dart runs
/// in the test font. store_home_screen_rubik_test.dart runs in the app's own Rubik, because whether
/// a word fits is a question about the real font. Each test file runs on its own, so the font one
/// file loads never reaches the other.

/// The page gutter.
const double homeGutter = DeliverySpacing.lg;

/// The gap between the two doors, across the row or down the stack: the house two-up gap.
const double homeDoorGap = DeliverySpacing.md - DeliverySpacing.xs;

/// Two banners, so the rail draws its dots as well: the doors have to clear the whole rail.
const List<Map<String, dynamic>> twoBanners = <Map<String, dynamic>>[
  <String, dynamic>{'id': 'b1', 'title': 'Ramadan at the corner shop', 'linkKind': 'NONE'},
  <String, dynamic>{'id': 'b2', 'title': 'Free delivery this weekend', 'linkKind': 'NONE'},
];

const Map<String, dynamic> _grocer = <String, dynamic>{
  'id': 's1',
  'slug': 's1',
  'name': 'Abu Hassan Mini Market',
  'vertical': 'GROCERY',
  'availability': 'OPEN',
  'rating': 4.6,
  'ratingCount': 12,
};

Map<String, dynamic> _page(List<Map<String, dynamic>> content) => <String, dynamic>{
      'content': content,
      'page': 0,
      'totalElements': content.length,
      'totalPages': 1,
    };

/// A Dio whose GETs Home makes are answered in-process; anything else is a 404.
Dio _fakeServer({required List<Map<String, dynamic>> banners, required bool withShops}) {
  Object? answer(RequestOptions options) {
    if (options.path.startsWith('/api/orders')) return _page(const <Map<String, dynamic>>[]);
    return switch (options.path) {
      '/api/stores' => _page(<Map<String, dynamic>>[if (withShops) _grocer]),
      '/api/stores/favorites' => _page(const <Map<String, dynamic>>[]),
      '/api/banners' => banners,
      '/api/categories/chips' => const <dynamic>[],
      '/api/delivery-zones' => const <dynamic>[],
      '/api/notifications/unread-count' => const <String, dynamic>{'unread': 0},
      '/api/butler/mine' => _page(const <Map<String, dynamic>>[]),
      _ => null,
    };
  }

  final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
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

/// Home through the real shell, on a phone [width] dp wide with text at [textScale]. The shell
/// decides whether Home gets a chat room at all: [withChat] hands it one. [withShops] false leaves
/// the shop grid under the doors empty.
Future<void> pumpHome(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  bool withChat = true,
  double width = 390,
  double textScale = 1.0,
  List<Map<String, dynamic>> banners = twoBanners,
  bool withShops = true,
}) async {
  const MethodChannel storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(storage, (MethodCall call) async => null);
  addTearDown(() => messenger.setMockMethodCallHandler(storage, null));

  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final Dio dio = _fakeServer(banners: banners, withShops: withShops);
  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    locale: locale,
    localizationsDelegates: const <LocalizationsDelegate<Object>>[
      DeliveryStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: LocaleController.supported,
    builder: (BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: CustomerShell(
      storeApi: StoreApi(dio),
      orderApi: OrderApi(dio),
      notificationApi: NotificationApi(dio),
      butlerApi: ButlerApi(dio),
      zoneApi: DeliveryZoneApi(dio),
      offerApi: OfferApi(dio),
      neighbourhoodChatApi: withChat ? NeighbourhoodChatApi(dio) : null,
      session: sessionWith(<DeliveryRole>{DeliveryRole.customer}),
      locale:
          LocaleController(read: () async => locale.languageCode, write: (String _) async {}),
      onSignOut: () async {},
    ),
  ));
  await tester.pumpAndSettle();
}

/// The door (a whole [YdCard]) whose title is [title].
Finder doorOf(String title) => find.ancestor(of: find.text(title), matching: find.byType(YdCard));

/// Something inside the door titled [title].
Finder inDoor(String title, Finder matching) =>
    find.descendant(of: doorOf(title), matching: matching);

/// Home's banner carousel.
Finder bannerRail() =>
    find.descendant(of: find.byType(StoreHomeScreen), matching: find.byType(PageView));
