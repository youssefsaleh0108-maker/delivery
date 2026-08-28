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
  late TrackingApi trackingApi;
  late OrderApi orderApi;
  late RiderPerformanceApi performanceApi;

  /// Rosters by provider id. Replaced per test.
  late Map<String, String> rosters;

  /// What `GET /api/orders/riders/delivered-today` answers. 'boom' takes the column down; the
  /// default is that it does, so the "what nothing reports" group keeps meaning exactly that.
  late String deliveredJson;

  /// Duty-hours reports by rider ref. A rider absent from this map 404s, which is what the tracking
  /// service returns for a rider it has never heard of.
  late Map<String, String> dutyJson;

  /// What the tracking roster answers. `[]` — nobody has ever declared duty — unless a test says
  /// otherwise; 'boom' takes the whole presence column down.
  late String presenceJson;

  /// Standings by rider ref. A rider missing from it gets a 404, which the screen must render as
  /// "nothing loaded", never as a score.
  late Map<String, String> standings;

  _FakeAdapter build() => _FakeAdapter((RequestOptions options) {
        if (options.path.contains('/tracking/riders/roster')) {
          if (presenceJson == 'boom') throw StateError('tracking is down');
          return _json(presenceJson);
        }
        if (options.path.endsWith('/duty/hours')) {
          for (final MapEntry<String, String> e in dutyJson.entries) {
            if (options.path.contains(e.key)) return _json(e.value);
          }
          return ResponseBody.fromString('{}', 404);
        }
        if (options.path.endsWith('/riders/delivered-today')) {
          if (deliveredJson == 'boom') throw StateError('the counter is down');
          return _json(deliveredJson);
        }
        if (options.path.endsWith('/rating')) {
          for (final MapEntry<String, String> e in standings.entries) {
            if (options.path.contains(e.key)) return _json(e.value);
          }
          return ResponseBody.fromString('{}', 404);
        }
        for (final MapEntry<String, String> e in rosters.entries) {
          if (options.path.contains('/${e.key}/riders')) {
            if (e.value == 'boom') throw StateError('that roster is down');
            return _json(e.value);
          }
        }
        if (options.path.contains('/riders')) return _json('{"providerId":"p","riders":[]}');
        return _json(_providersJson);
      });

  void wire() {
    adapter = build();
    final Dio dio =
        Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
    api = DeliveryProviderApi(dio);
    trackingApi = TrackingApi(dio);
    orderApi = OrderApi(dio);
    performanceApi = RiderPerformanceApi(dio);
  }

  setUp(() {
    deliveredJson = 'boom';
    dutyJson = <String, String>{};
    rosters = <String, String>{
      'p1': '{"providerId":"p1","riders":["rider-1111-2222-3333","rider-4444-5555-6666"]}',
      'p2': '{"providerId":"p2","riders":["rider-7777-8888-9999"]}',
    };
    presenceJson = '[]';
    standings = <String, String>{};
    wire();
  });

  Future<void> pump(WidgetTester tester, {Size size = const Size(1500, 1100)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(
        body: RidersScreen(
          api: api,
          trackingApi: trackingApi,
          orderApi: orderApi,
          performanceApi: performanceApi,
        ),
      ),
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
    wire();
    await pump(tester);

    expect(find.text('Falcon Express Delivery'), findsOneWidget);
    expect(find.text('Swift Logistics Group'), findsNothing);
  });

  group('what nothing reports', () {
    testWidgets('is left empty rather than guessed at', (WidgetTester tester) async {
      await pump(tester);

      // In this configuration nothing answers: region has no source at all, and the delivered
      // counter, the duty ledger and the ratings are all down. Four dashes per row, and not one
      // number among them — a failed request must never render as a zero.
      expect(find.byType(ConsoleNoValue), findsNWidgets(12));
      expect(find.textContaining('★'), findsNothing);
      expect(find.text('0'), findsNothing);
      expect(find.text('0.0h'), findsNothing);
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

    testWidgets('and a failed rating lookup is an empty cell, never a zero',
        (WidgetTester tester) async {
      await pump(tester);

      // Every standing lookup 404s in this configuration; the column stays empty rather than
      // painting anybody's livelihood as 0.0.
      expect(find.textContaining('★'), findsNothing);
      expect(find.text('New'), findsNothing);
    });

    testWidgets('and the region filter is not drawn at all',
        (WidgetTester tester) async {
      await pump(tester);

      // It used to be drawn dead, with a "coming soon" chip on it. Nothing ties a rider to a work
      // region anywhere on this platform — there is no field to filter on and no plan in the data
      // model that would create one — so the chip was promising an operator a capability that is
      // not coming. Gone entirely rather than drawn and marked.
      expect(find.text('All regions'), findsNothing);
      expect(find.byType(ConsoleComingSoonChip), findsNothing);

      // What replaces it is the two controls beside it, which are real and stay real.
      expect(find.text('All Carriers'), findsOneWidget);
      expect(find.widgetWithText(ConsoleSearchField, 'Search riders...'),
          findsOneWidget);
    });
  });

  group('what the tracking service now reports', () {
    testWidgets('renders roster states with last-seen, and "Unknown" only for the undeclared',
        (WidgetTester tester) async {
      final String seen = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      presenceJson = '''
[{"riderId":"rider-1111-2222-3333","carrierId":"p1","dutyState":"ON_DUTY","state":"ON_DUTY",
  "lastSeenAt":"$seen","lat":33.89,"lng":35.5},
 {"riderId":"rider-4444-5555-6666","carrierId":"p1","dutyState":"ON_DUTY","state":"STALE",
  "lastSeenAt":"$seen"}]''';
      wire();
      await pump(tester);

      expect(find.text('On duty'), findsOneWidget);
      // Declared on duty and went quiet: exactly who a dispatcher needs to see.
      expect(find.text('Signal lost'), findsOneWidget);
      expect(find.textContaining('seen '), findsNWidgets(2));
      // The third rider has never declared duty at all — Unknown, still not "Offline".
      expect(find.text('Unknown'), findsOneWidget);
    });

    testWidgets('a tracking outage reads "Unknown" for everyone, not "Off duty"',
        (WidgetTester tester) async {
      presenceJson = 'boom';
      wire();
      await pump(tester);

      // A fact about the platform, not about the riders — the column degrades, the page stays.
      expect(find.text('Unknown'), findsNWidgets(3));
      expect(find.text('Off duty'), findsNothing);
    });
  });

  group('the two columns the platform now answers', () {
    testWidgets('joins the delivered count onto the roster and draws its own zeros',
        (WidgetTester tester) async {
      // The endpoint omits riders who delivered nothing — that is the contract — so the zeros are
      // this screen's to draw against its own roster, and they are real zeros.
      deliveredJson =
          '[{"riderId":"rider-1111-2222-3333","delivered":4,"day":"2026-08-27"}]';
      wire();
      await pump(tester);

      expect(find.text('4'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2));
    });

    testWidgets('a delivered count that could not be read is a dash, never a zero',
        (WidgetTester tester) async {
      // 'boom' is the default; asserted explicitly because the distinction is the whole point.
      await pump(tester);

      expect(find.text('0'), findsNothing);
    });

    testWidgets('totals duty hours from the exact seconds, and 0.0h only when it means it',
        (WidgetTester tester) async {
      dutyJson = <String, String>{
        // An hour on one day and half an hour on the next: 5400 seconds, shown as 1.5h.
        'rider-1111-2222-3333': '''
{"riderId":"rider-1111-2222-3333","zone":"UTC","from":"2026-08-21","to":"2026-08-27",
 "days":[{"date":"2026-08-26","secondsOnline":3600,"hoursOnline":1.00,"sessions":1},
         {"date":"2026-08-27","secondsOnline":1800,"hoursOnline":0.50,"sessions":1}]}''',
        // Known to the tracking service, and never on duty in the window. The contract expresses
        // that as an empty `days` list, and it is a true zero.
        'rider-4444-5555-6666': '''
{"riderId":"rider-4444-5555-6666","zone":"UTC","from":"2026-08-21","to":"2026-08-27","days":[]}''',
      };
      wire();
      await pump(tester);

      expect(find.text('1.5h'), findsOneWidget);
      expect(find.text('0.0h'), findsOneWidget);
      // The third rider 404s — never heard of — and stays a dash rather than becoming another zero.
      expect(find.text('Hours Online (7d)'), findsOneWidget);
    });
  });

  testWidgets('renders the rating where one exists and "New" where nobody has rated',
      (WidgetTester tester) async {
    standings = <String, String>{
      'rider-1111-2222-3333':
          '{"riderId":"rider-1111-2222-3333","average":4.7,"ratings":12,"stars":{}}',
      'rider-4444-5555-6666':
          '{"riderId":"rider-4444-5555-6666","average":null,"ratings":0,"stars":{}}',
    };
    wire();
    await pump(tester);

    expect(find.text('★ 4.7'), findsOneWidget);
    // Unrated is "New", never a zero. The third rider's lookup 404s and stays an empty cell.
    expect(find.text('New'), findsOneWidget);
    expect(find.textContaining('0.0'), findsNothing);
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
    wire();
    await pump(tester);

    // An empty table here does not mean an empty platform, and saying so is the difference
    // between a screen that is honest and one that is simply wrong.
    expect(find.textContaining('in-house fleet'), findsWidgets);
  });
}
