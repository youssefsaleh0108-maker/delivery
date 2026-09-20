import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the Publish button says while it is waiting.
///
/// A shop cannot be listed without a map pin any more, and before this the merchant found that out
/// by pressing Publish and reading the server's English in a red snackbar — with no way to tell
/// which of the two rules had refused, and nothing offering the fix. The picker existed the whole
/// time, three taps further down the same page, and nothing ever pointed at it. Twelve live shops
/// on dev have no coordinates at all.
///
/// So the three things pinned here: the reason is on screen BEFORE the press, it is in the
/// merchant's own language, and the thing beside it is the fix.
class _DraftShopAdapter implements HttpClientAdapter {
  _DraftShopAdapter({this.pinned = false, this.hours = true});

  /// Whether the shop has coordinates. False is the state every real shop on dev is in.
  final bool pinned;

  /// Whether the server has a week of hours for it.
  final bool hours;

  final List<String> calls = <String>[];

  Map<String, dynamic> get store => <String, dynamic>{
        'id': 'store-1',
        'slug': 'falafel-king',
        'name': 'Falafel King',
        'vertical': 'RESTAURANT',
        'availability': 'CLOSED',
        'status': 'DRAFT',
        'address': 'Hamra Street, Beirut',
        'deliveryFee': 2.5,
        'minOrder': 10.0,
        'etaMinMinutes': 20,
        'etaMaxMinutes': 40,
        if (pinned) 'latitude': 33.8938,
        if (pinned) 'longitude': 35.5018,
      };

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');

    Object body;
    if (options.path.endsWith('/hours')) {
      body = hours
          ? <dynamic>[
              for (int day = 1; day <= 7; day++)
                <String, dynamic>{'dayOfWeek': day, 'opensAt': '09:00', 'closesAt': '22:00'},
            ]
          : <dynamic>[];
    } else if (options.path.endsWith('/mine')) {
      body = <String, dynamic>{
        'content': <Map<String, dynamic>>[store],
        'page': 0,
        'size': 20,
        'totalElements': 1,
        'totalPages': 1,
      };
    } else {
      body = store;
    }

    return ResponseBody.fromString(jsonEncode(body), 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Future<_DraftShopAdapter> _pump(WidgetTester tester,
    {bool pinned = false, bool hours = true, Locale locale = const Locale('en')}) async {
  tester.view.physicalSize = const Size(400, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _DraftShopAdapter adapter = _DraftShopAdapter(pinned: pinned, hours: hours);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;

  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    locale: locale,
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: StoreScreen(api: StoreApi(dio)),
  ));
  await tester.pumpAndSettle();
  return adapter;
}

/// The Publish control, found by its label rather than by position.
Finder _publish(DeliveryStrings t) => find.ancestor(
      of: find.text(t.publish),
      matching: find.byType(InkWell),
    );

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  testWidgets('an unpinned draft says the pin is what is missing', (WidgetTester tester) async {
    await _pump(tester);

    expect(find.text(en.merchPublishNeedsPin), findsOneWidget);
    expect(find.text(en.merchPublishNeedsHours), findsNothing);
  });

  testWidgets('and offers the picker beside it rather than only naming the problem',
      (WidgetTester tester) async {
    final _DraftShopAdapter adapter = await _pump(tester);

    await tester.tap(find.widgetWithText(TextButton, en.merchPinSetIt));
    await tester.pumpAndSettle();

    // The picker is a modal sheet with a Save that is disabled until a point exists.
    expect(find.text(en.merchPinShopLocation), findsWidgets);
    expect(find.text(en.save), findsOneWidget);
    // Opening it writes nothing.
    expect(adapter.calls.where((String c) => c.contains('/location')), isEmpty);
  });

  /// A button whose only possible outcome is a red snackbar is worse than one that says it is
  /// waiting. The server still enforces the rule; this is only about not making the merchant
  /// discover it by pressing.
  testWidgets('Publish is not offered while the pin is missing', (WidgetTester tester) async {
    final _DraftShopAdapter adapter = await _pump(tester);

    expect(find.text(en.publish), findsOneWidget);
    await tester.tap(_publish(en), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(adapter.calls.where((String c) => c.contains('/publish')), isEmpty);
  });

  testWidgets('a pinned draft may publish, and says nothing is missing',
      (WidgetTester tester) async {
    final _DraftShopAdapter adapter = await _pump(tester, pinned: true);

    expect(find.text(en.merchPublishNeedsPin), findsNothing);
    expect(find.text(en.merchPublishNeedsHours), findsNothing);

    await tester.tap(_publish(en));
    await tester.pumpAndSettle();

    expect(adapter.calls.any((String c) => c.contains('/publish')), isTrue);
  });

  /// Hours first, the same order the server refuses in: a shop with neither is being set up rather
  /// than corrected, and one problem beats a list of two.
  testWidgets('a shop with no hours is told about the hours first', (WidgetTester tester) async {
    await _pump(tester, hours: false, pinned: false);

    expect(find.text(en.merchPublishNeedsHours), findsOneWidget);
    expect(find.text(en.merchPublishNeedsPin), findsNothing);
  });

  /// The whole reason the server sends a code rather than only a sentence. Before this, the message
  /// a merchant saw was the server's English `detail`, whatever locale they were reading in.
  testWidgets('the reason is in Arabic for an Arabic merchant', (WidgetTester tester) async {
    await _pump(tester, locale: const Locale('ar'));

    expect(find.text(ar.merchPublishNeedsPin), findsOneWidget);
    expect(find.text(en.merchPublishNeedsPin), findsNothing);
  });
}
