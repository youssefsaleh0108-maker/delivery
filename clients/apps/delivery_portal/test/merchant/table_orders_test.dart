import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a restaurant actually sees when a diner sends from a table.
///
/// This file exists because its absence is why dine-in shipped half-built. The endpoint was covered,
/// the ledger was covered, the smoke script called the server with curl — and not one test opened the
/// shop's own screen and looked, so nothing contradicted a report that was true about the server and
/// silent about the app. Every assertion here is phrased as something a member of staff can read off a
/// screen, at 320dp and in Arabic, because that is the claim that was missing.
///
/// The four rules it pins: a table order reaches the queue marked with its table; a delivery order in
/// the same queue is untouched; two sends from one table read as round one and round two while a fresh
/// table starts again at one; and no figure about money moves because a ticket the platform is not a
/// party to arrived.

/// Answers the endpoints these screens call, per `kind`, and keeps every request.
///
/// Per kind because that is how the endpoint behaves: `kind` takes a single value, so the queue asks
/// twice. A stub answering both with the same page would put every order in the queue twice — which is
/// a bug in the stub that reads exactly like a passing test.
class _Script implements HttpClientAdapter {
  _Script({List<Map<String, dynamic>>? catalog, List<Map<String, dynamic>>? table})
      : catalog = catalog ?? <Map<String, dynamic>>[],
        table = table ?? <Map<String, dynamic>>[];

  final List<Map<String, dynamic>> catalog;
  final List<Map<String, dynamic>> table;
  final List<RequestOptions> requests = <RequestOptions>[];

  List<RequestOptions> get posts =>
      requests.where((RequestOptions r) => r.method == 'POST').toList();

  /// The `kind` of every merchant-queue read, in the order they were made.
  List<String> get kindsAsked => requests
      .where((RequestOptions r) => r.path == '/api/orders/merchant')
      .map((RequestOptions r) => '${r.queryParameters['kind']}')
      .toList();

  Map<String, dynamic>? _byId(String id) {
    for (final Map<String, dynamic> order in <Map<String, dynamic>>[...catalog, ...table]) {
      if (order['id'] == id) return order;
    }
    return null;
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    final (int status, Object? body) = _answer(options);
    return ResponseBody.fromString(body == null ? '{}' : jsonEncode(body), status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        });
  }

  (int, Object?) _answer(RequestOptions options) {
    if (options.path == '/api/orders/merchant') {
      final String kind = '${options.queryParameters['kind']}';
      return (
        200,
        _page(kind == OrderKind.table.wire
            ? table
            : kind == OrderKind.catalog.wire
                ? catalog
                : <Map<String, dynamic>>[])
      );
    }
    if (options.path == '/api/orders/merchant/summary') {
      return (200, _summary());
    }
    if (options.method == 'POST') {
      // A transition is answered with the order as it now stands. Which status that is does not
      // matter to these tests; that the call was made, and to which path, does.
      final String id = options.path.split('/')[3];
      return (200, _byId(id) ?? <String, dynamic>{});
    }
    if (options.method == 'GET' && options.path.startsWith('/api/orders/')) {
      final Map<String, dynamic>? order = _byId(options.path.split('/').last);
      return order == null ? (404, null) : (200, order);
    }
    return (404, null);
  }

  @override
  void close({bool force = false}) {}
}

Object _page(List<Map<String, dynamic>> orders) => <String, dynamic>{
      'content': orders,
      'page': 0,
      'size': 50,
      'totalElements': orders.length,
      'totalPages': 1,
    };

