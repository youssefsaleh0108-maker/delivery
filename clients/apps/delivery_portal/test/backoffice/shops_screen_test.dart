import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/backoffice/shops_screen.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Back office's Shops page and the Verified Local badge.
///
/// Pinned: the list is the storefront's own (goods shops, or service shops, searched and paged by the
/// server); the badge never changes without a confirmation, and cancelling sends nothing; the switch
/// shows what the server stored, a service shop badged exactly as a goods shop is; a refusal is said as
/// what it is and leaves the badge as it was; and the page is honest while loading, empty and failed,
/// at 1440, 1280 and a narrow window, and in Arabic.
typedef _Answer = ({int status, Object? body});

class _Routes implements HttpClientAdapter {
  _Routes(this.answer);

  final _Answer Function(RequestOptions options) answer;

  /// When set, the shop list waits on it — for the loading state.
  Completer<void>? gate;

  final List<RequestOptions> calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add(options);
    final Completer<void>? wait = gate;
    if (wait != null && options.method == 'GET') await wait.future;
    final _Answer a = answer(options);
    return ResponseBody.fromString(
      jsonEncode(a.body),
      a.status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A storefront card as `GET /api/stores` sends it.
Map<String, dynamic> _card({
  String id = 'store-print-1',
  String name = 'Print Point',
  String vertical = 'SERVICES',
  String? category = 'PRINTING',
  bool verified = false,
}) =>
    <String, dynamic>{
      'id': id,
      'slug': id,
      'name': name,
      'vertical': vertical,
      'serviceCategory': category,
      'tagline': 'Round the corner since 1998',
      'rating': null,
      'ratingCount': 0,
      'deliveryFee': 0,
      'minOrder': 0,
      'etaMinMinutes': 20,
      'etaMaxMinutes': 40,
      'availability': 'OPEN',
      'verifiedLocal': verified,
    };

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  late _Routes routes;
  late List<Map<String, dynamic>> shops;
  late int listStatus;
  late int totalPages;
  late int putStatus;

  setUp(() {
    shops = <Map<String, dynamic>>[
      _card(),
      _card(id: 'store-rose-1', name: 'Rose & Crust', vertical: 'RESTAURANT', category: null),
    ];
    listStatus = 200;
    totalPages = 1;
    putStatus = 200;
    routes = _Routes((RequestOptions o) {
      if (o.method == 'PUT') {
        if (putStatus != 200) {
          return (status: putStatus, body: <String, dynamic>{'status': putStatus});
        }
        final bool verified = (o.data as Map<String, dynamic>)['verified'] as bool;
        return (
          status: 200,
          body: <String, dynamic>{
            'id': 'store-print-1',
            'slug': 'print-point',
            'name': 'Print Point',
            'vertical': 'SERVICES',
            'serviceCategory': 'PRINTING',
            'status': 'ACTIVE',
            'availability': 'OPEN',
            'verifiedLocal': verified,
          },
        );
      }
      if (listStatus != 200) {
        return (status: listStatus, body: <String, dynamic>{'status': listStatus});
      }
      return (
        status: 200,
        body: <String, dynamic>{
          'content': shops,
          'page': int.tryParse('${o.queryParameters['page']}') ?? 0,
          'totalElements': shops.length,
          'totalPages': totalPages,
        },
      );
    });
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    Locale locale = const Locale('en'),
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = routes;
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      locale: locale,
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: Scaffold(body: ShopsScreen(api: StoreApi(dio))),
    ));
    if (settle) await tester.pumpAndSettle();
  }

  Iterable<RequestOptions> lists() => routes.calls.where((RequestOptions o) => o.method == 'GET');

  Iterable<RequestOptions> puts() => routes.calls.where((RequestOptions o) => o.method == 'PUT');

  Switch badgeOf(WidgetTester tester, int row) =>
      tester.widget<Switch>(find.byType(Switch).at(row));

