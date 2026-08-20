import 'package:backoffice_web/src/providers_screen.dart';
import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A carrier the platform cannot pay is silent until an order has already been delivered, so the
/// only thing that surfaces it is this screen. Driven through a real [DeliveryProviderApi] over a
/// stubbed transport, so the JSON mapping is under test too.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body) => ResponseBody.fromString(body, 200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });

String _provider({
  required String id,
  required String name,
  required String slug,
  String? accountRef,
  String payoutState = 'NONE',
  String? payoutDetail,
  String kind = 'EXTERNAL',
}) =>
    '''
{"id":"$id","slug":"$slug","name":"$name","kind":"$kind","status":"ACTIVE",
 "canTakeWork":true,"ownerRef":null,
 "accountRef":${accountRef == null ? 'null' : '"$accountRef"'},
 "contactName":"Ops","contactPhone":"+100",
 "payoutState":"$payoutState",
 "payoutCheckedAt":${payoutState == 'NONE' ? 'null' : '"2026-08-15T09:00:00Z"'},
 "payoutDetail":${payoutDetail == null ? 'null' : '"$payoutDetail"'},
 "createdAt":"2026-08-01T09:00:00Z"}''';

/// The register: the platform's own fleet, two companies, and a merchant's own drivers.
///
/// Named rather than inline so the tests that stub a failing dependency can still serve a real
/// register — losing the scores must not lose the page.
final String _providersJson = '''
{"content":[
  ${_provider(id: 'p0', name: 'In-house fleet', slug: 'in-house', kind: 'PLATFORM')},
  ${_provider(id: 'p1', name: 'Verified Couriers', slug: 'verified', accountRef: 'ACC-GOOD', payoutState: 'VERIFIED', payoutDetail: 'bank holder: Verified Couriers Ltd')},
  ${_provider(id: 'p2', name: 'Unchecked Couriers', slug: 'unchecked', accountRef: 'ACC-UNKNOWN', payoutState: 'UNCONFIRMED', payoutDetail: 'bank unreachable')},
  ${_provider(id: 'p3', name: 'Own drivers', slug: 'merchant-m1', kind: 'MERCHANT')}
 ],
 "page":0,"size":50,"totalElements":4,"totalPages":1}''';

