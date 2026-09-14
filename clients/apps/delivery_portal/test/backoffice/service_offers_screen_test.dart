import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/backoffice/service_offers_screen.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Back office's Service offers page.
///
/// Pinned: the list asks the server for exactly the filters on screen (status, taken down included;
/// category; shop; text; page); an offer's detail shows its shop, terms, price, photos, status and
/// trail; no take-down and no restore is sent without a reason, and the reason cannot outgrow the
/// server's 500, counted in UTF-16 units as the server counts; a refusal is said as what it is and the
/// list is read again; and the page is honest in every state — loading, empty, failed, refused — at
/// 1440, 1280 and a narrow window, and in Arabic.
///
/// The fake stands in for delivery_core's `BackofficeCatalogApi` and builds every row and trail entry
/// with `fromJson`, so what the page reads is what the client parses from the server's JSON.
typedef _ListCall = ({
  ServiceOfferStatusFilter? status,
  ServiceCategory? category,
  String? storeId,
  String? search,
  int page,
  int size,
});

class _FakeModeration implements BackofficeCatalogApi {
  final List<_ListCall> lists = <_ListCall>[];
  final List<({String id, String reason})> takeDowns = <({String id, String reason})>[];
  final List<({String id, String reason})> restores = <({String id, String reason})>[];
  final List<String> histories = <String>[];

  Future<Paged<BackofficeServiceOffer>> Function(_ListCall call) onList =
      (_ListCall _) async => _page(<Map<String, dynamic>>[_row()]);
  Future<BackofficeServiceOffer> Function(String id, String reason) onTakeDown =
      (String id, String reason) async => BackofficeServiceOffer.fromJson(_row(
          moderation: <String, dynamic>{
            'state': 'TAKEN_DOWN',
            'reason': reason,
            'takenDownAt': '2026-09-14T09:00:00Z',
          },
          status: 'ARCHIVED'));
  Future<BackofficeServiceOffer> Function(String id, String reason) onRestore =
      (String id, String reason) async => BackofficeServiceOffer.fromJson(_row(status: 'PAUSED'));
  Future<List<OfferModerationAction>> Function(String id) onHistory =
      (String _) async => <OfferModerationAction>[];

  @override
  Future<Paged<BackofficeServiceOffer>> serviceOffers({
    ServiceOfferStatusFilter? status,
    ServiceCategory? serviceCategory,
    String? storeId,
    String? search,
    int page = 0,
    int size = 20,
  }) {
    final _ListCall call = (
      status: status,
      category: serviceCategory,
      storeId: storeId,
      search: search,
      page: page,
      size: size,
    );
    lists.add(call);
    return onList(call);
  }

  @override
  Future<BackofficeServiceOffer> takeDown(String productId, {required String reason}) {
    takeDowns.add((id: productId, reason: reason));
    return onTakeDown(productId, reason);
  }

  @override
  Future<BackofficeServiceOffer> restore(String productId, {required String reason}) {
    restores.add((id: productId, reason: reason));
    return onRestore(productId, reason);
  }

  @override
  Future<List<OfferModerationAction>> moderationHistory(String productId) {
    histories.add(productId);
    return onHistory(productId);
  }
}

/// One row as `GET /api/products/services/all` sends it (product-service `BackofficeOfferResponse`).
Map<String, dynamic> _row({
  String id = 'offer-1',
  String name = 'Business cards',
  String status = 'ACTIVE',
  String storeId = 'store-print-1',
  String? storeName = 'Print Point',
  String category = 'PRINTING',
  List<String> images = const <String>[],
  Map<String, dynamic>? moderation,
}) =>
    <String, dynamic>{
      'offer': <String, dynamic>{
        'id': id,
        'merchantId': 'merchant-1',
        'storeId': storeId,
        'name': name,
        'description': 'Matte or gloss, 350gsm.',
        'price': 15.0,
        'categoryId': null,
        'imageRefs': const <String>[],
        'imageUrls': images,
        'status': status,
        'service': <String, dynamic>{
          'pricingType': 'FIXED',
          'unitLabel': 'cards',
          'unitSize': 500,
          'turnaroundMinHours': 24,
          'turnaroundMaxHours': 48,
          'fulfilmentModes': 'BOTH',
          'attachmentPolicy': 'REQUIRED',
          'instructionsPrompt': 'Which finish would you like?',
        },
        if (moderation != null) 'moderation': moderation,
      },
      'storeId': storeId,
      'storeName': storeName,
      'serviceCategory': category,
      'storeStatus': 'ACTIVE',
    };

