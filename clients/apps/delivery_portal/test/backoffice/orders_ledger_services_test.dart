import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/backoffice/dashboard_screen.dart';
import 'package:delivery_portal/src/backoffice/service_order_detail.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The orders ledger's services half.
///
/// Pinned: the kind and fulfilment filters are the server's (`GET /api/orders?kind=&fulfilment=`),
/// combined with the state pills rather than replacing them; a service order reads as one in the table
/// and opens with its line (packs × unit, options, instructions), fulfilment, estimated ready time and
/// status history; and the customer's files are read through back office's audited read only when the
/// operator asks, under a notice that the read is recorded, with opening a file saying so again.
typedef _Answer = ({int status, Object? body});

class _Routes implements HttpClientAdapter {
  _Routes(this.answer);

  final _Answer Function(RequestOptions options) answer;

  /// When set, the ledger's list waits on it — for the loading state.
  Completer<void>? gate;

  final List<RequestOptions> calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add(options);
    final Completer<void>? wait = gate;
    if (wait != null && options.path == '/api/orders') await wait.future;
    final _Answer a = answer(options);
    return ResponseBody.fromString(
      jsonEncode(a.body),
      a.status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A service order as order-manager answers it: one line of 2 packs of 500 cards, collected at the shop.
Map<String, dynamic> _serviceOrder({
  String status = 'PREPARING',
  String fulfilment = 'PICKUP',
  String attachmentPolicy = 'REQUIRED',
  String? cancelReason,
}) =>
    <String, dynamic>{
      'id': 'svc00001-aaaa',
      'customerId': 'cust-0001-bbbb',
      'merchantId': 'merch-0001-cccc',
      'riderId': null,
      'storeId': 'store-print-1',
      'storeName': 'Print Point',
      'status': status,
      'totalAmount': 30.0,
      'deliveryAddress': '',
      'items': <dynamic>[
        <String, dynamic>{
          'productId': 'offer-1',
          'productName': 'Business cards',
          'unitPrice': 15.0,
          'qty': 2,
          'lineTotal': 30.0,
          'optionsSummary': 'Finish: Matte',
          'service': <String, dynamic>{
            'unitSize': 500,
            'unitLabel': 'cards',
            'pricingType': 'FIXED',
            'turnaroundMinHours': 24,
            'turnaroundMaxHours': 48,
            'attachmentPolicy': attachmentPolicy,
            'instructionsPrompt': 'Which finish would you like?',
            'instructions': 'Name in bold, please.',
          },
        },
      ],
      'availableActions': <String>[],
      'placedAt': DateTime.now().subtract(const Duration(minutes: 30)).toUtc().toIso8601String(),
      'deliveredAt': null,
      'cancelReason': cancelReason,
      'kind': 'SERVICE',
      'fulfilment': fulfilment,
      'serviceCategory': 'PRINTING',
      'estimatedReadyAt': '2026-09-15T15:00:00Z',
    };

Map<String, dynamic> _basketOrder() => <String, dynamic>{
      'id': 'bask0001-dddd',
      'customerId': 'cust-0002-eeee',
      'merchantId': 'merch-0002-ffff',
      'riderId': 'rider-0001-aaaa',
      'storeName': 'Rose & Crust',
      'status': 'DELIVERED',
      'totalAmount': 24.5,
      'deliveryAddress': '12 Example Street',
      'items': <dynamic>[],
      'availableActions': <String>[],
      'placedAt': DateTime.now().subtract(const Duration(minutes: 5)).toUtc().toIso8601String(),
      'deliveredAt': null,
      'cancelReason': null,
    };

Map<String, dynamic> _file({required String url, required Duration validFor}) => <String, dynamic>{
      'fileId': 'file-1',
      'contentType': 'application/pdf',
      'sizeBytes': 2400000,
      'attachedAt': '2026-09-14T08:00:00Z',
      'url': url,
      'urlExpiresAt': DateTime.now().add(validFor).toUtc().toIso8601String(),
    };

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  late _Routes routes;
  late List<Map<String, dynamic>> orders;
  late int listStatus;
  late List<Map<String, dynamic>> history;
  late int filesStatus;
  late List<Map<String, dynamic>> files;
  late List<String> opened;

  setUp(() {
    orders = <Map<String, dynamic>>[_serviceOrder(), _basketOrder()];
    listStatus = 200;
    history = <Map<String, dynamic>>[
      <String, dynamic>{'status': 'PLACED', 'changedAt': '2026-09-14T08:00:00Z'},
      <String, dynamic>{
        'status': 'ACCEPTED',
        'changedAt': '2026-09-14T08:10:00Z',
        'changedBy': 'merch-0001-cccc',
      },
      <String, dynamic>{
        'status': 'PREPARING',
        'changedAt': '2026-09-14T08:10:00Z',
        'changedBy': 'merch-0001-cccc',
      },
    ];
    filesStatus = 200;
    files = <Map<String, dynamic>>[
      _file(url: 'https://files.test/file-1?signature=abc', validFor: const Duration(minutes: 10)),
    ];
    opened = <String>[];
    routes = _Routes((RequestOptions o) {
      if (o.path.endsWith('/history')) return (status: 200, body: history);
      if (o.path.endsWith('/attachments')) {
        return filesStatus == 200
            ? (status: 200, body: files)
            : (status: filesStatus, body: <String, dynamic>{'status': filesStatus});
      }
      return listStatus == 200
          ? (
              status: 200,
              body: <String, dynamic>{
                'content': orders,
                'page': 0,
                'totalElements': orders.length,
                'totalPages': 1,
              },
            )
          : (status: listStatus, body: <String, dynamic>{'status': listStatus});
    });
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    Locale locale = const Locale('en'),
    bool withFiles = true,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = routes;
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      locale: locale,
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: Scaffold(
        body: DashboardScreen(
          api: OrderApi(dio),
          attachmentApi: withFiles ? OrderAttachmentApi(dio) : null,
          openLink: opened.add,
        ),
      ),
    ));
    if (settle) await tester.pumpAndSettle();
  }

