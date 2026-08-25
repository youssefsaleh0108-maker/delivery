import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where this shop delivers and what it charges, on a phone.
///
/// The page renders in two hosts of very different widths — the portal's rail leaves it most of a
/// desktop, the Android app gives it 360dp and a gesture bar — and it is one widget, so the only
/// way a phone regression shows up is a test that pumps it at phone size. An overflow in Flutter is
/// a painted stripe and a logged exception, not a failure, so these assert on the exception.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({required this.zones, required this.coverage, required this.stores});

  final List<Map<String, dynamic>> zones;
  final List<Map<String, dynamic>> coverage;
  final List<Map<String, dynamic>> stores;

  /// Every write this screen can make, so a test can assert the form sent what the merchant typed.
  final List<String> writes = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final String path = options.path;
    if (options.method != 'GET') {
      writes.add('${options.method} $path ${jsonEncode(options.data)}');
      // dropCoverage returns nothing the screen reads; setCoverage's result is discarded too.
      return ResponseBody.fromString(jsonEncode(_coverageRow('z1', 1)), 200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType]
          });
    }

    final Object body = path.contains('/coverage/')
        ? coverage
        : path.startsWith('/api/delivery-zones')
            ? zones
            : <String, dynamic>{
                'content': stores,
                'page': 0,
                'totalElements': stores.length,
                'totalPages': 1,
              };
    return ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _zone(String id, String name, {String? region}) =>
    <String, dynamic>{'id': id, 'name': name, 'region': region, 'sortOrder': 100, 'active': true};

Map<String, dynamic> _coverageRow(String zoneId, double fee, {double? minOrder, int eta = 0}) =>
    <String, dynamic>{
      'zoneId': zoneId,
      'zoneName': 'covered',
      'deliveryFee': fee,
      'minOrder': minOrder,
      'etaExtraMinutes': eta,
    };

/// Deliberately unkind names. An area called "Downtown" proves nothing about 360dp, and the fee
/// line is the part that overflowed: fee, minimum and an ETA bump all on one line.
List<Map<String, dynamic>> _zones() => <Map<String, dynamic>>[
      _zone('z1', 'Sheikh Zayed City, 6th of October', region: 'Greater Cairo Metropolitan Area'),
      _zone('z2', 'New Administrative Capital', region: 'Greater Cairo Metropolitan Area'),
    ];

Widget _host(
  DeliveryZoneApi api,
  StoreApi storeApi, {
  Locale locale = const Locale('en'),
  double textScale = 1.0,
}) =>
    MaterialApp(
      theme: DeliveryTheme.light(),
      locale: locale,
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      // Scaling is applied here rather than by wrapping this MaterialApp in a MediaQuery. A bare
      // `MediaQueryData(textScaler: ...)` also declares a size of zero, and MaterialApp adopts an
      // ambient MediaQuery wholesale — the page then lays out in a zero-sized window where nothing
      // can overflow, and the test passes without having tested anything.
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: ZonesScreen(api: api, storeApi: storeApi)),
    );

({DeliveryZoneApi zone, StoreApi store, _StubAdapter adapter}) _apis({
  List<Map<String, dynamic>>? zones,
  List<Map<String, dynamic>>? coverage,
  bool hasStore = true,
}) {
  final _StubAdapter adapter = _StubAdapter(
    zones: zones ?? _zones(),
    coverage: coverage ?? <Map<String, dynamic>>[],
    stores: hasStore
        ? <Map<String, dynamic>>[
            <String, dynamic>{'id': 's1', 'slug': 's1', 'name': 'Shop', 'vertical': 'RESTAURANT'}
          ]
        : <Map<String, dynamic>>[],
  );
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://test'));
  dio.httpClientAdapter = adapter;
  return (zone: DeliveryZoneApi(dio), store: StoreApi(dio), adapter: adapter);
}

