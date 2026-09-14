import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart' show ShopThreadScreen;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/order_tracking_panel.dart';
import 'package:mobile_app/src/service_order_tracking_screen.dart';
import 'package:mobile_app/src/service_order_words.dart';

import 'service_fixtures.dart';

/// Tracking a service order (Figma 126:507), and the words every service order screen shares.
///
/// What these pin is what the frame got wrong and what it left out: the order's own reference instead
/// of "#8842", the shop instead of "Support Representative", a timeline that follows how the work is
/// collected, and an order that ended early told honestly — declined with the provider's reason, never
/// collected, or cancelled — with no promise left on screen for work that is not going to happen.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  DeliveryOrder order({
    String status = 'PREPARING',
    String fulfilment = 'PICKUP',
    String? cancelReason,
  }) =>
      DeliveryOrder.fromJson(
          serviceOrderJson(status: status, fulfilment: fulfilment, cancelReason: cancelReason));

  List<OrderStatusChange> history(List<String> statuses) =>
      historyJson(statuses).map(OrderStatusChange.maybeFromJson).whereType<OrderStatusChange>().toList();

  List<(String, ServiceStepState)> rows(List<ServiceTimelineStep> steps) =>
      steps.map((ServiceTimelineStep s) => (s.label, s.state)).toList();

  group('the timeline', () {
    test('a pickup in production has placed and accepted behind it, and collection ahead', () {
      expect(
        rows(serviceTimeline(order(), history(<String>['PLACED', 'ACCEPTED', 'PREPARING']), en)),
        <(String, ServiceStepState)>[
          (en.svcTimelinePlaced, ServiceStepState.done),
          (en.svcTimelineAccepted, ServiceStepState.done),
          (en.svcTimelineInProduction, ServiceStepState.current),
          (en.svcStatusReadyPickup, ServiceStepState.pending),
          (en.svcStatusCollected, ServiceStepState.pending),
        ],
      );
    });

    test('a delivery passes "Out for delivery" before it is delivered', () {
      expect(
        rows(serviceTimeline(
            order(status: 'PICKED_UP', fulfilment: 'DELIVERY'),
            history(<String>['PLACED', 'ACCEPTED', 'PREPARING', 'READY', 'PICKED_UP']),
            en)),
        <(String, ServiceStepState)>[
          (en.svcTimelinePlaced, ServiceStepState.done),
          (en.svcTimelineAccepted, ServiceStepState.done),
          (en.svcTimelineInProduction, ServiceStepState.done),
          (en.svcStatusReadyDelivery, ServiceStepState.done),
          (en.svcTimelineOutForDelivery, ServiceStepState.current),
          (en.stepDelivered, ServiceStepState.pending),
        ],
      );
    });

    test('a collected pickup is done all the way through', () {
      expect(
        serviceTimeline(order(status: 'DELIVERED'),
                history(<String>['PLACED', 'ACCEPTED', 'PREPARING', 'READY', 'DELIVERED']), en)
            .map((ServiceTimelineStep s) => s.state),
        everyElement(ServiceStepState.done),
      );
    });

    test('a declined order stops where it was declined, with the reason in the reader\'s words', () {
      final DeliveryOrder declined =
          order(status: 'CANCELLED', cancelReason: 'PROVIDER_DECLINED: FILE_PROBLEM');
      final List<OrderStatusChange> steps = history(<String>['PLACED', 'CANCELLED']);

      expect(rows(serviceTimeline(declined, steps, en)), <(String, ServiceStepState)>[
        (en.svcTimelinePlaced, ServiceStepState.done),
        (en.svcDeclinedReason(en.svcDeclineFileProblem), ServiceStepState.stopped),
      ]);
      expect(serviceTimeline(declined, steps, ar).last.label,
          ar.svcDeclinedReason(ar.svcDeclineFileProblem));
    });

    test('a pickup nobody came for keeps the steps it reached and then says it was not collected', () {
      expect(
        rows(serviceTimeline(
            order(status: 'CANCELLED', cancelReason: 'NOT_COLLECTED: waited three days'),
            history(<String>['PLACED', 'ACCEPTED', 'PREPARING', 'READY', 'CANCELLED']),
            en)),
        <(String, ServiceStepState)>[
          (en.svcTimelinePlaced, ServiceStepState.done),
          (en.svcTimelineAccepted, ServiceStepState.done),
          (en.svcTimelineInProduction, ServiceStepState.done),
          (en.svcStatusReadyPickup, ServiceStepState.done),
          (en.svcTimelineNotCollected, ServiceStepState.stopped),
        ],
      );
    });

    test('the customer\'s own cancellation is a plain cancellation, not a decline', () {
      expect(
        rows(serviceTimeline(order(status: 'CANCELLED', cancelReason: 'Cancelled by customer'),
            history(<String>['PLACED', 'CANCELLED']), en)),
        <(String, ServiceStepState)>[
          (en.svcTimelinePlaced, ServiceStepState.done),
          (en.statusCancelled, ServiceStepState.stopped),
        ],
      );
    });
  });

  test('the status reads by fulfilment, and a cancellation by what ended it', () {
    expect(serviceStatusLabel(order(status: 'PLACED'), en), en.svcStatusWaiting);
    expect(serviceStatusLabel(order(status: 'READY'), en), en.svcStatusReadyPickup);
    expect(serviceStatusLabel(order(status: 'READY', fulfilment: 'DELIVERY'), en),
        en.svcStatusReadyDelivery);
    expect(serviceStatusLabel(order(status: 'DELIVERED'), en), en.svcStatusCollected);
    expect(serviceStatusLabel(order(status: 'DELIVERED', fulfilment: 'DELIVERY'), en),
        en.svcStatusCompleted);
    expect(
        serviceStatusLabel(
            order(status: 'CANCELLED', cancelReason: 'PROVIDER_DECLINED: TOO_BUSY'), en),
        en.svcStatusDeclined);
    expect(serviceStatusLabel(order(status: 'CANCELLED', cancelReason: 'NOT_COLLECTED'), en),
        en.svcStatusNotCollected);
    expect(serviceStatusLabel(order(status: 'CANCELLED', cancelReason: 'Cancelled by customer'), en),
        en.statusCancelled);
  });

  testWidgets('a promise reads as today, tomorrow, or its date — in the reader\'s clock',
      (WidgetTester tester) async {
    final DateTime now = DateTime(2026, 9, 14, 10);
    late String today, tomorrow, later, time;
    await tester.pumpWidget(svcApp(Builder(builder: (BuildContext context) {
      today = serviceWhenLabel(context, DateTime(2026, 9, 14, 17), now: now);
      tomorrow = serviceWhenLabel(context, DateTime(2026, 9, 15, 14), now: now);
      later = serviceWhenLabel(context, DateTime(2026, 9, 17, 9, 30), now: now);
      time = MaterialLocalizations.of(context).formatTimeOfDay(const TimeOfDay(hour: 14, minute: 0));
      return const SizedBox();
    })));

    expect(today, en.svcTodayAt('5:00 PM'));
    expect(tomorrow, en.svcTomorrowAt(time));
    expect(later, startsWith('Thu'));
    expect(later, endsWith('9:30 AM'));
  });

  group('the screen', () {
    FakeServer serve({
      required FutureOr<Object?> Function() order,
      List<String> history = const <String>['PLACED', 'ACCEPTED', 'PREPARING'],
    }) =>
        FakeServer()
          ..on('GET', '/api/orders/$svcOrderId', (_) => order())
          ..on('GET', '/api/orders/$svcOrderId/history', (_) => historyJson(history))
          ..on('GET', '/api/stores/s1',
              (_) => storeJson(address: '12 Armenia Street, Mar Mikhael'))
          ..on('GET', '/api/stores/s1/hours', (_) => <Map<String, dynamic>>[
                for (int day = 1; day <= 7; day++)
                  <String, dynamic>{'dayOfWeek': day, 'opensAt': '09:00:00', 'closesAt': '18:00:00'},
              ]);

    Future<void> pump(
      WidgetTester tester,
      FakeServer server, {
      Locale locale = const Locale('en'),
      ShopChatApi? chat,
      Size size = const Size(390, 2400),
      bool settle = true,
    }) async {
      phone(tester, size: size);
      await tester.pumpWidget(svcApp(
        ServiceOrderTrackingScreen(
          orderApi: OrderApi(server.dio),
          storeApi: StoreApi(server.dio),
          orderId: svcOrderId,
          shopChatApi: chat,
        ),
        locale: locale,
      ));
      if (settle) await tester.pumpAndSettle();
    }

    List<ServiceStepState> dots(WidgetTester tester) => tester
        .widgetList<ServiceTimelineRow>(find.byType(ServiceTimelineRow))
        .map((ServiceTimelineRow row) => row.step.state)
        .toList();

    testWidgets('waits on a spinner until the order arrives', (WidgetTester tester) async {
      final Completer<Object?> answer = Completer<Object?>();
      await pump(tester, serve(order: () => answer.future), settle: false);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ServiceTimelineRow), findsNothing);

      answer.complete(serviceOrderJson());
      await tester.pumpAndSettle();
      expect(find.text(en.svcOrderNumber('abcd1234')), findsOneWidget);
    });

    testWidgets('an order it cannot read offers to try again, and trying again shows it',
        (WidgetTester tester) async {
      int reads = 0;
      await pump(
          tester, serve(order: () => ++reads == 1 ? const FakeReply(500) : serviceOrderJson()));

      expect(find.text(en.couldNotLoadOrder), findsOneWidget);
      await tester.tap(find.text(en.tryAgain));
      await tester.pumpAndSettle();

      expect(find.text(en.couldNotLoadOrder), findsNothing);
      expect(find.text(en.svcOrderNumber('abcd1234')), findsOneWidget);
    });

    testWidgets('an order in production: its reference, its shop, its promise and where to collect it',
        (WidgetTester tester) async {
      final DateTime now = DateTime.now();
      final DateTime tomorrow = DateTime(now.year, now.month, now.day + 1, 14);
      await pump(
          tester,
          serve(
              order: () => serviceOrderJson(
                  estimatedReadyAt: tomorrow.toUtc().toIso8601String(),
                  instructions: 'Leave a white border')));
      final MaterialLocalizations dates =
          MaterialLocalizations.of(tester.element(find.byType(ServiceOrderTrackingScreen)));
      String clock(int hour) => dates.formatTimeOfDay(TimeOfDay(hour: hour, minute: 0));

      expect(find.text(en.svcOrderNumber('abcd1234')), findsOneWidget);
      expect(find.text('Al Fakhry Press • ${en.svcCategoryPrinting}'), findsOneWidget);
      expect(find.text(en.svcStatusInProgress.toUpperCase()), findsOneWidget);
      expect(find.text(en.svcEstimatedCompletion.toUpperCase()), findsOneWidget);
      expect(find.text(en.svcTomorrowAt(clock(14))), findsOneWidget);
      expect(dots(tester), <ServiceStepState>[
        ServiceStepState.done,
        ServiceStepState.done,
        ServiceStepState.current,
        ServiceStepState.pending,
        ServiceStepState.pending,
      ]);

      // The shop, not "Support Representative", and a pickup's own details — never a rider's map.
      expect(find.text(en.svcProviderRole), findsOneWidget);
      expect(find.text('Support Representative'), findsNothing);
      expect(find.text(en.svcPickupFrom('Al Fakhry Press')), findsOneWidget);
      expect(find.text('12 Armenia Street, Mar Mikhael'), findsOneWidget);
      expect(find.text(en.svcTodayAt('${clock(9)} – ${clock(18)}')), findsOneWidget);
      expect(find.text(en.svcShowNumberAtPickup), findsOneWidget);
      expect(find.byType(OrderTrackingPanel), findsNothing);

      expect(find.text('Leave a white border'), findsOneWidget);
      expect(find.text(en.svcPayCashPickup), findsOneWidget);
      expect(find.text(en.cancelOrder), findsNothing, reason: 'only a new order can be cancelled');
    });

    testWidgets('a declined order says the provider declined and why, and promises nothing',
        (WidgetTester tester) async {
      await pump(
          tester,
          serve(
              order: () => serviceOrderJson(
                  status: 'CANCELLED', cancelReason: 'PROVIDER_DECLINED: FILE_PROBLEM'),
              history: const <String>['PLACED', 'CANCELLED']));

      expect(find.text(en.svcStatusDeclined.toUpperCase()), findsOneWidget);
      expect(find.text(en.svcDeclinedReason(en.svcDeclineFileProblem)), findsOneWidget);
      expect(find.text(en.svcEstimatedCompletion.toUpperCase()), findsNothing);
      expect(find.text(en.svcTimelineInProduction), findsNothing);
      expect(find.text(en.svcShowNumberAtPickup), findsNothing);
      expect(dots(tester), <ServiceStepState>[ServiceStepState.done, ServiceStepState.stopped]);
    });

    testWidgets('a pickup nobody came for is shown as not collected, not as a plain cancellation',
        (WidgetTester tester) async {
      await pump(
          tester,
          serve(
              order: () =>
                  serviceOrderJson(status: 'CANCELLED', cancelReason: 'NOT_COLLECTED: three days'),
              history: const <String>['PLACED', 'ACCEPTED', 'PREPARING', 'READY', 'CANCELLED']));

      expect(find.text(en.svcStatusNotCollected.toUpperCase()), findsOneWidget);
      expect(find.text(en.svcTimelineNotCollected), findsOneWidget);
      expect(find.text(en.statusCancelled.toUpperCase()), findsNothing);
    });

    testWidgets('a new order: the turnaround to expect, and Cancel, which cancels it',
        (WidgetTester tester) async {
      bool cancelled = false;
      final FakeServer server = serve(
        order: () => cancelled
            ? serviceOrderJson(status: 'CANCELLED', cancelReason: 'Cancelled by customer')
            : serviceOrderJson(status: 'PLACED', actions: const <String>['CANCEL']),
        history: const <String>['PLACED'],
      )..on('POST', '/api/orders/$svcOrderId/cancel', (_) {
          cancelled = true;
          return serviceOrderJson(status: 'CANCELLED', cancelReason: 'Cancelled by customer');
        });
      await pump(tester, server);

      expect(find.text(en.svcStatusWaiting.toUpperCase()), findsOneWidget);
      expect(find.text(en.svcEstimateAfterAccept(en.svcTurnaroundRange('24', '48'))), findsOneWidget);

      await tester.tap(find.text(en.cancelOrder));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.cancelOrder).last);
      await tester.pumpAndSettle();

      expect(server.sent('POST', '/api/orders/$svcOrderId/cancel').single.data,
          <String, dynamic>{'reason': 'Cancelled by customer'});
      expect(find.text(en.statusCancelled.toUpperCase()), findsOneWidget);
      expect(find.text(en.cancelOrder), findsNothing);
    });

    testWidgets('a delivery says where it is going, and a ready one waits without a rider map',
        (WidgetTester tester) async {
      await pump(
          tester,
          serve(
              order: () => serviceOrderJson(status: 'READY', fulfilment: 'DELIVERY', fee: 2),
              history: const <String>['PLACED', 'ACCEPTED', 'PREPARING', 'READY']));

      expect(find.text(en.svcStatusReadyDelivery.toUpperCase()), findsOneWidget);
      expect(find.text(en.svcDeliveringTo('12 Rose Street')), findsOneWidget);
      expect(find.text(en.svcTimelineOutForDelivery), findsOneWidget);
      expect(find.text(en.svcShowNumberAtPickup), findsNothing);
      expect(find.text(en.svcReadyByCaption.toUpperCase()), findsNothing,
          reason: 'the work is ready: there is nothing left to promise');
      expect(find.byType(OrderTrackingPanel), findsNothing);
      expect(find.text(en.svcPayCashDelivery), findsOneWidget);
    });

    testWidgets('chat with the shop is drawn only with the shop chat client, and opens its thread',
        (WidgetTester tester) async {
      final FakeServer server = serve(order: () => serviceOrderJson());
      await pump(tester, server);
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);

      final SemanticsHandle semantics = tester.ensureSemantics();
      await pump(tester, server, chat: ShopChatApi(server.dio));
      expect(find.bySemanticsLabel(en.chatShopWith('Al Fakhry Press')), findsOneWidget);
      semantics.dispose();

      await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ShopThreadScreen), findsOneWidget);
      expect(server.sent('POST', '/api/chat/stores/s1/thread'), hasLength(1));
    });

    testWidgets('reads right to left in Arabic', (WidgetTester tester) async {
      await pump(tester, serve(order: () => serviceOrderJson()), locale: const Locale('ar'));

      expect(find.text(ar.svcTrackTitle), findsOneWidget);
      expect(find.text(ar.svcTimelineInProduction), findsOneWidget);
      expect(find.text(ar.svcProviderRole), findsOneWidget);
      final Finder firstRow = find.byType(ServiceTimelineRow).first;
      expect(Directionality.of(tester.element(firstRow)), TextDirection.rtl);
      // The dot leads the label, which in Arabic puts it on the right.
      final Rect dot = tester.getRect(find.descendant(of: firstRow, matching: find.byType(Container)).first);
      final Rect label = tester.getRect(find.text(ar.svcTimelinePlaced));
      expect(dot.left, greaterThan(label.left));
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a 320dp phone with a long shop name and a long reason',
        (WidgetTester tester) async {
      await pump(
        tester,
        serve(
            order: () => serviceOrderJson(
                status: 'CANCELLED',
                cancelReason: 'PROVIDER_DECLINED: CANNOT_DO',
                storeName: 'Al Fakhry Press and Copy Centre of Greater Mar Mikhael'),
            history: const <String>['PLACED', 'CANCELLED']),
        chat: ShopChatApi(FakeServer().dio),
        size: const Size(320, 1600),
      );

      expect(find.text(en.svcDeclinedReason(en.svcDeclineCannotDo)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
