import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart'
    show PhotoPickSheet, PickedShelfPhoto, ShelfPhotoSource;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/item_search_screen.dart';

import 'widget_test.dart' show sessionWith;

/// Search by photo, as the customer meets it: the camera in Home's search box, the sheet that says
/// where the photo goes, and the results screen that sends it once and shows what it was read as.
///
/// Against a fake gateway answering `GET /api/products/search/capabilities` and
/// `POST /api/products/search/photo` as `PhotoSearchController` does. What the server makes of a photo
/// is product-service's own tests; these hold what the app does with the answer — and, above all, that
/// no camera is drawn unless the server says a real reader is there.

/// Stands in for the phone's camera and gallery.
class _Photos extends ShelfPhotoSource {
  _Photos({required this.bytes, this.canUseCamera = true});

  final Uint8List bytes;

  @override
  final bool canUseCamera;

  int cameraOpened = 0;
  int pickerOpened = 0;

  @override
  Future<PickedShelfPhoto?> takePhoto() async {
    cameraOpened++;
    return PickedShelfPhoto(bytes: bytes, contentType: 'image/jpeg');
  }

  @override
  Future<List<PickedShelfPhoto>> choosePhotos({required String label}) async {
    pickerOpened++;
    return <PickedShelfPhoto>[PickedShelfPhoto(bytes: bytes, contentType: 'image/jpeg')];
  }
}

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

  // A 1x1 JPEG: small enough that the app sends it untouched, which is what a phone photo already
  // prepared looks like by the time it reaches the API.
  final Uint8List jpeg = base64Decode('/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==');

  Map<String, dynamic> emptyPage() => <String, dynamic>{
        'content': <Object?>[],
        'page': 0,
        'totalElements': 0,
        'totalPages': 0,
      };

  Map<String, dynamic> shop() => <String, dynamic>{
        'store': <String, dynamic>{
          'id': 'shop-1',
          'slug': 'shop-1',
          'name': 'Corner Grocer',
          'vertical': 'GROCERY',
          'availability': 'OPEN',
          'deliveryFee': 1.5,
          'minOrder': 0,
          'etaMinMinutes': 20,
          'etaMaxMinutes': 30,
        },
        'latitude': 33.9008,
        'longitude': 35.4829,
        'distanceMetres': null,
        'items': <Object?>[
          <String, dynamic>{
            'id': 'p1',
            'merchantId': 'merchant-1',
            'storeId': 'shop-1',
            'name': 'Pepsi 1L',
            'price': 1.25,
            'status': 'ACTIVE',
            'inStock': true,
          },
        ],
        'matchedInStore': 1,
      };

  /// The photo answer, as `PhotoSearchController` writes it.
  Map<String, dynamic> photoAnswer({
    bool isProduct = true,
    bool similar = false,
    bool withShops = true,
  }) =>
      <String, dynamic>{
        'content': withShops ? <Object?>[shop()] : <Object?>[],
        'page': 0,
        'size': 10,
        'totalElements': withShops ? 1 : 0,
        'totalPages': withShops ? 1 : 0,
        'truncated': false,
        'candidateLimit': 300,
        'nearby': false,
        'understood': isProduct
            ? <String, dynamic>{
                'name': 'Pepsi 1L',
                'nameAr': 'بيبسي',
                'brand': 'Pepsi',
                'size': '1 L',
                'barcode': null,
                'isProduct': true,
              }
            : <String, dynamic>{'isProduct': false},
        'similar': similar,
        'nextQuery': isProduct
            ? <String, dynamic>{'terms': <String>['pepsi 1l'], 'barcode': null}
            : null,
        'photosLeftToday': 6,
      };

  /// Every request the app made, by path.
  final List<RequestOptions> requests = <RequestOptions>[];

  setUp(requests.clear);

  /// A fake gateway. [capabilities] is the capabilities answer, or null to fail that call; [photo] is
  /// what the photo search answers, with [photoStatus] for a refusal.
  Dio gateway({
    Map<String, dynamic>? capabilities,
    Map<String, dynamic>? photo,
    int photoStatus = 200,
  }) {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        requests.add(o);
        Object? body;
        int status = 200;
        if (o.path == '/api/products/search/capabilities') {
          if (capabilities == null) {
            h.reject(DioException(
              requestOptions: o,
              type: DioExceptionType.badResponse,
              response: Response<dynamic>(requestOptions: o, statusCode: 500),
            ));
            return;
          }
          body = capabilities;
        } else if (o.path == '/api/products/search/photo') {
          body = photo ?? photoAnswer();
          status = photoStatus;
        } else if (o.path == '/api/products/search/items') {
          body = photoAnswer();
        } else if (o.method == 'GET') {
          final String path = o.path;
          if (path == '/api/stores' ||
              path == '/api/stores/favorites' ||
              path == '/api/butler/mine' ||
              path.startsWith('/api/orders')) {
            body = emptyPage();
          } else if (path == '/api/banners' || path == '/api/categories/chips') {
            body = const <dynamic>[];
          } else if (path == '/api/notifications/unread-count') {
            body = const <String, dynamic>{'unread': 0};
          }
        }
        if (body == null || status != 200) {
          h.reject(DioException(
            requestOptions: o,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
                requestOptions: o, statusCode: body == null ? 404 : status, data: body),
          ));
          return;
        }
        h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: body));
      },
    ));
    return dio;
  }

  Widget app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
        theme: DeliveryTheme.light(),
        locale: locale,
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          DeliveryStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: LocaleController.supported,
        home: home,
      );

  Future<void> pumpHome(
    WidgetTester tester,
    Dio dio, {
    ShelfPhotoSource? photos,
    Size size = const Size(1000, 2400),
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(
      CustomerShell(
        storeApi: StoreApi(dio),
        orderApi: OrderApi(dio),
        notificationApi: NotificationApi(dio),
        butlerApi: ButlerApi(dio),
        zoneApi: DeliveryZoneApi(dio),
        offerApi: OfferApi(dio),
        photoSource: photos,
        session: sessionWith(<DeliveryRole>{DeliveryRole.customer}),
        locale: LocaleController(read: () async => 'en', write: (String _) async {}),
        onSignOut: () async {},
      ),
      locale: locale,
    ));
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> offered({bool photoSearch = true}) => <String, dynamic>{
        'photoSearch': photoSearch,
        'photosLeftToday': 7,
        'maxPhotoBytes': 2097152,
      };

  Finder camera() => find.byIcon(Icons.photo_camera_outlined);

  // -------------------------------------------------------------------------- whether to offer it

  group('the camera in Home', () {
    testWidgets('is drawn only when the server offers photo search', (WidgetTester tester) async {
      await pumpHome(tester, gateway(capabilities: offered()));
      expect(camera(), findsOneWidget);
      expect(find.bySemanticsLabel(en.psrchCamera), findsOneWidget);
    });

    testWidgets('is not drawn when the server says no', (WidgetTester tester) async {
      await pumpHome(tester, gateway(capabilities: offered(photoSearch: false)));

      expect(camera(), findsNothing);
      expect(requests.map((RequestOptions r) => r.path),
          contains('/api/products/search/capabilities'));
    });

    testWidgets('is not drawn when the server cannot say at all', (WidgetTester tester) async {
      await pumpHome(tester, gateway(capabilities: null));

      expect(camera(), findsNothing);
      // The rest of Home is unaffected by that failure.
      expect(find.text(en.isrchSearchHint), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------- the sheet

  group('the photo sheet', () {
    testWidgets('says where the photo goes, and offers the camera and the gallery',
        (WidgetTester tester) async {
      await pumpHome(tester, gateway(capabilities: offered()),
          photos: _Photos(bytes: jpeg));

      await tester.tap(camera());
      await tester.pumpAndSettle();

      expect(find.byType(PhotoPickSheet), findsOneWidget);
      expect(find.text(en.psrchSheetTitle), findsOneWidget);
      expect(find.text(en.psrchConsent), findsOneWidget);
      expect(find.text(en.psrchTakePhoto), findsOneWidget);
      expect(find.text(en.psrchChoosePhoto), findsOneWidget);
    });

    testWidgets('offers no camera on a device that has none, and still says where the photo goes',
        (WidgetTester tester) async {
      await pumpHome(tester, gateway(capabilities: offered()),
          photos: _Photos(bytes: jpeg, canUseCamera: false));

      await tester.tap(camera());
      await tester.pumpAndSettle();

      expect(find.text(en.psrchTakePhoto), findsNothing);
      expect(find.text(en.psrchChoosePhoto), findsOneWidget);
      expect(find.text(en.psrchConsent), findsOneWidget);
    });

    testWidgets('in Arabic, at 320 dp, it still reads and fits', (WidgetTester tester) async {
      await pumpHome(tester, gateway(capabilities: offered()),
          photos: _Photos(bytes: jpeg), size: const Size(320, 640), locale: const Locale('ar'));

      await tester.tap(camera());
      await tester.pumpAndSettle();

      expect(find.text(ar.psrchConsent), findsOneWidget);
      expect(find.text(ar.psrchChoosePhoto), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(Directionality.of(tester.element(find.text(ar.psrchConsent))), TextDirection.rtl);
    });
  });

  // -------------------------------------------------------------------------- the search itself

  group('searching by photo', () {
    /// Opens the sheet and chooses a photo from the gallery.
    Future<void> searchWithAPhoto(WidgetTester tester) async {
      await tester.tap(camera());
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.psrchChoosePhoto));
      await tester.pumpAndSettle();
    }

    testWidgets('sends the photo once, shows what it was read as, and the shops that sell it',
        (WidgetTester tester) async {
      final _Photos photos = _Photos(bytes: jpeg);
      await pumpHome(tester, gateway(capabilities: offered()), photos: photos);

      await searchWithAPhoto(tester);

      expect(photos.pickerOpened, 1);
      expect(find.byType(ItemSearchScreen), findsOneWidget);
      expect(
          requests.where((RequestOptions r) => r.path == '/api/products/search/photo'), hasLength(1));
      expect(find.text(en.psrchLooksLike('Pepsi 1L')), findsOneWidget);
      expect(find.text('Corner Grocer'), findsOneWidget);
      expect(find.text('Pepsi 1L'), findsWidgets);
    });

    testWidgets('the chip hands the words to the ordinary search, and the photo is not sent again',
        (WidgetTester tester) async {
      await pumpHome(tester, gateway(capabilities: offered()), photos: _Photos(bytes: jpeg));
      await searchWithAPhoto(tester);

      await tester.tap(find.text(en.psrchLooksLike('Pepsi 1L')));
      await tester.pumpAndSettle();

      final List<RequestOptions> items =
          requests.where((RequestOptions r) => r.path == '/api/products/search/items').toList();
      expect(items, isNotEmpty);
      expect((items.last.data as Map<dynamic, dynamic>)['q'], 'Pepsi 1L');
      expect(
          requests.where((RequestOptions r) => r.path == '/api/products/search/photo'), hasLength(1));
      // The chip goes with the photo it came from.
      expect(find.text(en.psrchLooksLike('Pepsi 1L')), findsNothing);
    });

    testWidgets('says when these shops sell the same kind of thing rather than the thing itself',
        (WidgetTester tester) async {
      await pumpHome(tester, gateway(capabilities: offered(), photo: photoAnswer(similar: true)),
          photos: _Photos(bytes: jpeg));

      await searchWithAPhoto(tester);

      expect(find.text(en.psrchSimilar), findsOneWidget);
    });

    testWidgets('says so when there was no product in the photo, and searches nothing',
        (WidgetTester tester) async {
      await pumpHome(
          tester,
          gateway(
              capabilities: offered(), photo: photoAnswer(isProduct: false, withShops: false)),
          photos: _Photos(bytes: jpeg));

      await searchWithAPhoto(tester);

      expect(find.text(en.psrchNotAProduct), findsOneWidget);
      expect(find.text(en.tryAgain), findsNothing);
    });
  });

  // -------------------------------------------------------------------------- refusals

  group('when the server refuses a photo', () {
    Future<void> refusing(WidgetTester tester, Map<String, dynamic> body, int status) async {
      await pumpHome(tester, gateway(capabilities: offered(), photo: body, photoStatus: status),
          photos: _Photos(bytes: jpeg));
      await tester.tap(camera());
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.psrchChoosePhoto));
      await tester.pumpAndSettle();
    }

    testWidgets("a day's photos spent says how many a day, with no retry", (WidgetTester tester) async {
      await refusing(
          tester,
          <String, dynamic>{
            'code': 'PHOTO_SEARCH_LIMIT',
            'limit': 10,
            'scope': 'DAY',
            'retryAfterSeconds': 3600,
          },
          429);

      expect(find.text(en.psrchLimitDay(10)), findsOneWidget);
      expect(find.text(en.tryAgain), findsNothing);
    });

    testWidgets('too many at once asks for a minute', (WidgetTester tester) async {
      await refusing(
          tester,
          <String, dynamic>{
            'code': 'PHOTO_SEARCH_LIMIT',
            'limit': 3,
            'scope': 'MINUTE',
            'retryAfterSeconds': 40,
          },
          429);

      expect(find.text(en.psrchLimitMinute), findsOneWidget);
      expect(find.text(en.psrchLimitDay(3)), findsNothing);
    });

    testWidgets('the whole platform being busy sends the customer to words', (WidgetTester tester) async {
      await refusing(
          tester,
          <String, dynamic>{
            'code': 'PHOTO_SEARCH_LIMIT',
            'limit': 1000,
            'scope': 'PLATFORM',
            'retryAfterSeconds': 600,
          },
          429);

      expect(find.text(en.psrchLimitPlatform), findsOneWidget);
    });

    testWidgets('a busy reader can be tried again', (WidgetTester tester) async {
      await refusing(tester, <String, dynamic>{'code': 'PHOTO_READER_BUSY'}, 503);

      expect(find.text(en.psrchBusy), findsOneWidget);
      expect(find.text(en.tryAgain), findsOneWidget);
    });

    testWidgets('an unavailable reader says so and takes the camera away with it',
        (WidgetTester tester) async {
      await refusing(tester, <String, dynamic>{'code': 'PHOTO_SEARCH_UNAVAILABLE'}, 503);

      expect(find.text(en.psrchUnavailable), findsOneWidget);
      expect(find.text(en.tryAgain), findsNothing);

      // Back on Home, the camera it came from is gone.
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(camera(), findsNothing);
    });

    testWidgets('a photo it could not read says so', (WidgetTester tester) async {
      await refusing(tester, <String, dynamic>{'code': 'PHOTO_UNREADABLE'}, 422);

      expect(find.text(en.psrchUnreadable), findsOneWidget);
    });

    testWidgets('a photo it would not search says its own thing', (WidgetTester tester) async {
      await refusing(tester, <String, dynamic>{'code': 'PHOTO_REFUSED'}, 422);

      expect(find.text(en.psrchRefused), findsOneWidget);
    });
  });
}