  /// The ledger polls; the tree has to go before the test ends or the timer outlives it.
  Future<void> close(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  Iterable<RequestOptions> lists() =>
      routes.calls.where((RequestOptions o) => o.path == '/api/orders');

  Iterable<RequestOptions> fileReads() =>
      routes.calls.where((RequestOptions o) => o.path.endsWith('/attachments'));

  Future<void> openOrder(WidgetTester tester, String shortId) async {
    await tester.tap(find.text('#$shortId'));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('states', () {
    testWidgets('a spinner while the ledger loads', (WidgetTester tester) async {
      routes.gate = Completer<void>();
      await pump(tester, settle: false);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      routes.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('#svc00001'), findsOneWidget);
      await close(tester);
    });

    testWidgets('a filter nothing matches says so', (WidgetTester tester) async {
      orders = <Map<String, dynamic>>[];
      await pump(tester);

      expect(find.text('No orders match this filter.'), findsOneWidget);
      await close(tester);
    });

    testWidgets('a failed read offers a retry', (WidgetTester tester) async {
      listStatus = 500;
      await pump(tester);

      expect(find.textContaining('Could not load orders.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await close(tester);
    });

    testWidgets('a refused read says this account may not read the ledger, and offers no retry',
        (WidgetTester tester) async {
      listStatus = 403;
      await pump(tester);

      expect(find.text(en.svcBoLedgerRefused), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await close(tester);
    });
  });

  testWidgets('the kind and fulfilment filters send exactly the query they show',
      (WidgetTester tester) async {
    await pump(tester);
    expect(lists().last.queryParameters.containsKey('kind'), isFalse);
    expect(lists().last.queryParameters.containsKey('fulfilment'), isFalse);

    await tester.tap(find.text(en.svcBoKindAll));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.svcBoKindService).last);
    await tester.pumpAndSettle();
    expect(lists().last.queryParameters['kind'], 'SERVICE');
    expect(lists().last.queryParameters.containsKey('fulfilment'), isFalse);

    await tester.tap(find.text(en.svcBoFulfilmentAll));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.svcBoFulfilmentPickup).last);
    await tester.pumpAndSettle();
    expect(lists().last.queryParameters['kind'], 'SERVICE');
    expect(lists().last.queryParameters['fulfilment'], 'PICKUP');

    // The state pills narrow the same query rather than replacing it. `.first` is the pill; the
    // basket row below carries a "Delivered" badge of its own.
    await tester.tap(find.text('Delivered').first);
    await tester.pumpAndSettle();
    expect(lists().last.queryParameters['status'], 'DELIVERED');
    expect(lists().last.queryParameters['kind'], 'SERVICE');
    expect(lists().last.queryParameters['fulfilment'], 'PICKUP');

    await tester.tap(find.text(en.svcBoFulfilmentPickup));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.svcBoFulfilmentDelivery).last);
    await tester.pumpAndSettle();
    expect(lists().last.queryParameters['fulfilment'], 'DELIVERY');

