import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/butler_request_details_screen.dart';
import 'package:mobile_app/src/butler_requests_list.dart';
import 'package:mobile_app/src/cart.dart';
import 'package:mobile_app/src/order_details_screen.dart';

/// Recent errands that open onto their own page, and buttons a customer can actually hit.
///
/// <p>The customer's complaint was two things at once: the recent-tasks buttons were unfriendly,
/// and tapping a task showed nothing. Both were literally true. A row was only tappable once the
/// errand had become an order — for the whole negotiation, tapping it did nothing — and the only
/// action on it was "Cancel" as an 11px text link that fired on a single touch, with no undo.
///
/// <p>What is pinned here is each half of that: a row opens the details page whatever state it is
/// in; the page shows the money and makes the right offer for the state (pay, cancel, track); and
/// cancelling — from the page or from the row — asks first and only then calls the server.
void main() {
  Widget app(Widget home) => MaterialApp(
        theme: DeliveryTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          DeliveryStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: DeliveryStrings.supportedLocales,
        home: home,
      );

  /// Tall enough that the lazy lists build every card, so no finder depends on a scroll offset.
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Dio dioFor(_FakeButler server) => Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = server
    ..transformer = SyncTransformer();

  Widget listFor(Dio dio) => Scaffold(
        body: ListView(
          children: <Widget>[
            ButlerRequestsList(
              api: ButlerApi(dio),
              orderApi: OrderApi(dio),
              storeApi: StoreApi(dio),
              cart: Cart(),
            ),
          ],
        ),
      );

  Widget detailsFor(Dio dio, Map<String, Object?> json) => ButlerRequestDetailsScreen(
        request: ButlerRequest.fromJson(json),
        api: ButlerApi(dio),
        orderApi: OrderApi(dio),
        storeApi: StoreApi(dio),
        cart: Cart(),
      );

  /// Lets the requests land and a route transition finish. Explicit pumps rather than
  /// pumpAndSettle: a busy pill's spinner and the five-second polls never "settle".
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// A page push or pop. The Material page transition runs longer than a dialog's, and until it
  /// finishes the page underneath is still on stage — its buttons included, so a finder for a
  /// label both pages carry ("Cancel errand", "Pay 24.90") would find two.
  Future<void> settleRoute(WidgetTester tester) async {
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 700));
  }

  testWidgets('tapping a recent task opens its details, before it has become an order', (
    WidgetTester tester,
  ) async {
    tall(tester);
    final _FakeButler server = _FakeButler()
      ..put(_errand('s1', 'Two boxes of books to my sister',
          mode: 'SEND',
          status: 'CLAIMED',
          pickupAddress: '8 Clemenceau Street, reception desk',
          recipient: 'Maya',
          claimedAt: '2026-09-10T09:20:00Z'));

    await tester.pumpWidget(app(listFor(dioFor(server))));
    await settle(tester);
    expect(find.byType(ButlerRequestDetailsScreen), findsNothing);

    // The row must be a comfortable target — it used to be exactly as tall as two lines of text.
    final Finder row = find
        .ancestor(of: find.text('Two boxes of books to my sister'), matching: find.byType(InkWell))
        .first;
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));

    await tester.tap(find.text('Two boxes of books to my sister'));
    await settleRoute(tester);

    expect(find.byType(ButlerRequestDetailsScreen), findsOneWidget,
        reason: 'a claimed errand has no order yet, and until now its row did nothing at all');
    expect(find.text('Errand details'), findsOneWidget);
    expect(find.text('8 Clemenceau Street, reception desk'), findsOneWidget);
    expect(find.text('Maya'), findsOneWidget);
    expect(find.text('A rider took it'), findsOneWidget,
        reason: 'the timeline says who has it, in words');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a quoted errand shows goods, fee and total, and Pay approves it', (
    WidgetTester tester,
  ) async {
    tall(tester);
    final _FakeButler server = _FakeButler()
      ..put(_errand('q1', 'A box of paracetamol and some plasters',
          status: 'QUOTED',
          sourceHint: 'Any pharmacy near Hamra',
          budgetCap: 30,
          goodsCost: 22.4,
          deliveryFee: 2.5,
          payableTotal: 24.9,
          receiptRef: 'R-118',
          claimedAt: '2026-09-10T09:20:00Z',
          quotedAt: '2026-09-10T09:45:00Z'));

    await tester.pumpWidget(app(listFor(dioFor(server))));
    await settle(tester);

    // The waiting-on-you card opens the same page.
    await tester.tap(find.text('A box of paracetamol and some plasters'));
    await settleRoute(tester);
    expect(find.byType(ButlerRequestDetailsScreen), findsOneWidget);

    expect(find.text('Goods'), findsOneWidget);
    expect(find.text('22.40'), findsOneWidget);
    expect(find.text('Errand fee'), findsOneWidget);
    expect(find.text('2.50'), findsOneWidget);
    expect(find.text('Total to pay'), findsOneWidget);
    expect(find.text('24.90'), findsOneWidget);
    expect(find.text('Your budget cap'), findsOneWidget);
    expect(find.text('R-118'), findsOneWidget);
    expect(find.text('Any pharmacy near Hamra'), findsOneWidget);

    final int readsBefore = server.readCalls;
    expect(server.approveCalls, 0);
    await tester.tap(find.text('Pay 24.90'));
    await settle(tester);

    expect(server.approveCalls, 1, reason: 'Pay is the call that agrees the price');
    expect(server.readCalls, greaterThan(readsBefore),
        reason: 'the page re-reads the errand after acting on it');
    expect(find.text('Track order'), findsOneWidget,
        reason: 'once agreed it is an order, and the page offers the way to follow it');
    expect(find.text('Pay 24.90'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Cancel on the details page asks first, and only a yes cancels', (
    WidgetTester tester,
  ) async {
    tall(tester);
    final Map<String, Object?> json = _errand('r1', 'Fetch a phone charger');
    final _FakeButler server = _FakeButler()..put(json);

    await tester.pumpWidget(app(detailsFor(dioFor(server), json)));
    await settle(tester);

    await tester.tap(find.text('Cancel errand'));
    await settle(tester);
    expect(find.text('Cancel this errand?'), findsOneWidget);
    expect(server.cancelCalls, 0, reason: 'opening the question must not answer it');

    await tester.tap(find.text('Keep it'));
    await settle(tester);
    expect(find.text('Cancel this errand?'), findsNothing);
    expect(server.cancelCalls, 0, reason: '"Keep it" keeps it');

    await tester.tap(find.text('Cancel errand'));
    await settle(tester);
    await tester.tap(find.text('Yes, cancel'));
    await settle(tester);

    expect(server.cancelCalls, 1);
    expect(find.text('Cancel errand'), findsNothing,
        reason: 'a cancelled errand is terminal; offering to cancel it again would be a lie');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the row\'s Cancel is a real button that asks first, and the list hears of changes', (
    WidgetTester tester,
  ) async {
    tall(tester);
    final _FakeButler server = _FakeButler()
      ..put(_errand('r1', 'Fetch a phone charger'))
      ..put(_errand('r2', 'Collect a prescription'));

    await tester.pumpWidget(app(listFor(dioFor(server))));
    await settle(tester);

    // A design-system pill, not an 11px text link.
    expect(find.widgetWithText(YdPillButton, 'Cancel errand'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(YdPillButton, 'Cancel errand').first);
    await settle(tester);
    expect(find.text('Cancel this errand?'), findsOneWidget);
    expect(server.cancelCalls, 0, reason: 'one stray touch used to cancel outright');
    await tester.tap(find.text('Yes, cancel'));
    await settle(tester);
    expect(server.cancelCalls, 1);

    // And a change made on the details page reaches the list as soon as the page closes, not on
    // the next poll: open the other one, cancel it there, come back.
    await tester.tap(find.text('Collect a prescription'));
    await settleRoute(tester);
    await tester.tap(find.text('Cancel errand'));
    await settle(tester);
    await tester.tap(find.text('Yes, cancel'));
    await settle(tester);
    expect(server.cancelCalls, 2);

    // About three and a half seconds in, so the list's first five-second poll has not fired and
    // cannot fire inside the next fifty milliseconds: a load counted here is the pop's doing.
    final int loadsBefore = server.mineCalls;
    await tester.tap(find.byType(YdBackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(server.mineCalls, greaterThan(loadsBefore),
        reason: 'the page popped saying it changed something, so the list reloads at once');

    await settleRoute(tester);
    expect(find.byType(ButlerRequestDetailsScreen), findsNothing);
    expect(find.widgetWithText(YdPillButton, 'Cancel errand'), findsNothing,
        reason: 'both errands are cancelled, and the list must already say so');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an agreed errand offers Track order, which opens the order', (
    WidgetTester tester,
  ) async {
    tall(tester);
    final Map<String, Object?> json = _errand('a1', 'Bread and milk',
        status: 'APPROVED',
        goodsCost: 4.1,
        deliveryFee: 2.5,
        payableTotal: 6.6,
        orderId: 'order-77',
        claimedAt: '2026-09-10T09:20:00Z',
        quotedAt: '2026-09-10T09:45:00Z',
        resolvedAt: '2026-09-10T09:50:00Z');
    final _FakeButler server = _FakeButler()..put(json);

    await tester.pumpWidget(app(detailsFor(dioFor(server), json)));
    await settle(tester);

    expect(find.text('Cancel errand'), findsNothing);
    expect(find.text('Price agreed'), findsOneWidget);

    await tester.tap(find.text('Track order'));
    await settleRoute(tester);

    final OrderDetailsScreen opened = tester.widget(find.byType(OrderDetailsScreen));
    expect(opened.orderId, 'order-77');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Map<String, Object?> _errand(
  String id,
  String what, {
  String mode = 'BUY',
  String status = 'REQUESTED',
  String? sourceHint,
  String? pickupAddress,
  String? recipient,
  double? budgetCap,
  double? goodsCost,
  double deliveryFee = 2.5,
  double payableTotal = 2.5,
  String? receiptRef,
  String? orderId,
  String? claimedAt,
  String? quotedAt,
  String? resolvedAt,
}) =>
    <String, Object?>{
      'id': id,
      'mode': mode,
      'status': status,
      'what': what,
      'sourceHint': sourceHint,
      'pickupAddress': pickupAddress,
      'recipient': recipient,
      'dropoffAddress': 'Hamra, Beirut',
      'budgetCap': budgetCap,
      'goodsCost': goodsCost,
      'deliveryFee': deliveryFee,
      'payableTotal': payableTotal,
      'overBudget': false,
      'receiptRef': receiptRef,
      'orderId': orderId,
      'createdAt': '2026-09-10T09:00:00Z',
      'claimedAt': claimedAt,
      'quotedAt': quotedAt,
      'resolvedAt': resolvedAt,
    };

/// A stand-in for the Butler endpoints the customer touches: no socket, so nothing races the
/// widget test's clock. The actions move the errand the way the server's machine does; anything
/// else (the order screen's own reads) is a 404, which that screen already handles.
class _FakeButler implements HttpClientAdapter {
  final Map<String, Map<String, Object?>> errands = <String, Map<String, Object?>>{};
  int mineCalls = 0;
  int readCalls = 0;
  int approveCalls = 0;
  int declineCalls = 0;
  int cancelCalls = 0;

  void put(Map<String, Object?> errand) => errands[errand['id']! as String] = errand;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    final List<String> path = options.uri.pathSegments;
    if (path.length < 3 || path[0] != 'api' || path[1] != 'butler') return _notFound();

    if (path[2] == 'mine') {
      mineCalls++;
      final List<Map<String, Object?>> rows = errands.values.toList();
      return _ok(<String, Object?>{
        'content': rows,
        'page': 0,
        'size': 20,
        'totalElements': rows.length,
        'totalPages': 1,
      });
    }

    final Map<String, Object?>? errand = errands[path[2]];
    if (errand == null) return _notFound();
    if (path.length == 3) {
      readCalls++;
      return _ok(errand);
    }

    const String now = '2026-09-10T10:00:00Z';
    switch (path[3]) {
      case 'approve':
        approveCalls++;
        errand
          ..['status'] = 'APPROVED'
          ..['orderId'] = 'order-${errand['id']}'
          ..['resolvedAt'] = now;
      case 'decline':
        declineCalls++;
        errand
          ..['status'] = 'DECLINED'
          ..['resolvedAt'] = now;
      case 'cancel':
        cancelCalls++;
        errand
          ..['status'] = 'CANCELLED'
          ..['resolvedAt'] = now;
      default:
        return _notFound();
    }
    return _ok(errand);
  }

  static ResponseBody _ok(Object body) =>
      ResponseBody.fromString(jsonEncode(body), 200, headers: _json);

  static ResponseBody _notFound() =>
      ResponseBody.fromString('{"detail":"not found"}', 404, headers: _json);

  static const Map<String, List<String>> _json = <String, List<String>>{
    Headers.contentTypeHeader: <String>[Headers.jsonContentType],
  };

  @override
  void close({bool force = false}) {}
}
