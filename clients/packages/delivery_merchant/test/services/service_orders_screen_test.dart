import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:delivery_merchant/src/services/service_order_steps.dart';
import 'package:delivery_merchant/src/services/service_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'svc_test_kit.dart';

/// The services shop's order queue (Figma 126:200): what each tab holds, what a card says, and that a
/// shop can do to an order exactly what the server offers — decline with a reason, accept into
/// production, collected at the counter, cancel an uncollected pickup once its time is up — and is
/// told plainly when the server refused.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  setUpAll(() => svcUseLbpRate(90000));

  Future<void> openInProgress(WidgetTester tester, int count) async {
    await tester.tap(find.text('${en.svcTabInProgress} ($count)'));
    await tester.pump();
  }

  testWidgets('shows a spinner until the queue arrives, and asks for service orders only',
      (WidgetTester tester) async {
    final FakeServiceOrders api = FakeServiceOrders(<DeliveryOrder>[])
      ..holdList = Completer<void>();
    await pumpSvc(tester, ServiceOrdersScreen(api: api));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(api.lastKind, OrderKind.service, reason: 'a goods shop\'s orders are not this queue\'s');

    api.holdList!.complete();
    await svcSettle(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(en.svcNoNewOrders), findsOneWidget);
  });

  testWidgets('a queue that cannot be read says so, and Try again reads it again',
      (WidgetTester tester) async {
    final FakeServiceOrders api = FakeServiceOrders(<DeliveryOrder>[])
      ..failList = Exception('gateway down');
    await pumpSvc(tester, ServiceOrdersScreen(api: api));

    expect(find.text(en.couldNotLoadOrdersShort), findsOneWidget);

    api
      ..failList = null
      ..orders = <DeliveryOrder>[svcOrder()];
    await tester.tap(find.text(en.tryAgain));
    await svcSettle(tester);

    expect(find.text(en.couldNotLoadOrdersShort), findsNothing);
    expect(find.text('Jean-Pierre D.'), findsOneWidget);
  });

  testWidgets('the tabs count New, In progress and Completed from one list',
      (WidgetTester tester) async {
    final FakeServiceOrders api = FakeServiceOrders(<DeliveryOrder>[
      svcOrder(id: '10000001-0', status: 'PLACED'),
      svcOrder(id: '10000002-0', status: 'ACCEPTED', actions: const <String>[]),
      svcOrder(id: '10000003-0', status: 'PREPARING', actions: const <String>['READY']),
      svcOrder(id: '10000004-0', status: 'READY', actions: const <String>[]),
      svcOrder(id: '10000005-0', status: 'DELIVERED', actions: const <String>[]),
      svcOrder(
        id: '10000006-0',
        status: 'CANCELLED',
        actions: const <String>[],
        cancelReason: 'PROVIDER_DECLINED: TOO_BUSY',
      ),
    ]);
    await pumpSvc(tester, ServiceOrdersScreen(api: api));

    expect(find.text('${en.svcTabNew} (1)'), findsOneWidget);
    expect(find.text('${en.svcTabInProgress} (3)'), findsOneWidget);
    expect(find.text(en.svcTabCompleted), findsOneWidget);
    expect(find.text(en.svcChipNew), findsOneWidget);

    await tester.tap(find.text(en.svcTabCompleted));
    await tester.pump();

    // A pickup that ended is a collection, and a decline says so and why.
    expect(find.text(en.svcChipCollected), findsOneWidget);
    expect(find.text(en.svcChipDeclined), findsOneWidget);
    expect(find.text(en.svcDeclineTooBusy), findsOneWidget);
  });

  testWidgets(
      'a card names the customer, the job in packs of the offer\'s pack, and what the shop earns '
      'with its LBP at the platform rate', (WidgetTester tester) async {
    final FakeServiceOrders api =
        FakeServiceOrders(<DeliveryOrder>[svcOrder(subtotal: 16, total: 19)]);
    await pumpSvc(tester, ServiceOrdersScreen(api: api));

    expect(find.text('Jean-Pierre D.'), findsOneWidget);
    expect(find.text('Business Card Printing'), findsOneWidget);
    // Two packs of 500.
    expect(find.text('1,000 cards · Matte finish'), findsOneWidget);
    // The subtotal, not the total with a delivery fee the shop never receives.
    expect(find.text(r'$16.00'), findsOneWidget);
    // Computed, never typed: the frame printed 1,350,000 LBP beside $16.00, which is 1,440,000.
    expect(find.text('1,440,000 LBP'), findsOneWidget);
    expect(find.text(MarketRates.instance.lbp(16)!), findsOneWidget);
    expect(find.text(en.svcChipPickup), findsOneWidget);
  });

  testWidgets('Accept takes a new order into production and says when it is promised',
      (WidgetTester tester) async {
    final DateTime promised = DateTime.now().add(const Duration(days: 2));
    final FakeServiceOrders api = FakeServiceOrders(<DeliveryOrder>[svcOrder()]);
    api.onAct = (String id, OrderAction action) {
      final DeliveryOrder moved = svcOrder(
        status: 'PREPARING',
        actions: const <String>['READY'],
        estimatedReadyAt: promised,
      );
      api.orders = <DeliveryOrder>[moved];
      return moved;
    };
    await pumpSvc(tester, ServiceOrdersScreen(api: api));

    await tester.tap(find.text(en.svcAcceptOrder));
    await svcSettle(tester);

    expect(api.calls, contains('act ACCEPT 11111111-0000'));
    final String when = svcWhenFormatter(tester.element(find.byType(ServiceOrdersScreen)))(promised);
    expect(find.text(en.svcAcceptedReadyBy(when)), findsOneWidget);

    await openInProgress(tester, 1);
    expect(find.text(en.svcChipInProduction), findsOneWidget);
    expect(find.text(en.svcReadyBy(when)), findsOneWidget);
    expect(find.text(en.actionMarkReady), findsOneWidget);
  });

  testWidgets('Decline asks why, sends nothing without a reason, and sends the one picked',
      (WidgetTester tester) async {
    final FakeServiceOrders api = FakeServiceOrders(<DeliveryOrder>[svcOrder()]);
    api.onDecline = (String id, DeclineReason reason) => ServiceOrderUpdated(svcOrder(
          status: 'CANCELLED',
          actions: const <String>[],
          cancelReason: reason.cancelReason,
        ));
    await pumpSvc(tester, ServiceOrdersScreen(api: api));

    await tester.tap(find.text(en.svcDecline));
    await tester.pumpAndSettle();
    expect(find.text(en.svcDeclineTitle), findsOneWidget);

    await tester.tap(find.text(en.svcDeclineConfirm));
    await tester.pumpAndSettle();
    expect(find.text(en.svcDeclineTitle), findsOneWidget, reason: 'no reason, no decline');
    expect(api.calls.where((String c) => c.startsWith('decline')), isEmpty);

    await tester.tap(find.text(en.svcDeclineTooBusy));
    await tester.pump();
    await tester.tap(find.text(en.svcDeclineConfirm));
    await tester.pumpAndSettle();

    expect(api.calls, contains('decline TOO_BUSY 11111111-0000'));
    expect(find.text(en.svcOrderDeclined), findsOneWidget);
  });

  testWidgets('a decline refused because the order was accepted meanwhile says so and reads again',
      (WidgetTester tester) async {
    final FakeServiceOrders api = FakeServiceOrders(<DeliveryOrder>[svcOrder()]);
    api.onDecline = (String id, DeclineReason reason) => const ServiceOrderActionRefused(
        refusal: ServiceOrderRefusal.notDeclinable, code: 'NOT_DECLINABLE');
    await pumpSvc(tester, ServiceOrdersScreen(api: api));
    final int readsBefore = api.count('list');

    await tester.tap(find.text(en.svcDecline));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.svcDeclineCannotDo));
    await tester.pump();
    await tester.tap(find.text(en.svcDeclineConfirm));
    await tester.pumpAndSettle();

    expect(api.calls, contains('decline CANNOT_DO 11111111-0000'));
    expect(find.text(en.svcRefusedNotDeclinable), findsOneWidget);
    expect(api.count('list'), greaterThan(readsBefore));
  });

  testWidgets('a ready pickup offers Customer collected only when the server does',
      (WidgetTester tester) async {
    final FakeServiceOrders api = FakeServiceOrders(<DeliveryOrder>[
      svcOrder(id: '20000001-0', status: 'READY', actions: const <String>[]),
    ]);
    api.onCollected = (String id) => ServiceOrderUpdated(
        svcOrder(id: id, status: 'DELIVERED', actions: const <String>[]));
    await pumpSvc(tester, ServiceOrdersScreen(api: api));
    await openInProgress(tester, 1);

    expect(find.text(en.svcWaitingForPickup), findsOneWidget);
    expect(find.text(en.svcActionCollected), findsNothing,
        reason: 'the server did not offer it, so no button');

    api.orders = <DeliveryOrder>[
      svcOrder(id: '20000001-0', status: 'READY', actions: const <String>['COLLECTED']),
    ];
    await tester.tap(find.byIcon(Icons.refresh));
    await svcSettle(tester);
    await tester.tap(find.text(en.svcActionCollected));
    await svcSettle(tester);

    expect(api.calls, contains('collected 20000001-0'));
    expect(find.text(en.svcOrderCollected), findsOneWidget);
  });

  testWidgets(
      'an uncollected pickup counts down to its cancel, and the cancel is offered once the server '
      'offers it', (WidgetTester tester) async {
    final DateTime now = DateTime(2026, 9, 14, 12);
    final FakeServiceOrders api = FakeServiceOrders(<DeliveryOrder>[
      svcOrder(
        status: 'READY',
        actions: const <String>[],
        uncollectedCancellableAt: now.add(const Duration(days: 2, hours: 5)),
      ),
    ]);
    await pumpSvc(tester, ServiceOrdersScreen(api: api, clock: () => now));
    await openInProgress(tester, 1);

    expect(
      find.text('${en.svcWaitingForPickup} · '
          '${en.svcCancelNotCollectedIn(en.svcDurationDaysHours('2', '5'))}'),
      findsOneWidget,
    );
    expect(find.text(en.svcCancelNotCollected), findsNothing);

    api
      ..orders = <DeliveryOrder>[
        svcOrder(
          status: 'READY',
          actions: const <String>['CANCEL'],
          uncollectedCancellableAt: now.subtract(const Duration(minutes: 1)),
        ),
      ]
      ..onCancelNotCollected = (String id, String? note) => ServiceOrderUpdated(svcOrder(
          status: 'CANCELLED', actions: const <String>[], cancelReason: 'NOT_COLLECTED'));
    await tester.tap(find.byIcon(Icons.refresh));
    await svcSettle(tester);

    await tester.tap(find.text(en.svcCancelNotCollected));
    await tester.pumpAndSettle();
    expect(find.text(en.svcCancelNotCollectedTitle), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Waited three days');
    await tester.tap(find.widgetWithText(TextButton, en.svcCancelNotCollected));
    await tester.pumpAndSettle();

    expect(api.calls, contains('notCollected 11111111-0000 Waited three days'));
    expect(find.text(en.svcOrderCancelledNotCollected), findsOneWidget);
  });

  testWidgets('a ready delivery waits for a rider and offers the shop nothing to press',
      (WidgetTester tester) async {
    final FakeServiceOrders api = FakeServiceOrders(<DeliveryOrder>[
      svcOrder(
        status: 'READY',
        fulfilment: 'DELIVERY',
        actions: const <String>[],
        address: 'Mar Mikhael, Beirut',
      ),
    ]);
    await pumpSvc(tester, ServiceOrdersScreen(api: api));
    await openInProgress(tester, 1);

    expect(find.text(en.svcWaitingForRider), findsOneWidget);
    expect(find.text(en.svcChipDelivery), findsOneWidget);
    expect(find.byType(SvcStepButton), findsNothing);
  });

  testWidgets('a new order with long names fits a 320dp phone', (WidgetTester tester) async {
    final FakeServiceOrders api = FakeServiceOrders(<DeliveryOrder>[
      svcOrder(
        customer: 'Jean-Pierre Dupont-Aznavourian',
        product: 'Corporate brochure design and full colour offset printing, folded and trimmed',
        options: 'Silk 170gsm, tri-fold, spot UV on the cover, rounded corners',
        subtotal: 1250,
      ),
    ]);
    await pumpSvc(tester, ServiceOrdersScreen(api: api), size: const Size(320, 900));

    expect(tester.takeException(), isNull);
    expect(find.text(en.svcAcceptOrder), findsOneWidget);
    expect(find.text(en.svcDecline), findsOneWidget);
  });

  testWidgets('the queue reads right to left in Arabic, with no English left on it',
      (WidgetTester tester) async {
    final FakeServiceOrders api = FakeServiceOrders(<DeliveryOrder>[
      svcOrder(
        customer: 'جان بيار د.',
        product: 'طباعة بطاقات عمل',
        unitLabel: 'بطاقة',
        options: 'ورق مطفي',
      ),
      svcOrder(
        id: '30000002-0',
        status: 'READY',
        actions: const <String>['COLLECTED'],
        customer: 'سارة ك.',
        product: 'طباعة لافتة',
        unitLabel: 'متر مربع',
        unitSize: 1,
        options: null,
        uncollectedCancellableAt: DateTime.now().add(const Duration(hours: 30)),
      ),
    ]);
    await pumpSvc(tester, ServiceOrdersScreen(api: api),
        locale: const Locale('ar'), size: const Size(320, 1200));

    expect(Directionality.of(tester.element(find.byType(ServiceOrdersScreen))), TextDirection.rtl);
    expect(tester.takeException(), isNull);
    expect(find.text(ar.svcIncomingOrders), findsOneWidget);
    expect(find.text(ar.svcAcceptOrder), findsOneWidget);
    expect(svcLatinText(tester), isEmpty);

    await tester.tap(find.text('${ar.svcTabInProgress} (1)'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(ar.svcActionCollected), findsOneWidget);
    expect(svcLatinText(tester), isEmpty);
  });
}
