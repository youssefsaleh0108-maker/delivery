import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
// For CustomSemanticsAction and SemanticsAction: the drag is a long press, so the move a test can
// drive without pixel geometry is the same named action a screen reader is offered.
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The menu builder (Figma 139:8): the shop's own sections with the items inside them.
///
/// What is pinned here is that it is the **existing** catalogue arranged, not a second one:
///
/// * the sections are the shop's own rows and the items are its own products, grouped and ordered
///   the way the public page groups and orders them;
/// * the availability switch sends `publish` and `archive` — the only thing this platform means by
///   "on the shelf", and the very calls the catalogue list sends — and never touches `inStock`,
///   which belongs to inventory-service;
/// * a drag sends the whole section's ids to **that shop's** endpoint, and a refusal puts the list
///   back rather than leaving the merchant looking at an order customers will never see;
/// * Preview opens the shop's real public page rather than a drawing of it.
const String _origin = 'https://www.youdrop.shop';

class _MenuServer implements HttpClientAdapter {
  _MenuServer({this.pinned = true, this.listed = true, this.sections = true});

  final bool pinned;
  final bool listed;

  /// False leaves every item unsectioned, which is the state of a shop that never made a section.
  final bool sections;

  /// Every write the screen made, newest last: `POST /api/products/{id}/publish` and so on.
  final List<String> wrote = <String>[];

  /// The body of the last reorder, so a test can assert the whole block went up.
  List<String>? reordered;
  String? reorderedPath;

  /// Set to refuse the reorder, which is the case the list has to put back.
  bool refuseReorder = false;

  Map<String, dynamic> _store() => <String, dynamic>{
        'id': 'store-1',
        'slug': 'boulangerie-antoine',
        'name': 'Boulangerie Antoine',
        'vertical': 'RESTAURANT',
        'availability': 'OPEN',
        'status': listed ? 'ACTIVE' : 'DRAFT',
        'deliveryFee': 2.5,
        'minOrder': 10.0,
        'etaMinMinutes': 20,
        'etaMaxMinutes': 40,
        if (pinned) 'latitude': 33.8938,
        if (pinned) 'longitude': 35.5018,
      };

  /// Three breads and two drinks. The positions and the names deliberately disagree, so a screen
  /// that fell back to the alphabet would be visible.
  static final List<Map<String, dynamic>> _shelf = <Map<String, dynamic>>[
    _item('p-knefe', 'Knefe', 5.0, 'sec-bread', 0, 'ACTIVE', 'Sweet cheese pastry'),
    _item('p-croissant', 'Croissant au Beurre', 2.5, 'sec-bread', 1, 'ACTIVE',
        'Fresh butter croissant'),
    _item('p-manouche', 'Zaatar Manouche', 1.5, 'sec-bread', 2, 'ARCHIVED', null),
    _item('p-ayran', 'Ayran', 1.0, 'sec-drinks', 0, 'ACTIVE', null),
    _item('p-coffee', 'Coffee', 2.0, 'sec-drinks', 1, 'ACTIVE', null),
  ];

  static Map<String, dynamic> _item(String id, String name, double price, String section,
          int position, String status, String? about) =>
      <String, dynamic>{
        'id': id,
        'merchantId': 'kc-sub-merchant',
        'storeId': 'store-1',
        'name': name,
        'description': about,
        'price': price,
        'categoryId': section,
        'status': status,
        'position': position,
        'inStock': true,
        'imageRefs': <String>[],
        'imageUrls': <String>[],
        'imageThumbUrls': <String>[],
      };

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final String path = options.path;
    Object body;

