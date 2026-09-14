import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'svc_test_kit.dart';

/// A services shop's offers, as the Offers tab lists them: this shop's offers only, how each is sold
/// and priced, its state, Pause and Resume that say what came of them, and the honest empty states.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  setUpAll(() => svcUseLbpRate(90000));

  Widget screen(FakeOffers api, {List<Store>? shops, String? storeId = 'shop-1'}) =>
      ServiceOffersScreen(
        api: api,
        storeApi: FakeStores(shops ?? <Store>[svcShop(lat: 33.89, lng: 35.51)]),
        storeId: storeId,
      );

  testWidgets('shows a spinner until the offers arrive, and reads only this shop\'s',
      (WidgetTester tester) async {
    final FakeOffers api = FakeOffers(<Product>[svcOffer()])..holdList = Completer<void>();
    await pumpSvc(tester, screen(api));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    api.holdList!.complete();
    await svcSettle(tester);

    expect(api.calls, contains('mine ALL shop-1 100'));
    expect(find.text('Business Card Printing'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('offers that cannot be read say so, and Try again reads them again',
      (WidgetTester tester) async {
    final FakeOffers api = FakeOffers(<Product>[svcOffer()])..failList = Exception('down');
    await pumpSvc(tester, screen(api));
    await svcSettle(tester);

    expect(find.text(en.svcOffersLoadFailed), findsOneWidget);

    api.failList = null;
    await tester.tap(find.text(en.tryAgain));
    await svcSettle(tester);

    expect(find.text(en.svcOffersLoadFailed), findsNothing);
    expect(find.text('Business Card Printing'), findsOneWidget);
  });

  testWidgets('a shop with no offers is offered its first; a provider with no shop is told when',
      (WidgetTester tester) async {
    await pumpSvc(tester, screen(FakeOffers(<Product>[])));
    await svcSettle(tester);

    expect(find.text(en.svcNoOffersYet), findsOneWidget);
    expect(find.text(en.svcAddOffer), findsWidgets);

    await pumpSvc(tester, const SizedBox.shrink());
    await pumpSvc(tester, screen(FakeOffers(<Product>[]), shops: <Store>[], storeId: null));
    await svcSettle(tester);

    expect(find.text(en.svcNoShopYet), findsOneWidget);
    expect(find.text(en.svcAddOffer), findsNothing, reason: 'an offer needs a shop to be sold in');
  });

  testWidgets(
      'each offer says how it is sold, its price with LBP, and whether it is live, paused or a '
      'draft; an archived offer is not listed', (WidgetTester tester) async {
    final FakeOffers api = FakeOffers(<Product>[
      svcOffer(),
      svcOffer(
        id: 'offer-2',
        name: 'Banner Printing',
        status: ProductStatus.paused,
        pricing: ServicePricingType.perUnit,
        unitLabel: 'sqm',
        unitSize: 1,
        price: 8,
      ),
      svcOffer(
        id: 'offer-3',
        name: 'Flyer Design + Print',
        status: ProductStatus.draft,
        pricing: ServicePricingType.from,
        unitLabel: 'pcs',
        unitSize: 1000,
        price: 25,
        fromPrice: 27.5,
      ),
      svcOffer(id: 'offer-4', name: 'Old calendars', status: ProductStatus.archived),
    ]);
    await pumpSvc(tester, screen(api));
    await svcSettle(tester);

    expect(find.text('500 cards'), findsOneWidget);
    expect(find.text('Per sqm'), findsOneWidget);
    expect(find.text('1,000 pcs'), findsOneWidget);
    expect(find.text(r'$15.00'), findsOneWidget);
    expect(find.text('1,350,000 LBP'), findsOneWidget);
    // A starting price is the catalogue's own sum, and its LBP is of that sum.
    expect(find.text(en.svcFromPrice(r'$27.50')), findsOneWidget);
    expect(find.text('2,475,000 LBP'), findsOneWidget);
    expect(find.text(en.svcOfferActive), findsOneWidget);
    expect(find.text(en.svcOfferPaused), findsOneWidget);
    expect(find.text(en.svcOfferDraft), findsOneWidget);
    expect(find.text('Old calendars'), findsNothing);
    expect(find.text(en.svcPauseOffer), findsOneWidget);
    expect(find.text(en.svcResumeOffer), findsOneWidget, reason: 'a draft is published from its form');
  });

  testWidgets('Pause takes a live offer off sale, and the row says so',
      (WidgetTester tester) async {
    final FakeOffers api = FakeOffers(<Product>[svcOffer()]);
    await pumpSvc(tester, screen(api));
    await svcSettle(tester);

    await tester.tap(find.text(en.svcPauseOffer));
    await svcSettle(tester);

    expect(api.calls, contains('pause offer-1'));
    expect(find.text(en.svcOfferPaused), findsOneWidget);
    expect(find.text(en.svcOfferPausedDone), findsOneWidget);
    expect(find.text(en.svcResumeOffer), findsOneWidget);
  });

  testWidgets('a resume the server refuses is said, and nothing changes',
      (WidgetTester tester) async {
    final FakeOffers api = FakeOffers(<Product>[
      svcOffer(status: ProductStatus.paused),
    ])
      ..failResume = svcHttpError(422);
    await pumpSvc(tester, screen(api));
    await svcSettle(tester);

    await tester.tap(find.text(en.svcResumeOffer));
    await svcSettle(tester);
    expect(api.calls, contains('resume offer-1'));
    expect(find.text(en.svcOfferRefused), findsOneWidget);
    expect(find.text(en.svcOfferPaused), findsOneWidget, reason: 'nothing changed');
  });

  testWidgets('a resume without a photo is never sent, and says a photo is needed',
      (WidgetTester tester) async {
    final FakeOffers bare = FakeOffers(<Product>[
      svcOffer(status: ProductStatus.paused, photo: false),
    ]);
    await pumpSvc(tester, screen(bare));
    await svcSettle(tester);
    await tester.tap(find.text(en.svcResumeOffer));
    await svcSettle(tester);

    expect(bare.calls.where((String c) => c.startsWith('resume')), isEmpty);
    expect(find.text(en.svcPhotoRequired), findsOneWidget);
  });

  testWidgets('the offers fit a 320dp phone', (WidgetTester tester) async {
    await pumpSvc(
      tester,
      screen(FakeOffers(<Product>[
        svcOffer(name: 'Corporate brochure design and full colour offset printing, folded'),
        svcOffer(id: 'offer-2', status: ProductStatus.paused, unitLabel: 'double-sided cards'),
      ])),
      size: const Size(320, 900),
    );
    await svcSettle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text(en.svcPauseOffer), findsOneWidget);
  });

  testWidgets('the offers read right to left in Arabic, with no English left on them',
      (WidgetTester tester) async {
    await pumpSvc(
      tester,
      screen(FakeOffers(<Product>[
        svcOffer(name: 'طباعة بطاقات عمل', unitLabel: 'بطاقة'),
        svcOffer(
          id: 'offer-2',
          name: 'طباعة لافتات',
          status: ProductStatus.paused,
          pricing: ServicePricingType.perUnit,
          unitLabel: 'متر مربع',
          unitSize: 1,
        ),
        svcOffer(id: 'offer-3', name: 'تصميم منشورات', status: ProductStatus.draft, unitLabel: null, unitSize: 1),
      ])),
      locale: const Locale('ar'),
      size: const Size(320, 1200),
    );
    await svcSettle(tester);

    expect(Directionality.of(tester.element(find.byType(ServiceOffersScreen))), TextDirection.rtl);
    expect(tester.takeException(), isNull);
    expect(find.text(ar.svcOffersTitle), findsOneWidget);
    expect(find.text(ar.svcOfferPaused), findsOneWidget);
    expect(svcLatinText(tester), isEmpty);
  });
}
