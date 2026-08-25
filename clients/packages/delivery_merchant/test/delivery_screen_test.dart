import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Who carries this shop's orders, on a phone.
///
/// The page renders in two hosts of very different widths — the portal's rail leaves it most of a
/// desktop, the Android app gives it 360dp and a gesture bar — and it is one widget, so the only
/// way a phone regression shows up is a test that pumps it at phone size. An overflow in Flutter is
/// a painted stripe and a logged exception, not a failure, so these assert on the exception.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({required this.available, required this.policy});

  final List<Map<String, dynamic>> available;
  final Map<String, dynamic> policy;

  /// How many requests have been served. A load is two, so this is how a test tells a re-fetch
  /// happened from a gesture that leaves the rendered page looking identical.
  int calls = 0;

  /// While true every request fails the way a phone fails: no response at all, so there is no
  /// server sentence to show and the screen has to find its own words.
  bool offline = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls++;
    if (offline) {
      throw DioException.connectionError(
          requestOptions: options, reason: 'no route to host');
    }
    final Object body = options.path.endsWith('/available') ? available : policy;
    return ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _provider(String id, String name, String kind, {bool canTakeWork = true}) =>
    <String, dynamic>{
      'id': id,
      'slug': id,
      'name': name,
      'kind': kind,
      'status': 'ACTIVE',
      'canTakeWork': canTakeWork,
    };

/// Deliberately unkind names. A carrier called "Fast" proves nothing about 360dp.
List<Map<String, dynamic>> _carriers() => <Map<String, dynamic>>[
      _provider('p1', 'YouDrop in-house riders', 'PLATFORM'),
      _provider('p2', 'Cairo Metropolitan Express Logistics Company', 'EXTERNAL',
          canTakeWork: false),
    ];

Widget _host(DeliveryProviderApi api, {Locale locale = const Locale('en')}) => MaterialApp(
      theme: DeliveryTheme.light(),
      locale: locale,
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: Scaffold(body: DeliveryScreen(api: api)),
    );

Map<String, dynamic> _defaultPolicy() => <String, dynamic>{
      'preferredProviderId': null,
      'allowFallback': true,
      'platformDecides': true,
    };

/// Wraps an adapter the test still holds a reference to, for the cases that assert on what the
/// screen asked the network for rather than on what it painted.
DeliveryProviderApi _apiOn(_StubAdapter adapter) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://test'));
  dio.httpClientAdapter = adapter;
  return DeliveryProviderApi(dio);
}

DeliveryProviderApi _api({List<Map<String, dynamic>>? available, Map<String, dynamic>? policy}) =>
    _apiOn(_StubAdapter(available: available ?? _carriers(), policy: policy ?? _defaultPolicy()));

/// A small phone, and then a small phone belonging to someone who has turned the font up.
void main() {
  testWidgets('lays out on a 360dp phone without overflowing', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_api()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Cairo Metropolitan Express Logistics Company'), findsOneWidget);
  });

  testWidgets('still fits at the largest font size Android offers', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: _host(_api()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the page never scrolls sideways', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_api()));
    await tester.pumpAndSettle();

    final ListView list = tester.widget<ListView>(find.byType(ListView));
    expect(list.scrollDirection, Axis.vertical);
    expect(find.byType(Scrollable), findsOneWidget);
  });

  testWidgets('every control a thumb has to hit is at least 48dp tall',
      (WidgetTester tester) async {
    // Phone width, but tall enough that the whole page is mounted at once: a ListView does not
    // build what is below the fold, and the controls further down are the ones worth measuring.
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // A fleet the merchant does not have yet, so the "set up my own drivers" button is on screen
    // alongside the carrier cards and the fallback row.
    await tester.pumpWidget(_host(_api()));
    await tester.pumpAndSettle();

    for (final Element element in find.byType(InkWell).evaluate()) {
      final Size size = element.size!;
      expect(size.height, greaterThanOrEqualTo(48),
          reason: 'a tappable ${size.width}x${size.height} is too short for a thumb');
    }
    expect(tester.getSize(find.byType(OutlinedButton)).height, greaterThanOrEqualTo(48));
  });

  testWidgets('the tapped carrier says it is working, and the others go quiet',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_api()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('YouDrop in-house riders'));
    await tester.pump();

    // One spinner, on the row that was tapped — the thing a bool `_busy` could not express.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('a wide window still gets the desktop gutter', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_api()));
    await tester.pumpAndSettle();

    final ListView list = tester.widget<ListView>(find.byType(ListView));
    expect((list.padding! as EdgeInsets).left, DeliverySpacing.lg);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed load offers a way out instead of a dead screen',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final _StubAdapter adapter = _StubAdapter(available: _carriers(), policy: _defaultPolicy())
      ..offline = true;

    await tester.pumpWidget(_host(_apiOn(adapter)));
    await tester.pumpAndSettle();

    // The merchant is told what happened in words. A DioException stringifies to its URI and its
    // stack, which is most of a 360dp screen and means nothing to a shop owner.
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('http://test'), findsNothing);

    // The portal has the browser's reload button behind this; Android has nothing, so the retry
    // has to be on the page or the screen is a dead end until the app is killed.
    final Finder retry = find.widgetWithText(OutlinedButton, 'Try again');
    expect(retry, findsOneWidget);
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));

    adapter.offline = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(find.text('Cairo Metropolitan Express Logistics Company'), findsOneWidget);
  });

  testWidgets('pull to refresh re-fetches, since a phone has no reload button',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final _StubAdapter adapter = _StubAdapter(available: _carriers(), policy: _defaultPolicy());
    await tester.pumpWidget(_host(_apiOn(adapter)));
    await tester.pumpAndSettle();

    // Two endpoints, fetched together, so one load is two requests.
    expect(adapter.calls, 2);

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(adapter.calls, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic fits the same phone', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_api(), locale: const Locale('ar')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(Directionality.of(tester.element(find.byType(ListView))), TextDirection.rtl);
  });
}
