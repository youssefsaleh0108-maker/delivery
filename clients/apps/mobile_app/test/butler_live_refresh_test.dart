import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/rider_butler_board.dart';

/// Errands arriving on their own, on the two screens that wait for somebody else to act.
///
/// <p>Both sides of Butler loaded once and then stopped asking. The rider's board refreshed only
/// after the rider claimed something or pulled it down by hand, so a rider watching an empty
/// board saw an empty board however many errands had been posted behind it. The customer's list
/// had the same shape and the worse consequence: everything they are waiting for happens on
/// somebody else's phone — a rider claims the errand, shops, and quotes a price — and the quote
/// sat on the server while the screen still read "waiting for a rider".
///
/// <p>Neither is a hypothetical. The delivery job board beside the errand board has polled every
/// five seconds all along; only Butler was left out, which is why it reads as the errands feature
/// being broken rather than slower.
///
/// <p>What is asserted here is the arrival AND the absence of a flicker. A poll that reassigns
/// the future without keeping the last page throws the screen back to a spinner every five
/// seconds, which is a worse screen than the stale one it replaced — so the third case is as
/// load-bearing as the second.
void main() {

  Widget board(ButlerApi api) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          DeliveryStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: DeliveryStrings.supportedLocales,
        home: Scaffold(body: RiderButlerBoard(api: api)),
      );

  testWidgets('an errand posted after the board loaded appears on its own', (
    WidgetTester tester,
  ) async {
    final _FakeServer server = _FakeServer();
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = server
      ..transformer = SyncTransformer();

    await tester.pumpWidget(board(ButlerApi(dio)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Fetch a phone charger'), findsNothing,
        reason: 'nothing has been posted yet');
    final int loadsBefore = server.availableCalls;

    // A customer posts one. Nothing touches the rider's phone.
    server.available = <Map<String, Object?>>[
      _errand('e1', 'Fetch a phone charger'),
    ];
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 200));

    expect(server.availableCalls, greaterThan(loadsBefore),
        reason: 'the board never asked again — this is the defect, not the assertion');
    expect(find.text('Fetch a phone charger'), findsOneWidget,
        reason: 'a rider staring at this screen must see work arrive without touching it');

    // Let the widget go, so the periodic timer is proven to be cancelled in dispose. Without the
    // cancel this line fails with "A Timer is still pending".
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('and the list does not blink back to a spinner while it refreshes', (
    WidgetTester tester,
  ) async {
    final _FakeServer server = _FakeServer()
      ..available = <Map<String, Object?>>[_errand('e1', 'Collect a prescription')];
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = server
      ..transformer = SyncTransformer();

    await tester.pumpWidget(board(ButlerApi(dio)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Collect a prescription'), findsOneWidget);

    // Straight after a poll fires, before its response lands.
    await tester.pump(const Duration(seconds: 5));

    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'a refresh that blanks the screen every five seconds is worse than the stale '
            'list it replaced');
    expect(find.text('Collect a prescription'), findsOneWidget,
        reason: 'the errand already on screen must stay there while the next page loads');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a poll that fails leaves the last good board alone', (WidgetTester tester) async {
    final _FakeServer server = _FakeServer()
      ..available = <Map<String, Object?>>[_errand('e1', 'Buy bread')];
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = server
      ..transformer = SyncTransformer();

    await tester.pumpWidget(board(ButlerApi(dio)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Buy bread'), findsOneWidget);

    // The network drops between two ticks.
    server.failing = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Buy bread'), findsOneWidget,
        reason: 'the rider did not ask for this refresh, so its failure is not their problem — '
            'showing them an error for it would replace a working board with nothing');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Map<String, Object?> _errand(String id, String what) => <String, Object?>{
      'id': id,
      'mode': 'PURCHASE',
      'status': 'OPEN',
      'what': what,
      'dropoffAddress': 'Hamra, Beirut',
      'deliveryFee': 2.5,
      'payableTotal': 2.5,
      'createdAt': '2026-09-10T09:00:00Z',
    };

/// A stand-in server: no socket, so nothing races the widget test's clock.
class _FakeServer implements HttpClientAdapter {
  List<Map<String, Object?>> available = <Map<String, Object?>>[];
  List<Map<String, Object?>> claimed = <Map<String, Object?>>[];
  bool failing = false;
  int availableCalls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    if (failing) {
      return ResponseBody.fromString('{"detail":"upstream is down"}', 503,
          headers: _json);
    }
    final bool isAvailable = options.uri.path.contains('available');
    if (isAvailable) availableCalls++;
    final List<Map<String, Object?>> rows = isAvailable ? available : claimed;
    return ResponseBody.fromString(
      jsonEncode(<String, Object?>{
        'content': rows,
        'page': 0,
        'size': 30,
        'totalElements': rows.length,
        'totalPages': 1,
      }),
      200,
      headers: _json,
    );
  }

  static const Map<String, List<String>> _json = <String, List<String>>{
    Headers.contentTypeHeader: <String>[Headers.jsonContentType],
  };

  @override
  void close({bool force = false}) {}
}