/// A table order exactly as order-manager serialises one: no address, no rider, no fee, no phone.
Map<String, dynamic> _tableOrder({
  required String id,
  int table = 7,
  String status = 'PLACED',
  List<String>? actions,
  String placedAt = '2026-09-23T18:00:00Z',
  double total = 20.0,
}) =>
    <String, dynamic>{
      'id': id,
      'kind': 'TABLE',
      'customerId': 'table:5e00abcd-$table:9f3a1b2c',
      'merchantId': 'merchant-1',
      'riderId': null,
      'status': status,
      'totalAmount': total,
      'subtotal': total,
      'deliveryFee': 0,
      'deliveryFeeCharged': 0,
      'deliveryTier': 'STANDARD',
      'expressSurcharge': 0,
      'deliveryFeeWaived': false,
      'merchantFeeWaived': false,
      'carrierFeeWaived': false,
      'storeId': 'ffffffff-0000-4000-8000-00000000000f',
      'storeName': 'Dekkanet Al Rawche',
      'deliveryAddress': null,
      'paymentMethod': 'CASH',
      'paymentStatus': 'DUE',
      'contactPhone': null,
      'notes': 'No onions, and one plate without garlic please.',
      'gift': null,
      'checkoutId': null,
      'items': <dynamic>[
        <String, dynamic>{
          'productId': 'p1',
          'productName': 'Hummus Beiruti with warm bread',
          'unitPrice': 10.0,
          'qty': 2,
          'lineTotal': total,
        },
      ],
      'availableActions': actions ?? _actionsAt(status),
      'placedAt': placedAt,
      'deliveredAt': status == 'DELIVERED' ? '2026-09-23T19:00:00Z' : null,
      'cancelReason': null,
      'fulfilment': 'DINE_IN',
      'tableLabel': table,
    };

/// What the server offers a merchant on a table order in each state — `OrderService.actionsFor`.
List<String> _actionsAt(String status) => switch (status) {
      'PLACED' => const <String>['ACCEPT', 'CANCEL'],
      'ACCEPTED' => const <String>['PREPARE', 'CANCEL'],
      'PREPARING' => const <String>['READY', 'CANCEL'],
      'READY' => const <String>['COLLECTED', 'CANCEL'],
      _ => const <String>[],
    };

/// A delivery order, so every assertion about a table order can be shown not to have changed one.
Map<String, dynamic> _deliveryOrder({
  String id = 'bbbbbbbb-0000-4000-8000-000000000002',
  String status = 'PLACED',
  String? riderId,
  double total = 24.5,
}) =>
    <String, dynamic>{
      'id': id,
      'kind': 'CATALOG',
      'customerId': 'customer-1',
      'merchantId': 'merchant-1',
      'riderId': riderId,
      'status': status,
      'totalAmount': total,
      'subtotal': 21.0,
      'deliveryFee': 3.5,
      'deliveryFeeCharged': 3.5,
      'deliveryAddress': 'Building 42, Rue des Martyrs, Hamra, Beirut',
      'contactPhone': '+96170000000',
      'notes': 'Ring the bell twice.',
      'items': <dynamic>[
        <String, dynamic>{
          'productId': 'p2',
          'productName': 'Manoushe Zaatar',
          'unitPrice': 10.5,
          'qty': 2,
          'lineTotal': 21.0,
        },
      ],
      'availableActions': _actionsAt(status),
      'placedAt': '2026-09-23T18:05:00Z',
      'deliveredAt': null,
      'cancelReason': null,
      'fulfilment': 'DELIVERY',
      'tableLabel': null,
    };

Map<String, dynamic> _day(String day, int orders, double money) => <String, dynamic>{
      'day': day,
      'orders': orders,
      'delivered': orders,
      'money': money,
      'waived': 0.0,
    };

/// A summary whose figures are deliberately nothing like any order's total, so a figure that moved
/// because an order arrived could not be mistaken for the figure that was always there.
Map<String, dynamic> _summary() => <String, dynamic>{
      'windowDays': 14,
      'days': <Map<String, dynamic>>[
        _day('2026-09-22', 9, 311.25),
        _day('2026-09-23', 11, 407.75),
      ],
      'today': _day('2026-09-23', 11, 407.75),
      'yesterday': _day('2026-09-22', 9, 311.25),
      'window': <String, dynamic>{
        'orders': 128,
        'delivered': 120,
        'money': 4820.50,
        'waived': 0.0,
      },
      'platformFees': 602.56,
      'savedByOffers': 0.0,
      'commissionPercentage': 12.5,
      'awaitingYou': 2,
      'preparing': 0,
      'readyForPickup': 0,
      'onTheWay': 0,
      'topProducts': <Map<String, dynamic>>[],
    };

