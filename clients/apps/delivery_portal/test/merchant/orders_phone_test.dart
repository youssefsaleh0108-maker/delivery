import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The order queue on a phone.
///
/// The portal has always given this screen a wide window, so nothing here was ever asked to fit
/// 320dp — and a layout that does not fit fails silently in a release build, where the overflow
/// stripe is not drawn and the merchant simply cannot reach the Accept button. These pump it at the
/// sizes a real phone reports and let the framework's own overflow errors fail the test.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body);

  final Object body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _order({
  required String id,
  String status = 'PLACED',
  String? riderId,
  List<String> actions = const <String>['ACCEPT', 'CANCEL'],
}) =>
    <String, dynamic>{
      'id': id,
      'customerId': 'customer-1',
      'merchantId': 'merchant-1',
      'riderId': riderId,
      'status': status,
      'totalAmount': 1234.50,
      'deliveryFee': 3.5,
      'merchantFeeWaived': true,
      // Long on purpose. A short address fits anywhere and finds nothing.
      'deliveryAddress':
          'Building 42, Fourth Floor, Rue des Martyrs de la Liberté, Bab El Oued, Algiers',
      'contactPhone': '+213555000111',
      'notes': 'Please ring the bell twice, the intercom on the street door has been broken '
          'since the spring and nobody upstairs can hear it.',
      'items': <dynamic>[
        <String, dynamic>{
          'productId': 'p1',
          'productName': 'Slow-Roasted Something With A Very Long Product Name',
          'unitPrice': 12.5,
          'qty': 2,
          'lineTotal': 25.0,
        },
      ],
      'availableActions': actions,
      'placedAt': '2026-08-16T10:00:00Z',
      'deliveredAt': null,
      'cancelReason': null,
    };

Object _page(List<Map<String, dynamic>> orders) => <String, dynamic>{
      'content': orders,
      'page': 0,
      'size': 50,
      'totalElements': orders.length,
      'totalPages': 1,
    };

OrderApi _api(Object page) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
    ..httpClientAdapter = _StubAdapter(page);
  return OrderApi(dio);
}

Widget _wrap(Widget child, {Locale locale = const Locale('en'), double textScale = 1.0}) =>
    MaterialApp(
      locale: locale,
      theme: DeliveryTheme.light(),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // The scaler goes inside the app, not around it. MaterialApp installs its own MediaQuery from
      // the view, so a MediaQuery wrapped around it is discarded and a "textScale 1.3" test quietly
      // becomes a second copy of the 1.0 one.
      builder: (BuildContext context, Widget? home) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: home!,
      ),
      // A Scaffold because the screen shows a SnackBar when an action is refused, and because the
      // hosts both give it one.
      home: Scaffold(body: child),
    );

/// An order row, as opposed to any old card.
///
/// The four counter tiles at the top are SoftCards too, so `find.byType(SoftCard)` answers "is
/// anything drawn" rather than "is an order drawn" — and reports four of them on an empty queue.
/// Only an order row prints a `#id`.
final Finder _orderRows = find.textContaining('#');

Object _busyQueue() => _page(<Map<String, dynamic>>[
      _order(id: 'aaaaaaaa-1111'),
      _order(id: 'bbbbbbbb-2222', status: 'ACCEPTED', actions: <String>['PREPARE', 'CANCEL']),
      _order(
          id: 'cccccccc-3333',
          status: 'READY',
          riderId: 'rider-9',
          actions: <String>['CANCEL']),
      _order(id: 'dddddddd-4444', status: 'DELIVERED', actions: <String>[]),
    ]);

