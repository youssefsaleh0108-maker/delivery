import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'svc_test_kit.dart';

/// The service offer form (Figma 126:133): a dollar price with its LBP shown and never typed, what
/// Product Service would refuse said before anything is sent, the offer's terms sent whole, and the
/// steps a live offer takes from its menu.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  setUpAll(() => svcUseLbpRate(90000));

  // The fields in the order the form draws them.
  const int title = 0;
  const int description = 1;
  const int price = 2;
  const int unit = 3;
  const int pack = 4;
  const int prompt = 5;

  Future<FakeOffers> pumpForm(
    WidgetTester tester, {
    FakeOffers? api,
    Product? existing,
    bool? reach = true,
    bool pending = false,
    Locale locale = const Locale('en'),
    Size size = const Size(420, 2600),
  }) async {
    final FakeOffers offers = api ?? FakeOffers(existing == null ? <Product>[] : <Product>[existing]);
    await pumpSvc(
      tester,
      ServiceOfferFormScreen(
        api: offers,
        shop: svcShop(lat: 33.89, lng: 35.51),
        storeApi: FakeStores(<Store>[svcShop()]),
        deliveryReach: reach,
        existing: existing,
        pendingApproval: pending,
      ),
      locale: locale,
      size: size,
    );
    return offers;
  }

  Finder field(int index) => find.byType(TextFormField).at(index);

  Finder snack(String text) =>
      find.descendant(of: find.byType(SnackBar), matching: find.text(text));

  Future<void> fillValidOffer(WidgetTester tester) async {
    await tester.enterText(field(title), 'Business Card Printing');
    await tester.enterText(field(description), 'Premium cards, printed and trimmed.');
    await tester.enterText(field(price), '15');
    await tester.enterText(field(unit), 'cards');
    await tester.enterText(field(pack), '500');
    await tester.tap(find.text(en.svcTurnaround1to2));
    await tester.tap(find.text(en.svcFulfilmentBoth));
    await tester.tap(find.text(en.svcCustomerFileRequired));
    await tester.enterText(field(prompt), 'Which names go on the cards?');
    await tester.pump();
  }

  testWidgets('the LBP beside the price is the platform\'s conversion, and cannot be typed into',
      (WidgetTester tester) async {
    await pumpForm(tester);

    await tester.enterText(field(price), '20');
    await tester.pump();

    expect(find.text(en.svcLbpPreview('1,800,000 LBP')), findsOneWidget);
    expect(find.text(en.svcLbpPreview(MarketRates.instance.lbp(20)!)), findsOneWidget);
    // Shown, not an input: there is no field for pounds, and the figure is in none of them.
    expect(find.byType(TextFormField), findsNWidgets(6));
    expect(find.descendant(of: find.byType(TextFormField), matching: find.textContaining('LBP')),
        findsNothing);

    // An Arabic keyboard's digits are the same price.
    await tester.enterText(field(price), '٢٠');
    await tester.pump();
    expect(find.text(en.svcLbpPreview('1,800,000 LBP')), findsOneWidget);
  });

  testWidgets('a price of zero or with three decimals is refused, and nothing is sent',
      (WidgetTester tester) async {
    final FakeOffers api = await pumpForm(tester);
    await fillValidOffer(tester);

    await tester.enterText(field(price), '0');
    await tester.tap(find.text(en.svcSaveDraft));
    await tester.pump();
    expect(find.text(en.svcPriceInvalid), findsOneWidget);

    await tester.enterText(field(price), '12.345');
    await tester.tap(find.text(en.svcSaveDraft));
    await tester.pump();
    expect(find.text(en.svcPriceInvalid), findsOneWidget);

    expect(api.calls, isEmpty);
  });

  testWidgets('a turnaround and how customers get the work must be chosen',
      (WidgetTester tester) async {
    final FakeOffers api = await pumpForm(tester);
    await tester.enterText(field(title), 'Flyers');
    await tester.enterText(field(price), '20');

    await tester.tap(find.text(en.svcSaveDraft));
    await tester.pump();

    expect(find.text(en.svcTurnaroundRequired), findsOneWidget);
    expect(find.text(en.svcFulfilmentRequired), findsOneWidget);
    expect(api.calls, isEmpty);
  });

  testWidgets('the pack preview reads 500 cards; a price per unit is one unit and names its unit',
      (WidgetTester tester) async {
    final FakeOffers api = await pumpForm(tester);
    await tester.enterText(field(unit), 'cards');
    await tester.enterText(field(pack), '500');
    await tester.pump();

    expect(find.text(en.svcPackPreview('500 cards')), findsOneWidget);

    await tester.tap(find.text(en.svcPricingPerUnit));
    await tester.pump();
    expect(tester.widget<TextFormField>(field(pack)).controller!.text, '1');
    expect(find.text(en.svcPerUnitIsOne), findsOneWidget);
    expect(find.text('Per cards'), findsOneWidget);

    await tester.enterText(field(unit), '');
    await tester.enterText(field(title), 'Banners');
    await tester.enterText(field(price), '8');
    await tester.tap(find.text(en.svcSaveDraft));
    await tester.pump();

    expect(find.text(en.svcUnitRequired), findsOneWidget);
    expect(api.calls, isEmpty);
  });

  testWidgets('a draft goes to the shop with its whole service terms', (WidgetTester tester) async {
    final FakeOffers api = await pumpForm(tester);
    await fillValidOffer(tester);

    await tester.tap(find.text(en.svcSaveDraft));
    await svcSettle(tester);

    expect(api.calls, <String>['create']);
    final Map<String, dynamic> body = api.sent.single;
    expect(body['name'], 'Business Card Printing');
    expect(body['storeId'], 'shop-1');
    expect(body['price'], 15.0);
    expect(body['service'], <String, dynamic>{
      'pricingType': 'FIXED',
      'unitLabel': 'cards',
      'unitSize': 500,
      'turnaroundMinHours': 24,
      'turnaroundMaxHours': 48,
      'fulfilmentModes': 'BOTH',
      'attachmentPolicy': 'REQUIRED',
      'instructionsPrompt': 'Which names go on the cards?',
    });
    expect(snack(en.svcDraftSaved), findsOneWidget);
  });

  testWidgets('publishing without a photo says one is needed, and nothing is published',
      (WidgetTester tester) async {
    final FakeOffers api = await pumpForm(tester);
    await fillValidOffer(tester);

    await tester.tap(find.text(en.svcPublishOffer));
    await svcSettle(tester);

    expect(api.calls, contains('create'));
    expect(api.calls.where((String c) => c.startsWith('publish')), isEmpty);
    expect(snack(en.svcPhotoRequired), findsOneWidget);
  });

  testWidgets('publishing waits for approval, and says so', (WidgetTester tester) async {
    await pumpForm(tester, pending: true);

    expect(find.text(en.svcPublishAfterApproval), findsOneWidget);
    expect(
      tester.widget<YdPillButton>(find.widgetWithText(YdPillButton, en.svcPublishOffer)).onPressed,
      isNull,
    );
    expect(
      tester.widget<YdPillButton>(find.widgetWithText(YdPillButton, en.svcSaveDraft)).onPressed,
      isNotNull,
      reason: 'a draft can still be made',
    );
  });

  testWidgets('YouDrop delivery cannot be chosen by a shop that reaches nobody',
      (WidgetTester tester) async {
    final FakeOffers api = await pumpForm(tester, reach: false);
    await tester.enterText(field(title), 'Flyers');
    await tester.enterText(field(price), '20');
    await tester.tap(find.text(en.svcTurnaroundSameDay));

    expect(find.text(en.svcDeliveryNeedsAreas), findsOneWidget);
    await tester.tap(find.text(en.svcFulfilmentDelivery));
    await tester.tap(find.text(en.svcSaveDraft));
    await tester.pump();
    expect(find.text(en.svcFulfilmentRequired), findsOneWidget, reason: 'the tap chose nothing');

    await tester.tap(find.text(en.svcFulfilmentPickup));
    await tester.tap(find.text(en.svcSaveDraft));
    await svcSettle(tester);
    expect(api.calls, <String>['create']);
    expect((api.sent.single['service'] as Map<String, dynamic>)['fulfilmentModes'], 'PICKUP');
  });

  testWidgets('a refused publish of a deliverable offer says to set delivery areas',
      (WidgetTester tester) async {
    final Product draft = svcOffer(
      status: ProductStatus.draft,
      fulfilment: ServiceFulfilment.delivery,
    );
    final FakeOffers api = FakeOffers(<Product>[draft])..failPublish = svcHttpError(422);
    await pumpForm(tester, api: api, existing: draft, reach: null);

    await tester.tap(find.text(en.svcPublishOffer));
    await svcSettle(tester);

    expect(api.calls, containsAllInOrder(<String>['update offer-1', 'publish offer-1']));
    expect(snack(en.svcDeliveryNeedsAreas), findsOneWidget);
  });

  testWidgets('an offer opens with its own terms, and a live one is paused from its menu',
      (WidgetTester tester) async {
    final FakeOffers api = await pumpForm(tester, existing: svcOffer());

    expect(find.text(en.svcEditOffer), findsOneWidget);
    expect(tester.widget<TextFormField>(field(title)).controller!.text, 'Business Card Printing');
    expect(find.text(en.svcPackPreview('500 cards')), findsOneWidget);
    expect(find.text(en.svcSaveChanges), findsOneWidget);

    await tester.tap(find.byTooltip(en.svcMoreActions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.svcPauseOffer));
    await tester.pumpAndSettle();

    expect(api.calls, contains('pause offer-1'));
    expect(snack(en.svcOfferPausedDone), findsOneWidget);
  });

  testWidgets('terms this build cannot read are said, and cannot be saved over',
      (WidgetTester tester) async {
    await pumpForm(tester, existing: svcOffer(pricing: ServicePricingType.unknown));

    expect(find.text(en.svcOfferNotEditable), findsOneWidget);
    expect(
      tester.widget<YdPillButton>(find.widgetWithText(YdPillButton, en.svcSaveChanges)).onPressed,
      isNull,
    );
  });

  testWidgets('a save that fails says so, and nothing is taken as saved',
      (WidgetTester tester) async {
    final FakeOffers api = FakeOffers(<Product>[])..failCreate = svcHttpError(500);
    await pumpForm(tester, api: api);
    await fillValidOffer(tester);

    await tester.tap(find.text(en.svcSaveDraft));
    await svcSettle(tester);

    expect(snack(en.svcOfferSaveFailed), findsOneWidget);
    expect(find.byTooltip(en.svcMoreActions), findsNothing, reason: 'there is no offer yet');
    expect(
      tester.widget<YdPillButton>(find.widgetWithText(YdPillButton, en.svcSaveDraft)).onPressed,
      isNotNull,
      reason: 'the provider can try again',
    );
  });

  testWidgets('a save the server refuses says to check the offer', (WidgetTester tester) async {
    final FakeOffers api = FakeOffers(<Product>[])..failCreate = svcHttpError(422);
    await pumpForm(tester, api: api);
    await fillValidOffer(tester);

    await tester.tap(find.text(en.svcPublishOffer));
    await svcSettle(tester);

    expect(snack(en.svcOfferRefused), findsOneWidget);
    expect(api.calls, <String>['create'], reason: 'nothing is published after a refused save');
  });

  testWidgets('the form fits a 320dp phone', (WidgetTester tester) async {
    await pumpForm(tester, existing: svcOffer(prompt: 'Which names and job titles go on the cards?'),
        size: const Size(320, 3200));

    expect(tester.takeException(), isNull);
    expect(find.text(en.svcSaveChanges), findsOneWidget);
  });

  testWidgets('the form reads right to left in Arabic, with no English left on it',
      (WidgetTester tester) async {
    await pumpForm(tester, locale: const Locale('ar'), size: const Size(320, 3200));
    await tester.enterText(field(price), '20');
    await tester.enterText(field(unit), 'بطاقة');
    await tester.enterText(field(pack), '500');
    await tester.tap(find.text(ar.svcSaveDraft));
    await tester.pump();

    expect(Directionality.of(tester.element(find.byType(ServiceOfferFormScreen))),
        TextDirection.rtl);
    expect(tester.takeException(), isNull);
    expect(find.text(ar.svcNewOffer), findsOneWidget);
    expect(find.text(ar.svcOfferTitleRequired), findsOneWidget);
    expect(find.text(ar.svcLbpPreview('1,800,000 ل.ل.')), findsOneWidget);
    expect(svcLatinText(tester), isEmpty);
  });
}
