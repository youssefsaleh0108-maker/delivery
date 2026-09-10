import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_portal/src/backoffice/dashboard_screen.dart';
import 'package:delivery_portal/src/backoffice/reconciliation_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'live_backend.dart';

/// **What the back office sees when a customer buys something.**
///
/// <p>An order placed on a phone ripples outward: the merchant's queue first, then the rider's
/// board, then the customer's own list — and, all the way through, the back office, which is the
/// only surface that can see every order on the platform and the money behind it. Support answers
/// the phone from this screen. An order that is not on it is an order nobody can help with.
///
/// <p><strong>Why this is split in two, and why that is not a cop-out.</strong> The twelve tests
/// beside this one hand their screen a hand-written JSON literal through a replaced adapter. They
/// ask "does the screen render what the server said", which is worth asking and is not the same
/// as "does the server say it" — a portal that renders a beautiful, correct, EMPTY ledger passes
/// every one of them.
///
/// <p>So the ripple is asked of the real deployment, over real HTTP, outside the widget zone; and
/// the rendering is then asked of the real screen, seeded with the bytes that deployment actually
/// returned. Both halves are real. The seam exists for a mechanical reason: inside `testWidgets`
/// the clock and the microtask queue are faked, a real socket's keep-alive and timeout timers are
/// created against that fake clock and never fire, and the test then fails on "A Timer is still
/// pending" — a message about the harness, reported as a failure of whatever the test was about.
/// Keeping the socket out of the faked zone removes that whole class of problem and costs
/// nothing: the JSON the screen parses is the JSON the server sent.
///
/// ```
/// flutter test test/live --dart-define=LIVE_BACKEND=true \
///   --dart-define=API_BASE_URL=https://api-dev.youdrop.shop \
///   --dart-define=KEYCLOAK_ISSUER=https://iam-dev.youdrop.shop/realms/delivery-platform
/// ```
void main() {
  // A desktop window: the ledger is a table, and the portal collapses to cards below 1024.
  const Size window = Size(1440, 900);

  late String orderId;
  late String shortId;

  /// What the deployment actually returned, by request path.
  final Map<String, Object> captured = <String, Object>{};

  setUpAll(() async {
    if (!Live.enabled) return;
    Live.allowRealNetwork();

    final Dio backoffice = Live.dioFor(await Live.signIn('backoffice'));
    final Dio customer = Live.dioFor(await Live.signIn('customer'));
    final Dio merchant = Live.dioFor(await Live.signIn('merchant'));
    final Dio rider = Live.dioFor(await Live.signIn('rider'));

    final String tag = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    final Map<String, dynamic> store = await LiveOrders.merchantStore(merchant);
    final Map<String, dynamic> product = await LiveOrders.sellableProduct(
      merchant,
      customer,
      store['id'] as String,
      'Portal Plate',
    );

    final Map<String, dynamic> order =
        await LiveOrders.place(customer, product['id'] as String, 'Flat $tag, Hamra, Beirut');
    orderId = order['id'] as String;
    shortId = orderId.substring(0, 8);

    // All the way to delivered, each hop by the role that owns it.
    await LiveOrders.advance(merchant, orderId, <String>['accept', 'prepare', 'ready']);
    await LiveOrders.advance(rider, orderId, <String>['claim', 'pick-up', 'deliver']);

    captured['/api/orders'] =
        await Live.call(backoffice, 'GET', '/api/orders?page=0&size=50') as Object;

    // Settlement is posted asynchronously off an order.delivered event, so this waits for the
    // ledger rather than asserting into a race.
    final Object? legs = await Live.waitFor<Object>(() async {
      final dynamic body = await Live.call(backoffice, 'GET', '/api/accounting/orders/$orderId');
      final List<dynamic> rows = body is List
          ? body
          : ((body as Map<String, dynamic>)['transactions'] ??
              body['legs'] ??
              const <dynamic>[]) as List<dynamic>;
      return rows.isEmpty ? null : body as Object;
    }, timeout: const Duration(seconds: 120));
    if (legs != null) captured['/api/accounting/orders'] = legs;
  });

  /// Serves the deployment's own bytes back to a real API client, with no socket involved.
  Dio replaying(Map<String, Object> responses) => Dio(BaseOptions(baseUrl: Live.apiBaseUrl))
    ..httpClientAdapter = _Replay(responses)
    // Dio hands a large response body to compute(), which is an ISOLATE, and an isolate never
    // runs under the faked clock inside testWidgets — the screen simply stays on its spinner
    // forever and the failure reads as "the ledger did not draw the order". A page of fifty real
    // orders is comfortably over that threshold. Decoding on this thread is what makes the real
    // parsing observable.
    ..transformer = SyncTransformer();

  Future<void> show(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(window);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
    // Never pumpAndSettle: the ledger polls for the life of the screen and never settles.
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the deployment puts a brand-new order at the top of the ledger',
      (WidgetTester tester) async {
    final Map<String, dynamic> body = captured['/api/orders']! as Map<String, dynamic>;
    final List<dynamic> rows = body['content'] as List<dynamic>;

    expect(rows.any((dynamic o) => (o as Map<String, dynamic>)['id'] == orderId), isTrue,
        reason: 'Order $orderId was placed and delivered minutes ago and is not in the first '
            'fifty of the cross-merchant ledger. Support cannot answer the phone about an order '
            'they cannot find.');

    // Newest first, which is the whole point of the sort: the order somebody is phoning about is
    // the one that just happened. The unfiltered branch used to call findAll(pageable), which
    // applies no order at all, so page 0 came back in the database's own sequence.
    expect((rows.first as Map<String, dynamic>)['id'], orderId,
        reason: 'The newest order is not the first row, so the ledger is not sorted newest-first '
            'and the order support is being asked about can be on any page.');

    final List<DateTime> placed = rows
        .map((dynamic o) => DateTime.parse((o as Map<String, dynamic>)['placedAt'] as String))
        .toList();
    for (int i = 1; i < placed.length; i++) {
      expect(placed[i].isAfter(placed[i - 1]), isFalse,
          reason: 'Row $i was placed after row ${i - 1}, so the page is not in descending order.');
    }
  }, skip: !Live.enabled);

  testWidgets('and the ledger screen shows it, parsed from those same bytes',
      (WidgetTester tester) async {
    await show(tester, DashboardScreen(api: OrderApi(replaying(captured))));

    final List<String> onScreen = find
        .byType(Text)
        .evaluate()
        .map((Element e) => (e.widget as Text).data ?? '')
        .where((String t) => t.trim().isNotEmpty)
        .toList();

    expect(find.textContaining('#$shortId'), findsWidgets,
        reason: 'The server returned this order and the screen did not draw it, so the failure is '
            'on the client: the parsing, the default filter, or the row builder. '
            'On screen: ${onScreen.join(' | ')}');
    expect(find.text('No orders match this filter.'), findsNothing,
        reason: 'The ledger is showing its empty state over a page of real orders.');

    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !Live.enabled);

  testWidgets('the money reached the ledger, and reconciliation opens on it',
      (WidgetTester tester) async {
    expect(captured['/api/accounting/orders'], isNotNull,
        reason: 'The order was delivered but settlement posted no accounting legs within two '
            'minutes. The customer paid at the door and nobody has been credited.');

    await show(tester, ReconciliationScreen(api: AccountingApi(replaying(captured))));

    // An operator who cannot open reconciliation cannot close the day. What the screen chooses to
    // show is its own business; throwing while rendering real settlement data is not.
    expect(tester.takeException(), isNull,
        reason: 'The reconciliation screen threw while rendering real settlement data.');
    expect(find.byType(ReconciliationScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !Live.enabled);
}

/// Replays captured responses by path prefix. No sockets, so no timers against the faked clock.
///
/// Anything the screen asks for that was not captured answers `200 []`, so an unrelated sidebar
/// fetch cannot fail a test about the ledger.
class _Replay implements HttpClientAdapter {
  _Replay(this.responses);

  final Map<String, Object> responses;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    final String path = options.uri.path;
    Object? body;
    for (final MapEntry<String, Object> entry in responses.entries) {
      if (path.startsWith(entry.key)) {
        body = entry.value;
        break;
      }
    }
    return ResponseBody.fromString(
      jsonEncode(body ?? const <dynamic>[]),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
