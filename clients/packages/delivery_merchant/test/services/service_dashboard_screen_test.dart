import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'svc_test_kit.dart';

/// The provider dashboard (Figma 126:51): figures the platform has — the catalogue's live count,
/// Order Manager's last seven days, the shop's rating or "New" — a dash for one that could not be
/// read, the Verified Local badge only when it is set, the shop's offers with Pause and Resume, and
/// doors to the shell's Orders and Offers tabs and to notifications only when the shell hands them over.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  setUpAll(() => svcUseLbpRate(90000));

  List<Product> catalogue() => <Product>[
        svcOffer(id: 'offer-1'),
        svcOffer(id: 'offer-2', name: 'Banner Printing', unitLabel: 'sqm', unitSize: 1),
        svcOffer(id: 'offer-3', name: 'Posters', unitLabel: 'posters', unitSize: 10),
        svcOffer(id: 'offer-4', name: 'Flyer Design + Print', status: ProductStatus.paused),
        svcOffer(id: 'offer-5', name: 'Stickers', status: ProductStatus.draft),
      ];

  Future<void> pumpDashboard(
    WidgetTester tester, {
    FakeServiceOrders? orders,
    FakeOffers? offers,
    List<Store>? shops,
    String? storeId = 'shop-1',
    VoidCallback? onViewOrders,
    VoidCallback? onShowOffers,
    VoidCallback? onNotifications,
    int? unread,
    Locale locale = const Locale('en'),
    Size size = const Size(420, 1800),
  }) async {
    await pumpSvc(
      tester,
      ServiceDashboardScreen(
        orderApi: orders ?? FakeServiceOrders(<DeliveryOrder>[]),
        catalogApi: offers ?? FakeOffers(catalogue()),
        storeApi: FakeStores(shops ?? <Store>[svcShop(rating: 4.8, ratingCount: 31)]),
        storeId: storeId,
        onViewOrders: onViewOrders,
        onShowOffers: onShowOffers,
        onNotifications: onNotifications,
        unreadNotifications: unread,
      ),
      locale: locale,
      size: size,
    );
    await svcSettle(tester);
  }

  testWidgets('shows a spinner until the shop and its figures are read',
      (WidgetTester tester) async {
    final FakeOffers offers = FakeOffers(catalogue())..holdList = Completer<void>();
    await pumpSvc(
      tester,
      ServiceDashboardScreen(
        orderApi: FakeServiceOrders(<DeliveryOrder>[]),
        catalogApi: offers,
        storeApi: FakeStores(<Store>[svcShop()]),
        storeId: 'shop-1',
      ),
    );
    await svcSettle(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    offers.holdList!.complete();
    await svcSettle(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Al Fakhry Press'), findsOneWidget);
  });

  testWidgets(
      'the figures are the platform\'s: live offers counted by the catalogue, orders placed in the '
      'last seven days, and the shop\'s rating', (WidgetTester tester) async {
    final FakeServiceOrders orders = FakeServiceOrders(<DeliveryOrder>[]);
    final FakeOffers offers = FakeOffers(catalogue());
    await pumpDashboard(tester, orders: orders, offers: offers);

    expect(offers.calls, contains('mine ACTIVE shop-1 1'),
        reason: 'a count the server made, of this shop\'s live offers');
    expect(find.text('3'), findsOneWidget);
    expect(orders.summaryDays, 7);
    expect(find.text('12'), findsOneWidget);
    expect(find.text(en.svcDashboardThisWeekCaption), findsOneWidget);
    expect(find.text('★ 4.8'), findsOneWidget);
    expect(find.text('Mar Mikhael'), findsOneWidget);
  });

  testWidgets('a shop nobody has rated reads New, and a figure that could not be read is a dash',
      (WidgetTester tester) async {
    await pumpDashboard(
      tester,
      orders: FakeServiceOrders(<DeliveryOrder>[])..failSummary = Exception('order manager down'),
      shops: <Store>[svcShop()],
    );

    expect(find.text(en.ratingNew), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('3'), findsOneWidget, reason: 'the other figures still show');
  });

  testWidgets('the Verified Local badge shows only when the back office set it',
      (WidgetTester tester) async {
    await pumpDashboard(tester, shops: <Store>[svcShop()]);
    expect(find.byIcon(Icons.verified_rounded), findsNothing);

    await pumpSvc(tester, const SizedBox.shrink());
    await pumpDashboard(tester, shops: <Store>[svcShop(verifiedLocal: true)]);
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    expect(tester.widget<Icon>(find.byIcon(Icons.verified_rounded)).semanticLabel, en.custVerifiedLocal);
  });

  testWidgets('current offers carry their state, and Pause works from here',
      (WidgetTester tester) async {
    final FakeOffers offers = FakeOffers(catalogue());
    await pumpDashboard(tester, offers: offers);

    expect(find.text(en.svcOfferActive), findsNWidgets(3));
    expect(find.text(en.svcOfferPaused), findsOneWidget);
    expect(find.text(en.svcOfferDraft), findsOneWidget);
    expect(find.text('500 cards'), findsNWidgets(3));

    await tester.tap(find.text(en.svcPauseOffer).first);
    await svcSettle(tester);

    expect(offers.calls, contains('pause offer-1'));
    expect(find.text(en.svcOfferPaused), findsNWidgets(2));
    expect(find.text('2'), findsOneWidget, reason: 'one fewer live offer');
  });

  testWidgets(
      'Active offers counts live offers only: a held offer is listed with its hold, and a resume the '
      'hold refuses takes nothing off the count', (WidgetTester tester) async {
    final FakeOffers offers = FakeOffers(<Product>[
      svcOffer(
        id: 'offer-6',
        name: 'Wedding invitations',
        takenDown: true,
        takenDownReason: 'Copied photos',
      ),
      ...catalogue(),
    ])
      ..failResume = svcHttpError(422)
      ..nextReads.add(svcOffer(
        id: 'offer-4',
        name: 'Flyer Design + Print',
        takenDown: true,
        takenDownReason: 'Prices do not match the photos',
      ));
    await pumpDashboard(tester, offers: offers);

    expect(find.text('3'), findsOneWidget, reason: 'the catalogue\'s own count of live offers');
    expect(find.text(en.svcOfferTakenDown), findsOneWidget);

    await tester.tap(find.text(en.svcResumeOffer));
    await svcSettle(tester);

    expect(offers.calls, contains('resume offer-4'));
    expect(find.text('3'), findsOneWidget, reason: 'a paused offer taken down was never live');
    expect(find.text(en.svcOfferTakenDown), findsNWidgets(2));
  });

  testWidgets('a resume refused while the application is pending says why',
      (WidgetTester tester) async {
    final FakeOffers offers = FakeOffers(<Product>[svcOffer(status: ProductStatus.paused)])
      ..failResume = svcHttpError(403);
    await pumpDashboard(tester, offers: offers);

    await tester.tap(find.text(en.svcResumeOffer));
    await svcSettle(tester);

    expect(offers.calls, contains('resume offer-1'));
    expect(find.text(en.svcPublishAfterApproval), findsOneWidget);
  });

  testWidgets('a shop with no offers is offered its first, which opens the offer form',
      (WidgetTester tester) async {
    await pumpDashboard(tester, offers: FakeOffers(<Product>[]));

    expect(find.text(en.svcNoOffersYet), findsOneWidget);
    await tester.tap(find.text(en.svcAddOffer).first);
    await tester.pumpAndSettle();

    expect(find.byType(ServiceOfferFormScreen), findsOneWidget);
  });

  testWidgets('a dashboard that cannot be read at all says so, and Try again reads it again',
      (WidgetTester tester) async {
    final FakeServiceOrders orders = FakeServiceOrders(<DeliveryOrder>[])
      ..failSummary = Exception('down');
    final FakeOffers offers = FakeOffers(catalogue())..failList = Exception('down');
    await pumpDashboard(tester, orders: orders, offers: offers);

    expect(find.text(en.svcDashboardLoadFailed), findsOneWidget);

    orders.failSummary = null;
    offers.failList = null;
    await tester.tap(find.text(en.tryAgain));
    await svcSettle(tester);

    expect(find.text(en.svcDashboardLoadFailed), findsNothing);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('a provider whose shop is not open yet is told when it opens',
      (WidgetTester tester) async {
    await pumpDashboard(tester, shops: <Store>[], storeId: null);

    expect(find.text(en.svcNoShopYet), findsOneWidget);
    expect(find.text(en.svcAddOffer), findsNothing);
  });

  testWidgets('View orders, See all and the bell hand over to the shell, and only when wired',
      (WidgetTester tester) async {
    final List<String> opened = <String>[];
    await pumpDashboard(
      tester,
      offers: FakeOffers(<Product>[
        ...catalogue(),
        svcOffer(id: 'offer-6', name: 'Wedding invitations'),
      ]),
      onViewOrders: () => opened.add('orders'),
      onShowOffers: () => opened.add('offers'),
      onNotifications: () => opened.add('bell'),
      unread: 2,
    );

    await tester.tap(find.text(en.svcViewOrders));
    await tester.tap(find.text(en.svcSeeAllOffers));
    await tester.tap(find.byTooltip(en.notifications));
    await tester.pump();
    expect(opened, <String>['orders', 'offers', 'bell']);
    expect(find.text('2'), findsOneWidget, reason: 'the bell counts what is unread');

    await pumpSvc(tester, const SizedBox.shrink());
    await pumpDashboard(tester);
    expect(find.text(en.svcViewOrders), findsNothing);
    expect(find.text(en.svcSeeAllOffers), findsNothing);
    expect(find.byTooltip(en.notifications), findsNothing);
  });

  testWidgets('the dashboard fits a 320dp phone', (WidgetTester tester) async {
    await pumpDashboard(
      tester,
      shops: <Store>[
        svcShop(
          name: 'Al Fakhry Press and Digital Printing House',
          verifiedLocal: true,
          rating: 4.85,
          neighborhood: 'Mar Mikhael, Armenia Street',
        ),
      ],
      onViewOrders: () {},
      onNotifications: () {},
      unread: 12,
      size: const Size(320, 1600),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(en.svcCurrentOffers), findsOneWidget);
  });

  testWidgets('the dashboard reads right to left in Arabic, with no English left on it',
      (WidgetTester tester) async {
    await pumpDashboard(
      tester,
      shops: <Store>[svcShop(name: 'مطبعة الفخري', neighborhood: 'مار مخايل', verifiedLocal: true)],
      offers: FakeOffers(<Product>[
        svcOffer(name: 'طباعة بطاقات عمل', unitLabel: 'بطاقة'),
        svcOffer(id: 'offer-2', name: 'طباعة لافتات', status: ProductStatus.paused, unitLabel: null, unitSize: 1),
      ]),
      onViewOrders: () {},
      onNotifications: () {},
      locale: const Locale('ar'),
      size: const Size(320, 1600),
    );

    expect(
        Directionality.of(tester.element(find.byType(ServiceDashboardScreen))), TextDirection.rtl);
    expect(tester.takeException(), isNull);
    expect(find.text(ar.svcQuickActions), findsOneWidget);
    expect(find.text(ar.ratingNew), findsOneWidget);
    expect(svcLatinText(tester), isEmpty);
  });
}
