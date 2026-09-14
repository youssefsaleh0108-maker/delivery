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
import 'package:mobile_app/src/service_order_files.dart';
import 'package:mobile_app/src/service_order_screen.dart';
import 'package:mobile_app/src/service_order_tracking_screen.dart';
import 'package:mobile_app/src/services_kit.dart';

import 'service_fixtures.dart';

/// Configuring and placing a service order (Figma 126:437).
///
/// The rules that matter here are invisible in a screenshot and decisive at the counter: the packs
/// the stepper sends against the units it shows, a price that is always the server's and never there
/// before it answered, a required file that really blocks placement, a refusal in words, exactly one
/// placement per tap carrying everything the provider needs — and no placement at all offline, since a
/// service order is never queued.
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

  const Map<String, dynamic> paperType = <String, dynamic>{
    'id': 'g1',
    'name': 'Paper type',
    'minSelect': 1,
    'maxSelect': 1,
    'required': true,
    'singleChoice': true,
    'options': <Map<String, dynamic>>[
      <String, dynamic>{'id': 'o1', 'name': 'Matte', 'priceDelta': 0},
      <String, dynamic>{'id': 'o2', 'name': 'Gloss', 'priceDelta': 1.5},
    ],
  };

  /// A server for one offer: its options, a quote that prices whatever it is asked (a pack at $15, a
  /// delivery at $2.50), a placement, and the placed order for the tracking screen that follows.
  FakeServer serve({
    List<Map<String, dynamic>> options = const <Map<String, dynamic>>[],
    FakeAnswer? quote,
    FakeAnswer? place,
  }) {
    return FakeServer()
      ..on('GET', '/api/products/p1/options', (_) => options)
      ..on('POST', '/api/orders/quote', quote ??
          (RequestOptions r) {
            final Map<dynamic, dynamic> body = r.data as Map<dynamic, dynamic>;
            final int packs = ((body['items'] as List<dynamic>).first as Map<dynamic, dynamic>)['qty'] as int;
            return quoteJson(subtotal: 15.0 * packs, fee: body['fulfilment'] == 'DELIVERY' ? 2.5 : 0);
          })
      ..on('POST', '/api/orders', place ?? (_) => FakeReply(201, serviceOrderJson(status: 'PLACED')))
      ..on('GET', '/api/orders/$svcOrderId', (_) => serviceOrderJson(status: 'PLACED'))
      ..on('GET', '/api/orders/$svcOrderId/history', (_) => historyJson(<String>['PLACED']));
  }

  ServicesKit kit(
    FakeServer server, {
    DeliveryAddressStore? addresses,
    ValueListenable<bool>? online,
    ServiceOrderFiles? files,
    ServiceFilePicker? pick,
  }) =>
      ServicesKit(
        storeApi: StoreApi(server.dio),
        orderApi: OrderApi(server.dio),
        zoneApi: DeliveryZoneApi(server.dio),
        addresses: addresses ?? DeliveryAddressStore(ownerId: 'test-user'),
        connectivity: online ?? ValueNotifier<bool>(true),
        files: files,
        pickFile: pick ?? () async => null,
      );

  Future<void> pump(
    WidgetTester tester,
    FakeServer server, {
    ServicesKit? with_,
    Map<String, dynamic>? offer,
    Map<String, dynamic>? store,
    Locale locale = const Locale('en'),
    Size size = const Size(390, 2400),
    bool settle = true,
  }) async {
    phone(tester, size: size);
    await tester.pumpWidget(svcApp(
      ServiceOrderScreen(
        kit: with_ ?? kit(server),
        store: Store.fromJson(store ?? storeJson()),
        offer: Product.fromJson(offer ?? offerJson()),
      ),
      locale: locale,
    ));
    if (settle) await tester.pumpAndSettle();
  }

  YdPillButton placeButton(WidgetTester tester) => tester.widget<YdPillButton>(find.byWidgetPredicate(
      (Widget w) => w is YdPillButton && w.label.startsWith(en.svcPlaceOrderTotal('').trim())));

  Map<dynamic, dynamic> lastQuote(FakeServer server) =>
      server.sent('POST', '/api/orders/quote').last.data as Map<dynamic, dynamic>;

  group('before there is anything to order', () {
    testWidgets('waits on the offer\'s options, and offers to try again when they cannot be read',
        (WidgetTester tester) async {
      final Completer<Object?> first = Completer<Object?>();
      int reads = 0;
      final FakeServer server = serve()
        ..on('GET', '/api/products/p1/options', (_) => ++reads == 1 ? first.future : <dynamic>[]);
      await pump(tester, server, settle: false);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      first.complete(const FakeReply(500));
      await tester.pumpAndSettle();
      expect(find.text(en.svcCouldNotLoadOffer), findsOneWidget);
      expect(server.sent('POST', '/api/orders/quote'), isEmpty);

      await tester.tap(find.text(en.tryAgain));
      await tester.pumpAndSettle();
      expect(find.text('Business Card Printing'), findsOneWidget);
      expect(find.text(en.svcProviderLine('Al Fakhry Press')), findsOneWidget);
    });

    testWidgets('an offer with a term this build does not know is not offered for ordering',
        (WidgetTester tester) async {
      final FakeServer server = serve();
      await pump(tester, server, offer: offerJson(fulfilment: 'DRONE'));

      expect(find.text(en.svcRefusedOfferNotOrderable), findsOneWidget);
      expect(find.byType(YdPillButton), findsNothing);
      expect(server.sent('GET', '/api/products/p1/options'), isEmpty);
    });
  });

  group('the order as configured', () {
    testWidgets('the stepper shows units and sends packs, and stops at 99 packs',
        (WidgetTester tester) async {
      final FakeServer server = serve();
      await pump(tester, server);

      expect(find.text('500'), findsOneWidget);
      expect(find.text('${en.svcUnitsLine('500', 'cards')} · ${en.svcPacksCount(1)}'), findsOneWidget);
      expect((lastQuote(server)['items'] as List<dynamic>).first['qty'], 1);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(find.text('1,000'), findsOneWidget);
      expect((lastQuote(server)['items'] as List<dynamic>).first['qty'], 2);
      expect(find.text(en.svcPlaceOrderTotal('\$30.00')), findsOneWidget);

      for (int i = 0; i < 110; i++) {
        await tester.tap(find.byIcon(Icons.add_rounded), warnIfMissed: false);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('49,500'), findsOneWidget);
      expect((lastQuote(server)['items'] as List<dynamic>).first['qty'], 99);
    });

    testWidgets('a required option is chosen before there is a price to place at',
        (WidgetTester tester) async {
      final FakeServer server = serve(options: <Map<String, dynamic>>[paperType]);
      await pump(tester, server);

      expect(server.sent('POST', '/api/orders/quote'), isEmpty);
      expect(find.text('Paper type: ${en.svcChooseOption}'), findsOneWidget);
      expect(placeButton(tester).onPressed, isNull);

      await tester.tap(find.text(en.svcChooseOption).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gloss (+\$1.50)').last);
      await tester.pumpAndSettle();

      expect(lastQuote(server)['items'].first['optionIds'], <String>['o2']);
      expect(placeButton(tester).onPressed, isNotNull);
    });

    testWidgets('the total is a dash while the server is asked, and while it could not answer',
        (WidgetTester tester) async {
      Completer<Object?> answer = Completer<Object?>();
      final FakeServer server = serve(quote: (_) => answer.future);
      // Settles with the quote still unanswered: nothing on screen animates while a price is asked.
      await pump(tester, server);

      expect(server.sent('POST', '/api/orders/quote'), hasLength(1));
      expect(find.text(en.svcPlaceOrderTotal('—')), findsOneWidget);
      expect(placeButton(tester).onPressed, isNull);

      answer.complete(quoteJson(subtotal: 15));
      await tester.pumpAndSettle();
      expect(find.text(en.svcPlaceOrderTotal('\$15.00')), findsOneWidget);
      expect(placeButton(tester).onPressed, isNotNull);

      answer = Completer<Object?>()..complete(const FakeReply(500));
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(find.text(en.svcPlaceOrderTotal('—')), findsOneWidget);
      expect(find.text(en.svcQuoteFailed), findsOneWidget);
      expect(placeButton(tester).onPressed, isNull);

      answer = Completer<Object?>()..complete(quoteJson(subtotal: 30));
      await tester.tap(find.text(en.tryAgain));
      await tester.pumpAndSettle();
      expect(find.text(en.svcPlaceOrderTotal('\$30.00')), findsOneWidget);
    });

    testWidgets('a quote the server refuses says why, and leaves nothing to place',
        (WidgetTester tester) async {
      await pump(
          tester,
          serve(
              quote: (_) => const FakeReply(
                  422, <String, dynamic>{'code': 'FULFILMENT_NOT_OFFERED', 'detail': 'no'})));

      expect(find.text(en.svcRefusedFulfilment), findsOneWidget);
      expect(find.text(en.svcPlaceOrderTotal('—')), findsOneWidget);
      expect(placeButton(tester).onPressed, isNull);
    });

    testWidgets('pickup shows FREE and no address; delivery asks for one and shows the quoted fee',
        (WidgetTester tester) async {
      final DeliveryAddressStore addresses = DeliveryAddressStore(ownerId: 'test-user');
      final FakeServer server = serve();
      await pump(tester, server, with_: kit(server, addresses: addresses));

      expect(find.text(en.free.toUpperCase()), findsOneWidget);
      expect(find.text(en.deliveryAddress), findsNothing);
      expect(lastQuote(server)['fulfilment'], 'PICKUP');
      expect(find.text(en.svcPayCashPickup), findsOneWidget);

      await tester.tap(find.text(en.svcYouDropDelivery));
      await tester.pumpAndSettle();
      expect(find.text(en.chooseAnAddress), findsOneWidget);
      expect(find.text(en.svcChooseDeliveryAddress), findsOneWidget);
      expect(placeButton(tester).onPressed, isNull);

      await addresses.select(const DeliveryAddress(
          line: '12 Rose Street', label: 'Home', zoneId: 'zone-home', zoneName: 'Riverside'));
      await tester.pumpAndSettle();

      expect(lastQuote(server)['fulfilment'], 'DELIVERY');
      expect(lastQuote(server)['deliveryZoneId'], 'zone-home');
      expect(find.text(en.svcDeliveryFeePlus('\$2.50')), findsOneWidget);
      expect(find.text('\$2.50'), findsOneWidget);
      expect(find.text(en.svcPlaceOrderTotal('\$17.50')), findsOneWidget);
      expect(find.text(en.svcPayCashDelivery), findsOneWidget);
    });

    testWidgets('a delivery to an area the shop does not serve is said, and cannot be placed',
        (WidgetTester tester) async {
      final DeliveryAddressStore addresses = DeliveryAddressStore(ownerId: 'test-user');
      await addresses.select(const DeliveryAddress(line: '1 Far Road', zoneId: 'zone-far'));
      final FakeServer server = serve(quote: (_) => quoteJson(refusal: 'NOT_SERVED'));
      await pump(tester, server,
          with_: kit(server, addresses: addresses), offer: offerJson(fulfilment: 'DELIVERY'));

      expect(find.text(en.svcNotServed('Al Fakhry Press')), findsOneWidget);
      expect(placeButton(tester).onPressed, isNull);
    });
  });

  group('files', () {
    testWidgets('a REQUIRED file keeps Place disabled until its upload confirms',
        (WidgetTester tester) async {
      final _FakeFiles files = _FakeFiles()..pending = Completer<String>();
      final FakeServer server = serve();
      await pump(tester, server,
          with_: kit(server, files: files, pick: () async => _picked('design.pdf')),
          offer: offerJson(attachmentPolicy: 'REQUIRED'));

      expect(find.text(en.svcFileRequired), findsOneWidget);
      expect(find.text(en.svcPlaceOrderTotal('\$15.00')), findsOneWidget);
      expect(placeButton(tester).onPressed, isNull);

      await tester.tap(find.text(en.svcUploadHint));
      await tester.pumpAndSettle();
      expect(find.text('design.pdf'), findsOneWidget);
      expect(find.text(en.svcUploading), findsNWidgets(2), reason: 'the row, and why Place waits');
      expect(placeButton(tester).onPressed, isNull);

      files.pending!.complete('file-7');
      await tester.pumpAndSettle();
      expect(find.text(en.svcUploaded), findsOneWidget);
      expect(placeButton(tester).onPressed, isNotNull);

      await tester.tap(find.text(en.svcPlaceOrderTotal('\$15.00')));
      await tester.pumpAndSettle();
      expect((server.sent('POST', '/api/orders').single.data as Map<dynamic, dynamic>)['attachmentFileIds'],
          <String>['file-7']);
    });

    testWidgets('an .ai file, or one over 10 MB, is refused before any upload',
        (WidgetTester tester) async {
      final _FakeFiles files = _FakeFiles();
      PickedServiceFile next = _picked('artwork.ai');
      final FakeServer server = serve();
      await pump(tester, server,
          with_: kit(server, files: files, pick: () async => next),
          offer: offerJson(attachmentPolicy: 'OPTIONAL'));

      await tester.tap(find.text(en.svcUploadHint));
      await tester.pumpAndSettle();
      expect(find.text(en.svcRefusedWrongType), findsOneWidget);

      next = _picked('scan.pdf', size: 11 * 1024 * 1024);
      await tester.tap(find.text(en.svcUploadHint));
      await tester.pumpAndSettle();
      expect(find.text(en.svcRefusedTooLarge), findsOneWidget);

      expect(files.uploads, isEmpty);
      expect(find.text('scan.pdf'), findsNothing);
    });

    testWidgets('an upload the server refuses says why, and a removed file is taken back',
        (WidgetTester tester) async {
      final _FakeFiles files = _FakeFiles()
        ..failWith = const ServiceFileRefused(ServiceOrderRefusal.tooManyFilesWaiting);
      final FakeServer server = serve();
      await pump(tester, server,
          with_: kit(server, files: files, pick: () async => _picked('design.png')),
          offer: offerJson(attachmentPolicy: 'REQUIRED'));

      await tester.tap(find.text(en.svcUploadHint));
      await tester.pumpAndSettle();
      expect(find.text(en.svcRefusedTooManyWaiting), findsOneWidget);
      expect(placeButton(tester).onPressed, isNull);

      files.failWith = null;
      await tester.tap(find.text(en.svcRemoveFile));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.svcUploadHint));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.svcRemoveFile));
      await tester.pumpAndSettle();
      expect(files.removed, <String>['file-1']);
      expect(find.text(en.svcFileRequired), findsOneWidget);
    });

    testWidgets('without the attachment client, an offer that needs a file cannot be placed',
        (WidgetTester tester) async {
      await pump(tester, serve(), offer: offerJson(attachmentPolicy: 'REQUIRED'));

      expect(find.text(en.svcUploadHint), findsNothing);
      expect(find.text(en.svcRefusedAttachmentsUnavailable), findsOneWidget);
      expect(placeButton(tester).onPressed, isNull);
    });
  });

  group('placing', () {
    testWidgets('one placement per tap, with fulfilment, files, instructions, the key and the total',
        (WidgetTester tester) async {
      final Completer<Object?> placed = Completer<Object?>();
      final _FakeFiles files = _FakeFiles();
      final FakeServer server = serve(place: (_) => placed.future);
      await pump(tester, server,
          with_: kit(server, files: files, pick: () async => _picked('design.pdf')),
          offer: offerJson(attachmentPolicy: 'OPTIONAL'));

      await tester.tap(find.text(en.svcUploadHint));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  Leave a white border  ');
      await tester.pumpAndSettle();

      // Dio sends on the next turn of the clock, so each tap is given one.
      await tester.tap(find.text(en.svcPlaceOrderTotal('\$15.00')));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.tap(find.byType(YdPillButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 1));

      final List<RequestOptions> sends = server.sent('POST', '/api/orders');
      expect(sends, hasLength(1));
      final Map<dynamic, dynamic> body = sends.single.data as Map<dynamic, dynamic>;
      expect(body['fulfilment'], 'PICKUP');
      expect(body.containsKey('deliveryAddress'), isFalse);
      expect(body['attachmentFileIds'], <String>['file-1']);
      expect(body['serviceInstructions'], 'Leave a white border');
      expect(body['paymentMethod'], 'CASH');
      expect(body['expectedTotal'], 15);
      expect(body['items'], <Map<String, dynamic>>[
        <String, dynamic>{'productId': 'p1', 'qty': 1},
      ]);
      expect(sends.single.headers[OrderApi.idempotencyKeyHeader], isNotEmpty);

      placed.complete(FakeReply(201, serviceOrderJson(status: 'PLACED')));
      await tester.pumpAndSettle();
      expect(find.byType(ServiceOrderTrackingScreen), findsOneWidget);
      expect(find.byType(ServiceOrderScreen), findsNothing);
    });

    testWidgets('a total that moved is shown and asked again, and placed at it with the same key',
        (WidgetTester tester) async {
      int sends = 0;
      final FakeServer server = serve(
        place: (_) => ++sends == 1
            ? const FakeReply(409,
                <String, dynamic>{'code': 'PRICE_CHANGED', 'total': 16.5, 'expectedTotal': 15})
            : FakeReply(201, serviceOrderJson(status: 'PLACED')),
      );
      await pump(tester, server);

      await tester.tap(find.text(en.svcPlaceOrderTotal('\$15.00')));
      await tester.pumpAndSettle();
      expect(find.text(en.svcPriceChangedBody('\$16.50', '\$15.00')), findsOneWidget);

      await tester.tap(find.text(en.svcPlaceOrderTotal('\$16.50')).last);
      await tester.pumpAndSettle();

      final List<RequestOptions> placements = server.sent('POST', '/api/orders');
      expect(placements, hasLength(2));
      expect((placements.last.data as Map<dynamic, dynamic>)['expectedTotal'], 16.5);
      expect(placements.last.headers[OrderApi.idempotencyKeyHeader],
          placements.first.headers[OrderApi.idempotencyKeyHeader]);
      expect(find.byType(ServiceOrderTrackingScreen), findsOneWidget);
    });

    testWidgets('refusals are said in words and place nothing', (WidgetTester tester) async {
      FakeReply reply = const FakeReply(422, <String, dynamic>{'code': 'CATEGORY_CLOSED'});
      final FakeServer server = serve(place: (_) => reply);
      await pump(tester, server);

      await tester.tap(find.text(en.svcPlaceOrderTotal('\$15.00')));
      await tester.pumpAndSettle();
      expect(find.text(en.svcRefusedCategoryClosed), findsOneWidget);
      expect(find.byType(ServiceOrderTrackingScreen), findsNothing);

      reply = const FakeReply(503, <String, dynamic>{'code': 'SERVICES_DIRECTORY_UNAVAILABLE'});
      await tester.tap(find.text(en.svcPlaceOrderTotal('\$15.00')));
      await tester.pumpAndSettle();
      expect(find.text(en.svcDirectoryUnavailable), findsOneWidget);

      reply = const FakeReply(
          422, <String, dynamic>{'detail': 'Al Fakhry Press is closed and is not taking orders right now'});
      await tester.tap(find.text(en.svcPlaceOrderTotal('\$15.00')));
      await tester.pumpAndSettle();
      expect(find.text('Al Fakhry Press is closed and is not taking orders right now'), findsOneWidget);
      expect(find.byType(ServiceOrderTrackingScreen), findsNothing);
    });

    testWidgets('a send whose answer never came is never called a failure, and is retried as itself',
        (WidgetTester tester) async {
      bool answered = false;
      final FakeServer server = serve(place: (RequestOptions r) {
        if (!answered) {
          answered = true;
          throw noAnswer(r);
        }
        return FakeReply(201, serviceOrderJson(status: 'PLACED'));
      });
      await pump(tester, server);

      await tester.tap(find.text(en.svcPlaceOrderTotal('\$15.00')));
      await tester.pumpAndSettle();
      expect(find.text(en.offlineUnconfirmedRetry), findsOneWidget);
      expect(find.text(en.couldNotPlaceOrder), findsNothing);

      await tester.tap(find.text(en.svcPlaceOrderTotal('\$15.00')));
      await tester.pumpAndSettle();
      final List<RequestOptions> placements = server.sent('POST', '/api/orders');
      expect(placements, hasLength(2));
      expect(placements.last.headers[OrderApi.idempotencyKeyHeader],
          placements.first.headers[OrderApi.idempotencyKeyHeader]);
    });

    testWidgets('never offered offline: no placement until the platform answers again',
        (WidgetTester tester) async {
      final ValueNotifier<bool> online = ValueNotifier<bool>(false);
      final FakeServer server = serve();
      await pump(tester, server, with_: kit(server, online: online));

      expect(find.text(en.svcOfflineNoQueue), findsOneWidget);
      expect(placeButton(tester).onPressed, isNull);
      await tester.tap(find.byType(YdPillButton), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(server.sent('POST', '/api/orders'), isEmpty);
      expect(find.text(en.offlineQueueAction), findsNothing, reason: 'nothing offers to queue it');

      online.value = true;
      await tester.pumpAndSettle();
      expect(find.text(en.svcOfflineNoQueue), findsNothing);
      expect(placeButton(tester).onPressed, isNotNull);
    });
  });

  testWidgets('reads right to left in Arabic', (WidgetTester tester) async {
    final FakeServer server = serve(options: <Map<String, dynamic>>[paperType]);
    await pump(tester, server, locale: const Locale('ar'), offer: offerJson(attachmentPolicy: 'REQUIRED'));

    expect(find.text(ar.svcOrderServiceTitle), findsOneWidget);
    expect(find.text(ar.svcPickupAtShop), findsOneWidget);
    expect(Directionality.of(tester.element(find.text(ar.svcQuantity))), TextDirection.rtl);
    // The quantity label leads the row, which in Arabic puts it right of the stepper.
    expect(tester.getCenter(find.text(ar.svcQuantity)).dx,
        greaterThan(tester.getCenter(find.byIcon(Icons.add_rounded)).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a 320dp phone with options, a required file and a delivery',
      (WidgetTester tester) async {
    final DeliveryAddressStore addresses = DeliveryAddressStore(ownerId: 'test-user');
    await addresses.select(const DeliveryAddress(
        line: '12 Rose Street, third floor, the building behind the pharmacy', zoneId: 'zone-home'));
    final FakeServer server = serve(options: <Map<String, dynamic>>[paperType]);
    await pump(
      tester,
      server,
      with_: kit(server, addresses: addresses, files: _FakeFiles()),
      offer: offerJson(
          name: 'Business Card Printing — Premium Heavyweight Stock, Double Sided',
          attachmentPolicy: 'REQUIRED',
          fulfilment: 'DELIVERY'),
      size: const Size(320, 2000),
    );

    expect(find.text(en.svcUploadHint), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

PickedServiceFile _picked(String name, {int size = 2048}) => PickedServiceFile(
      name: name,
      sizeBytes: size,
      readBytes: () async => Uint8List(size > 4096 ? 4096 : size),
    );

/// The attachment client, answered in-process: confirmed ids in order, a refusal when told to, or an
/// upload held open until [pending] completes.
class _FakeFiles implements ServiceOrderFiles {
  final List<String> uploads = <String>[];
  final List<String> removed = <String>[];
  Completer<String>? pending;
  ServiceFileRefused? failWith;
  int _next = 0;

  @override
  Future<String> upload({
    required Uint8List bytes,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    uploads.add(contentType);
    onProgress?.call(bytes.length ~/ 2, bytes.length);
    final ServiceFileRefused? refusal = failWith;
    if (refusal != null) throw refusal;
    final Completer<String>? hold = pending;
    if (hold != null) return hold.future;
    return 'file-${++_next}';
  }

  @override
  Future<void> remove(String fileId) async => removed.add(fileId);
}