  group('states', () {
    testWidgets('a spinner while the shops load', (WidgetTester tester) async {
      routes.gate = Completer<void>();
      await pump(tester, settle: false);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      routes.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Print Point'), findsOneWidget);
    });

    testWidgets('no match says so', (WidgetTester tester) async {
      shops = <Map<String, dynamic>>[];
      await pump(tester);

      expect(find.text(en.svcBoShopsEmpty), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('a failed read says so, and Try again reads again', (WidgetTester tester) async {
      listStatus = 500;
      await pump(tester);

      expect(find.text(en.svcBoShopsLoadFailed), findsOneWidget);
      listStatus = 200;
      await tester.tap(find.text(en.tryAgain));
      await tester.pumpAndSettle();
      expect(lists(), hasLength(2));
      expect(find.text('Print Point'), findsOneWidget);
    });
  });

  for (final Size size in const <Size>[Size(1440, 900), Size(1280, 800), Size(1024, 720)]) {
    testWidgets('lists shops with their kind and badge at ${size.width.toInt()}px',
        (WidgetTester tester) async {
      await pump(tester, size: size);

      expect(find.text(en.svcBoShopsListedOnly), findsOneWidget);
      expect(find.text(en.svcBoKindServiceIn(en.svcCategoryPrinting)), findsOneWidget);
      expect(find.text(StoreVertical.restaurant.labelIn(en)), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(2));
    });
  }

  testWidgets('goods or service shops, search and pages are asked of the server',
      (WidgetTester tester) async {
    totalPages = 2;
    await pump(tester);
    expect(lists().last.queryParameters.containsKey('vertical'), isFalse);

    await tester.tap(find.text(en.svcBoShopsServices));
    await tester.pumpAndSettle();
    expect(lists().last.queryParameters['vertical'], 'SERVICES');
    expect(lists().last.queryParameters['page'], 0);

    await tester.enterText(find.byType(TextField), ' print ');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(lists().last.queryParameters['search'], 'print');

    await tester.tap(find.text(en.next));
    await tester.pumpAndSettle();
    expect(lists().last.queryParameters['page'], 1);
    expect(lists().last.queryParameters['vertical'], 'SERVICES');
  });

  testWidgets('the badge never changes without a confirmation, and cancelling sends nothing',
      (WidgetTester tester) async {
    await pump(tester);
    expect(badgeOf(tester, 0).value, isFalse);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text(en.svcBoVerifyGrantTitle('Print Point')), findsOneWidget);
    expect(find.text(en.svcBoVerifyGrantBody), findsOneWidget);

    await tester.tap(find.widgetWithText(ConsoleButton, en.cancel));
    await tester.pumpAndSettle();
    expect(puts(), isEmpty);
    expect(badgeOf(tester, 0).value, isFalse);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ConsoleButton, en.svcBoVerifyGrant));
    await tester.pumpAndSettle();

    final RequestOptions sent = puts().single;
    expect(sent.path, '/api/stores/store-print-1/verified-local');
    expect(sent.data, <String, dynamic>{'verified': true});
    // A service shop is badged exactly as a goods shop is, and the switch shows what was stored.
    expect(badgeOf(tester, 0).value, isTrue);
    expect(find.text(en.svcBoVerifyGranted('Print Point')), findsOneWidget);
  });

  testWidgets('withdrawing the badge asks too, and says what was stored',
      (WidgetTester tester) async {
    shops = <Map<String, dynamic>>[_card(verified: true)];
    await pump(tester);
    expect(badgeOf(tester, 0).value, isTrue);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text(en.svcBoVerifyRevokeTitle('Print Point')), findsOneWidget);
    await tester.tap(find.widgetWithText(ConsoleButton, en.svcBoVerifyRevoke));
    await tester.pumpAndSettle();

    expect(puts().single.data, <String, dynamic>{'verified': false});
    expect(badgeOf(tester, 0).value, isFalse);
    expect(find.text(en.svcBoVerifyRevoked('Print Point')), findsOneWidget);
  });

  testWidgets('a refused change says only back office may, and leaves the badge as it was',
      (WidgetTester tester) async {
    putStatus = 403;
    await pump(tester);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ConsoleButton, en.svcBoVerifyGrant));
    await tester.pumpAndSettle();

    expect(find.text(en.svcBoVerifyRefused), findsOneWidget);
    expect(badgeOf(tester, 0).value, isFalse);
  });

  testWidgets('a shop that is gone says so', (WidgetTester tester) async {
    putStatus = 404;
    await pump(tester);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ConsoleButton, en.svcBoVerifyGrant));
    await tester.pumpAndSettle();

    expect(find.text(en.svcBoVerifyGone), findsOneWidget);
    expect(badgeOf(tester, 0).value, isFalse);
  });

  testWidgets('reads right to left in Arabic, the confirmation included',
      (WidgetTester tester) async {
    await pump(tester, locale: const Locale('ar'), size: const Size(1024, 720));

    expect(find.text(ar.svcBoShopsTitle), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(ConsoleTable))), TextDirection.rtl);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.text(ar.svcBoVerifyGrantTitle('Print Point')), findsOneWidget);
    await tester.tap(find.widgetWithText(ConsoleButton, ar.svcBoVerifyGrant));
    await tester.pumpAndSettle();
    expect(find.text(ar.svcBoVerifyGranted('Print Point')), findsOneWidget);
  });
}