Paged<BackofficeServiceOffer> _page(List<Map<String, dynamic>> rows,
        {int page = 0, int totalPages = 1, int? total}) =>
    Paged<BackofficeServiceOffer>(
      content: rows.map(BackofficeServiceOffer.fromJson).toList(),
      page: page,
      totalElements: total ?? rows.length,
      totalPages: totalPages,
    );

DioException _refused(int status, {String? code}) {
  final RequestOptions request = RequestOptions(path: '/api/products/offer-1/moderation/take-down');
  return DioException.badResponse(
    statusCode: status,
    requestOptions: request,
    response: Response<dynamic>(
      requestOptions: request,
      statusCode: status,
      data: <String, dynamic>{'status': status, if (code != null) 'code': code},
    ),
  );
}

final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

void main() {
  late _FakeModeration api;

  setUp(() => api = _FakeModeration());

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    Locale locale = const Locale('en'),
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      locale: locale,
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: Scaffold(body: ServiceOffersScreen(api: api)),
    ));
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> openOffer(WidgetTester tester, String name) async {
    await tester.tap(find.text(name).first);
    await tester.pumpAndSettle();
  }

  Finder dialogField() =>
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));

  Finder dialogButton(String label) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(ConsoleButton, label));

  group('states', () {
    testWidgets('shows a spinner while the first page is on its way', (WidgetTester tester) async {
      final Completer<Paged<BackofficeServiceOffer>> answer = Completer<Paged<BackofficeServiceOffer>>();
      api.onList = (_ListCall _) => answer.future;
      await pump(tester, settle: false);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(en.svcBoOffersEmpty), findsNothing);

      answer.complete(_page(<Map<String, dynamic>>[]));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('says plainly when no offer matches', (WidgetTester tester) async {
      api.onList = (_ListCall _) async => _page(<Map<String, dynamic>>[]);
      await pump(tester);

      expect(find.text(en.svcBoOffersEmpty), findsOneWidget);
    });

    testWidgets('a failed read says so and Try again reads again', (WidgetTester tester) async {
      api.onList = (_ListCall _) async => throw _refused(500);
      await pump(tester);

      expect(find.text(en.svcBoOffersLoadFailed), findsOneWidget);
      await tester.tap(find.text(en.tryAgain));
      await tester.pumpAndSettle();
      expect(api.lists, hasLength(2));
    });

    testWidgets('a refused read says this account may not, and offers no pointless retry',
        (WidgetTester tester) async {
      api.onList = (_ListCall _) async => throw _refused(403);
      await pump(tester);

      expect(find.text(en.svcBoOffersRefused), findsOneWidget);
      expect(find.text(en.tryAgain), findsNothing);
    });
  });

  for (final Size size in const <Size>[Size(1440, 900), Size(1280, 800), Size(1024, 720)]) {
    testWidgets('lists offers with shop, category, price and status at ${size.width.toInt()}px',
        (WidgetTester tester) async {
      api.onList = (_ListCall _) async => _page(<Map<String, dynamic>>[
            _row(),
            _row(
              id: 'offer-2',
              name: 'Hem trousers',
              storeId: 'store-tailor-1',
              storeName: null,
              category: 'TAILORING',
              status: 'ARCHIVED',
              moderation: <String, dynamic>{'state': 'TAKEN_DOWN', 'reason': 'Fake reviews'},
            ),
          ]);
      await pump(tester, size: size);

      expect(find.text('Business cards'), findsOneWidget);
      expect(find.text('Print Point'), findsWidgets);
      expect(find.text(en.svcCategoryPrinting), findsOneWidget);
      expect(find.text(en.svcBoPricePerPack(r'$15.00', 500, 'cards')), findsNWidgets(2));
      expect(find.text(en.svcBoOfferActive), findsWidgets);
      // A held offer reads as taken down, not as the archive the hold left underneath.
      expect(find.text(en.svcBoOfferTakenDown), findsWidgets);
      // A shop the server did not name is a dash, never an empty cell.
      expect(find.text('—'), findsOneWidget);
    });
  }

  testWidgets('each filter sends exactly what it shows', (WidgetTester tester) async {
    api.onList = (_ListCall call) async =>
        _page(<Map<String, dynamic>>[_row()], page: call.page, totalPages: 3, total: 45);
    await pump(tester);

    expect(api.lists.single,
        (status: null, category: null, storeId: null, search: null, page: 0, size: 20));

    await tester.tap(find.text(en.svcBoOfferTakenDown));
    await tester.pumpAndSettle();
    expect(api.lists.last.status, ServiceOfferStatusFilter.takenDown);

    await tester.tap(find.text(en.svcBoAllCategories));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.svcCategoryTailoring).last);
    await tester.pumpAndSettle();
    expect(api.lists.last.category, ServiceCategory.tailoring);
    expect(api.lists.last.status, ServiceOfferStatusFilter.takenDown);

    await tester.tap(find.text(en.svcBoAllShops));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Print Point').last);
    await tester.pumpAndSettle();
    expect(api.lists.last.storeId, 'store-print-1');

    await tester.enterText(find.byType(TextField), '  cards ');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(api.lists.last.search, 'cards');

    expect(find.text('${en.svcBoOffersCount(45)} · ${en.svcBoPageOf(1, 3)}'), findsOneWidget);
    await tester.tap(find.text(en.next));
    await tester.pumpAndSettle();
    expect(api.lists.last.page, 1);
    expect(api.lists.last.size, 20);
    // Paging keeps every filter it was given.
    expect(api.lists.last.storeId, 'store-print-1');
    expect(api.lists.last.category, ServiceCategory.tailoring);

    // A new filter starts again from the first page. `.first` is the pill: the rows below carry an
    // "Active" status pill of their own.
    await tester.tap(find.text(en.svcBoOfferActive).first);
    await tester.pumpAndSettle();
    expect(api.lists.last.page, 0);
  });

  testWidgets('an offer opens with its shop, terms, price, photos, status and trail',
      (WidgetTester tester) async {
    api.onList = (_ListCall _) async =>
        _page(<Map<String, dynamic>>[_row(images: const <String>['http://files.test/card.png'])]);
    api.onHistory = (String _) async => <OfferModerationAction>[
          OfferModerationAction.fromJson(const <String, dynamic>{
            'id': 'act-2',
            'productId': 'offer-1',
            'storeId': 'store-print-1',
            'action': 'RESTORE',
            'reason': 'Logo licence shown',
            'actorId': 'ops-0001-aaaa',
            'actorName': 'maya.ops',
            'createdAt': '2026-09-13T10:00:00Z',
          }),
          OfferModerationAction.fromJson(const <String, dynamic>{
            'id': 'act-1',
            'productId': 'offer-1',
            'storeId': 'store-print-1',
            'action': 'TAKE_DOWN',
            'reason': 'Printing a trademarked logo',
            'actorId': 'ops-0002-bbbb',
            'createdAt': '2026-09-12T10:00:00Z',
          }),
        ];
    await pump(tester);
    await openOffer(tester, 'Business cards');

    expect(find.text(en.svcBoSectionShop.toUpperCase()), findsOneWidget);
    expect(find.text(en.svcBoShopListed), findsOneWidget);
    expect(find.text(en.svcBoPricingFixed), findsOneWidget);
    expect(find.text(en.svcBoPackOf(500, 'cards')), findsOneWidget);
    expect(find.text(en.svcBoTurnaroundRange(24, 48)), findsOneWidget);
    expect(find.text(en.svcBoFulfilBoth), findsOneWidget);
    expect(find.text(en.svcBoFilesPolicyRequired), findsOneWidget);
    expect(find.text('Which finish would you like?'), findsOneWidget);
    expect(find.text('Matte or gloss, 350gsm.'), findsOneWidget);
    expect(find.byType(DeliveryProductImage), findsOneWidget);
    expect(api.histories, <String>['offer-1']);
    expect(find.text('Logo licence shown'), findsOneWidget);
    expect(find.textContaining(en.svcBoActBy('maya.ops')), findsOneWidget);
    // No username on the token: the account id, shortened, rather than nobody.
    expect(find.textContaining(en.svcBoActBy('ops-0002')), findsOneWidget);
  });

  testWidgets('take down is never sent without a reason, and the reason stops at 500',
      (WidgetTester tester) async {
    await pump(tester);
    await openOffer(tester, 'Business cards');

    await tester.tap(find.widgetWithText(ConsoleButton, en.svcBoTakeDown));
    await tester.pumpAndSettle();
    expect(find.text(en.svcBoTakeDownTitle('Business cards')), findsOneWidget);
    expect(find.text(en.svcBoReasonLength(0, 500)), findsOneWidget);

    await tester.tap(dialogButton(en.svcBoTakeDown));
    await tester.pumpAndSettle();
    expect(find.text(en.svcBoReasonRequired), findsOneWidget);

    await tester.enterText(dialogField(), '    ');
    await tester.tap(dialogButton(en.svcBoTakeDown));
    await tester.pumpAndSettle();
    expect(find.text(en.svcBoReasonRequired), findsOneWidget);
    expect(api.takeDowns, isEmpty);

    await tester.enterText(dialogField(), 'x' * 600);
    await tester.pump();
    expect(tester.widget<TextField>(dialogField()).controller!.text.length, 500);
    expect(find.text(en.svcBoReasonLength(500, 500)), findsOneWidget);

    await tester.enterText(dialogField(), '  Printing a trademarked logo ');
    await tester.tap(dialogButton(en.svcBoTakeDown));
    await tester.pumpAndSettle();

    expect(api.takeDowns.single, (id: 'offer-1', reason: 'Printing a trademarked logo'));
    expect(find.text(en.svcBoTakenDownDone('Business cards')), findsOneWidget);
    // The offer now shows its hold, offers Restore instead, and the trail and the list are read again.
    expect(find.text(en.svcBoSectionHold.toUpperCase()), findsOneWidget);
    expect(find.widgetWithText(ConsoleButton, en.svcBoRestore), findsOneWidget);
    expect(api.histories, hasLength(2));
    expect(api.lists, hasLength(2));
  });

  testWidgets('the reason is held to the 500 units the server counts, where an emoji counts twice',
      (WidgetTester tester) async {
    await pump(tester);
    await openOffer(tester, 'Business cards');
    await tester.tap(find.widgetWithText(ConsoleButton, en.svcBoTakeDown));
    await tester.pumpAndSettle();
    String kept() => tester.widget<TextField>(dialogField()).controller!.text;

    // One unit of room is no room for an emoji, and the cut never splits one in two.
    await tester.enterText(dialogField(), '${'x' * 499}😀');
    await tester.pump();
    expect(kept(), 'x' * 499);

    // 300 emoji: 300 characters, which a maxLength of 500 lets through, and 600 UTF-16 units, which
    // the server's @Size(max = 500) refuses with a 400.
    await tester.enterText(dialogField(), '😀' * 300);
    await tester.pump();
    expect(kept(), '😀' * 250);
    expect(kept().length, 500);
    expect(find.text(en.svcBoReasonLength(500, 500)), findsOneWidget);

    await tester.tap(dialogButton(en.svcBoTakeDown));
    await tester.pumpAndSettle();
    expect(api.takeDowns.single, (id: 'offer-1', reason: '😀' * 250));
  });

  testWidgets('restore is never sent without a reason either', (WidgetTester tester) async {
    api.onList = (_ListCall _) async => _page(<Map<String, dynamic>>[
          _row(status: 'ARCHIVED', moderation: <String, dynamic>{
            'state': 'TAKEN_DOWN',
            'reason': 'Printing a trademarked logo',
            'takenDownAt': '2026-09-12T10:00:00Z',
          }),
        ]);
    await pump(tester);
    await openOffer(tester, 'Business cards');

    expect(find.text('Printing a trademarked logo'), findsOneWidget);
    expect(find.widgetWithText(ConsoleButton, en.svcBoTakeDown), findsNothing);

    await tester.tap(find.widgetWithText(ConsoleButton, en.svcBoRestore));
    await tester.pumpAndSettle();
    expect(find.text(en.svcBoRestoreTitle('Business cards')), findsOneWidget);
    expect(find.text(en.svcBoReasonLength(0, 500)), findsOneWidget);

    await tester.tap(dialogButton(en.svcBoRestore));
    await tester.pumpAndSettle();
    expect(find.text(en.svcBoReasonRequired), findsOneWidget);
    expect(api.restores, isEmpty);

    await tester.enterText(dialogField(), 'Licence from the brand owner received');
    await tester.tap(dialogButton(en.svcBoRestore));
    await tester.pumpAndSettle();

    expect(api.restores.single, (id: 'offer-1', reason: 'Licence from the brand owner received'));
    expect(find.text(en.svcBoRestoredDone('Business cards')), findsOneWidget);
  });

  testWidgets('cancelling the reason dialog sends nothing', (WidgetTester tester) async {
    await pump(tester);
    await openOffer(tester, 'Business cards');

    await tester.tap(find.widgetWithText(ConsoleButton, en.svcBoTakeDown));
    await tester.pumpAndSettle();
    await tester.enterText(dialogField(), 'Changed my mind');
    await tester.tap(dialogButton(en.cancel));
    await tester.pumpAndSettle();

    expect(api.takeDowns, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  group('refusals', () {
    Future<void> takeDownRefusedWith(WidgetTester tester, DioException refusal) async {
      api.onTakeDown = (String _, String __) async => throw refusal;
      await pump(tester);
      await openOffer(tester, 'Business cards');
      await tester.tap(find.widgetWithText(ConsoleButton, en.svcBoTakeDown));
      await tester.pumpAndSettle();
      await tester.enterText(dialogField(), 'Fake reviews');
      await tester.tap(dialogButton(en.svcBoTakeDown));
      await tester.pumpAndSettle();
    }

    testWidgets('a 422 says the offer is already down, and the list is read again',
        (WidgetTester tester) async {
      await takeDownRefusedWith(tester, _refused(422));

      expect(find.text(en.svcBoTakeDownRefused), findsOneWidget);
      expect(api.lists, hasLength(2));
      expect(find.text(en.svcBoTakenDownDone('Business cards')), findsNothing);
    });

    testWidgets('a 409 PRODUCT_CHANGED says the offer changed and nothing was recorded',
        (WidgetTester tester) async {
      await takeDownRefusedWith(tester, _refused(409, code: 'PRODUCT_CHANGED'));

      expect(find.text(en.svcBoOfferChanged), findsOneWidget);
      expect(api.lists, hasLength(2));
    });

    testWidgets('a 404 says the offer is gone and leaves nothing to press',
        (WidgetTester tester) async {
      await takeDownRefusedWith(tester, _refused(404));

      expect(find.text(en.svcBoOfferGone), findsWidgets);
      expect(find.widgetWithText(ConsoleButton, en.svcBoTakeDown), findsNothing);
      expect(find.widgetWithText(ConsoleButton, en.svcBoRestore), findsNothing);
    });

    testWidgets('a 403 says this account may not moderate', (WidgetTester tester) async {
      await takeDownRefusedWith(tester, _refused(403));

      expect(find.text(en.svcBoModerateRefused), findsOneWidget);
    });

    testWidgets('a restore refused with a 422 says the offer is not down any more',
        (WidgetTester tester) async {
      api.onList = (_ListCall _) async => _page(<Map<String, dynamic>>[
            _row(moderation: <String, dynamic>{'state': 'TAKEN_DOWN', 'reason': 'Fake reviews'}),
          ]);
      api.onRestore = (String _, String __) async => throw _refused(422);
      await pump(tester);
      await openOffer(tester, 'Business cards');
      await tester.tap(find.widgetWithText(ConsoleButton, en.svcBoRestore));
      await tester.pumpAndSettle();
      await tester.enterText(dialogField(), 'Reviews were genuine');
      await tester.tap(dialogButton(en.svcBoRestore));
      await tester.pumpAndSettle();

      expect(find.text(en.svcBoRestoreRefused), findsOneWidget);
      expect(api.lists, hasLength(2));
    });
  });

  testWidgets('reads right to left in Arabic, list and detail alike', (WidgetTester tester) async {
    await pump(tester, locale: const Locale('ar'), size: const Size(1280, 800));

    expect(find.text(ar.svcBoOffersTitle), findsOneWidget);
    expect(find.text(ar.svcBoOfferActive), findsWidgets);
    expect(Directionality.of(tester.element(find.byType(ConsoleTable))), TextDirection.rtl);

    await openOffer(tester, 'Business cards');
    expect(find.text(ar.svcBoFulfilBoth), findsOneWidget);
    expect(find.widgetWithText(ConsoleButton, ar.svcBoTakeDown), findsOneWidget);
  });
}