Future<void> _pumpPhone(
  WidgetTester tester,
  Widget widget, {
  Size size = const Size(360, 640),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lays out on a 360dp phone without overflowing', (WidgetTester tester) async {
    final ({DeliveryZoneApi zone, StoreApi store, _StubAdapter adapter}) a =
        _apis(coverage: <Map<String, dynamic>>[_coverageRow('z1', 15, eta: 20)]);
    await _pumpPhone(tester, _host(a.zone, a.store));

    expect(tester.takeException(), isNull);
    expect(find.text('Sheikh Zayed City, 6th of October'), findsOneWidget);
  });

  testWidgets('still fits at the largest font size Android offers', (WidgetTester tester) async {
    final ({DeliveryZoneApi zone, StoreApi store, _StubAdapter adapter}) a =
        _apis(coverage: <Map<String, dynamic>>[_coverageRow('z1', 15, minOrder: 200, eta: 20)]);
    await _pumpPhone(
      tester,
      _host(a.zone, a.store, textScale: 2.0),
      // Tall, so the whole list is mounted: a ListView does not build what is below the fold, and
      // at 2x text the rows below the fold are exactly the ones that would overflow.
      size: const Size(360, 2400),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('the page never scrolls sideways', (WidgetTester tester) async {
    final ({DeliveryZoneApi zone, StoreApi store, _StubAdapter adapter}) a = _apis();
    await _pumpPhone(tester, _host(a.zone, a.store));

    final ListView list = tester.widget<ListView>(find.byType(ListView));
    expect(list.scrollDirection, Axis.vertical);
    expect(find.byType(Scrollable), findsOneWidget);
  });

  testWidgets('every control a thumb has to hit is at least 48dp tall',
      (WidgetTester tester) async {
    final ({DeliveryZoneApi zone, StoreApi store, _StubAdapter adapter}) a =
        _apis(coverage: <Map<String, dynamic>>[_coverageRow('z1', 15)]);
    // A served area and an unserved one, so both the edit button and the drop button are on screen.
    await _pumpPhone(tester, _host(a.zone, a.store), size: const Size(360, 1600));

    for (final Element element in find.byType(InkWell).evaluate()) {
      final Size size = element.size!;
      expect(size.height, greaterThanOrEqualTo(48),
          reason: 'a tappable ${size.width}x${size.height} is too short for a thumb');
    }
  });

  testWidgets('the destructive action says what it does instead of hiding in a tooltip',
      (WidgetTester tester) async {
    final ({DeliveryZoneApi zone, StoreApi store, _StubAdapter adapter}) a =
        _apis(coverage: <Map<String, dynamic>>[_coverageRow('z1', 15)]);
    await _pumpPhone(tester, _host(a.zone, a.store), size: const Size(360, 1600));

    // The wide layout's bare X carries its meaning in a tooltip, and a phone has no hover.
    expect(find.widgetWithText(TextButton, 'Stop delivering here'), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('terms are edited in a sheet on a phone, not a dialog under the keyboard',
      (WidgetTester tester) async {
    final ({DeliveryZoneApi zone, StoreApi store, _StubAdapter adapter}) a = _apis();
    await _pumpPhone(tester, _host(a.zone, a.store), size: const Size(360, 1600));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Add an area').first);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);

    // Fee, minimum, extra minutes — in that order, and the fee is the only required one.
    await tester.enterText(find.byType(TextFormField).first, '17.5');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(a.adapter.writes.single, contains('"deliveryFee":17.5'));
    // Blank minimum is "use the shop's own", not zero.
    expect(a.adapter.writes.single, contains('"minOrder":null'));
  });

  testWidgets('a wide window keeps the desktop row and its dialog', (WidgetTester tester) async {
    final ({DeliveryZoneApi zone, StoreApi store, _StubAdapter adapter}) a =
        _apis(coverage: <Map<String, dynamic>>[_coverageRow('z1', 15)]);
    await _pumpPhone(tester, _host(a.zone, a.store), size: const Size(1400, 900));

    final ListView list = tester.widget<ListView>(find.byType(ListView));
    expect((list.padding! as EdgeInsets).left, DeliverySpacing.lg);
    // The compact X with its tooltip is the wide layout's, and it is still there.
    expect(find.byType(IconButton), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a merchant with no shop yet can still pull to try again',
      (WidgetTester tester) async {
    final ({DeliveryZoneApi zone, StoreApi store, _StubAdapter adapter}) a =
        _apis(hasStore: false);
    await _pumpPhone(tester, _host(a.zone, a.store));

    // The empty state is a scrollable, not a centred Text, so the pull gesture exists on the one
    // state a phone most needs it on.
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.byType(Scrollable), findsOneWidget);
  });

  testWidgets('Arabic fits the same phone', (WidgetTester tester) async {
    final ({DeliveryZoneApi zone, StoreApi store, _StubAdapter adapter}) a =
        _apis(coverage: <Map<String, dynamic>>[_coverageRow('z1', 15, minOrder: 200, eta: 20)]);
    await _pumpPhone(tester, _host(a.zone, a.store, locale: const Locale('ar')));

    expect(tester.takeException(), isNull);
    expect(Directionality.of(tester.element(find.byType(ListView))), TextDirection.rtl);
  });
}
