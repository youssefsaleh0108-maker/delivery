import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Do I already have this?" — a merchant photographs a pack, and what happens next.
///
/// Against a recording adapter answering product-service's `PhotoFindController`. Also pins the bug
/// this work fixes: the product form now carries SKU and Barcode, and SENDS them, so saving an edit
/// no longer clears the codes the till and the shelf labels depend on.
class _Gateway implements HttpClientAdapter {
  _Gateway({this.find, this.findError, this.findStatus = 200});

  /// The find answer, or null when the call is refused with [findError] and [findStatus].
  final Map<String, dynamic>? find;

  /// The refusal body, as `ApiExceptionHandler` writes one.
  final Map<String, dynamic>? findError;
  final int findStatus;

  final List<RequestOptions> requests = <RequestOptions>[];
  final List<String> bodies = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    if (requestStream != null) {
      final List<int> sent = <int>[];
      await for (final Uint8List chunk in requestStream) {
        sent.addAll(chunk);
      }
      bodies.add(latin1.decode(sent));
    } else if (options.data != null) {
      bodies.add(jsonEncode(options.data));
    }

    Object? body = const <String, dynamic>{};
    int status = 200;
    if (options.path == '/api/products/mine/find-by-photo') {
      body = find ?? findError ?? const <String, dynamic>{'code': 'PHOTO_READER_FAILED'};
      status = find == null ? findStatus : 200;
    } else if (options.path == '/api/products/mine') {
      body = <String, dynamic>{'content': <Object?>[], 'page': 0, 'totalElements': 0, 'totalPages': 0};
    } else if (options.path == '/api/categories') {
      body = const <Object?>[];
    } else if (options.method == 'PUT' || options.method == 'POST') {
      body = <String, dynamic>{
        'id': 'p1',
        'merchantId': 'm1',
        'name': 'Pepsi 1L',
        'price': 1.25,
        'status': 'DRAFT',
      };
    }
    return ResponseBody.fromString(jsonEncode(body), status, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Stands in for the camera and the gallery.
class _Photos extends ShelfPhotoSource {
  _Photos({required this.bytes, this.canUseCamera = true});

  final Uint8List bytes;

  @override
  final bool canUseCamera;

  @override
  Future<PickedShelfPhoto?> takePhoto() async =>
      PickedShelfPhoto(bytes: bytes, contentType: 'image/jpeg');

  @override
  Future<List<PickedShelfPhoto>> choosePhotos({required String label}) async =>
      <PickedShelfPhoto>[PickedShelfPhoto(bytes: bytes, contentType: 'image/jpeg')];
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));
  // A 1x1 JPEG, as the Blitz test carries a 1x1 PNG: the fake gateway never decodes it, and the
  // app's own preparation leaves anything under its cap untouched.
  final Uint8List jpeg = base64Decode('/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==');

  /// A find answer: one product the shop already has, matched by its barcode.
  Map<String, dynamic> found({
    bool sample = false,
    bool withMatch = true,
    bool isProduct = true,
    String? suggestedBarcode = '5449000000996',
  }) =>
      <String, dynamic>{
        'provider': sample ? 'FAKE' : 'CLAUDE',
        'sample': sample,
        'understood': isProduct
            ? <String, dynamic>{'name': 'Pepsi 1L', 'nameAr': 'بيبسي', 'isProduct': true}
            : <String, dynamic>{'isProduct': false},
        'matches': <Object?>[
          if (withMatch)
            <String, dynamic>{
              'product': <String, dynamic>{
                'id': 'p1',
                'merchantId': 'm1',
                'storeId': 'shop-1',
                'name': 'Pepsi 1 litre',
                'price': 1.25,
                'status': 'ARCHIVED',
                'sku': 'SKU-1',
                'barcode': '5449000000996',
              },
              'matchedBy': 'BARCODE',
            },
        ],
        'suggestion': isProduct
            ? <String, dynamic>{
                'name': 'Pepsi 1L',
                'barcode': suggestedBarcode,
                'categoryId': null,
              }
            : null,
        'findsLeftToday': 29,
      };

