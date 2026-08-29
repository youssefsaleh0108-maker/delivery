import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/rider_statement_screen.dart';

/// The rider's own statement.
///
/// What is worth pinning here is not the layout but the honesty, because this is the one screen in
/// the rider app where the true number is usually against the reader. Every order is cash: the
/// rider collects the whole basket at the door, so most of the time the ledger says the rider owes
/// the platform. Four things must hold, and each has a test below:
///
/// * the figures on screen are the ledger's own strings, not anything this app worked out;
/// * a debt is *worded* — "you owe the platform" — and drawn unsigned and un-alarming, never as a
///   minus sign next to somebody's pay;
/// * a period with no activity says so, rather than rendering as a balance of zero;
/// * a failed load renders the failure and nothing else — no zeroes, and above all not "settled".
///
/// Backed by a Dio whose adapter is replaced rather than a hand-written fake [StatementsApi], so
/// the real contract parsing in `statement_models.dart` is exercised too — a client that shows
/// 2,121.8 where the ledger wrote 2121.80 is the failure this whole layer exists to prevent.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body);

  /// The JSON to answer with. Null makes the request fail instead.
  final String? body;

  /// Every request this screen made, so a test can assert on which route was called. A rider must
  /// only ever reach `/mine`; a path naming a counterparty would be a rider reading somebody else.
  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    final String? json = body;
    if (json == null) {
      throw DioException(requestOptions: options, message: 'network down');
    }
    return ResponseBody.fromString(json, 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  /// A rider mid-month, holding more of the platform's cash than they have earned back — the
  /// ordinary shape of a cash-only delivery business, and the one this screen must not alarm
  /// somebody about.
  const String inDebtJson = '''
{
  "kind": "RIDER",
  "ref": "rider-1",
  "name": "Sam Carter",
  "from": "2026-08-01",
  "to": "2026-08-29",
  "currency": "USD",
  "generatedAt": "2026-08-29T05:00:00Z",
  "lines": [
    {"label": "Cash collected at the door", "amount": "2425.00", "direction": "DEBIT",
     "note": "45 orders"},
    {"label": "Cash handed over", "amount": "1900.00", "direction": "CREDIT", "note": null},
    {"label": "Delivery fees earned", "amount": "180.00", "direction": "CREDIT", "note": null}
  ],
  "net": {"amount": "345.00", "direction": "THEY_OWE"},
  "entries": [
    {"orderId": "11111111-2222-3333-4444-555555555555", "at": "2026-08-23T11:09:40Z",
     "gross": "19.50", "commission": "2.44", "net": "4.00", "paymentMethod": "CASH"}
  ],
  "note": "Cash you are still carrying is counted here."
}''';

  /// A period the rider did not work. Not an error, and not a zero balance to be shown as one.
  const String emptyJson = '''
{
  "kind": "RIDER",
  "ref": "rider-1",
  "name": "Sam Carter",
  "from": "2026-07-01",
  "to": "2026-07-31",
  "currency": "USD",
  "generatedAt": "2026-08-29T05:00:00Z",
  "lines": [],
  "entries": [],
  "net": {"amount": "0.00", "direction": "SETTLED"},
  "note": null
}''';

  Future<_FakeAdapter> pump(WidgetTester tester, String? json, {Locale? locale}) async {
    final _FakeAdapter adapter = _FakeAdapter(json);
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(MaterialApp(
      locale: locale,
      theme: DeliveryTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supported,
      home: RiderStatementScreen(api: StatementsApi(dio)),
    ));
    await tester.pumpAndSettle();
    return adapter;
  }

  testWidgets('a loaded statement renders the ledger\'s own figures', (WidgetTester tester) async {
    await pump(tester, inDebtJson);

    // The summary lines, in the server's words, with the server's signs. A minus is safe here
    // because the label beside it says what went down.
    expect(find.text('Cash collected at the door'), findsOneWidget);
    expect(find.text('-2425.00'), findsOneWidget);
    expect(find.text('45 orders'), findsOneWidget);
    expect(find.text('Cash handed over'), findsOneWidget);
    expect(find.text('+1900.00'), findsOneWidget);
    expect(find.text('Delivery fees earned'), findsOneWidget);
    expect(find.text('+180.00'), findsOneWidget);

    // The order behind it: the reference, what was taken at the door, and what of it was the
    // rider's. None of the three is derived from the others here.
    expect(find.textContaining('11111111'), findsOneWidget);
    expect(find.text('You collected 19.50 at the door'), findsOneWidget);
    expect(find.text('4.00'), findsOneWidget);

    // The server's own explanation of anything the figures cannot state.
    expect(find.text('Cash you are still carrying is counted here.'), findsOneWidget);
  });

  testWidgets('a debt is worded, not shown as a negative wage', (WidgetTester tester) async {
    await pump(tester, inDebtJson);

    // The direction is a sentence. NetDirection is written from the PLATFORM's point of view by
    // contract, so a rider reading WE_OWE/THEY_OWE raw would read it backwards.
    expect(find.text('You owe the platform'), findsOneWidget);
    expect(find.text('The platform owes you'), findsNothing);

    // Unsigned. A rider's settling figure must never appear as a minus: the amount is real, the
    // minus is the platform's vantage point, and together they read as negative pay.
    expect(find.text('345.00'), findsOneWidget);
    expect(find.text('-345.00'), findsNothing);

    // Caution, not the critical colour. Carrying the platform's cash is the ordinary state of a
    // working shift; an alarm colour on the ordinary state teaches riders to ignore the colour.
    final Text headline = tester.widget<Text>(find.text('You owe the platform'));
    expect(headline.style?.color, DeliveryAccent.caution.color);
    expect(headline.style?.color, isNot(DeliveryAccent.critical.color));

    // And it says why, so nobody reads it as a charge against them.
    expect(
      find.textContaining('it is not a deduction from your pay'),
      findsOneWidget,
    );
  });

  testWidgets('a period with no activity says so rather than showing a zero balance',
      (WidgetTester tester) async {
    await pump(tester, emptyJson);

    expect(find.text('No money moved in this period.'), findsOneWidget);
    // The server sent a settled zero, and it is still not drawn as a headline figure: "nothing
    // happened" and "your balance is nil" are different claims, and only the first one is true of
    // a month the rider did not work.
    expect(find.text('0.00'), findsNothing);
    expect(find.text('How it adds up'.toUpperCase()), findsNothing);
  });

  testWidgets('a failed load invents nothing', (WidgetTester tester) async {
    await pump(tester, null);

    expect(find.text('Could not load your statement'), findsOneWidget);

    // Nothing else. Above all not "settled", which a rider would reasonably act on — the whole
    // point of this screen is telling somebody whether they owe money.
    expect(find.text('Nothing outstanding either way'), findsNothing);
    expect(find.text('You owe the platform'), findsNothing);
    expect(find.text('The platform owes you'), findsNothing);
    expect(find.textContaining('0.00'), findsNothing);
    expect(find.text('How it adds up'.toUpperCase()), findsNothing);
  });

  testWidgets('a net the server did not send reads as unknown, never as settled',
      (WidgetTester tester) async {
    // No `net` block at all — an older server, or a field this build predates. The parse turns it
    // into NetDirection.unknown, and the screen must not resolve that into good news.
    await pump(tester, '''
{
  "kind": "RIDER", "ref": "rider-1", "name": "Sam Carter",
  "currency": "USD",
  "lines": [{"label": "Delivery fees earned", "amount": "180.00", "direction": "CREDIT"}],
  "entries": []
}''');

    expect(find.text('This balance could not be read'), findsOneWidget);
    expect(find.text('Nothing outstanding either way'), findsNothing);
    // Unknown gets a dash, not a zero. "We were not told" is not "nothing is owed".
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0.00'), findsNothing);
  });

  testWidgets('a rider can only ever ask for their own statement', (WidgetTester tester) async {
    final _FakeAdapter adapter = await pump(tester, inDebtJson);

    // /mine names nobody: whose statement comes back is decided by the token. The ref is in the
    // payload above and must not have found its way into a path.
    expect(adapter.calls, <String>['GET /api/accounting/statements/mine']);
    expect(adapter.calls.any((String call) => call.contains('rider-1')), isFalse);
    expect(adapter.calls.any((String call) => call.contains('RIDER')), isFalse);
  });

  testWidgets('in Arabic it reads right-to-left and the debt is worded in Arabic',
      (WidgetTester tester) async {
    await pump(tester, inDebtJson, locale: const Locale('ar'));

    expect(
      Directionality.of(tester.element(find.byType(RiderStatementScreen))),
      TextDirection.rtl,
    );
    // The sentence that carries the whole meaning of the screen. An untranslated one here is how
    // an Arabic build tells a rider nothing at all about what they owe.
    expect(find.text('أنت مدين للمنصة'), findsOneWidget);
    expect(find.text('You owe the platform'), findsNothing);
    // The figures stay the ledger's own digits in either language.
    expect(find.text('345.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