    if (path.endsWith('/products/order')) {
      if (refuseReorder) {
        // No `detail`, so the screen falls back to its own sentence. A server that sent one would
        // have it shown instead — that passthrough is pinned by the catalogue list's own tests.
        return _json(<String, dynamic>{}, 422);
      }
      reorderedPath = path;
      reordered = ((options.data as Map<String, dynamic>)['productIds'] as List<dynamic>)
          .cast<String>();
      body = reordered!;
    } else if (path.endsWith('/publish') || path.endsWith('/resume')) {
      wrote.add(path);
      body = _afterWrite(path, 'ACTIVE');
    } else if (options.method == 'DELETE' && path.startsWith('/api/products/')) {
      wrote.add('$path#archive');
      body = _afterWrite(path, 'ARCHIVED');
    } else if (path.contains('/categories')) {
      body = sections
          ? <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'sec-bread',
                'name': 'Breads & Pastries',
                'storeId': 'store-1',
                'position': 0,
              },
              <String, dynamic>{
                'id': 'sec-drinks',
                'name': 'Drinks',
                'storeId': 'store-1',
                'position': 1,
              },
            ]
          : <Map<String, dynamic>>[];
    } else if (path.endsWith('/products/mine')) {
      body = <String, dynamic>{
        // Deliberately not in menu order: the wire order is `createdAt DESC`, and the screen has
        // to arrange it. A test that received it sorted would prove nothing.
        'content': _shelf.reversed.toList(),
        'page': 0,
        'size': 200,
        'totalElements': _shelf.length,
        'totalPages': 1,
      };
    } else {
      body = _store();
    }
    return _json(body, 200);
  }

  Map<String, dynamic> _afterWrite(String path, String status) {
    final String id = path.split('/')[3];
    final Map<String, dynamic> item = Map<String, dynamic>.of(
        _shelf.firstWhere((Map<String, dynamic> p) => p['id'] == id));
    item['status'] = status;
    return item;
  }

  ResponseBody _json(Object body, int status) =>
      ResponseBody.fromString(jsonEncode(body), status, headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType]
      });

  @override
  void close({bool force = false}) {}
}

/// What the app asked a browser to open.
class _Spy {
  final List<String> launched = <String>[];