    await tester.tap(find.text(en.svcBoKindService));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.svcBoKindAll).last);
    await tester.pumpAndSettle();
    expect(lists().last.queryParameters.containsKey('kind'), isFalse);
    expect(lists().last.queryParameters['fulfilment'], 'DELIVERY');
    expect(lists().last.queryParameters['status'], 'DELIVERED');
    await close(tester);
  });

  for (final Size size in const <Size>[Size(1440, 900), Size(1280, 800), Size(1024, 720)]) {
    testWidgets('a service order reads as one in the table at ${size.width.toInt()}px',
        (WidgetTester tester) async {
      await pump(tester, size: size);

      expect(find.text(en.svcBoServiceTag), findsOneWidget);
      expect(find.text(en.svcBoStatusInProduction), findsOneWidget);
      // A pickup never gets a rider: the column says where it goes rather than "Unassigned".
      expect(find.text(en.svcBoFulfilPickup), findsOneWidget);
      expect(find.text('Unassigned'), findsNothing);
      await close(tester);
    });
  }

  testWidgets('a service order opens with its line, fulfilment, ready time and history',
      (WidgetTester tester) async {
    await pump(tester);
    await openOrder(tester, 'svc00001');

    expect(find.text(en.svcBoKindServiceIn(en.svcCategoryPrinting)), findsOneWidget);
    expect(find.text('Business cards — ${en.svcBoPacksOfUnits(2, 500, 'cards')}'), findsOneWidget);
    expect(find.text('Finish: Matte'), findsOneWidget);
    expect(find.text('Which finish would you like?'), findsOneWidget);
    expect(find.text('Name in bold, please.'), findsOneWidget);
    expect(find.text(en.svcBoDetailReadyBy), findsOneWidget);
    // The timeline's steps, looked for inside the service part only: the ledger's state pills and the
    // dialog's own "Placed" row use the same words.
    Finder step(String label) =>
        find.descendant(of: find.byType(ServiceOrderDetail), matching: find.text(label));
    expect(step(en.svcBoStatusPlaced), findsOneWidget);
    expect(step(en.svcBoStatusAccepted), findsOneWidget);
    expect(step(en.svcBoStatusInProduction), findsOneWidget);
    expect(routes.calls.where((RequestOptions o) => o.path == '/api/orders/svc00001-aaaa/history'),
        hasLength(1));
    await close(tester);
  });

  testWidgets('no file is read until the operator asks, under the audit notice',
      (WidgetTester tester) async {
    await pump(tester);
    await openOrder(tester, 'svc00001');

    expect(find.text(en.svcBoFilesAuditNotice), findsOneWidget);
    expect(fileReads(), isEmpty);

    await tapVisible(tester, find.text(en.svcBoFilesShow));

    expect(fileReads().single.path, '/api/orders/svc00001-aaaa/attachments');
    expect(find.text('${en.svcBoFilePdf} · ${en.svcBoSizeMb('2.3')}'), findsOneWidget);
    // The notice stays: a link asked for again is another recorded read.
    expect(find.text(en.svcBoFilesAuditNotice), findsOneWidget);
    expect(find.text(en.svcBoFileOpened), findsNothing);

    await tapVisible(tester, find.text(en.svcBoFileOpen));

    expect(opened, <String>['https://files.test/file-1?signature=abc']);
    expect(find.text(en.svcBoFileOpened), findsOneWidget);
    // A link still good is opened as it is, without reading the list again.
    expect(fileReads(), hasLength(1));
    await close(tester);
  });

  testWidgets('a link that has run out is asked for again before it is opened',
      (WidgetTester tester) async {
    files = <Map<String, dynamic>>[
      _file(url: 'https://files.test/file-1?signature=old', validFor: const Duration(minutes: -1)),
    ];
    await pump(tester);
    await openOrder(tester, 'svc00001');
    await tapVisible(tester, find.text(en.svcBoFilesShow));

    files = <Map<String, dynamic>>[
      _file(url: 'https://files.test/file-1?signature=fresh', validFor: const Duration(minutes: 10)),
    ];
    await tapVisible(tester, find.text(en.svcBoFileOpen));

    expect(fileReads(), hasLength(2));
    expect(opened, <String>['https://files.test/file-1?signature=fresh']);
    await close(tester);
  });

  testWidgets('a refused file read says so and offers nothing that would be refused again',
      (WidgetTester tester) async {
    filesStatus = 404;
    await pump(tester);
    await openOrder(tester, 'svc00001');
    await tapVisible(tester, find.text(en.svcBoFilesShow));

    expect(find.text(en.svcBoFilesRefused), findsOneWidget);
    expect(find.text(en.svcBoFilesShow), findsNothing);
    expect(opened, isEmpty);
    await close(tester);
  });

  testWidgets('files that cannot be reached right now can be asked for again',
      (WidgetTester tester) async {
    filesStatus = 503;
    await pump(tester);
    await openOrder(tester, 'svc00001');
    await tapVisible(tester, find.text(en.svcBoFilesShow));

    expect(find.text(en.svcBoFilesUnavailable), findsOneWidget);

    filesStatus = 200;
    await tapVisible(tester, find.text(en.svcBoFilesShow));
    expect(find.text(en.svcBoFileOpen), findsOneWidget);
    await close(tester);
  });

  testWidgets('an offer that takes no files says so, with no read to start',
      (WidgetTester tester) async {
    orders = <Map<String, dynamic>>[_serviceOrder(attachmentPolicy: 'NONE')];
    await pump(tester);
    await openOrder(tester, 'svc00001');

    expect(find.text(en.svcBoFilesNotTaken), findsOneWidget);
    expect(find.text(en.svcBoFilesShow), findsNothing);
    expect(find.text(en.svcBoFilesAuditNotice), findsNothing);
    await close(tester);
  });

  testWidgets('without the attachment client the detail draws no files block',
      (WidgetTester tester) async {
    await pump(tester, withFiles: false);
    await openOrder(tester, 'svc00001');

    expect(find.text(en.svcBoFilesTitle), findsNothing);
    expect(find.text(en.svcBoFilesShow), findsNothing);
    await close(tester);
  });

  testWidgets('a basket order opens as it always did, with no service part',
      (WidgetTester tester) async {
    await pump(tester);
    await openOrder(tester, 'bask0001');

    expect(find.text('Order #bask0001'), findsOneWidget);
    expect(find.text(en.svcBoHistoryTitle), findsNothing);
    expect(routes.calls.where((RequestOptions o) => o.path.endsWith('/history')), isEmpty);
    await close(tester);
  });

  testWidgets('a declined service order is named as declined, with the reason in words',
      (WidgetTester tester) async {
    orders = <Map<String, dynamic>>[
      _serviceOrder(status: 'CANCELLED', cancelReason: 'PROVIDER_DECLINED: TOO_BUSY'),
    ];
    history = <Map<String, dynamic>>[
      <String, dynamic>{'status': 'PLACED', 'changedAt': '2026-09-14T08:00:00Z'},
      <String, dynamic>{
        'status': 'CANCELLED',
        'changedAt': '2026-09-14T08:05:00Z',
        'note': 'PROVIDER_DECLINED: TOO_BUSY',
      },
    ];
    await pump(tester);
    expect(find.text(en.svcBoStatusDeclined), findsOneWidget);

    await openOrder(tester, 'svc00001');
    // The table's badge, the dialog's, and the step on the timeline.
    expect(find.text(en.svcBoStatusDeclined), findsNWidgets(3));
    expect(find.text(en.svcDeclineTooBusy), findsWidgets);
    expect(find.text('PROVIDER_DECLINED: TOO_BUSY'), findsNothing);
    await close(tester);
  });

  testWidgets('reads right to left in Arabic, the service detail and the audited read included',
      (WidgetTester tester) async {
    await pump(tester, locale: const Locale('ar'), size: const Size(1024, 720));

    expect(Directionality.of(tester.element(find.byType(ConsoleTable))), TextDirection.rtl);
    expect(find.text(ar.svcBoKindAll), findsOneWidget);
    expect(find.text(ar.svcBoStatusInProduction), findsOneWidget);

    await openOrder(tester, 'svc00001');
    expect(find.text(ar.svcBoFilesAuditNotice), findsOneWidget);
    await tapVisible(tester, find.text(ar.svcBoFilesShow));
    await tapVisible(tester, find.text(ar.svcBoFileOpen));
    expect(find.text(ar.svcBoFileOpened), findsOneWidget);
    await close(tester);
  });
}
