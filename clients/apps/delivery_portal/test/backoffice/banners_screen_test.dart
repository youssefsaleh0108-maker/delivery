import 'dart:async';
import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_portal/src/backoffice/banners_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the banner editor does with a destination the service will not resolve.
///
/// A banner is the most expensive dialog in the console to refill: a title, a subtitle, a link
/// kind, the id it points at, a position and a live switch. It is also the one most likely to be
/// refused, because the service checks that a STORE or CATEGORY id actually exists and the
/// operator types that id in by hand — there is no picker. The screen used to pop the dialog the
/// moment Create was pressed and report the refusal afterwards in a SnackBar, so a mistyped id
/// cost all six fields.
///
/// These pin the corrected shape: the dialog submits, and it survives being refused with the
/// draft intact. The client-side rules it already had — a title is required, a linked banner
/// needs a destination, a position is 0..999 — are pinned alongside, because moving the submit
/// is exactly the change that could have dropped them.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<String> calls = <String>[];
  final List<Object?> bodies = <Object?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method} ${options.path}');
    bodies.add(options.data);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? body, int status) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );

void main() {
  /// One live banner in the list, and a POST that answers however the test wants.
  ({_FakeAdapter adapter, Widget app}) harness({int postStatus = 200, String? postMessage}) {
    final _FakeAdapter adapter = _FakeAdapter((RequestOptions options) {
      if (options.method == 'GET' && options.path.contains('/api/banners/all')) {
        return _json(<String, dynamic>{
          'content': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'b-1',
              'title': 'Free delivery on your first order',
              'linkKind': 'NONE',
              'position': 1,
              'active': true,
            },
          ],
          'totalElements': 1,
          'totalPages': 1,
          'number': 0,
          'size': 20,
        }, 200);
      }
      if (options.method == 'GET') {
        return _json(<dynamic>[], 200);
      }
      if (postStatus != 200) {
        return _json(<String, dynamic>{'message': postMessage}, postStatus);
      }
      return _json(<String, dynamic>{
        'id': 'b-2',
        'title': 'Frozen aisle now open',
        'linkKind': 'NONE',
        'position': 0,
        'active': true,
      }, 200);
    });

    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter;

    return (
      adapter: adapter,
      app: MaterialApp(
        home: Scaffold(
          body: BannersScreen(api: BannerApi(dio), catalogApi: CatalogApi(dio)),
        ),
      ),
    );
  }

  Future<void> openNew(WidgetTester tester) async {
    await tester.tap(find.text('New banner'));
    await tester.pumpAndSettle();
  }

  /// The dialog's fields in order: title, subtitle, destination id, position.
  Future<void> fill(WidgetTester tester, {required String title, String? target}) async {
    await tester.enterText(find.byType(TextField).at(0), title);
    if (target != null) {
      // Choosing CATEGORY is what makes the destination field appear.
      await tester.tap(find.byType(DropdownButtonFormField<BannerLinkKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Category').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(2), target);
    }
    await tester.pump();
  }

  testWidgets('a destination the service cannot resolve keeps the whole draft',
      (WidgetTester tester) async {
    final ({_FakeAdapter adapter, Widget app}) h = harness(
      postStatus: 422,
      postMessage: 'Nothing found for CATEGORY 00000000-0000-4000-8000-000000000000',
    );
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    await openNew(tester);
    await fill(
      tester,
      title: 'Frozen aisle now open',
      target: '00000000-0000-4000-8000-000000000000',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create'));
    await tester.pumpAndSettle();

    // The service's own sentence, in the dialog, with everything still typed.
    expect(find.text('Nothing found for CATEGORY 00000000-0000-4000-8000-000000000000'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, 'Frozen aisle now open'), findsOneWidget);
    expect(find.widgetWithText(TextField, '00000000-0000-4000-8000-000000000000'), findsOneWidget,
        reason: 'the id is the field that was wrong — retyping the other five is the cost this '
            'fix removes');
    expect(find.widgetWithText(ElevatedButton, 'Create'), findsOneWidget);
  });

  testWidgets('a banner that saves closes the dialog and reloads the list',
      (WidgetTester tester) async {
    final ({_FakeAdapter adapter, Widget app}) h = harness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();
    final int listedBefore =
        h.adapter.calls.where((String c) => c.contains('/api/banners/all')).length;

    await openNew(tester);
    await fill(tester, title: 'Frozen aisle now open');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing, reason: 'the dialog is gone');
    expect(find.text('Banner created'), findsOneWidget);
    expect(h.adapter.calls.where((String c) => c.contains('/api/banners/all')).length,
        listedBefore + 1);
  });

  testWidgets('the rules the dialog enforces itself never reach the wire',
      (WidgetTester tester) async {
    final ({_FakeAdapter adapter, Widget app}) h = harness();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    await openNew(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.text('A banner needs a title'), findsOneWidget);

    // A linked banner with nowhere to go.
    await fill(tester, title: 'Frozen aisle now open', target: '');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.text('A category banner needs a destination'), findsOneWidget);

    // A position outside the rail. The destination has to be filled first or the rule above
    // fires again — they are checked in field order.
    await tester.enterText(find.byType(TextField).at(2), 'c-groceries');
    await tester.enterText(find.byType(TextField).at(3), '1000');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.text('Position must be a number from 0 to 999'), findsOneWidget);

    expect(h.adapter.calls.where((String c) => c.startsWith('POST')), isEmpty,
        reason: 'none of these three should have cost a round trip');
  });
}