void main() {
  Future<void> pumpAt(WidgetTester tester, Size size,
      {double textScale = 1.0, Locale locale = const Locale('en'), Object? page}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(
      OrdersScreen(api: _api(page ?? _busyQueue())),
      locale: locale,
      textScale: textScale,
    ));
    await tester.pumpAndSettle();
    // The screen polls on a periodic Timer, which the test binding refuses to leave running. Only
    // dispose cancels it, so the tree has to go before the test ends.
    addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
  }

  for (final Size size in <Size>[
    const Size(320, 640),
    const Size(360, 640),
    const Size(360, 800),
    const Size(412, 915),
    // A phone on its side: wide enough to look like a desktop and far too short to pin a header.
    const Size(800, 360),
  ]) {
    testWidgets('orders @ $size', (WidgetTester tester) async {
      await pumpAt(tester, size);
      expect(_orderRows, findsWidgets);
    });

    testWidgets('orders @ $size textScale 1.3', (WidgetTester tester) async {
      await pumpAt(tester, size, textScale: 1.3);
      expect(_orderRows, findsWidgets);
    });

    testWidgets('orders @ $size in Arabic', (WidgetTester tester) async {
      await pumpAt(tester, size, locale: const Locale('ar'));
      expect(_orderRows, findsWidgets);
    });
  }

  testWidgets('nothing scrolls sideways on a phone', (WidgetTester tester) async {
    // Both widths and both scales: the tab strip that carries four translated labels and their
    // counts is the widest thing on this page, and 1.3 is the scale this file has always run at on
    // CI — it is where a strip that fits at 320dp stops fitting.
    for (final Size size in <Size>[const Size(320, 640), const Size(360, 640)]) {
      for (final double scale in <double>[1.0, 1.3]) {
        await pumpAt(tester, size, textScale: scale);
        final Iterable<Scrollable> scrollables =
            tester.widgetList<Scrollable>(find.byType(Scrollable));
        expect(scrollables, isNotEmpty, reason: '$size @ $scale');
        for (final Scrollable s in scrollables) {
          expect(s.axisDirection, anyOf(AxisDirection.down, AxisDirection.up),
              reason: 'a horizontal scroller on a ${size.width}dp page hides half the row '
                  'behind a gesture');
        }
      }
    }
  });

  testWidgets('the counters scroll away with the header on a phone', (WidgetTester tester) async {
    await pumpAt(tester, const Size(360, 640));
    // One scroll view for the whole page, not a pinned block above a second one.
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    // The four counter tiles are the four counted tabs now. Both they and the title band are
    // inside that one scroll view rather than pinned above it, which is what this test has always
    // meant by "scroll away with the header".
    final Finder page = find.byType(CustomScrollView);
    expect(find.descendant(of: page, matching: find.byType(MerchantScreenHeader)), findsOneWidget);
    expect(find.descendant(of: page, matching: find.textContaining('New (')), findsOneWidget);
  });

  testWidgets('the wide portal keeps its pinned header', (WidgetTester tester) async {
    await pumpAt(tester, const Size(1280, 900));
    expect(find.byType(CustomScrollView), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
    // The show-completed Switch this test used to count is gone, and not by accident: the redesign
    // replaced one boolean with the four-bucket tab strip, which the phone and the portal now share
    // — so "the toggle keeps its own shape up here" no longer has a subject to protect. What the
    // toggle was *for* does: a day of delivered orders stays out of the way until it is asked for,
    // and asking for it is one tap on either host. That is what is asserted instead.
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.textContaining('#dddddddd'), findsNothing, reason: 'DELIVERED, so not in New');
    await tester.tap(find.textContaining('Completed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('#dddddddd'), findsOneWidget);
    // Still the pinned shape after the switch of buckets, not a different layout underneath.
    expect(find.byType(CustomScrollView), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('every action button clears 48dp on a phone', (WidgetTester tester) async {
    // Accept and Reject are MerchantActionButton now rather than Material's own buttons — the
    // 48dp floor is the point, not which class draws it, so the predicate names both. Checked at
    // 1.3 as well: a taller label must not be what finally pushes the button over the line.
    for (final double scale in <double>[1.0, 1.3]) {
      await pumpAt(tester, const Size(360, 640), textScale: scale);
      final Finder buttons = find.byWidgetPredicate((Widget w) =>
          w is MerchantActionButton ||
          w is YdPillButton ||
          w is ElevatedButton ||
          w is OutlinedButton);
      expect(buttons, findsWidgets);
      for (final Element e in buttons.evaluate()) {
        expect(tester.getSize(find.byWidget(e.widget)).height, greaterThanOrEqualTo(48.0),
            reason: 'textScale $scale');
      }
    }
  });

  testWidgets('an empty queue can still be pulled to refresh', (WidgetTester tester) async {
    await pumpAt(tester, const Size(360, 640), page: _page(<Map<String, dynamic>>[]));
    expect(_orderRows, findsNothing);
    // The pull has to work on the empty state too — it is the state a merchant most wants to
    // retry, and the refresh button above it may be scrolled past.
    final Finder scrollView = find.byType(CustomScrollView);
    await tester.drag(scrollView, const Offset(0, 250));
    await tester.pump();
    expect(find.byType(RefreshProgressIndicator), findsWidgets);
    await tester.pumpAndSettle();
  });
}