void main() {
  late _FakeAdapter adapter;
  late DeliveryProviderApi api;

  /// What the verify-payout call answers with. Set per test.
  late String verifyResponse;

  setUp(() {
    verifyResponse = _provider(
        id: 'p2', name: 'Unchecked Couriers', slug: 'unchecked',
        accountRef: 'ACC-UNKNOWN', payoutState: 'VERIFIED',
        payoutDetail: 'bank holder: Unchecked Couriers Ltd');

    adapter = _FakeAdapter((RequestOptions options) {
      if (options.path.contains('verify-payout')) return _json(verifyResponse);
      // Before /riders and the register: both of those also match a suffix of this path.
      if (options.path.endsWith('/staff')) {
        return _json('{"providerId":"p1","riders":["staff-11111111-2222"]}');
      }
      if (options.path.contains('/scores')) {
        return _json('''
[{"providerId":"p1","name":"Verified Couriers","score":88,"orders":140,
  "completionRate":0.97,"avgSecondsToClaim":180,"avgSecondsOnRoad":900,"provisional":false},
 {"providerId":"p2","name":"Unchecked Couriers","score":70,"orders":2,
  "completionRate":1.0,"avgSecondsToClaim":null,"avgSecondsOnRoad":null,"provisional":true}]''');
      }
      if (options.path.contains('/riders')) return _json('[]');
      return _json(_providersJson);
    });
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
    api = DeliveryProviderApi(dio);
  });

  Future<void> pump(WidgetTester tester, {Size size = const Size(1400, 1400)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(body: ProvidersScreen(api: api)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('counts carriers whose payout account was never checked',
      (WidgetTester tester) async {
    await pump(tester);

    // Counted rather than left to be found by reading every card: an unpayable carrier says
    // nothing until an order has already been delivered.
    expect(find.text('UNCHECKED PAYOUT'), findsOneWidget);
    expect(find.text('ask the bank'), findsOneWidget);
  });

  testWidgets('says which account is confirmed and which is not',
      (WidgetTester tester) async {
    await pump(tester);

    expect(find.textContaining('ACC-GOOD · verified'), findsOneWidget);
    expect(find.textContaining('ACC-UNKNOWN · unconfirmed'), findsOneWidget);
  });

  testWidgets('an unconfirmed account is not described as a bad one',
      (WidgetTester tester) async {
    await pump(tester);

    // It usually is not one. Saying otherwise sends an operator to chase a carrier about a
    // problem at our end.
    expect(find.textContaining('has not confirmed this account'), findsOneWidget);
    expect(find.textContaining('bank unreachable'), findsOneWidget);
  });

  testWidgets('offers to ask the bank, and reports what came back',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Check with the bank'));
    await tester.pumpAndSettle();

    expect(adapter.calls.any((String c) => c.contains('POST') && c.contains('p2/verify-payout')),
        isTrue);
    expect(find.textContaining('the bank confirmed ACC-UNKNOWN'), findsOneWidget);
  });

  testWidgets('a re-check that still cannot confirm says so, not "done"',
      (WidgetTester tester) async {
    // The normal outcome when the account is genuinely wrong. A blanket success message here would
    // read as the opposite of what happened.
    verifyResponse = _provider(
        id: 'p2', name: 'Unchecked Couriers', slug: 'unchecked',
        accountRef: 'ACC-UNKNOWN', payoutState: 'UNCONFIRMED',
        payoutDetail: 'no such account at the bank');
    await pump(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Check with the bank'));
    await tester.pumpAndSettle();

    expect(find.textContaining('still unconfirmed'), findsOneWidget);
    expect(find.textContaining('no such account at the bank'), findsOneWidget);
  });

  testWidgets('a carrier with no account is offered no bank check',
      (WidgetTester tester) async {
    await pump(tester);

    // Two carriers have accounts; the in-house fleet has none and cannot have one.
    expect(find.widgetWithText(TextButton, 'Check with the bank'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Re-check account'), findsOneWidget);
  });

  group('the delivery score', () {
    testWidgets('is shown against each carrier', (WidgetTester tester) async {
      await pump(tester);

      expect(find.text('88'), findsOneWidget);
      // A provisional score is marked rather than presented as earned.
      expect(find.text('70?'), findsOneWidget);
    });

    testWidgets('with the parts an operator can quote back', (WidgetTester tester) async {
      await pump(tester);

      // "Why am I being sent less work" is the question this answers.
      expect(find.textContaining('97% of 140 delivered'), findsOneWidget);
      expect(find.textContaining('claims in 3m'), findsOneWidget);
    });

    testWidgets('and the register still renders if scores cannot be loaded',
        (WidgetTester tester) async {
      // The ranking is context; the register is the page. Losing one must not lose the other.
      adapter = _FakeAdapter((RequestOptions options) {
        if (options.path.contains('/scores')) throw StateError('scores are down');
        if (options.path.endsWith('/staff')) return _json('{"providerId":"p1","riders":[]}');
        if (options.path.contains('/riders')) return _json('[]');
        return _json(_providersJson);
      });
      api = DeliveryProviderApi(
          Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter);
      await pump(tester);

      expect(find.text('Verified Couriers'), findsOneWidget);
      expect(find.text('88'), findsNothing);
    });
  });

  group('carrier logins', () {
    testWidgets('a company with nobody attached is called out',
        (WidgetTester tester) async {
      // The step everyone forgets. Its symptom from the carrier's side is a portal telling them
      // they belong to no company, which is a long way from the cause.
      adapter = _FakeAdapter((RequestOptions options) {
        if (options.path.endsWith('/staff')) return _json('{"providerId":"p1","riders":[]}');
        if (options.path.contains('/scores')) return _json('[]');
        if (options.path.contains('/riders')) return _json('[]');
        return _json(_providersJson);
      });
      api = DeliveryProviderApi(
          Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter);
      await pump(tester);

      expect(find.textContaining('Nobody can sign in'), findsWidgets);
    });

    testWidgets('and one can be given access', (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Give someone access').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sub-abc-123');
      await tester.tap(find.widgetWithText(FilledButton, 'Give access'));
      await tester.pumpAndSettle();

      expect(
        adapter.calls.any((String c) => c.contains('POST') && c.contains('/staff')),
        isTrue,
      );
    });

    testWidgets('only companies have logins, not merchant fleets',
        (WidgetTester tester) async {
      await pump(tester);

      // p3 is a merchant's own fleet: its owner administers it from their own portal.
      final int companies = 2;
      expect(find.widgetWithText(TextButton, 'Give someone access'), findsNWidgets(companies));
    });
  });
}
