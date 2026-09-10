import 'dart:async';
import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_portal/src/backoffice/categories_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the new-category dialog does with a name the server will not take.
///
/// The taxonomy is append-only from this screen — there is no rename, no re-parent and no delete —
/// so the one write it has is the only thing worth testing hard. It used to close the dialog the
/// instant Create was pressed and report the outcome afterwards in a SnackBar, which meant the two
/// realistic failures both threw the operator's typing away: a name that collides with a sibling
/// (409, and the service enforces uniqueness on (name, parent), so the fix is usually one word)
/// and a write that did not land at all. An empty name was worse than either — Create simply
/// returned, so the button looked broken.
///
/// These pin the corrected shape: the dialog is the thing that submits, and it survives being
/// refused.
///
/// Driven through a real Dio with a replaced adapter rather than a fake API object, so
/// [CatalogApi]'s own request building and JSON parsing are under test too.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<String> calls = <String>[];
  final List<Object?> bodies = <Object?>[];

  /// When set, a POST waits on this before answering — the only way to observe the dialog while
  /// its write is still in flight.
  Completer<void>? holdPosts;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method} ${options.path}');
    bodies.add(options.data);
    if (options.method == 'POST' && holdPosts != null) {
      await holdPosts!.future;
    }
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
  /// The taxonomy the screen loads, then a POST that answers however the test wants.
  ({_FakeAdapter adapter, Widget app}) harness({required int postStatus}) {
    final _FakeAdapter adapter = _FakeAdapter((RequestOptions options) {
      if (options.method == 'GET') {
        return _json(<Map<String, dynamic>>[
          <String, dynamic>{'id': 'c-groceries', 'name': 'Groceries', 'children': <dynamic>[]},
        ], 200);
      }
      if (postStatus != 200) {
        return _json(<String, dynamic>{'detail': 'refused'}, postStatus);
      }
      return _json(<String, dynamic>{'id': 'c-new', 'name': 'Frozen'}, 200);
    });

    final Dio dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter;

    return (
      adapter: adapter,
      app: MaterialApp(home: CategoriesScreen(api: CatalogApi(dio))),
    );
  }

  Future<void> openDialogAndType(WidgetTester tester, String name) async {
    await tester.tap(find.text('New category'));
    await tester.pumpAndSettle();
    if (name.isNotEmpty) {
      await tester.enterText(find.byType(TextField), name);
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create'));
  }

  testWidgets('an empty name says so instead of doing nothing', (WidgetTester tester) async {
    final ({_FakeAdapter adapter, Widget app}) h = harness(postStatus: 200);
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    await openDialogAndType(tester, '');
    await tester.pumpAndSettle();

    expect(find.text('Give the category a name'), findsOneWidget,
        reason: 'a dead Create button reads as a broken screen, not as a missing field');
    expect(find.text('New category'), findsWidgets, reason: 'the dialog stays open');
    expect(h.adapter.calls.where((String c) => c.startsWith('POST')), isEmpty,
        reason: 'nothing should be sent for a name that is only whitespace');
  });

  testWidgets('a name that collides keeps the dialog and the typing', (WidgetTester tester) async {
    final ({_FakeAdapter adapter, Widget app}) h = harness(postStatus: 409);
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    await openDialogAndType(tester, 'Frozen');
    await tester.pumpAndSettle();

    expect(find.text('A category with that name already exists here'), findsOneWidget);
    // THE POINT. The operator fixes a 409 by editing one word, which they can only do if the word
    // is still there.
    expect(find.widgetWithText(TextField, 'Frozen'), findsOneWidget,
        reason: 'the dialog must not throw away what was typed when the service refuses it');
    expect(find.widgetWithText(ElevatedButton, 'Create'), findsOneWidget,
        reason: 'Create comes back so the corrected name can be sent');
  });

  testWidgets('any other refusal is reported in the same place', (WidgetTester tester) async {
    final ({_FakeAdapter adapter, Widget app}) h = harness(postStatus: 500);
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    await openDialogAndType(tester, 'Frozen');
    await tester.pumpAndSettle();

    expect(find.text('Could not create the category'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Frozen'), findsOneWidget);
  });

  testWidgets('a write that lands closes the dialog and reloads the tree',
      (WidgetTester tester) async {
    final ({_FakeAdapter adapter, Widget app}) h = harness(postStatus: 200);
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();
    final int getsBefore = h.adapter.calls.where((String c) => c.startsWith('GET')).length;

    await openDialogAndType(tester, 'Frozen');
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing, reason: 'the dialog is gone');
    final int posted = h.adapter.calls.indexWhere((String c) => c.startsWith('POST'));
    expect(posted, isNonNegative);
    expect(h.adapter.bodies[posted], containsPair('name', 'Frozen'));
    expect(h.adapter.calls.where((String c) => c.startsWith('GET')).length, getsBefore + 1,
        reason: 'the tree has to be re-read or the new row never appears');
  });

  testWidgets('the dialog cannot be submitted twice while the first write is in flight',
      (WidgetTester tester) async {
    final ({_FakeAdapter adapter, Widget app}) h = harness(postStatus: 200);
    h.adapter.holdPosts = Completer<void>();
    await tester.pumpWidget(h.app);
    await tester.pumpAndSettle();

    await openDialogAndType(tester, 'Frozen');
    // Not pumpAndSettle: the spinner never settles, and the whole point is the window while it
    // is up. A handful of frames is enough for the request to reach the adapter and stop there.
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(h.adapter.calls.where((String c) => c.startsWith('POST')), hasLength(1));

    // Mid-write: the button is a spinner, and pressing everything in sight adds no second POST.
    expect(find.descendant(
      of: find.byType(ElevatedButton),
      matching: find.byType(CircularProgressIndicator),
    ), findsOneWidget);
    await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'), warnIfMissed: false);
    await tester.pump();
    expect(h.adapter.calls.where((String c) => c.startsWith('POST')), hasLength(1));

    h.adapter.holdPosts!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });
}
