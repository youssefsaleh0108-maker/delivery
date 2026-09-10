import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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
import 'package:mobile_app/src/rider_butler_board.dart';

/// Recent errands that open onto their own page, and buttons a customer can actually hit.
///
/// <p>The customer's complaint was two things at once: the recent-tasks buttons were unfriendly,
/// and tapping a task showed nothing. Both were literally true. A row was only tappable once the
/// errand had become an order — for the whole negotiation, tapping it did nothing — and the only
/// action on it was "Cancel" as an 11px text link that fired on a single touch, with no undo.
///
/// <p>What is pinned here is each half of that: a row opens the details page whatever state it is
/// in; the page shows the money and makes the right offer for the state (pay, confirm, cancel,
/// track); and anything final — cancelling, declining — asks first and only then calls the server.
///
/// <p>And what review of the first cut found: a claimed send had no way forward at all (the
/// server makes it an order only on the customer's approve, and nothing offered one); the
/// timeline worded steps that had not happened as if they had, aloud as well as on screen; ended
/// errands still showed a bold "Total to pay"; a tap on a busy button fell through to the card
/// behind it; the buttons were 44 tall; the status words were unreadable on their badges; and the
/// chevron pointed backwards in Arabic.
void main() {
  Widget app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
        theme: DeliveryTheme.light(),
        locale: locale,
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

  Finder pill(String label) => find.widgetWithText(YdPillButton, label);

  /// A purchase the shopper has bought and priced, waiting on the customer.
  Map<String, Object?> quoted(String id, String what) => _errand(id, what,
      status: 'QUOTED',
      goodsCost: 22.4,
      deliveryFee: 2.5,
      payableTotal: 24.9,
      claimedAt: '2026-09-10T09:20:00Z',
      quotedAt: '2026-09-10T09:45:00Z');

  testWidgets('tapping a recent task opens its details, before it has become an order', (
    WidgetTester tester,
  ) async {
    tall(tester);
    final _FakeButler server = _FakeButler()
      ..put(_errand('s1', 'Two boxes of books to my sister',
          mode: 'SEND',
          pickupAddress: '8 Clemenceau Street, reception desk',
          recipient: 'Maya'));

    await tester.pumpWidget(app(listFor(dioFor(server))));
    await settle(tester);
    expect(find.byType(ButlerRequestDetailsScreen), findsNothing);

    // The row must be a comfortable target — it used to be exactly as tall as two lines of text.
    final Finder row = find
        .ancestor(of: find.text('Two boxes of books to my sister'), matching: find.byType(InkWell))
        .first;
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
    // The status word kept the 12px it had before it became a badge.
    expect(tester.widget<YdBadge>(find.widgetWithText(YdBadge, 'Pending')).fontSize, 12);

    await tester.tap(find.text('Two boxes of books to my sister'));
    await settleRoute(tester);

    expect(find.byType(ButlerRequestDetailsScreen), findsOneWidget,
        reason: 'an errand nobody has taken has no order, and until now its row did nothing');
    expect(find.text('Errand details'), findsOneWidget);
    expect(find.text('8 Clemenceau Street, reception desk'), findsOneWidget);
    expect(find.text('Maya'), findsOneWidget);
    expect(find.text('Waiting for a rider'), findsOneWidget,
        reason: 'the timeline says where it has got to, in words');
    expect(find.text('You confirm the fee'), findsOneWidget);
    // A send has nothing to price, so it has no quote step at all — finished or ahead.
    expect(find.text('Price quoted'), findsNothing);
    expect(find.text('The shopper tells you the price'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a claimed send waits on the customer to confirm, and confirming makes it an order', (
    WidgetTester tester,
  ) async {
    tall(tester);
    final _FakeButler server = _FakeButler()
      ..put(_errand('s1', 'Two boxes of books to my sister',
          mode: 'SEND',
          status: 'CLAIMED',
          pickupAddress: '8 Clemenceau Street, reception desk',
          claimedAt: '2026-09-10T09:20:00Z'));

    await tester.pumpWidget(app(listFor(dioFor(server))));
    await settle(tester);

    // Lifted out of the history like a quote, with the answer on the card.
    expect(find.text('Waiting on you'), findsOneWidget);
    expect(pill('Confirm 2.50'), findsOneWidget,
        reason: 'the server makes a send an order only when the customer approves it, and '
            'nothing on this screen used to offer that');
    expect(find.text('A rider took it. Confirm the fee of 2.50 and they will collect it.'),
        findsOneWidget);

    await tester.tap(find.text('Two boxes of books to my sister'));
    await settleRoute(tester);

    expect(find.text('A rider took it'), findsOneWidget);
    expect(find.text('Price quoted'), findsNothing, reason: 'a send is never quoted');
    expect(find.text('You confirm the fee'), findsOneWidget);
    expect(find.text('Waiting on you'), findsOneWidget,
        reason: 'the step it is waiting on is the customer\'s own');
    expect(find.text('Track order'), findsNothing);

    await tester.tap(find.text('Confirm 2.50'));
    await settle(tester);

    expect(server.approveCalls, 1, reason: 'Confirm is the approve call, as for a quote');
    expect(find.text('Confirmed'), findsOneWidget,
        reason: 'the step is finished now, and says so in its finished wording');
    expect(find.text('Track order'), findsOneWidget,
        reason: 'a confirmed send is an order — the part that could never be reached before');

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

  testWidgets('a new request does not claim steps it has not reached, in words or aloud', (
    WidgetTester tester,
  ) async {
    tall(tester);
    final Map<String, Object?> json = _errand('r1', 'Fetch a phone charger');
    final _FakeButler server = _FakeButler()..put(json);
    final SemanticsHandle semantics = tester.ensureSemantics();

    await tester.pumpWidget(app(detailsFor(dioFor(server), json)));
    await settle(tester);

    // The first cut read "A shopper took it · Price quoted · Price agreed" for a request nobody
    // had even seen yet.
    expect(find.text('A shopper took it'), findsNothing);
    expect(find.text('Price quoted'), findsNothing);
    expect(find.text('Price agreed'), findsNothing);
    expect(find.text('Waiting for a shopper'), findsOneWidget);
    expect(find.text('The shopper tells you the price'), findsOneWidget);
    expect(find.text('You agree the price'), findsOneWidget);

    // A screen reader hears where each step stands, not only its words — the dot says nothing.
    expect(find.bySemanticsLabel(RegExp(r'^Done\nRequest sent')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Now\nWaiting for a shopper')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Still to come\nYou agree the price')), findsOneWidget);

    // Nothing has been bought, so there is no goods price and no total yet.
    expect(find.text('Known once the shopper has paid'), findsOneWidget);
    expect(find.text('Total to pay'), findsNothing);

    semantics.dispose();
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

  testWidgets('No thanks on the details page asks first, and only a yes declines', (
    WidgetTester tester,
  ) async {
    tall(tester);
    final Map<String, Object?> json = quoted('q1', 'A box of paracetamol');
    final _FakeButler server = _FakeButler()..put(json);

    await tester.pumpWidget(app(detailsFor(dioFor(server), json)));
    await settle(tester);

    await tester.tap(find.text('No thanks'));
    await settle(tester);
    expect(find.text('Turn down this price?'), findsOneWidget);
    expect(server.declineCalls, 0, reason: 'it used to decline on one touch, beside Pay');

    await tester.tap(find.text('Back'));
    await settle(tester);
    expect(find.text('Turn down this price?'), findsNothing);
    expect(server.declineCalls, 0, reason: 'backing out of the question declines nothing');

    await tester.tap(find.text('No thanks'));
    await settle(tester);
    await tester.tap(find.text('Yes, decline'));
    await settle(tester);

    expect(server.declineCalls, 1);
    expect(find.text('Pay 24.90'), findsNothing);
    expect(find.text('You declined this price'), findsWidgets);
    expect(find.text('Total to pay'), findsNothing,
        reason: 'nothing is owed on a price the customer just refused');
    expect(find.text('Quoted total'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the quote card\'s No thanks asks first too', (WidgetTester tester) async {
    tall(tester);
    final _FakeButler server = _FakeButler()..put(quoted('q1', 'A box of paracetamol'));

    await tester.pumpWidget(app(listFor(dioFor(server))));
    await settle(tester);

    await tester.tap(pill('No thanks'));
    await settle(tester);
    expect(find.text('Turn down this price?'), findsOneWidget);
    expect(server.declineCalls, 0);

    await tester.tap(find.text('Yes, decline'));
    await settle(tester);
    expect(server.declineCalls, 1);

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
    expect(pill('Cancel errand'), findsNWidgets(2));

    await tester.tap(pill('Cancel errand').first);
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
    expect(pill('Cancel errand'), findsNothing,
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
    expect(find.text('Total to pay'), findsOneWidget,
        reason: 'an agreed total is exactly what is to be paid on delivery');

    await tester.tap(find.text('Track order'));
    await settleRoute(tester);

    final OrderDetailsScreen opened = tester.widget(find.byType(OrderDetailsScreen));
    expect(opened.orderId, 'order-77');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an errand that ended says how, and never shows a total to pay', (
    WidgetTester tester,
  ) async {
    tall(tester);
    Future<void> open(Map<String, Object?> json) async {
      await tester.pumpWidget(app(detailsFor(dioFor(_FakeButler()..put(json)), json)));
      await settle(tester);
    }

    // Declined: the reason, and the figure turned down under a name that does not say it is owed.
    await open(_errand('d1', 'A box of paracetamol',
        status: 'DECLINED',
        goodsCost: 22.4,
        payableTotal: 24.9,
        claimedAt: '2026-09-10T09:20:00Z',
        quotedAt: '2026-09-10T09:45:00Z',
        resolvedAt: '2026-09-10T09:50:00Z',
        declineReason: 'Too expensive'));
    expect(find.text('Reason: Too expensive'), findsOneWidget);
    expect(find.text('Quoted total'), findsOneWidget);
    expect(find.text('24.90'), findsOneWidget);
    expect(find.text('Total to pay'), findsNothing);
    expect(find.byType(YdPillButton), findsNothing, reason: 'there is nothing left to do');
    await tester.pumpWidget(const SizedBox.shrink());

    // Cancelled send: the fee is still listed, but nothing was agreed, so there is no total.
    await open(_errand('c1', 'Two boxes of books',
        mode: 'SEND',
        status: 'CANCELLED',
        pickupAddress: '8 Clemenceau Street',
        resolvedAt: '2026-09-10T09:10:00Z'));
    expect(find.text('Errand fee'), findsOneWidget);
    expect(find.text('Total to pay'), findsNothing,
        reason: 'it used to end on a bold "Total to pay 2.50" for an errand nobody will run');
    expect(find.text('Quoted total'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());

    // Expired: why, in words, and still no bill.
    await open(_errand('e1', 'Fetch a phone charger',
        status: 'EXPIRED', resolvedAt: '2026-09-10T11:00:00Z'));
    expect(find.text('Nobody picked this up'), findsWidgets);
    expect(find.text('Total to pay'), findsNothing);
    expect(find.text('Known once the shopper has paid'), findsNothing);
    expect(find.text('Cancel errand'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the page follows the errand on its own, and stops asking once it has ended', (
    WidgetTester tester,
  ) async {
    tall(tester);
    final Map<String, Object?> json = _errand('r1', 'A box of paracetamol');
    final _FakeButler server = _FakeButler()..put(json);

    await tester.pumpWidget(app(detailsFor(dioFor(server), json)));
    await settle(tester);
    expect(find.text('Pay 24.90'), findsNothing);

    // The shopper takes it, buys it and quotes — all on their own phone.
    server.errands['r1']!
      ..['status'] = 'QUOTED'
      ..['goodsCost'] = 22.4
      ..['payableTotal'] = 24.9
      ..['claimedAt'] = '2026-09-10T09:20:00Z'
      ..['quotedAt'] = '2026-09-10T09:45:00Z';
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(find.text('Pay 24.90'), findsOneWidget,
        reason: 'a quote that lands while the page is open must appear without a pull');

    // Agreed somewhere else — on another of the customer's devices.
    server.errands['r1']!
      ..['status'] = 'APPROVED'
      ..['orderId'] = 'order-r1'
      ..['resolvedAt'] = '2026-09-10T09:50:00Z';
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(find.text('Track order'), findsOneWidget);

    // Terminal now: nothing more can happen to it here, so the page stops asking.
    final int reads = server.readCalls;
    await tester.pump(const Duration(seconds: 15));
    expect(server.readCalls, reads, reason: 'an ended errand is not polled');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a change the page only saw on a poll still reloads the list on the way back', (
    WidgetTester tester,
  ) async {
    tall(tester);
    final _FakeButler server = _FakeButler()..put(_errand('r1', 'Fetch a phone charger'));

    await tester.pumpWidget(app(listFor(dioFor(server))));
    await settle(tester);
    await tester.tap(find.text('Fetch a phone charger'));
    await settleRoute(tester);
    expect(find.byType(ButlerRequestDetailsScreen), findsOneWidget);

    // A shopper takes it while the customer is reading. The customer does nothing at all.
    server.errands['r1']!
      ..['status'] = 'CLAIMED'
      ..['claimedAt'] = '2026-09-10T09:20:00Z';
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('A shopper took it'), findsOneWidget,
        reason: 'the page\'s own poll picked it up');

    // About five and a half seconds in: the list's own poll fired at five and does not fire again
    // until ten, so a load counted in the next fifty milliseconds is the pop's doing.
    final int loadsBefore = server.mineCalls;
    await tester.tap(find.byType(YdBackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(server.mineCalls, greaterThan(loadsBefore),
        reason: 'the errand moved while the page was open, so the list reloads at once');

    await settleRoute(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a tap on a busy button does not fall through and open the page mid-request', (
    WidgetTester tester,
  ) async {
    tall(tester);
    final _FakeButler server = _FakeButler()
      ..put(quoted('q1', 'A box of paracetamol'))
      ..put(_errand('r1', 'Fetch a phone charger'));

    await tester.pumpWidget(app(listFor(dioFor(server))));
    await settle(tester);

    // Pay, with the server slow to answer.
    server.hold = Completer<void>();
    await tester.tap(pill('Pay 24.90'));
    await tester.pump();
    expect(find.text('Pay 24.90'), findsNothing, reason: 'the pill has swapped to its spinner');

    // A second tap on the same spot. The pill refuses it — and the card behind must too, or it
    // opens a page that offers Pay again for a payment already on its way.
    await tester.tap(find.byType(YdPillButton).at(1));
    await settleRoute(tester);
    expect(find.byType(ButlerRequestDetailsScreen), findsNothing);

    server.hold!.complete();
    server.hold = null;
    await settle(tester);
    expect(server.approveCalls, 1);

    // The row's Cancel, the same way.
    await tester.tap(pill('Cancel errand'));
    await settle(tester);
    server.hold = Completer<void>();
    await tester.tap(find.text('Yes, cancel'));
    await settle(tester);
    expect(find.byType(YdPillButton), findsOneWidget, reason: 'only the busy Cancel is left');
    await tester.tap(find.byType(YdPillButton));
    await settleRoute(tester);
    expect(find.byType(ButlerRequestDetailsScreen), findsNothing);

    server.hold!.complete();
    server.hold = null;
    await settle(tester);
    expect(server.cancelCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('every button a customer taps here is at least 48 tall', (
    WidgetTester tester,
  ) async {
    tall(tester);
    final _FakeButler server = _FakeButler()
      ..put(quoted('q1', 'A box of paracetamol'))
      ..put(_errand('s1', 'Two boxes of books',
          mode: 'SEND',
          status: 'CLAIMED',
          pickupAddress: '8 Clemenceau Street',
          claimedAt: '2026-09-10T09:20:00Z'))
      ..put(_errand('r1', 'Fetch a phone charger'));

    await tester.pumpWidget(app(listFor(dioFor(server))));
    await settle(tester);
    for (final String label in <String>[
      'No thanks',
      'Pay 24.90',
      'Cancel',
      'Confirm 2.50',
      'Cancel errand',
    ]) {
      expect(tester.getSize(pill(label)).height, greaterThanOrEqualTo(48), reason: label);
    }
    await tester.pumpWidget(const SizedBox.shrink());

    // And the details page's bar, which has all the room it needs and used 44 anyway.
    final Map<String, Object?> json = quoted('q2', 'A box of paracetamol');
    await tester.pumpWidget(app(detailsFor(dioFor(_FakeButler()..put(json)), json)));
    await settle(tester);
    for (final String label in <String>['No thanks', 'Pay 24.90']) {
      expect(tester.getSize(pill(label)).height, greaterThanOrEqualTo(48), reason: label);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('in Arabic the chevron points the way the row opens', (WidgetTester tester) async {
    tall(tester);
    final _FakeButler server = _FakeButler()..put(_errand('r1', 'Fetch a phone charger'));

    Finder chevron(String label) =>
        find.byWidgetPredicate((Widget w) => w is Icon && w.semanticLabel == label);
    Iterable<Transform> flipsUnder(Finder icon) => tester
        .widgetList<Transform>(find.descendant(of: icon, matching: find.byType(Transform)));

    await tester.pumpWidget(app(listFor(dioFor(server)), locale: const Locale('ar')));
    await settle(tester);

    final Finder rtl = chevron('عرض التفاصيل');
    expect(tester.widget<Icon>(rtl).icon, Icons.chevron_right);
    // chevron_right flips itself in RTL — exactly once. Choosing chevron_left for Arabic, as the
    // row did, flipped it a second time and pointed it back the way the customer came.
    final Iterable<Transform> flips = flipsUnder(rtl);
    expect(flips, hasLength(1));
    expect(flips.single.transform.storage[0], -1);
    await tester.pumpWidget(const SizedBox.shrink());

    await tester.pumpWidget(app(listFor(dioFor(server))));
    await settle(tester);
    expect(flipsUnder(chevron('View details')), isEmpty, reason: 'and not at all in English');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('every status badge can be read on its own fill', () {
    // A 12px word, so WCAG's 4.5:1. The first cut wrote each status in its accent on that
    // accent's tint: amber measured 1.96, green 2.27, the ended grey 2.33.
    final DeliveryStrings t = lookupDeliveryStrings(const Locale('en'));
    for (final String mode in <String>['BUY', 'SEND']) {
      for (final ButlerStatus s in ButlerStatus.values) {
        final ButlerStatusLook look = butlerStatusOf(
            ButlerRequest.fromJson(_errand('x', 'y', mode: mode, status: s.wireValue)), t);
        final Color fill = Color.alphaBlend(look.fill, DeliveryColors.white);
        expect(_contrast(look.text, fill), greaterThanOrEqualTo(4.5),
            reason: '$mode ${s.name}: "${look.label}"');
      }
    }
  });

  testWidgets('a rider who took a send is told to wait for the customer, not to go and run it', (
    WidgetTester tester,
  ) async {
    tall(tester);
    final _FakeButler server = _FakeButler()
      ..put(_errand('s1', 'Two boxes of books',
          mode: 'SEND',
          status: 'CLAIMED',
          pickupAddress: '8 Clemenceau Street',
          claimedAt: '2026-09-10T09:20:00Z'));

    await tester.pumpWidget(app(Scaffold(body: RiderButlerBoard(api: ButlerApi(dioFor(server))))));
    await settle(tester);

    expect(find.text('Waiting on them to approve. Do not deliver until they do.'), findsOneWidget);
    expect(find.text('Collect it and drop it off. It is in your Deliveries tab.'), findsNothing,
        reason: 'there is no order to collect against until the customer confirms');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
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
  String? declineReason,
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
      'declineReason': declineReason,
      'createdAt': '2026-09-10T09:00:00Z',
      'claimedAt': claimedAt,
      'quotedAt': quotedAt,
      'resolvedAt': resolvedAt,
    };

/// A stand-in for the Butler endpoints: no socket, so nothing races the widget test's clock. The
/// actions move the errand the way the server's machine does; anything else (the order screen's
/// own reads) is a 404, which that screen already handles.
class _FakeButler implements HttpClientAdapter {
  final Map<String, Map<String, Object?>> errands = <String, Map<String, Object?>>{};
  int mineCalls = 0;
  int readCalls = 0;
  int approveCalls = 0;
  int declineCalls = 0;
  int cancelCalls = 0;

  /// While set, every action waits on it — a server slow to answer, so the busy state can be
  /// looked at.
  Completer<void>? hold;

  void put(Map<String, Object?> errand) => errands[errand['id']! as String] = errand;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    final List<String> path = options.uri.pathSegments;
    if (path.length < 3 || path[0] != 'api' || path[1] != 'butler') return _notFound();

    if (path.length == 3 && <String>['mine', 'available', 'claimed'].contains(path[2])) {
      if (path[2] == 'mine') mineCalls++;
      // The rider's two lists: the open board, and what they have taken.
      final List<Map<String, Object?>> rows = errands.values
          .where((Map<String, Object?> e) => switch (path[2]) {
                'available' => e['status'] == 'REQUESTED',
                'claimed' => e['status'] != 'REQUESTED',
                _ => true,
              })
          .toList();
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

    final Completer<void>? gate = hold;
    if (gate != null) await gate.future;

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
