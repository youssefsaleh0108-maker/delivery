import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_portal/src/backoffice/riders_screen.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Riders Control Panel (Figma `backoffice-riders` 3:3088).
///
/// The screen the design draws is mostly made of things the platform does not measure — presence,
/// region, deliveries today, a rating. What it *can* answer is who rides for whom, and that answer
/// has to be assembled from one roster per carrier because there is no rider index.
///
/// So these tests are as much about what must not appear as about what must: no invented count, no
/// "Offline" for a rider nobody has asked, and no page lost to one carrier whose roster is down.
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
  String kind = 'EXTERNAL',
}) =>
    '''
{"id":"$id","slug":"$slug","name":"$name","kind":"$kind","status":"ACTIVE",
 "canTakeWork":true,"ownerRef":null,"accountRef":null,
 "contactName":null,"contactPhone":null,
 "payoutState":"NONE","payoutCheckedAt":null,"payoutDetail":null,
 "createdAt":"2026-01-10T09:00:00Z"}''';

final String _providersJson = '''
{"content":[
  ${_provider(id: 'p0', name: 'In-house fleet', slug: 'in-house', kind: 'PLATFORM')},
  ${_provider(id: 'p1', name: 'Swift Logistics Group', slug: 'swift')},
  ${_provider(id: 'p2', name: 'Falcon Express Delivery', slug: 'falcon')}
 ],
 "page":0,"size":50,"totalElements":3,"totalPages":1}''';

void main() {
  late _FakeAdapter adapter;
  late DeliveryProviderApi api;

  /// Rosters by provider id. Replaced per test.
  late Map<String, String> rosters;

  _FakeAdapter build() => _FakeAdapter((RequestOptions options) {
        for (final MapEntry<String, String> e in rosters.entries) {
          if (options.path.contains('/${e.key}/riders')) {
            if (e.value == 'boom') throw StateError('that roster is down');
            return _json(e.value);
          }
        }
        if (options.path.contains('/riders')) return _json('{"providerId":"p","riders":[]}');
        return _json(_providersJson);
      });

  setUp(() {
    rosters = <String, String>{
      'p1': '{"providerId":"p1","riders":["rider-1111-2222-3333","rider-4444-5555-6666"]}',
      'p2': '{"providerId":"p2","riders":["rider-7777-8888-9999"]}',
    };
    adapter = build();
    api = DeliveryProviderApi(
        Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter);
  });

  Future<void> pump(WidgetTester tester, {Size size = const Size(1500, 1100)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(body: RidersScreen(api: api)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('joins every carrier roster into one list', (WidgetTester tester) async {
    await pump(tester);

    // The answer to "who rides for us", which previously took opening every carrier in turn.
    expect(find.byType(ConsoleNameCell), findsNWidgets(3));
    // Two ride for Swift and one for Falcon, and each row names its own carrier.
    expect(find.text('Swift Logistics Group'), findsNWidgets(2));
    expect(find.text('Falcon Express Delivery'), findsOneWidget);
  });

  testWidgets('does not ask the in-house fleet for a roster it cannot have',
      (WidgetTester tester) async {
    await pump(tester);

    // Membership in it is opt-in, so its roster is empty by construction. Asking would spend a
    // request to learn nothing.
    expect(adapter.calls.any((String c) => c.contains('/p0/riders')), isFalse);
    expect(adapter.calls.any((String c) => c.contains('/p1/riders')), isTrue);
  });

  testWidgets('one unreachable roster does not lose the other riders',
      (WidgetTester tester) async {
    rosters['p1'] = 'boom';
    adapter = build();
    api = DeliveryProviderApi(
        Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter);
    await pump(tester);

    expect(find.text('Falcon Express Delivery'), findsOneWidget);
    expect(find.text('Swift Logistics Group'), findsNothing);
  });

  group('what nothing reports', () {
    testWidgets('is left empty rather than guessed at', (WidgetTester tester) async {
      await pump(tester);

      // Region, deliveries today and rating: three per row, and not one number among them.
      expect(find.byType(ConsoleNoValue), findsNWidgets(9));
      expect(find.textContaining('★'), findsNothing);
    });

    testWidgets('and presence reads "Unknown", never "Offline"',
        (WidgetTester tester) async {
      await pump(tester);

      // Painting every rider red would be a fact about the platform dressed up as a fact about
      // the rider.
      expect(find.text('Unknown'), findsNWidgets(3));
      expect(find.text('Online'), findsNothing);
      expect(find.text('Offline'), findsNothing);
    });

    testWidgets('and the region filter is drawn, marked, and does nothing',
        (WidgetTester tester) async {
      await pump(tester);

      final ConsoleFilterButton region = tester.widget<ConsoleFilterButton>(
          find.widgetWithText(ConsoleFilterButton, 'All regions'));
      expect(region.onPressed, isNull);
      expect(
        find.descendant(
          of: find.widgetWithText(ConsoleFilterButton, 'All regions'),
          matching: find.byType(ConsoleComingSoonChip),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('narrows the roster to one carrier', (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.widgetWithText(ConsoleFilterButton, 'All Carriers'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<int>, 'Falcon Express Delivery'));
    await tester.pumpAndSettle();

    expect(find.byType(ConsoleNameCell), findsOneWidget);
    expect(find.text('Falcon Express Delivery'), findsWidgets);
  });

  /// Flutter fails a test on a layout overflow, so rendering at the widths the console is actually
  /// opened on is the cheapest check there is — and the only stand-in available here for opening a
  /// browser. The design is drawn at 1440; 1280 and 1024 are real laptops.
  for (final Size window in <Size>[
    const Size(1440, 900),
    const Size(1280, 800),
    const Size(1024, 720),
  ]) {
    testWidgets('lays out at ${window.width.round()}px', (WidgetTester tester) async {
      await pump(tester, size: window);
      expect(find.byType(ConsoleTable), findsOneWidget);
    });
  }

  testWidgets('says where the riders it cannot show have gone',
      (WidgetTester tester) async {
    rosters = <String, String>{};
    adapter = build();
    api = DeliveryProviderApi(
        Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter);
    await pump(tester);

    // An empty table here does not mean an empty platform, and saying so is the difference
    // between a screen that is honest and one that is simply wrong.
    expect(find.textContaining('in-house fleet'), findsWidgets);
  });
}