  void install(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (MethodCall call) async {
        final Object? arguments = call.arguments;
        if (arguments is Map<Object?, Object?> && arguments['url'] is String) {
          launched.add(arguments['url']! as String);
        }
        return true;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'), null));
  }
}

late _MenuServer _server;

Future<_Spy> _pump(
  WidgetTester tester, {
  String? storeId = 'store-1',
  bool pinned = true,
  bool listed = true,
  bool sections = true,
  Locale locale = const Locale('en'),
  Size size = const Size(400, 2000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _Spy spy = _Spy()..install(tester);
  _server = _MenuServer(pinned: pinned, listed: listed, sections: sections);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = _server;

  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    locale: locale,
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: MenuBuilderScreen(
      api: CatalogApi(dio),
      storeApi: StoreApi(dio),
      storeId: storeId,
    ),
  ));
  await tester.pumpAndSettle();
  return spy;
}

/// Opens a section by tapping its heading.
Future<void> _open(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  // ---------------------------------------------------------------- the shop's real menu

  testWidgets("it draws the shop's own sections, with its own items counted",
      (WidgetTester tester) async {
    await _pump(tester);

    expect(find.text('Breads & Pastries'), findsOneWidget);
    expect(find.text('Drinks'), findsOneWidget);
    expect(find.text(en.menuItemCount(3)), findsOneWidget);
    expect(find.text(en.menuItemCount(2)), findsOneWidget);
    // The first section opens by default, as the design draws it; a shop with nine sections should
    // not open onto ninety rows.
    expect(find.text('Croissant au Beurre'), findsOneWidget);
    expect(find.text('Ayran'), findsNothing);
  });

  testWidgets('an item card carries its photo slot, name, price, description and switch',
      (WidgetTester tester) async {
    await _pump(tester);

    expect(find.text('Croissant au Beurre'), findsOneWidget);
    expect(find.text('\$2.50'), findsOneWidget);
    expect(find.text('Fresh butter croissant'), findsOneWidget);
    // Three items in the open section, three switches.
    expect(find.byType(MerchantAvailabilitySwitch), findsNWidgets(3));
    // No photo on any of them, which is the commonest row in a shop's first week.
    expect(find.byTooltip(en.noPhoto), findsNWidgets(3));
    // An item with nothing written about it says so rather than leaving a hole.
    expect(find.text(en.menuNoDescription), findsOneWidget);
  });

  testWidgets('the items come out in the order the shop put them in, not the alphabet',
      (WidgetTester tester) async {
    await _pump(tester);

    final double knefe = tester.getTopLeft(find.text('Knefe')).dy;
    final double croissant = tester.getTopLeft(find.text('Croissant au Beurre')).dy;
    final double manouche = tester.getTopLeft(find.text('Zaatar Manouche')).dy;
    // position 0, 1, 2. Alphabetically it would be Croissant, Knefe, Zaatar — so a screen that
    // sorted by name would fail here, and so would one that drew the wire order.
    expect(knefe, lessThan(croissant));
    expect(croissant, lessThan(manouche));
  });

  testWidgets('an item the merchant switched off is still on the menu, switched off',
      (WidgetTester tester) async {
    await _pump(tester);

    // Archived is "not on the shelf", not "gone": it keeps its place, so switching it back on does
    // not drop it to the bottom.
    final MerchantAvailabilitySwitch manouche = tester.widget<MerchantAvailabilitySwitch>(
        find.byType(MerchantAvailabilitySwitch).at(2));
    expect(manouche.value, isFalse);
  });

  testWidgets('a shop with no sections still shows what it sells', (WidgetTester tester) async {
    await _pump(tester, sections: false);

    // The page draws unsectioned items in a block of its own at the end, so the builder does too —
    // hiding them would be hiding items the shop really does sell.
    expect(find.text(en.menuOtherItems), findsOneWidget);
    expect(find.text(en.menuItemCount(5)), findsOneWidget);
  });

  // ---------------------------------------------------------------- the switch

  testWidgets('switching an item on sends publish — the platform\'s own "on the shelf"',
      (WidgetTester tester) async {
    await _pump(tester);

    // The archived one, third in the open section.
    await tester.tap(find.byType(MerchantAvailabilitySwitch).at(2));
    await tester.pumpAndSettle();

    expect(_server.wrote, <String>['/api/products/p-manouche/publish']);
    final MerchantAvailabilitySwitch manouche = tester.widget<MerchantAvailabilitySwitch>(
        find.byType(MerchantAvailabilitySwitch).at(2));
    expect(manouche.value, isTrue);
  });

  testWidgets('switching an item off asks first, then archives it', (WidgetTester tester) async {
    await _pump(tester);

    await tester.tap(find.byType(MerchantAvailabilitySwitch).first);
    await tester.pumpAndSettle();

    // A mis-tapped switch beside a scrolling list should not take an item off a live page silently.
    expect(find.text(en.menuTakeOffTitle), findsOneWidget);
    await tester.tap(find.text(en.menuTakeOff));
    await tester.pumpAndSettle();

    expect(_server.wrote, <String>['/api/products/p-knefe#archive']);
  });

  testWidgets('cancelling the question leaves the item on the shelf', (WidgetTester tester) async {
    await _pump(tester);

    await tester.tap(find.byType(MerchantAvailabilitySwitch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.cancel));
    await tester.pumpAndSettle();

    expect(_server.wrote, isEmpty);
    expect(
        tester.widget<MerchantAvailabilitySwitch>(find.byType(MerchantAvailabilitySwitch).first)
            .value,
        isTrue);
  });

  // ---------------------------------------------------------------- the drag

  testWidgets('moving an item sends the whole section, to this shop, and settles on the answer',
      (WidgetTester tester) async {
    await _pump(tester);

    // The accessible path to the same move the long press makes — and the one a test can drive
    // without a gesture that depends on pixel geometry.
    final SemanticsHandle handle = tester.ensureSemantics();
    await _moveDown(tester, 'Knefe', en.menuMoveDown);
    handle.dispose();

    // The whole block, in the order it now stands, to the section it belongs to — under this shop,
    // never "the merchant's first shop".
    expect(_server.reorderedPath,
        '/api/stores/store-1/categories/sec-bread/products/order');
    expect(_server.reordered, <String>['p-croissant', 'p-knefe', 'p-manouche']);
    // Including the archived one: leaving it out would be a partial list, which the server refuses.
    expect(_server.reordered, contains('p-manouche'));

    final double knefe = tester.getTopLeft(find.text('Knefe')).dy;
    final double croissant = tester.getTopLeft(find.text('Croissant au Beurre')).dy;
    expect(croissant, lessThan(knefe));
  });

  testWidgets('a refused move puts the menu back the way customers will see it',
      (WidgetTester tester) async {
    await _pump(tester);
    _server.refuseReorder = true;

    final SemanticsHandle handle = tester.ensureSemantics();
    await _moveDown(tester, 'Knefe', en.menuMoveDown);
    handle.dispose();

    expect(find.text(en.menuCouldNotReorder), findsOneWidget);
    // A screen that silently kept an order the server refused would be lying about the page.
    final double knefe = tester.getTopLeft(find.text('Knefe')).dy;
    final double croissant = tester.getTopLeft(find.text('Croissant au Beurre')).dy;
    expect(knefe, lessThan(croissant));
  });

  testWidgets('the unsectioned block has no order to drag', (WidgetTester tester) async {
    await _pump(tester, sections: false);
    await _open(tester, en.menuOtherItems);

    // There is no section behind it to hold an order, and the page draws those items last.
    expect(find.byType(ReorderableListView), findsNothing);
  });

  // ---------------------------------------------------------------- Preview

  testWidgets("Preview opens the shop's real page in the merchant's language",
      (WidgetTester tester) async {
    final _Spy spy = await _pump(tester, locale: const Locale('ar'));

    await tester.tap(find.text(ar.menuPreview));
    await tester.pumpAndSettle();

    expect(spy.launched, <String>['$_origin/s/boulangerie-antoine?lang=ar']);
  });

  testWidgets('a shop with no page offers no preview of a 404', (WidgetTester tester) async {
    final _Spy spy = await _pump(tester, pinned: false);

    await tester.tap(find.text(en.menuPreview));
    await tester.pumpAndSettle();

    expect(spy.launched, isEmpty);
  });

  // ---------------------------------------------------------------- the two edges

  testWidgets('a merchant with two shops arranges the one they are looking at',
      (WidgetTester tester) async {
    await _pump(tester, storeId: 'store-2');

    final SemanticsHandle handle = tester.ensureSemantics();
    await _moveDown(tester, 'Knefe', en.menuMoveDown);
    handle.dispose();

    // The shop in the widget's own storeId, never "the first shop this merchant owns": a drag in
    // the second shop's menu must not arrive at the first one's.
    expect(_server.reorderedPath,
        '/api/stores/store-2/categories/sec-bread/products/order');
  });

  testWidgets('a host that has not resolved the shop yet asks for nothing',
      (WidgetTester tester) async {
    await _pump(tester, storeId: null);

    expect(find.text(en.noShopYet), findsOneWidget);
  });

  testWidgets('it reads in Arabic on a 320dp phone without overflowing',
      (WidgetTester tester) async {
    await _pump(tester, locale: const Locale('ar'), size: const Size(320, 2000));

    expect(Directionality.of(tester.element(find.byType(MenuBuilderScreen))), TextDirection.rtl);
    expect(find.text(ar.menuBuilderTitle), findsOneWidget);
    expect(find.text(ar.menuAddItem), findsOneWidget);
    expect(find.text(ar.menuPreview), findsOneWidget);
    expect(find.text(ar.menuNoDescription), findsOneWidget);
    // A price read right to left is a price read wrong.
    final Text price = tester.widget<Text>(find.text('\$2.50'));
    expect(price.textDirection, TextDirection.ltr);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every switch a thumb has to hit is on a card a thumb can hit',
      (WidgetTester tester) async {
    await _pump(tester, size: const Size(320, 2000));

    for (int i = 0; i < 3; i++) {
      final Size card = tester.getSize(find.byType(MerchantAvailabilitySwitch).at(i));
      expect(card.width, greaterThanOrEqualTo(44));
    }
    expect(tester.takeException(), isNull);
  });
}

/// Drives the row's "move down" semantics action, which is the same move as the long-press drag.
///
/// Through semantics rather than a gesture: the drag is a long press on the card, and a test that
/// aimed one would be asserting pixel geometry. This is the path a screen reader takes, so pinning
/// it pins both — the order that reaches the server, and the fact that the order is reachable at
/// all without a long press.
Future<void> _moveDown(WidgetTester tester, String item, String label) async {
  final SemanticsNode node = tester.getSemantics(
      find.ancestor(of: find.text(item), matching: find.byType(YdCard)));
  final int id = node.getSemanticsData().customSemanticsActionIds!.firstWhere(
      (int id) => CustomSemanticsAction.getAction(id)!.label == label);
  tester.binding.performSemanticsAction(
      SemanticsActionEvent(type: SemanticsAction.customAction, nodeId: node.id, viewId: 0,
          arguments: id));
  await tester.pumpAndSettle();
}
