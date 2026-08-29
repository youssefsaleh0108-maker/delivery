import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shop's own statement.
///
/// Three things are load-bearing here and each has a test that fails loudly if it stops being true.
///
/// 1. The route is `/mine` and carries no counterparty. A shop can only ever be shown itself, and
///    the moment a ref appears in a path on this screen that is a data leak rather than a feature.
/// 2. The figure is the ledger's record and *not a payment*. There is no payout mechanism; a shop
///    that reads "owed to you" as "money is coming" will wait for a transfer nobody is going to
///    send. The sentence saying so has to be on screen with the number, on the first paint, on a
///    phone.
/// 3. A range with no trade in it, and a request that failed, must never render as money. An empty
///    range is not a settled balance and a failure is not a zero — both of those are claims the
///    ledger did not make, and both of them are claims a shop would act on.
class _StatementAdapter implements HttpClientAdapter {
  _StatementAdapter(this.body, {this.status = 200});

  final Object body;
  final int status;

  /// Every request, path and range, in the order they were made.
  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}'
        '?from=${options.queryParameters['from']}&to=${options.queryParameters['to']}');
    return ResponseBody.fromString(jsonEncode(body), status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

/// The contract's own example, with the production numbers behind it: 2425.00 collected, 303.20 of
/// commission at 12.5%, 2121.80 left for the shop.
Map<String, dynamic> _statement({
  Object? net = const <String, dynamic>{'amount': '2121.80', 'direction': 'WE_OWE'},
  List<Map<String, dynamic>>? lines,
  List<Map<String, dynamic>>? entries,
  String? note,
}) =>
    <String, dynamic>{
      'kind': 'MERCHANT',
      'ref': 'e2b0c7f4-0000-4000-8000-000000000001',
      'name': 'Rose & Crust Pizzeria',
      'from': '2026-08-01',
      'to': '2026-08-29',
      'currency': 'USD',
      'generatedAt': '2026-08-29T05:00:00Z',
      'net': net,
      'lines': lines ??
          <Map<String, dynamic>>[
            <String, dynamic>{
              'label': 'Goods sold',
              'amount': '2425.00',
              'direction': 'CREDIT',
              'note': '45 orders',
            },
            <String, dynamic>{
              'label': 'Platform commission (12.5%)',
              'amount': '303.20',
              'direction': 'DEBIT',
              'note': null,
            },
          ],
      'entries': entries ??
          <Map<String, dynamic>>[
            <String, dynamic>{
              'orderId': 'a1b2c3d4-9999-4000-8000-00000000000f',
              'at': '2026-08-23T11:09:40Z',
              'gross': '19.50',
              'commission': '2.44',
              'net': '17.06',
              'paymentMethod': 'CASH',
            },
          ],
      'note': note,
    };

/// A range the shop did no trade in: no lines, no orders, and a net the server calls settled.
Map<String, dynamic> _quietRange() => <String, dynamic>{
      'kind': 'MERCHANT',
      'ref': 'e2b0c7f4-0000-4000-8000-000000000001',
      'name': 'Rose & Crust Pizzeria',
      'from': '2026-07-01',
      'to': '2026-07-31',
      'currency': 'USD',
      'lines': <dynamic>[],
      'entries': <dynamic>[],
      'net': <String, dynamic>{'amount': '0.00', 'direction': 'SETTLED'},
    };

/// The 29th of August 2026, so "this month" is a range the tests can name exactly.
final DateTime _today = DateTime(2026, 8, 29);

Future<_StatementAdapter> _pump(
  WidgetTester tester, {
  Object? body,
  int status = 200,
  Locale locale = const Locale('en'),
  Size size = const Size(400, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _StatementAdapter adapter = _StatementAdapter(body ?? _statement(), status: status);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;

  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    locale: locale,
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: MerchantStatementScreen(api: StatementsApi(dio), today: _today),
  ));
  await tester.pumpAndSettle();
  return adapter;
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  const MerchantStatementWords w = MerchantStatementWords.en;
  const MerchantStatementWords war = MerchantStatementWords.ar;

  group('scope', () {
    testWidgets('asks the self-serve route and names no counterparty',
        (WidgetTester tester) async {
      final _StatementAdapter adapter = await _pump(tester);

      // `/mine` decides whose statement it is from the token. A ref anywhere in this path would be
      // one shop able to address another.
      expect(adapter.calls,
          <String>['GET /api/accounting/statements/mine?from=2026-08-01&to=2026-08-29']);
      expect(adapter.calls.single, isNot(contains('MERCHANT')));
    });

    testWidgets('a new range is a new request, not a client-side filter',
        (WidgetTester tester) async {
      // Wide enough that the whole preset strip is on screen and tappable.
      final _StatementAdapter adapter =
          await _pump(tester, size: const Size(900, 2400));

      await tester.tap(find.text(w.presetLast7));
      await tester.pumpAndSettle();

      // Seven days INCLUSIVE ends on today, so the 23rd is the first of them.
      expect(adapter.calls.last,
          'GET /api/accounting/statements/mine?from=2026-08-23&to=2026-08-29');
    });

    testWidgets('last month ends when last month ended', (WidgetTester tester) async {
      final _StatementAdapter adapter =
          await _pump(tester, size: const Size(900, 2400));

      await tester.tap(find.text(w.presetLastMonth));
      await tester.pumpAndSettle();

      // Not "1 July to today" — a shop reconciling July must not be handed August as well.
      expect(adapter.calls.last,
          'GET /api/accounting/statements/mine?from=2026-07-01&to=2026-07-31');
    });
  });

  group('a loaded statement', () {
    testWidgets('shows the ledger\'s own digits, unrounded and unrecomputed',
        (WidgetTester tester) async {
      await _pump(tester);

      // The bottom line, unsigned — the direction is words, not a character to interpret.
      expect(find.text('2121.80'), findsOneWidget);
      expect(find.text(w.owedToYou), findsOneWidget);
      expect(find.text('USD'), findsOneWidget);

      // The summary, with the server's own labels and its own commission percentage.
      expect(find.text('Goods sold'), findsOneWidget);
      expect(find.text('Platform commission (12.5%)'), findsOneWidget);
      expect(find.text('45 orders'), findsOneWidget);
      expect(find.text('+2425.00'), findsOneWidget);
      expect(find.text('-303.20'), findsOneWidget);
    });

    testWidgets('lists the orders behind it so a shop can check its till',
        (WidgetTester tester) async {
      await _pump(tester);

      expect(find.text(w.ordersBehind), findsOneWidget);
      // The same first-eight reference the merchant's own order cards carry.
      expect(find.text('#a1b2c3d4'), findsOneWidget);
      expect(find.text('19.50'), findsOneWidget);
      expect(find.text('2.44'), findsOneWidget);
      expect(find.text('17.06'), findsOneWidget);

      // The ledger has no delivered-at on a merchant leg, so the date is when settlement was
      // written. A shop reconciling by day has to be told that, or an order that landed just
      // after midnight looks like a missing one.
      expect(find.text(w.entriesDateNote), findsOneWidget);
    });

    testWidgets('says on the first paint that the figure is not a payment',
        (WidgetTester tester) async {
      await _pump(tester);

      // The whole reason this screen is careful. There is no payout mechanism, so "owed to you"
      // must never be read as "on its way" — and the sentence saying so sits in the same card as
      // the number, not at the bottom of a scroll a shop owner will not reach.
      expect(find.text(w.notAPayment), findsOneWidget);
      expect(w.notAPayment, contains('not a payment'));

      final Offset figure = tester.getCenter(find.text('2121.80'));
      final Offset caveat = tester.getCenter(find.text(w.notAPayment));
      expect(caveat.dy, greaterThan(figure.dy));
      // Within a phone screen of it, rather than somewhere further down the page.
      expect(caveat.dy - figure.dy, lessThan(400));
    });

    testWidgets('renders the server\'s note rather than dropping it',
        (WidgetTester tester) async {
      const String note =
          'Commission could not be split between goods and delivery on 3 orders.';
      await _pump(tester, body: _statement(note: note));

      // It is where accounting explains a total that would otherwise look wrong. Dropping it
      // leaves the shop with the wrong-looking total and none of the explanation.
      expect(find.text(note), findsOneWidget);
    });

    testWidgets('a figure the server did not send is a dash, never a zero',
        (WidgetTester tester) async {
      await _pump(
        tester,
        body: _statement(
          net: null,
          entries: <Map<String, dynamic>>[
            <String, dynamic>{
              'orderId': 'a1b2c3d4-9999-4000-8000-00000000000f',
              'at': '2026-08-23T11:09:40Z',
              'gross': '19.50',
              // No commission and no net came back for this order.
              'paymentMethod': 'CASH',
            },
          ],
        ),
      );

      expect(find.text('0.00'), findsNothing);
      expect(find.text(w.unknownFigure), findsWidgets);
      // And with no net block at all the direction is unclear, not settled — "nobody is waiting on
      // money" is not a safe thing to guess at.
      expect(find.text(w.unclear), findsOneWidget);
      expect(find.text(w.settled), findsNothing);
    });
  });

  group('a range with nothing in it', () {
    testWidgets('says so instead of drawing zeros as if the account were settled',
        (WidgetTester tester) async {
      await _pump(tester, body: _quietRange());

      expect(find.text(w.noneInRange), findsOneWidget);
      // The server called it SETTLED 0.00 and it may well be right, but this screen was asked
      // about a date range and only knows that the range was quiet. A shop shown "Settled 0.00"
      // for a month it did not trade in would believe an outstanding balance had been cleared.
      expect(find.text('0.00'), findsNothing);
      expect(find.text(w.settled), findsNothing);
      expect(find.text(w.owedToYou), findsNothing);
      expect(find.text(w.notAPayment), findsNothing);
    });
  });

  group('a failed load', () {
    testWidgets('renders no number at all and offers the way back',
        (WidgetTester tester) async {
      await _pump(tester, status: 500, body: <String, dynamic>{'detail': 'ledger unavailable'});

      expect(find.text(w.couldNotLoad), findsOneWidget);
      expect(find.text(en.tryAgain), findsOneWidget);

      // Not one invented figure: not a zero, not a dash standing where a total belongs, and no
      // direction claimed. "We could not ask the ledger" is the only honest thing on screen.
      expect(find.text('0.00'), findsNothing);
      expect(find.text('2121.80'), findsNothing);
      expect(find.text(w.owedToYou), findsNothing);
      expect(find.text(w.settled), findsNothing);
      expect(find.text(w.ordersBehind), findsNothing);
    });

    testWidgets('does not leave the previous range\'s money under the new heading',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Good for the first range, broken for the second.
      int call = 0;
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
        ..httpClientAdapter = _SwitchingAdapter(() => call++ == 0);

      await tester.pumpWidget(MaterialApp(
        theme: DeliveryTheme.light(),
        localizationsDelegates: DeliveryStrings.localizationsDelegates,
        supportedLocales: DeliveryStrings.supportedLocales,
        home: MerchantStatementScreen(api: StatementsApi(dio), today: _today),
      ));
      await tester.pumpAndSettle();
      expect(find.text('2121.80'), findsOneWidget);

      await tester.tap(find.text(w.presetLast7));
      await tester.pumpAndSettle();

      // August's total under a "23 Aug – 29 Aug" heading is a wrong answer that looks like a
      // right one.
      expect(find.text('2121.80'), findsNothing);
      expect(find.text(w.couldNotLoad), findsOneWidget);
    });
  });

  testWidgets('fits a 360dp phone in Arabic, caveat included',
      (WidgetTester tester) async {
    await _pump(tester, locale: const Locale('ar'), size: const Size(360, 2400));

    expect(tester.takeException(), isNull);
    expect(find.text(war.title), findsWidgets);
    // The sentence that matters most is the one that must not be left in English on an Arabic
    // phone. See the note on MerchantStatementWords for why these strings live in this package.
    expect(find.text(war.notAPayment), findsOneWidget);
    expect(find.text(war.owedToYou), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text(war.notAPayment))),
      TextDirection.rtl,
    );
  });

  group('the settings row', () {
    testWidgets('opens the statement once the host wires the client',
        (WidgetTester tester) async {
      final _StatementAdapter adapter = await _pumpSettings(tester, wired: true);

      expect(find.text(w.title), findsOneWidget);
      await tester.tap(find.text(w.title));
      await tester.pumpAndSettle();

      expect(find.byType(MerchantStatementScreen), findsOneWidget);
      expect(adapter.calls, isNotEmpty);
    });

    testWidgets('and is absent, not marked Soon, for a host that wired nothing',
        (WidgetTester tester) async {
      await _pumpSettings(tester, wired: false);

      // The frame never drew this row, so a host without the client simply does not offer the
      // page. A "Soon" chip here would promise a shop a screen nobody has agreed to give them —
      // and the three chips that belong to the rows the frame DOES draw must be untouched.
      expect(find.text(w.title), findsNothing);
      expect(find.byType(YdComingSoon), findsNWidgets(3));
    });
  });
}

/// Answers the first request and refuses the rest.
class _SwitchingAdapter implements HttpClientAdapter {
  _SwitchingAdapter(this.healthy);

  final bool Function() healthy;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final bool ok = healthy();
    return ResponseBody.fromString(
      jsonEncode(ok ? _statement() : <String, dynamic>{'detail': 'ledger unavailable'}),
      ok ? 200 : 500,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<_StatementAdapter> _pumpSettings(WidgetTester tester, {required bool wired}) async {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _StatementAdapter adapter = _StatementAdapter(_statement());
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
  final LocaleController locale = LocaleController(
    read: () async => 'en',
    write: (String _) async {},
  );
  addTearDown(locale.dispose);

  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: MerchantSettingsScreen(
      locale: locale,
      accountName: 'Falafel King',
      statements: wired ? StatementsApi(dio) : null,
    ),
  ));
  await tester.pumpAndSettle();
  return adapter;
}