final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

Widget _wrap(Widget child, {Locale locale = const Locale('en'), double textScale = 1.0}) =>
    MaterialApp(
      locale: locale,
      theme: DeliveryTheme.light(),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (BuildContext context, Widget? home) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: home!,
      ),
      home: Scaffold(body: child),
    );

/// The narrowest phone the design carries, and a roomy window. Anything drawn for a table order is
/// asserted at both.
const Size _phone = Size(320, 640);
const Size _window = Size(1280, 900);

void main() {
  Future<_Script> pumpQueue(
    WidgetTester tester, {
    List<Map<String, dynamic>>? catalog,
    List<Map<String, dynamic>>? table,
    Size size = _window,
    Locale locale = const Locale('en'),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final _Script script = _Script(catalog: catalog, table: table);
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = script;
    // An empty tree first, because several tests here pump this screen more than once. Pumping a
    // second OrdersScreen straight over the first reuses its State — initState does not run again, so
    // the queue would still be showing the orders the previous call staged, and an assertion about the
    // new ones would be testing the old ones.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
        _wrap(OrdersScreen(api: OrderApi(dio)), locale: locale, textScale: textScale));
    await tester.pumpAndSettle();
    // The queue polls on a periodic Timer that only dispose cancels.
    addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
    return script;
  }

  Future<_Script> pumpDetail(
    WidgetTester tester,
    Map<String, dynamic> order, {
    List<Map<String, dynamic>>? alsoOpen,
    Size size = _window,
    Locale locale = const Locale('en'),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final List<Map<String, dynamic>> table = <Map<String, dynamic>>[
      order,
      ...?alsoOpen,
    ];
    final bool isTable = order['kind'] == 'TABLE';
    final _Script script = _Script(
      catalog: isTable ? <Map<String, dynamic>>[] : <Map<String, dynamic>>[order],
      table: isTable ? table : <Map<String, dynamic>>[],
    );
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = script;
    // As in pumpQueue: a fresh State, so a second pump in one test reloads rather than reusing.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_wrap(
      MerchantOrderDetailScreen(
        api: OrderApi(dio),
        order: DeliveryOrder.fromJson(order),
        queue: <DeliveryOrder>[
          for (final Map<String, dynamic> o in table) DeliveryOrder.fromJson(o),
        ],
      ),
      locale: locale,
      textScale: textScale,
    ));
    await tester.pumpAndSettle();
    return script;
  }

  group('a ticket from a table reaches the kitchen', () {
    testWidgets('the queue asks for the kinds it can work, and only those',
        (WidgetTester tester) async {
      final _Script script = await pumpQueue(tester,
          catalog: <Map<String, dynamic>>[_deliveryOrder()],
          table: <Map<String, dynamic>>[_tableOrder(id: 'aaaa-1')]);

      expect(script.kindsAsked, containsAll(<String>['CATALOG', 'TABLE']));
      expect(script.kindsAsked, isNot(contains('SERVICE')),
          reason: 'this queue has no button that moves a service order');
      expect(script.kindsAsked, everyElement(isNot('null')),
          reason: 'an unfiltered read would sweep in the kinds this screen cannot work');
    });

    testWidgets('a table order is in the list, marked with its table',
        (WidgetTester tester) async {
      await pumpQueue(tester, table: <Map<String, dynamic>>[_tableOrder(id: 'aaaa-1', table: 7)]);

      // The ticket is there at all — the whole of finding 11.
      expect(find.textContaining('#aaaa-1'), findsOneWidget);
      // And it says which table, which is the whole of what the staff need that a delivery does not
      // give them.
      expect(find.text(en.merchTableTicket(7)), findsOneWidget);
      expect(find.byIcon(Icons.table_restaurant_outlined), findsOneWidget);
      // Its lines and its note travelled with it.
      expect(find.textContaining('Hummus Beiruti'), findsOneWidget);
      // And it can be worked from here: the server offers ACCEPT, so the button is drawn.
      expect(find.widgetWithText(MerchantActionButton, en.actionAccept), findsOneWidget);
    });

    testWidgets('nothing on the card claims an address, a rider or a phone',
        (WidgetTester tester) async {
      await pumpQueue(tester, table: <Map<String, dynamic>>[_tableOrder(id: 'aaaa-1')]);

      // Not an empty row where the address was; no row at all.
      expect(find.byIcon(Icons.place_outlined), findsNothing);
      // Nothing waits for a rider who is not coming.
      expect(find.byIcon(Icons.two_wheeler), findsNothing);
      expect(find.text(en.riderAssigned), findsNothing);
      // And the queue never offers a rider's transitions on it — the server does not send them, and
      // the card draws only what the server sent.
      expect(find.widgetWithText(MerchantActionButton, en.actionClaim), findsNothing);
      expect(find.widgetWithText(MerchantActionButton, en.actionPickedUp), findsNothing);
      expect(find.widgetWithText(MerchantActionButton, en.actionDelivered), findsNothing);
    });

    testWidgets('a delivery order beside it is exactly as it was', (WidgetTester tester) async {
      await pumpQueue(tester,
          catalog: <Map<String, dynamic>>[_deliveryOrder(riderId: 'rider-9', status: 'READY')],
          table: <Map<String, dynamic>>[_tableOrder(id: 'aaaa-1')]);

      // The table's ticket is in New, on its own, and once — not twice, which is what two requests
      // answered with one page would produce.
      expect(find.textContaining('#aaaa-1'), findsOneWidget);
      expect(find.textContaining('#bbbbbbbb'), findsNothing, reason: 'READY, so not in New');

      await tester.tap(find.textContaining(en.stepReady));
      await tester.pumpAndSettle();

      expect(find.textContaining('#bbbbbbbb'), findsOneWidget);

      // The delivery keeps its address and its rider, and gains no table.
      expect(find.textContaining('Rue des Martyrs'), findsOneWidget);
      expect(find.byIcon(Icons.place_outlined), findsOneWidget);
      expect(find.text(en.riderAssigned), findsOneWidget);
      expect(find.byIcon(Icons.table_restaurant_outlined), findsNothing);
      // And READY still reads as a delivery's READY, not a table's.
      expect(find.text(OrderStatus.ready.labelIn(en)), findsWidgets);
      expect(find.text(en.merchTableStatusReady), findsNothing);
    });

    testWidgets('at 320dp and in Arabic the marked ticket still fits and still says its table',
        (WidgetTester tester) async {
      for (final (Locale locale, DeliveryStrings t) in <(Locale, DeliveryStrings)>[
        (const Locale('en'), en),
        (const Locale('ar'), ar),
      ]) {
        for (final double scale in <double>[1.0, 1.3]) {
          await pumpQueue(
            tester,
            catalog: <Map<String, dynamic>>[_deliveryOrder()],
            table: <Map<String, dynamic>>[
              _tableOrder(id: 'aaaa-1', placedAt: '2026-09-23T18:00:00Z'),
              _tableOrder(id: 'aaaa-2', placedAt: '2026-09-23T18:40:00Z'),
            ],
            size: _phone,
            locale: locale,
            textScale: scale,
          );

          final String where = '${locale.languageCode} @ $scale';
          // The longest form of the mark — table and round — at the narrowest width and the largest
          // scale the suite runs. An overflow paints a stripe and logs rather than failing, so the
          // framework's own error is what has to be absent.
          expect(find.text(t.merchTableTicketRound(7, 2)), findsOneWidget, reason: where);
          expect(tester.takeException(), isNull, reason: where);
          // Nothing hides behind a sideways drag on a 320dp page.
          for (final Scrollable s in tester.widgetList<Scrollable>(find.byType(Scrollable))) {
            expect(s.axisDirection, anyOf(AxisDirection.down, AxisDirection.up), reason: where);
          }
        }
      }
    });

    testWidgets('in Arabic the page reads right to left', (WidgetTester tester) async {
      await pumpQueue(tester,
          table: <Map<String, dynamic>>[_tableOrder(id: 'aaaa-1')],
          size: _phone,
          locale: const Locale('ar'));

      expect(find.text(ar.merchTableTicket(7)), findsOneWidget);
      expect(Directionality.of(tester.element(find.text(ar.merchTableTicket(7)))),
          TextDirection.rtl);
      // The Arabic mark is a translation, not the English string left in place.
      expect(find.text(en.merchTableTicket(7)), findsNothing);
    });
  });

  group('rounds, counted rather than stored', () {
    testWidgets('two sends from one table read as round one and round two',
        (WidgetTester tester) async {
      await pumpQueue(tester, table: <Map<String, dynamic>>[
        _tableOrder(id: 'aaaa-1', table: 7, placedAt: '2026-09-23T18:00:00Z'),
        _tableOrder(id: 'aaaa-2', table: 7, placedAt: '2026-09-23T18:40:00Z'),
      ]);

      expect(find.text(en.merchTableTicketRound(7, 1)), findsOneWidget);
      expect(find.text(en.merchTableTicketRound(7, 2)), findsOneWidget);
      // Two tickets, not one replaced by the other: sending again adds a round, deliberately.
      expect(find.textContaining('#aaaa-1'), findsOneWidget);
      expect(find.textContaining('#aaaa-2'), findsOneWidget);
    });

    testWidgets('a fresh table starts at round one, and says no round at all',
        (WidgetTester tester) async {
      // The party that was at table 7 has paid; their two tickets are served. Nothing told the app
      // anybody left, and the next send must still read as a first round.
      await pumpQueue(tester, table: <Map<String, dynamic>>[
        _tableOrder(id: 'aaaa-1', status: 'DELIVERED', placedAt: '2026-09-23T18:00:00Z'),
        _tableOrder(id: 'aaaa-2', status: 'DELIVERED', placedAt: '2026-09-23T18:40:00Z'),
        _tableOrder(id: 'aaaa-3', status: 'PLACED', placedAt: '2026-09-23T20:30:00Z'),
      ]);

      // The new party's ticket is in New, marked with its table and no round: it is round one, and a
      // round is only printed once there are two tickets to tell apart.
      expect(find.textContaining('#aaaa-3'), findsOneWidget);
      expect(find.text(en.merchTableTicket(7)), findsOneWidget);
      expect(find.text(en.merchTableTicketRound(7, 3)), findsNothing,
          reason: 'a new party must not inherit the last one\'s count');
      expect(find.text(en.merchTableTicketRound(7, 1)), findsNothing);
    });

    testWidgets('a round is counted across tabs, not within the one in view',
        (WidgetTester tester) async {
      // Round one has been accepted, so it sits in Preparing while round two is still in New. Counting
      // only the visible tab would call round two "round one".
      await pumpQueue(tester, table: <Map<String, dynamic>>[
        _tableOrder(id: 'aaaa-1', status: 'ACCEPTED', placedAt: '2026-09-23T18:00:00Z'),
        _tableOrder(id: 'aaaa-2', status: 'PLACED', placedAt: '2026-09-23T18:40:00Z'),
      ]);

      expect(find.text(en.merchTableTicketRound(7, 2)), findsOneWidget);
      await tester.tap(find.textContaining(en.stepPreparing));
      await tester.pumpAndSettle();
      expect(find.text(en.merchTableTicketRound(7, 1)), findsOneWidget);
    });

    testWidgets('two tables keep their own counts', (WidgetTester tester) async {
      await pumpQueue(tester, table: <Map<String, dynamic>>[
        _tableOrder(id: 'aaaa-1', table: 7, placedAt: '2026-09-23T18:00:00Z'),
        _tableOrder(id: 'aaaa-2', table: 7, placedAt: '2026-09-23T18:40:00Z'),
        _tableOrder(id: 'aaaa-3', table: 12, placedAt: '2026-09-23T18:50:00Z'),
      ]);

      expect(find.text(en.merchTableTicketRound(7, 1)), findsOneWidget);
      expect(find.text(en.merchTableTicketRound(7, 2)), findsOneWidget);
      // Table 12 has one ticket, so it is table 12 and nothing else.
      expect(find.text(en.merchTableTicket(12)), findsOneWidget);
      expect(find.text(en.merchTableTicketRound(12, 1)), findsNothing);
    });
  });

  group('what the staff are offered at each state', () {
    testWidgets('accept, prepare, ready, then served to the table', (WidgetTester tester) async {
      final Map<String, ({String label, String status})> expected =
          <String, ({String label, String status})>{
        'PLACED': (label: en.actionAccept, status: OrderStatus.placed.labelIn(en)),
        'ACCEPTED': (label: en.actionPrepare, status: OrderStatus.accepted.labelIn(en)),
        'PREPARING': (label: en.actionMarkReady, status: OrderStatus.preparing.labelIn(en)),
        // The hand-over. Not "Customer collected": nobody comes to a counter for this.
        'READY': (label: en.merchTableActionServed, status: en.merchTableStatusReady),
      };

      for (final MapEntry<String, ({String label, String status})> step in expected.entries) {
        await pumpQueue(tester,
            table: <Map<String, dynamic>>[_tableOrder(id: 'aaaa-1', status: step.key)]);
        // Completed is the only bucket that is not the live queue; every state above is in one of the
        // first three tabs, which open on New.
        if (step.key != 'PLACED') {
          await tester.tap(find.textContaining(
              step.key == 'READY' ? en.stepReady : en.stepPreparing));
          await tester.pumpAndSettle();
        }
        expect(find.text(step.value.status), findsWidgets, reason: step.key);
        expect(find.widgetWithText(MerchantActionButton, step.value.label), findsOneWidget,
            reason: step.key);
        // Reject is beside every one of them, as it is on a basket.
        expect(find.widgetWithText(MerchantActionButton, en.merchReject), findsOneWidget,
            reason: step.key);
      }
    });

    testWidgets('a served ticket says served, and offers nothing more',
        (WidgetTester tester) async {
      await pumpQueue(tester,
          table: <Map<String, dynamic>>[_tableOrder(id: 'aaaa-1', status: 'DELIVERED')]);

      await tester.tap(find.textContaining(en.merchTabCompleted));
      await tester.pumpAndSettle();

      expect(find.text(en.merchTableStatusServed), findsOneWidget);
      // Never "Delivered": nothing was delivered, it crossed the floor.
      expect(find.text(OrderStatus.delivered.labelIn(en)), findsNothing);
      expect(find.byType(MerchantActionButton), findsNothing);
    });

    testWidgets('serving it sends the collected transition, once', (WidgetTester tester) async {
      final _Script script = await pumpQueue(tester,
          table: <Map<String, dynamic>>[_tableOrder(id: 'aaaa-1', status: 'READY')]);

      await tester.tap(find.textContaining(en.stepReady));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MerchantActionButton, en.merchTableActionServed));
      await tester.pumpAndSettle();

      expect(script.posts, hasLength(1));
      expect(script.posts.single.path, '/api/orders/aaaa-1/collected');
    });

    testWidgets('every button on a table order clears 48dp at 320dp',
        (WidgetTester tester) async {
      for (final double scale in <double>[1.0, 1.3]) {
        await pumpQueue(tester,
            table: <Map<String, dynamic>>[_tableOrder(id: 'aaaa-1', status: 'READY')],
            size: _phone,
            textScale: scale,
            locale: const Locale('ar'));
        await tester.tap(find.textContaining(ar.stepReady));
        await tester.pumpAndSettle();

        final Finder buttons = find.byType(MerchantActionButton);
        expect(buttons, findsWidgets, reason: 'scale $scale');
        for (final Element e in buttons.evaluate()) {
          expect(tester.getSize(find.byWidget(e.widget)).height, greaterThanOrEqualTo(48.0),
              reason: 'the longest Arabic label at scale $scale');
        }
        expect(tester.takeException(), isNull, reason: 'scale $scale');
      }
    });
  });

  group('the ticket in full, on its own page', () {
    testWidgets('the table stands where the customer would, and says why nothing else does',
        (WidgetTester tester) async {
      await pumpDetail(tester, _tableOrder(id: 'aaaa-1'));

      expect(find.text(en.merchTableSection.toUpperCase()), findsOneWidget);
      expect(find.text(en.merchTableTicket(7)), findsOneWidget);
      // The absence is stated, so it reads as dining in rather than as a field that failed to load.
      expect(find.text(en.merchTableInTheRoom), findsOneWidget);
      // And the delivery card it replaces is gone entirely — not present with nothing after it.
      expect(find.text(en.merchCustomerDetails.toUpperCase()), findsNothing);
      expect(find.textContaining(en.deliverTo), findsNothing);
      // The diner's note is what the kitchen reads, and it is kept.
      expect(find.textContaining('No onions'), findsOneWidget);
    });

    testWidgets('the flow ends where the kitchen\'s work ends', (WidgetTester tester) async {
      await pumpDetail(tester, _tableOrder(id: 'aaaa-1', status: 'READY'));

      expect(find.text(en.stepAccepted), findsOneWidget);
      expect(find.text(en.stepPreparing), findsWidgets);
      expect(find.text(en.stepReady), findsWidgets);
      // "Picked up" is a transition Order.canMoveTo refuses for a fulfilment nobody carries, so a
      // fourth bar would be one that can never light.
      expect(find.text(en.merchStepPickedUp), findsNothing);
      expect(find.text(en.merchTableStatusReady), findsWidgets);
    });

    testWidgets('a delivery order keeps its fourth step', (WidgetTester tester) async {
      await pumpDetail(tester, _deliveryOrder(status: 'READY'));

      expect(find.text(en.merchStepPickedUp), findsOneWidget);
      expect(find.text(en.merchCustomerDetails.toUpperCase()), findsOneWidget);
      expect(find.textContaining(en.deliverTo), findsOneWidget);
      expect(find.text(en.merchTableSection.toUpperCase()), findsNothing);
    });

    testWidgets('the receipt is the food, with no fee row and no waiver claim',
        (WidgetTester tester) async {
      await pumpDetail(tester, _tableOrder(id: 'aaaa-1', total: 20.0));

      // No row of 0.00 pretending to be a delivery that happened to be free.
      expect(find.text(en.deliveryFeeLabelMerchant), findsNothing);
      expect(find.text('0.00'), findsNothing);
      // The sentence instead, which also answers the question a merchant would ask next.
      expect(find.text(en.merchTableBooksNothing), findsOneWidget);
      // Never a waiver: a waiver is a charge the platform dropped, and nothing was charged.
      expect(find.text(en.noCommissionOnThisOrder), findsNothing);
      expect(find.text(en.deliveryPaidByPlatform), findsNothing);
      // The grand total is the goods and only the goods.
      expect(find.text(en.merchGrandTotal), findsOneWidget);
      expect(find.text('20.00'), findsWidgets);
    });

    testWidgets('the page fits 320dp in Arabic, at both scales', (WidgetTester tester) async {
      for (final double scale in <double>[1.0, 1.3]) {
        await pumpDetail(
          tester,
          _tableOrder(id: 'aaaa-1', status: 'READY'),
          alsoOpen: <Map<String, dynamic>>[
            _tableOrder(id: 'aaaa-2', placedAt: '2026-09-23T18:40:00Z'),
          ],
          size: _phone,
          locale: const Locale('ar'),
          textScale: scale,
        );

        expect(find.text(ar.merchTableSection.toUpperCase()), findsOneWidget, reason: 'scale $scale');
        expect(find.text(ar.merchTableInTheRoom), findsOneWidget, reason: 'scale $scale');
        expect(find.text(ar.merchTableBooksNothing), findsOneWidget, reason: 'scale $scale');
        expect(find.text(ar.merchTableTicketRound(7, 1)), findsOneWidget, reason: 'scale $scale');
        expect(tester.takeException(), isNull, reason: 'scale $scale');
      }
    });
  });

  group('no figure about money moves because a table ordered', () {
    testWidgets('the queue has no total, and the cards are each their own order',
        (WidgetTester tester) async {
      await pumpQueue(tester,
          catalog: <Map<String, dynamic>>[_deliveryOrder(total: 24.5)],
          table: <Map<String, dynamic>>[
            _tableOrder(id: 'aaaa-1', total: 20.0),
            _tableOrder(id: 'aaaa-2', total: 11.25, placedAt: '2026-09-23T18:40:00Z'),
          ]);

      // Each order shows what that order came to.
      expect(find.text('24.50'), findsOneWidget);
      expect(find.text('20.00'), findsOneWidget);
      expect(find.text('11.25'), findsOneWidget);
      // And no figure anywhere is any of the sums a later change might be tempted to add. This is the
      // assertion that fails the day somebody puts "today's takings" on this screen by folding the
      // list, which would count a ticket the platform is not a party to.
      for (final String sum in <String>['55.75', '31.25', '44.50', '35.75']) {
        expect(find.text(sum), findsNothing, reason: 'a total including a table order');
      }
    });

    testWidgets('the tabs count orders, and a table order is an order',
        (WidgetTester tester) async {
      await pumpQueue(tester,
          catalog: <Map<String, dynamic>>[_deliveryOrder()],
          table: <Map<String, dynamic>>[_tableOrder(id: 'aaaa-1')]);

      // A ticket waiting to be accepted is work waiting, whoever sent it, so the New tab counts it.
      // That is a count of jobs and not of money, which is the distinction this group is about.
      expect(find.textContaining('${en.merchTabNew} (2)'), findsOneWidget);
    });

    testWidgets('the dashboard\'s earnings are the server\'s, and a table ticket does not touch them',
        (WidgetTester tester) async {
      tester.view.physicalSize = _phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final _Script script = _Script(
        catalog: <Map<String, dynamic>>[_deliveryOrder(total: 24.5)],
        table: <Map<String, dynamic>>[_tableOrder(id: 'aaaa-1', total: 20.0)],
      );
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = script;
      await tester.pumpWidget(_wrap(MerchantDashboardScreen(api: OrderApi(dio))));
      await tester.pumpAndSettle();
      addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));

      // Sales today is the figure the summary endpoint sent, to the penny, and the orders list is not
      // consulted for it. 407.75 + 20.00 would be 427.75.
      expect(find.text('407.75'), findsWidgets);
      expect(find.text('427.75'), findsNothing);
      expect(find.text('447.75'), findsNothing);
      // Orders today is the server's count too — eleven, not twelve because a ticket is on screen.
      expect(find.text('11'), findsWidgets);
      expect(find.text('12'), findsNothing);
      // The table's ticket is nonetheless previewed, marked, so this page does not contradict its own
      // "awaiting you" count.
      expect(find.textContaining(en.merchTableTicket(7)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