  Widget app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
        theme: DeliveryTheme.light(),
        locale: locale,
        localizationsDelegates: DeliveryStrings.localizationsDelegates,
        supportedLocales: DeliveryStrings.supportedLocales,
        home: home,
      );

  /// The Inventory tab of one particular shop, which is where a multi-shop merchant stands.
  Future<void> pumpInventory(
    WidgetTester tester,
    _Gateway gateway, {
    required String storeId,
    ShelfPhotoSource? photos,
  }) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = gateway;
    await tester.pumpWidget(app(InventoryScreen(
      catalogApi: CatalogApi(dio),
      storeId: storeId,
      photoSource: photos,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> pumpList(
    WidgetTester tester,
    _Gateway gateway, {
    ShelfPhotoSource? photos,
    String? storeId,
    Size size = const Size(1200, 2200),
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = gateway;
    await tester.pumpWidget(app(
      ProductListScreen(api: CatalogApi(dio), storeId: storeId, photoSource: photos),
      locale: locale,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Opens the camera, chooses a photo, and waits for the answer.
  Future<void> findWithAPhoto(WidgetTester tester, {required DeliveryStrings t}) async {
    await tester.tap(find.byIcon(Icons.photo_camera_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.psrchChoosePhoto));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('the camera in the merchant catalogue', () {
    testWidgets('is drawn only when the host hands over a photo source', (WidgetTester tester) async {
      await pumpList(tester, _Gateway(find: found()));
      expect(find.byIcon(Icons.photo_camera_outlined), findsNothing);

      await pumpList(tester, _Gateway(find: found()), photos: _Photos(bytes: jpeg));
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
      expect(find.bySemanticsLabel(en.pfindCamera), findsOneWidget);
    });

    testWidgets('opens a sheet that says where the photo goes, with no camera on the web',
        (WidgetTester tester) async {
      await pumpList(tester, _Gateway(find: found()),
          photos: _Photos(bytes: jpeg, canUseCamera: false));

      await tester.tap(find.byIcon(Icons.photo_camera_outlined));
      await tester.pumpAndSettle();

      expect(find.text(en.pfindSheetTitle), findsOneWidget);
      expect(find.text(en.psrchConsent), findsOneWidget);
      expect(find.text(en.psrchTakePhoto), findsNothing);
      expect(find.text(en.psrchChoosePhoto), findsOneWidget);
    });
  });

  group('what the sheet says', () {
    testWidgets('shows what the photo was read as and the product the shop already has',
        (WidgetTester tester) async {
      final _Gateway gateway = _Gateway(find: found());
      await pumpList(tester, gateway, photos: _Photos(bytes: jpeg));

      await findWithAPhoto(tester, t: en);

      expect(gateway.requests.where((RequestOptions r) => r.path.endsWith('find-by-photo')),
          hasLength(1));
      expect(find.text(en.psrchLooksLike('Pepsi 1L')), findsOneWidget);
      expect(find.text(en.pfindInCatalogue), findsOneWidget);
      expect(find.text('Pepsi 1 litre'), findsOneWidget);
      // Its status travels with it: archived, not hidden.
      expect(find.text(en.merchbOffShelf), findsWidgets);
      expect(find.text(en.pfindMatchedByBarcode), findsOneWidget);
      expect(find.text(en.pfindAddNew), findsOneWidget);
    });

    testWidgets('says plainly when the shop does not have it yet', (WidgetTester tester) async {
      await pumpList(tester, _Gateway(find: found(withMatch: false)), photos: _Photos(bytes: jpeg));

      await findWithAPhoto(tester, t: en);

      expect(find.text(en.pfindNoMatch), findsOneWidget);
      expect(find.text(en.pfindAddNew), findsOneWidget);
    });

    testWidgets('labels a sample answer in Merchant Blitz words', (WidgetTester tester) async {
      await pumpList(tester, _Gateway(find: found(sample: true)), photos: _Photos(bytes: jpeg));

      await findWithAPhoto(tester, t: en);

      expect(find.text(en.blitzSampleTitle), findsOneWidget);
      expect(find.text(en.blitzSampleBody), findsOneWidget);
    });

    testWidgets('a sample offers a blank form, never one prefilled from the example',
        (WidgetTester tester) async {
      await pumpList(tester, _Gateway(find: found(sample: true)), photos: _Photos(bytes: jpeg));

      await findWithAPhoto(tester, t: en);

      // The example's own words are not on an "Add as a new product" button.
      expect(find.text(en.pfindAddNew), findsNothing);
      expect(find.text(en.pfindAddBlank), findsOneWidget);
      expect(find.text(en.pfindSampleNoPrefill), findsOneWidget);
    });

    testWidgets('says so when the photo showed no product, and offers nothing to add',
        (WidgetTester tester) async {
      await pumpList(tester, _Gateway(find: found(isProduct: false, withMatch: false)),
          photos: _Photos(bytes: jpeg));

      await findWithAPhoto(tester, t: en);

      expect(find.text(en.psrchNotAProduct), findsOneWidget);
      expect(find.text(en.pfindAddNew), findsNothing);
    });

    testWidgets("the merchant's own daily limit says how many a day, with no retry",
        (WidgetTester tester) async {
      await pumpList(
          tester,
          _Gateway(findError: const <String, dynamic>{
            'code': 'PHOTO_FIND_LIMIT',
            'limit': 30,
            'scope': 'DAY',
            'retryAfterSeconds': 900,
          }, findStatus: 429),
          photos: _Photos(bytes: jpeg));

      await findWithAPhoto(tester, t: en);

      expect(find.text(en.pfindLimitDay(30)), findsOneWidget);
      expect(find.text(en.tryAgain), findsNothing);
    });

    testWidgets('a burst is worded as a minute to wait, not as the day being spent',
        (WidgetTester tester) async {
      await pumpList(
          tester,
          _Gateway(findError: const <String, dynamic>{
            'code': 'PHOTO_FIND_LIMIT',
            'limit': 3,
            'scope': 'MINUTE',
            'retryAfterSeconds': 40,
          }, findStatus: 429),
          photos: _Photos(bytes: jpeg));

      await findWithAPhoto(tester, t: en);

      expect(find.text(en.psrchLimitMinute), findsOneWidget);
      expect(find.text(en.pfindLimitDay(3)), findsNothing);
    });

    testWidgets("the whole platform's day is said as the platform's, never as this shop's allowance",
        (WidgetTester tester) async {
      await pumpList(
          tester,
          _Gateway(findError: const <String, dynamic>{
            'code': 'PHOTO_FIND_LIMIT',
            'limit': 500,
            'scope': 'PLATFORM',
            'retryAfterSeconds': 300,
          }, findStatus: 429),
          photos: _Photos(bytes: jpeg));

      await findWithAPhoto(tester, t: en);

      expect(find.text(en.pfindLimitPlatform), findsOneWidget);
      // "You can look up 500 photos a day" would be a plain untruth: this shop may look up 30.
      expect(find.text(en.pfindLimitDay(500)), findsNothing);
    });

    testWidgets('a reader that failed can be tried again', (WidgetTester tester) async {
      await pumpList(
          tester,
          _Gateway(findError: const <String, dynamic>{'code': 'PHOTO_READER_FAILED'}, findStatus: 502),
          photos: _Photos(bytes: jpeg));

      await findWithAPhoto(tester, t: en);

      expect(find.text(en.psrchFailed), findsOneWidget);
      expect(find.text(en.tryAgain), findsOneWidget);
    });

    testWidgets('fits 320 dp and reads in Arabic', (WidgetTester tester) async {
      await pumpList(tester, _Gateway(find: found()),
          photos: _Photos(bytes: jpeg), size: const Size(320, 640), locale: const Locale('ar'));

      await findWithAPhoto(tester, t: ar);

      expect(find.text(ar.pfindInCatalogue), findsOneWidget);
      expect(find.text(ar.psrchConsent), findsWidgets);
      expect(tester.takeException(), isNull);
      expect(Directionality.of(tester.element(find.text(ar.pfindInCatalogue))), TextDirection.rtl);
    });
  });

  group('where the sheet leads', () {
    testWidgets('a match opens that product in the form, with its codes in the fields',
        (WidgetTester tester) async {
      await pumpList(tester, _Gateway(find: found()), photos: _Photos(bytes: jpeg));
      await findWithAPhoto(tester, t: en);

      await tester.tap(find.text('Pepsi 1 litre'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ProductFormScreen), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Pepsi 1 litre'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'SKU-1'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '5449000000996'), findsOneWidget);
    });

    testWidgets('"Add as a new product" opens a form prefilled with the name, the code and the photo',
        (WidgetTester tester) async {
      await pumpList(tester, _Gateway(find: found()), photos: _Photos(bytes: jpeg));
      await findWithAPhoto(tester, t: en);

      await tester.tap(find.text(en.pfindAddNew));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ProductFormScreen), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Pepsi 1L'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '5449000000996'), findsOneWidget);
      // The photo is the new product's first image, and can be removed like any other.
      expect(find.byType(PendingProductImageTile), findsOneWidget);
    });

    /// The merchant has two shops. They are standing in the second one — its Inventory tab, whose
    /// find was scoped to it — so the product they add from it has to be created there. Without the
    /// shop in the request the service files it in whichever it calls their first, which is the shop
    /// they were not looking at.
    testWidgets('a product added from a shop is created in THAT shop, not the merchant\'s first',
        (WidgetTester tester) async {
      final _Gateway gateway = _Gateway(find: found(withMatch: false));
      await pumpInventory(tester, gateway, storeId: 'shop-2', photos: _Photos(bytes: jpeg));

      await findWithAPhoto(tester, t: en);
      // The find was scoped to this shop on the way out, too — it travels in the multipart body.
      expect(gateway.bodies.first, contains('shop-2'));

      await tester.tap(find.text(en.pfindAddNew));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Name and barcode came from the reading; a price is the merchant's to put in. Fields in
      // order: name, description, price.
      await tester.enterText(find.byType(TextFormField).at(2), '1.25');
      await tester.tap(find.text(en.merchbSaveMenuItem));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The create itself, not the image presign that follows it.
      final String sent =
          gateway.bodies.firstWhere((String body) => body.contains('"price":1.25'));
      expect(sent, contains('"storeId":"shop-2"'));
      expect(sent, contains('"name":"Pepsi 1L"'));
    });

    /// The same merchant, the same two shops, standing in the Products page of the second one —
    /// the portal scopes that page to a shop exactly as it scopes Inventory. The catalogue LIST is
    /// every shop they own, which is right; what must name a shop is the product they add from it.
    testWidgets('the catalogue scopes its find and its new product to the shop it is standing in',
        (WidgetTester tester) async {
      final _Gateway gateway = _Gateway(find: found(withMatch: false));
      await pumpList(tester, gateway, storeId: 'shop-2', photos: _Photos(bytes: jpeg));

      await findWithAPhoto(tester, t: en);
      expect(gateway.bodies.first, contains('shop-2'));

      await tester.tap(find.text(en.pfindAddNew));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextFormField).at(2), '1.25');
      await tester.tap(find.text(en.merchbSaveMenuItem));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final String sent =
          gateway.bodies.firstWhere((String body) => body.contains('"price":1.25'));
      expect(sent, contains('"storeId":"shop-2"'));
    });

    /// And the plain "Add Product" button, which is the way most products are added and reaches
    /// the form without going anywhere near a photo.
    testWidgets('Add Product on the catalogue creates in that shop too',
        (WidgetTester tester) async {
      final _Gateway gateway = _Gateway(find: found());
      await pumpList(tester, gateway, storeId: 'shop-2');

      await tester.tap(find.text(en.merchbAddProduct));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextFormField).at(0), 'Pepsi 1L');
      await tester.enterText(find.byType(TextFormField).at(2), '1.25');
      await tester.tap(find.text(en.merchbSaveMenuItem));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final String sent =
          gateway.bodies.firstWhere((String body) => body.contains('"price":1.25'));
      expect(sent, contains('"storeId":"shop-2"'));
    });

    /// A host that is not standing in any shop sends nothing, and the server decides — which is
    /// what the phone's merchant shell does, and what a merchant with one shop always gets.
    testWidgets('a catalogue with no shop in hand names none, and lets the server decide',
        (WidgetTester tester) async {
      final _Gateway gateway = _Gateway(find: found());
      await pumpList(tester, gateway);

      await tester.tap(find.text(en.merchbAddProduct));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextFormField).at(0), 'Pepsi 1L');
      await tester.enterText(find.byType(TextFormField).at(2), '1.25');
      await tester.tap(find.text(en.merchbSaveMenuItem));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final String sent =
          gateway.bodies.firstWhere((String body) => body.contains('"price":1.25'));
      expect(sent, isNot(contains('"storeId"')));
    });

    testWidgets('a sample leads to an empty form, with only the merchant\'s own photo on it',
        (WidgetTester tester) async {
      await pumpList(tester, _Gateway(find: found(sample: true)), photos: _Photos(bytes: jpeg));
      await findWithAPhoto(tester, t: en);

      await tester.tap(find.text(en.pfindAddBlank));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ProductFormScreen), findsOneWidget);
      // Nothing the example said reached a field: no name, and no barcode the till would scan.
      expect(find.widgetWithText(TextFormField, 'Pepsi 1L'), findsNothing);
      expect(find.widgetWithText(TextFormField, '5449000000996'), findsNothing);
      // Their own photo is not an example, so it still comes along.
      expect(find.byType(PendingProductImageTile), findsOneWidget);
    });
  });

  group('the codes an edit used to wipe', () {
    /// An existing product with both codes, as the server sends it.
    const Product saved = Product(
      id: 'p1',
      merchantId: 'm1',
      name: 'Pepsi 1L',
      description: 'Bottle',
      price: 1.25,
      status: ProductStatus.draft,
      sku: 'SKU-1',
      barcode: '5449000000996',
    );

    Future<void> pumpForm(WidgetTester tester, _Gateway gateway, {Product? existing}) async {
      tester.view.physicalSize = const Size(1200, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = gateway;
      await tester.pumpWidget(app(ProductFormScreen(api: CatalogApi(dio), existing: existing)));
      // Fixed frames: the dropzone's dashed border animates for ever, so nothing ever settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('an edit keeps the SKU and the barcode', (WidgetTester tester) async {
      final _Gateway gateway = _Gateway(find: null);
      await pumpForm(tester, gateway, existing: saved);

      expect(find.widgetWithText(TextFormField, 'SKU-1'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '5449000000996'), findsOneWidget);

      // Change the price, as a shopkeeper does twenty times a day, and save.
      await tester.enterText(find.widgetWithText(TextFormField, '1.25'), '1.50');
      await tester.tap(find.text(en.saveChanges));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final String sent = gateway.bodies.last;
      expect(sent, contains('"sku":"SKU-1"'));
      expect(sent, contains('"barcode":"5449000000996"'));
      expect(sent, contains('"price":1.5'));
    });

    testWidgets('a code the merchant clears is really cleared', (WidgetTester tester) async {
      final _Gateway gateway = _Gateway(find: null);
      await pumpForm(tester, gateway, existing: saved);

      await tester.enterText(find.widgetWithText(TextFormField, 'SKU-1'), '');
      await tester.tap(find.text(en.saveChanges));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final String sent = gateway.bodies.last;
      expect(sent, contains('"sku":""'));
      expect(sent, contains('"barcode":"5449000000996"'));
    });
  });
}
