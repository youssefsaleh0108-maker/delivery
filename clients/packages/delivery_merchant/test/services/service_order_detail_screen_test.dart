import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:delivery_merchant/src/services/service_order_steps.dart';
import 'package:delivery_merchant/src/services/service_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'svc_test_kit.dart';

/// One service order in full, for the shop: the customer's own words under the shop's question, when
/// the work is promised, the customer's files opened from links that work, the shop's conversations,
/// and a refused step said plainly.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  setUpAll(() => svcUseLbpRate(90000));

  OrderAttachment pdf({String url = 'https://files.example/one?sig=a', DateTime? expires}) =>
      OrderAttachment(
        fileId: 'file-1',
        contentType: 'application/pdf',
        url: url,
        sizeBytes: 2400000,
        urlExpiresAt: expires,
      );

  testWidgets('the job, the customer\'s instructions under the shop\'s question, and the promise',
      (WidgetTester tester) async {
    final DateTime promised = DateTime.now().add(const Duration(days: 1));
    final DeliveryOrder order = svcOrder(
      status: 'PREPARING',
      actions: const <String>['READY'],
      estimatedReadyAt: promised,
      prompt: 'Which names go on the cards?',
      instructions: 'Rana Haddad, Ziad Khoury',
    );
    final FakeServiceOrders api = FakeServiceOrders(<DeliveryOrder>[order]);
    await pumpSvc(tester, ServiceOrderDetailScreen(api: api, order: order));
    await svcSettle(tester);

    expect(find.text(en.svcOrderTitle('11111111')), findsOneWidget);
    expect(find.text('1,000 cards · Matte finish'), findsOneWidget);
    expect(find.text('Which names go on the cards?'), findsOneWidget);
    expect(find.text('Rana Haddad, Ziad Khoury'), findsOneWidget);
    expect(find.text(en.svcFulfilmentPickupDetail), findsOneWidget);
    final String when =
        svcWhenFormatter(tester.element(find.byType(ServiceOrderDetailScreen)))(promised);
    expect(find.text('${en.svcEstimatedReady}: $when'), findsOneWidget);
    expect(find.text(en.actionMarkReady), findsOneWidget);
    expect(api.calls, contains('read 11111111-0000'), reason: 'the queue\'s copy may be stale');
  });

  testWidgets('a new order says how long the work takes once accepted, and what nobody wrote',
      (WidgetTester tester) async {
    final DeliveryOrder order = svcOrder();
    await pumpSvc(tester,
        ServiceOrderDetailScreen(api: FakeServiceOrders(<DeliveryOrder>[order]), order: order));
    await svcSettle(tester);

    expect(find.text(en.svcTurnaroundAfterAccept(en.svcTurnaround1to2)), findsOneWidget);
    expect(find.text(en.svcNoInstructions), findsOneWidget);
  });

  testWidgets('a customer\'s file opens from its link, and an expired link is fetched afresh first',
      (WidgetTester tester) async {
    final DeliveryOrder order = svcOrder();
    final FakeOrderFiles files = FakeOrderFiles(<OrderAttachment>[
      pdf(expires: DateTime.now().subtract(const Duration(minutes: 1))),
    ]);
    final List<Uri> opened = <Uri>[];
    await pumpSvc(
      tester,
      ServiceOrderDetailScreen(
        api: FakeServiceOrders(<DeliveryOrder>[order]),
        order: order,
        files: files,
        openLink: (Uri link) async {
          opened.add(link);
          return true;
        },
      ),
    );
    await svcSettle(tester);

    expect(find.text('${en.svcFileDocument} · ${en.svcFileSizeMb('2.3')}'), findsOneWidget);

    files.files = <OrderAttachment>[
      pdf(url: 'https://files.example/one?sig=b', expires: DateTime.now().add(const Duration(minutes: 5))),
    ];
    await tester.tap(find.text(en.svcOpenFile));
    await svcSettle(tester);

    expect(files.reads, 2, reason: 'the held link had expired');
    expect(opened, <Uri>[Uri.parse('https://files.example/one?sig=b')]);
  });

  testWidgets('a link that runs out within the minute is fetched afresh before it is opened',
      (WidgetTester tester) async {
    final DeliveryOrder order = svcOrder();
    final FakeOrderFiles files = FakeOrderFiles(<OrderAttachment>[
      pdf(expires: DateTime.now().add(const Duration(seconds: 30))),
    ]);
    final List<Uri> opened = <Uri>[];
    await pumpSvc(
      tester,
      ServiceOrderDetailScreen(
        api: FakeServiceOrders(<DeliveryOrder>[order]),
        order: order,
        files: files,
        openLink: (Uri link) async {
          opened.add(link);
          return true;
        },
      ),
    );
    await svcSettle(tester);

    files.files = <OrderAttachment>[
      pdf(url: 'https://files.example/one?sig=b', expires: DateTime.now().add(const Duration(minutes: 5))),
    ];
    await tester.tap(find.text(en.svcOpenFile));
    await svcSettle(tester);

    expect(files.reads, 2, reason: 'thirty seconds left is not a link to hand over');
    expect(opened, <Uri>[Uri.parse('https://files.example/one?sig=b')]);
  });

  testWidgets('a link that cannot be fetched afresh is not opened dead, and the shop is told',
      (WidgetTester tester) async {
    final DeliveryOrder order = svcOrder();
    final FakeOrderFiles files = FakeOrderFiles(<OrderAttachment>[
      pdf(expires: DateTime.now().subtract(const Duration(minutes: 1))),
    ]);
    final List<Uri> opened = <Uri>[];
    await pumpSvc(
      tester,
      ServiceOrderDetailScreen(
        api: FakeServiceOrders(<DeliveryOrder>[order]),
        order: order,
        files: files,
        openLink: (Uri link) async {
          opened.add(link);
          return true;
        },
      ),
    );
    await svcSettle(tester);

    files.fail = Exception('storage down');
    await tester.tap(find.text(en.svcOpenFile));
    await svcSettle(tester);

    expect(opened, isEmpty);
    expect(find.text(en.svcFileLinkRefreshFailed), findsOneWidget);
  });

  testWidgets(
      'a second tap while a step is out sends nothing more, and the buttons wait for the order to be '
      'read back', (WidgetTester tester) async {
    final DeliveryOrder order = svcOrder(status: 'PREPARING', actions: const <String>['READY']);
    final FakeServiceOrders api = FakeServiceOrders(<DeliveryOrder>[order])
      ..holdAct = Completer<void>();
    api.onAct = (String id, OrderAction action) {
      final DeliveryOrder moved = svcOrder(status: 'READY', actions: const <String>['COLLECTED']);
      api.orders = <DeliveryOrder>[moved];
      return moved;
    };
    await pumpSvc(tester, ServiceOrderDetailScreen(api: api, order: order));
    await svcSettle(tester);

    await tester.tap(find.text(en.actionMarkReady));
    await tester.tap(find.text(en.actionMarkReady));
    await tester.pump();
    expect(api.calls.where((String c) => c.startsWith('act ')), hasLength(1));

    api.holdRead = Completer<void>();
    api.holdAct!.complete();
    await svcSettle(tester);
    expect(find.text(en.svcActionCollected), findsNothing);
    expect(
      find.descendant(
          of: find.byType(SvcStepButton), matching: find.byType(CircularProgressIndicator)),
      findsOneWidget,
      reason: 'answered, but not read back yet',
    );

    api.holdRead!.complete();
    await svcSettle(tester);
    expect(find.text(en.svcActionCollected), findsOneWidget);
  });

  testWidgets('files that cannot be read say so, and Try again reads them again',
      (WidgetTester tester) async {
    final DeliveryOrder order = svcOrder();
    final FakeOrderFiles files = FakeOrderFiles(<OrderAttachment>[pdf()])
      ..fail = Exception('storage down');
    await pumpSvc(
      tester,
      ServiceOrderDetailScreen(
          api: FakeServiceOrders(<DeliveryOrder>[order]), order: order, files: files),
    );
    await svcSettle(tester);

    expect(find.text(en.svcFilesLoadFailed), findsOneWidget);

    files.fail = null;
    await tester.tap(find.text(en.tryAgain));
    await svcSettle(tester);

    expect(find.text(en.svcFilesLoadFailed), findsNothing);
    expect(find.text(en.svcOpenFile), findsOneWidget);
  });

  testWidgets('files still loading show a spinner; none sent is said; no files client, no section',
      (WidgetTester tester) async {
    final DeliveryOrder order = svcOrder();
    final FakeOrderFiles files = FakeOrderFiles(<OrderAttachment>[])..hold = Completer<void>();
    await pumpSvc(
      tester,
      ServiceOrderDetailScreen(
          api: FakeServiceOrders(<DeliveryOrder>[order]), order: order, files: files),
    );

    expect(find.text(en.svcCustomerFiles), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    files.hold!.complete();
    await svcSettle(tester);
    expect(find.text(en.svcNoFiles), findsOneWidget);

    await pumpSvc(tester,
        ServiceOrderDetailScreen(api: FakeServiceOrders(<DeliveryOrder>[order]), order: order));
    await svcSettle(tester);
    expect(find.text(en.svcCustomerFiles), findsNothing);
  });

  group('Chat with customer', () {
    String dayOf(WidgetTester tester, DateTime at) =>
        MaterialLocalizations.of(tester.element(find.byType(ServiceOrderDetailScreen)))
            .formatShortMonthDay(at);

    testWidgets('is there only with the shop\'s conversations, and opens this order\'s own thread',
        (WidgetTester tester) async {
      final DeliveryOrder order = svcOrder();
      await pumpSvc(tester,
          ServiceOrderDetailScreen(api: FakeServiceOrders(<DeliveryOrder>[order]), order: order));
      await svcSettle(tester);
      expect(find.text(en.svcChatWithCustomer), findsNothing);

      final FakeShopChat chat = FakeShopChat();
      await pumpSvc(
        tester,
        ServiceOrderDetailScreen(
          api: FakeServiceOrders(<DeliveryOrder>[order]),
          order: order,
          shopChat: chat,
        ),
      );
      await svcSettle(tester);
      await tester.tap(find.text(en.svcChatWithCustomer));
      await tester.pumpAndSettle();

      expect(chat.opened, <String>['11111111-0000']);
      expect(find.byType(ShopInboxScreen), findsNothing, reason: 'this order\'s thread, not every one');
      expect(tester.widget<ShopThreadScreen>(find.byType(ShopThreadScreen)).thread?.orderId,
          '11111111-0000');
      // The thread screen the inbox opens: the customer by name, over the order it is about.
      expect(find.text('Jean-Pierre D.'), findsOneWidget);
      expect(find.text(shopThreadOrderLabel(chat.threadFor('11111111-0000'), en)!), findsOneWidget);
    });

    testWidgets('a second tap while the thread is being opened asks nothing more, and the button spins',
        (WidgetTester tester) async {
      final DeliveryOrder order = svcOrder();
      final FakeShopChat chat = FakeShopChat()..holdOpen = Completer<void>();
      await pumpSvc(
        tester,
        ServiceOrderDetailScreen(
            api: FakeServiceOrders(<DeliveryOrder>[order]), order: order, shopChat: chat),
      );
      await svcSettle(tester);
      final Offset button = tester.getCenter(find.text(en.svcChatWithCustomer));

      await tester.tapAt(button);
      await tester.tapAt(button);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tapAt(button);
      await tester.pump();
      expect(chat.opened, hasLength(1));

      chat.holdOpen!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ShopThreadScreen), findsOneWidget);
      expect(chat.opened, hasLength(1));
    });

    testWidgets(
        'closed (409) says when chat about the order closed, draws no button, and leaves the order\'s '
        'steps as they were', (WidgetTester tester) async {
      // In production and long overdue: the shop's window can close on an order that is still open.
      final DeliveryOrder order = svcOrder(
        status: 'PREPARING',
        actions: const <String>['READY'],
        estimatedReadyAt: DateTime(2026, 9, 5, 18),
      );
      final FakeServiceOrders api = FakeServiceOrders(<DeliveryOrder>[order]);
      api.onAct = (String id, OrderAction action) {
        final DeliveryOrder moved = svcOrder(status: 'READY', actions: const <String>['COLLECTED']);
        api.orders = <DeliveryOrder>[moved];
        return moved;
      };
      final DateTime closedAt = DateTime(2026, 9, 12, 18);
      final FakeShopChat chat = FakeShopChat()..failOpen = ShopOrderChatClosedException(closedAt);
      await pumpSvc(
        tester,
        ServiceOrderDetailScreen(
            api: api, order: order, shopChat: chat, clock: () => DateTime(2026, 9, 15, 10)),
      );
      await svcSettle(tester);

      await tester.tap(find.text(en.svcChatWithCustomer));
      await svcSettle(tester);

      final String day = dayOf(tester, closedAt);
      expect(find.text(en.svcChatClosedOn(day)), findsOneWidget);
      expect(find.text(en.svcChatWithCustomer), findsNothing);
      expect(find.byType(ShopThreadScreen), findsNothing);

      await tester.tap(find.text(en.actionMarkReady));
      await svcSettle(tester);
      expect(api.calls.where((String c) => c.startsWith('act ')), hasLength(1),
          reason: 'chat about the order closing is not the order closing');
      expect(find.text(en.svcActionCollected), findsOneWidget);
      expect(find.text(en.svcChatClosedOn(day)), findsOneWidget);
    });

    testWidgets('closed with no date given still says chat about the order has closed',
        (WidgetTester tester) async {
      final DeliveryOrder order = svcOrder();
      final FakeShopChat chat = FakeShopChat()
        ..failOpen = const ShopOrderChatClosedException(null);
      await pumpSvc(
        tester,
        ServiceOrderDetailScreen(
            api: FakeServiceOrders(<DeliveryOrder>[order]), order: order, shopChat: chat),
      );
      await svcSettle(tester);

      await tester.tap(find.text(en.svcChatWithCustomer));
      await svcSettle(tester);

      expect(find.text(en.svcChatClosed), findsOneWidget);
      expect(find.text(en.svcChatWithCustomer), findsNothing);
    });

    testWidgets('not found (404) says so and reads the order again', (WidgetTester tester) async {
      final DeliveryOrder order = svcOrder();
      final FakeServiceOrders api = FakeServiceOrders(<DeliveryOrder>[order]);
      final FakeShopChat chat = FakeShopChat()..failOpen = svcHttpError(404);
      await pumpSvc(tester, ServiceOrderDetailScreen(api: api, order: order, shopChat: chat));
      await svcSettle(tester);
      final int readsBefore = api.count('read 11111111-0000');

      await tester.tap(find.text(en.svcChatWithCustomer));
      await svcSettle(tester);

      expect(find.text(en.svcChatOrderNotFound), findsOneWidget);
      expect(api.count('read 11111111-0000'), readsBefore + 1);
      expect(find.byType(ShopThreadScreen), findsNothing);
      expect(find.text(en.svcChatWithCustomer), findsOneWidget, reason: 'nothing says chat closed');
    });

    testWidgets(
        'unavailable (503) says so in place of the button, and Try again opens the thread once it is '
        'back', (WidgetTester tester) async {
      final DeliveryOrder order = svcOrder();
      final FakeShopChat chat = FakeShopChat()..failOpen = svcHttpError(503);
      await pumpSvc(
        tester,
        ServiceOrderDetailScreen(
            api: FakeServiceOrders(<DeliveryOrder>[order]), order: order, shopChat: chat),
      );
      await svcSettle(tester);

      await tester.tap(find.text(en.svcChatWithCustomer));
      await svcSettle(tester);
      expect(find.text(en.svcChatUnavailable), findsOneWidget);
      expect(find.text(en.svcChatWithCustomer), findsNothing);
      expect(find.byType(ShopThreadScreen), findsNothing);

      chat.failOpen = null;
      await tester.tap(find.text(en.tryAgain));
      await tester.pumpAndSettle();

      expect(chat.opened, hasLength(2));
      expect(find.byType(ShopThreadScreen), findsOneWidget);
    });

    testWidgets('an unavailable chat, and one that closed last year, both fit a 320dp phone',
        (WidgetTester tester) async {
      final DeliveryOrder order = svcOrder(customer: 'Jean-Pierre Dupont-Aznavourian');
      final FakeShopChat chat = FakeShopChat()..failOpen = svcHttpError(503);
      await pumpSvc(
        tester,
        ServiceOrderDetailScreen(
          api: FakeServiceOrders(<DeliveryOrder>[order]),
          order: order,
          shopChat: chat,
          clock: () => DateTime(2026, 9, 15, 10),
        ),
        size: const Size(320, 900),
      );
      await svcSettle(tester);

      await tester.tap(find.text(en.svcChatWithCustomer));
      await svcSettle(tester);
      expect(find.text(en.svcChatUnavailable), findsOneWidget);
      expect(tester.takeException(), isNull);

      final DateTime closedAt = DateTime(2025, 12, 30, 9);
      chat.failOpen = ShopOrderChatClosedException(closedAt);
      await tester.tap(find.text(en.tryAgain));
      await svcSettle(tester);

      final String date =
          MaterialLocalizations.of(tester.element(find.byType(ServiceOrderDetailScreen)))
              .formatShortDate(closedAt);
      expect(find.text(en.svcChatClosedOn(date)), findsOneWidget, reason: 'not this year: with it');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'in Arabic, the thread opens labelled with the order, and a closed chat says when, with no '
        'English left', (WidgetTester tester) async {
      final DeliveryOrder order = svcOrder(
        status: 'PREPARING',
        actions: const <String>['READY'],
        fulfilment: 'DELIVERY',
        customer: 'جان بيار د.',
        product: 'طباعة بطاقات عمل',
        unitLabel: 'بطاقة',
        options: 'ورق مطفي',
        address: 'مار مخايل، بيروت',
        estimatedReadyAt: DateTime.now().add(const Duration(days: 2)),
      );
      final FakeShopChat chat = FakeShopChat(customerName: 'جان بيار د.');
      await pumpSvc(
        tester,
        ServiceOrderDetailScreen(
          api: FakeServiceOrders(<DeliveryOrder>[order]),
          order: order,
          shopChat: chat,
          clock: () => DateTime(2026, 9, 15, 10),
        ),
        locale: const Locale('ar'),
        size: const Size(320, 1400),
      );
      await svcSettle(tester);

      await tester.tap(find.text(ar.svcChatWithCustomer));
      await tester.pumpAndSettle();
      expect(Directionality.of(tester.element(find.byType(ShopThreadScreen))), TextDirection.rtl);
      expect(find.text(shopThreadOrderLabel(chat.threadFor('11111111-0000'), ar)!), findsOneWidget);
      expect(svcLatinText(tester), isEmpty);

      Navigator.of(tester.element(find.byType(ShopThreadScreen))).pop();
      await tester.pumpAndSettle();
      final DateTime closedAt = DateTime(2026, 9, 12, 18);
      chat.failOpen = ShopOrderChatClosedException(closedAt);
      await tester.tap(find.text(ar.svcChatWithCustomer));
      await svcSettle(tester);

      expect(find.text(ar.svcChatClosedOn(dayOf(tester, closedAt))), findsOneWidget);
      expect(svcLatinText(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a refused step says why and reads the order again', (WidgetTester tester) async {
    final DeliveryOrder order =
        svcOrder(status: 'READY', actions: const <String>['COLLECTED']);
    final FakeServiceOrders api = FakeServiceOrders(<DeliveryOrder>[order])
      ..onCollected = (String id) => const ServiceOrderActionRefused(
          refusal: ServiceOrderRefusal.notCollectable, code: 'NOT_COLLECTABLE');
    await pumpSvc(tester, ServiceOrderDetailScreen(api: api, order: order));
    await svcSettle(tester);
    final int readsBefore = api.count('read 11111111-0000');

    await tester.tap(find.text(en.svcActionCollected));
    await svcSettle(tester);

    expect(api.calls, contains('collected 11111111-0000'));
    expect(find.text(en.svcRefusedNotCollectable), findsOneWidget);
    expect(api.count('read 11111111-0000'), greaterThan(readsBefore));
  });

  testWidgets('a delivery order with long words fits a 320dp phone', (WidgetTester tester) async {
    final DeliveryOrder order = svcOrder(
      status: 'PLACED',
      fulfilment: 'DELIVERY',
      customer: 'Jean-Pierre Dupont-Aznavourian',
      product: 'Corporate brochure design and full colour offset printing, folded and trimmed',
      address: 'Building 14, Pharaon Street, Mar Mikhael, Beirut, next to the stairs',
      instructions: 'Please use the logo in the PDF, not the one on our website; it is outdated.',
      prompt: 'Anything we should know about the artwork?',
    );
    await pumpSvc(
      tester,
      ServiceOrderDetailScreen(
        api: FakeServiceOrders(<DeliveryOrder>[order]),
        order: order,
        files: FakeOrderFiles(<OrderAttachment>[pdf()]),
        shopChat: FakeShopChat(),
      ),
      size: const Size(320, 900),
    );
    await svcSettle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(en.svcAcceptOrder), findsOneWidget);
  });

  testWidgets('the order detail reads right to left in Arabic, with no English left on it',
      (WidgetTester tester) async {
    final DeliveryOrder order = svcOrder(
      status: 'PREPARING',
      actions: const <String>['READY'],
      fulfilment: 'DELIVERY',
      customer: 'جان بيار د.',
      product: 'طباعة بطاقات عمل',
      unitLabel: 'بطاقة',
      options: 'ورق مطفي',
      address: 'مار مخايل، بيروت',
      prompt: 'ما الأسماء على البطاقات؟',
      instructions: 'رنا حداد، زياد خوري',
      estimatedReadyAt: DateTime.now().add(const Duration(days: 2)),
    );
    await pumpSvc(
      tester,
      ServiceOrderDetailScreen(
        api: FakeServiceOrders(<DeliveryOrder>[order]),
        order: order,
        files: FakeOrderFiles(<OrderAttachment>[pdf()]),
        shopChat: FakeShopChat(),
      ),
      locale: const Locale('ar'),
      size: const Size(320, 1400),
    );
    await svcSettle(tester);

    expect(
        Directionality.of(tester.element(find.byType(ServiceOrderDetailScreen))), TextDirection.rtl);
    expect(tester.takeException(), isNull);
    expect(find.text(ar.svcChatWithCustomer), findsOneWidget);
    expect(find.text(ar.svcCustomerFiles), findsOneWidget);
    expect(svcLatinText(tester), isEmpty);
  });
}
