import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_portal/src/backoffice/onboarding_screen.dart';
import 'package:delivery_portal/src/shell/console_controls.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Merchants Directory (Figma `backoffice-merchants` 3:2666).
///
/// Two things are being protected here at once: the decision — which is the only screen in the
/// platform where somebody is told yes or no — and the honesty of the table around it. The design
/// draws columns the platform cannot fill, and the failure this guards against is the obvious one:
/// filling them with a plausible number.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<String> calls = <String>[];
  final List<Object?> bodies = <Object?>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    bodies.add(options.data);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body) => ResponseBody.fromString(body, 200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });

String _application({
  required String id,
  required String name,
  String status = 'SUBMITTED',
  String kind = 'MERCHANT',
  String? emailVerifiedAt = '2026-08-20T09:00:00Z',
  String details = 'null',
  String? rejectionReason,
}) =>
    '''
{"id":"$id","reference":"REF-$id","kind":"$kind","businessName":"$name",
 "contactName":"Sam Owner","contactEmail":"sam@$id.example","contactPhone":"+9611000",
 "emailVerifiedAt":${emailVerifiedAt == null ? 'null' : '"$emailVerifiedAt"'},
 "phoneVerifiedAt":null,"notes":"We open at seven.","details":$details,
 "status":"$status","createdAt":"2026-08-19T08:00:00Z",
 "decidedAt":${status == 'SUBMITTED' ? 'null' : '"2026-08-21T08:00:00Z"'},
 "decidedBy":${status == 'SUBMITTED' ? 'null' : '"operator-1234-5678"'},
 "rejectionReason":${rejectionReason == null ? 'null' : '"$rejectionReason"'},
 "provisionedUserRef":null,"provisionedEntityId":null}''';

String _document({
  required String id,
  String kind = 'NATIONAL_ID',
  String status = 'PENDING',
  String? rejectionReason,
}) =>
    '''
{"id":"$id","kind":"$kind","status":"$status",
 "rejectionReason":${rejectionReason == null ? 'null' : '"$rejectionReason"'},
 "reviewerNote":null,"uploadedAt":"2026-08-20T09:00:00Z","reviewedAt":null,
 "reviewedBy":null,"superseded":false,"viewUrl":"http://files/doc-$id"}''';

void main() {
  late _FakeAdapter adapter;
  late OnboardingApi api;
  late DocumentsApi documentsApi;

  /// The waiting queue. Set per test before [pump].
  late String queueJson;

  /// What `/applications/{id}/documents` answers. Empty unless a test uploads something.
  late String documentsJson;

  setUp(() {
    queueJson = '''
[${_application(id: 'a1', name: 'Rose & Crust Pizzeria', details: '{"businessType":"Pizza & Italian","vehicleType":"Van"}')},
 ${_application(id: 'a2', name: 'Waffle Wonder', emailVerifiedAt: null)}]''';
    documentsJson = '[]';

    adapter = _FakeAdapter((RequestOptions options) {
      // Document verdicts first: their paths also end in /approve and /reject, and answering them
      // with an application would be a shape lie.
      if (options.path.contains('/documents/') && options.path.endsWith('/approve')) {
        return _json(_document(id: 'd1', status: 'APPROVED'));
      }
      if (options.path.contains('/documents/') && options.path.endsWith('/reject')) {
        return _json(
            _document(id: 'd1', status: 'REJECTED', rejectionReason: 'Too blurred'));
      }
      if (options.path.endsWith('/documents')) return _json(documentsJson);
      if (options.path.endsWith('/approve')) {
        return _json(_application(id: 'a1', name: 'Rose & Crust Pizzeria', status: 'APPROVED'));
      }
      if (options.path.endsWith('/reject')) {
        return _json(_application(
            id: 'a1', name: 'Rose & Crust Pizzeria', status: 'REJECTED',
            rejectionReason: 'Outside the area we cover'));
      }
      if (options.path.endsWith('/applications/all')) {
        return _json('''
[${_application(id: 'a9', name: 'Sushi Express', status: 'PROVISIONED')},
 ${_application(id: 'a8', name: 'Salad & Co.', status: 'REJECTED', rejectionReason: 'No address')}]''');
      }
      return _json(queueJson);
    });

    final Dio dio =
        Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
    api = OnboardingApi(dio);
    documentsApi = DocumentsApi(dio);
  });

  Future<void> pump(WidgetTester tester, {Size size = const Size(1500, 1200)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(body: OnboardingScreen(api: api, documentsApi: documentsApi)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('opens on what is waiting, and counts it', (WidgetTester tester) async {
    await pump(tester);

    // The queue is the tab with somebody on the other end of it.
    expect(find.text('Pending Approval (2)'), findsOneWidget);
    expect(find.text('Rose & Crust Pizzeria'), findsOneWidget);
  });

  testWidgets('still counts what is waiting from the full directory',
      (WidgetTester tester) async {
    await pump(tester);
    await tester.tap(find.text('All Partners'));
    await tester.pumpAndSettle();

    // The full list carries every application with its status, so the undecided ones are still
    // countable — an operator reading the directory can see there is work waiting next door.
    // The stub's "all" response is two decided applications, and that is the honest answer.
    expect(find.text('Pending Approval (0)'), findsOneWidget);
    expect(find.text('Sushi Express'), findsOneWidget);
  });

  testWidgets('approves from the row', (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.widgetWithIcon(ConsoleRowAction, Icons.check).first);
    await tester.pumpAndSettle();

    expect(adapter.calls.any((String c) => c.contains('POST') && c.contains('a1/approve')),
        isTrue);
  });

  group('declining', () {
    testWidgets('will not send an empty reason', (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.widgetWithIcon(ConsoleRowAction, Icons.close).first);
      await tester.pumpAndSettle();

      // Disabled rather than validated on submit: the server refuses an empty reason, and finding
      // that out after pressing the button teaches nothing the button could have said.
      final ConsoleButton decline = tester.widget<ConsoleButton>(
          find.widgetWithText(ConsoleButton, 'Decline').hitTestable());
      expect(decline.onPressed, isNull);
    });

    testWidgets('sends what was typed, verbatim', (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.widgetWithIcon(ConsoleRowAction, Icons.close).first);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
          'The address given is outside the area we cover');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ConsoleButton, 'Decline').hitTestable());
      await tester.pumpAndSettle();

      // The applicant is sent this word for word, so it must arrive unedited.
      expect(
        adapter.bodies.any((Object? b) =>
            b is Map && b['reason'] == 'The address given is outside the area we cover'),
        isTrue,
      );
    });
  });

  group('the drawer a row opens', () {
    testWidgets('shows what the wizard collected, when it collected any',
        (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.text('Rose & Crust Pizzeria'));
      await tester.pumpAndSettle();

      expect(find.text('FROM THEIR APPLICATION'), findsOneWidget);
      expect(find.text('BUSINESS TYPE'), findsOneWidget);
      expect(find.text('Pizza & Italian'), findsWidgets);
      expect(find.text('VEHICLE TYPE'), findsOneWidget);
    });

    testWidgets('and no such block at all when it collected none',
        (WidgetTester tester) async {
      // Older applications predate the field. A section of dashes would say the wizard asked and
      // they refused, which is not what happened.
      await pump(tester);

      await tester.tap(find.text('Waffle Wonder'));
      await tester.pumpAndSettle();

      expect(find.text('FROM THEIR APPLICATION'), findsNothing);
      expect(find.text('APPLICANT'), findsOneWidget);
    });

    testWidgets('reviews the uploaded papers one by one', (WidgetTester tester) async {
      documentsJson = '[${_document(id: 'd1')}, ${_document(id: 'd2', kind: 'DRIVING_LICENCE', status: 'APPROVED')}]';
      await pump(tester);

      await tester.tap(find.text('Rose & Crust Pizzeria'));
      await tester.pumpAndSettle();

      // Each paper by its human name, with its own verdict badge — the pill language elsewhere on
      // the page says 'Waiting' too, so the badge type is what disambiguates.
      expect(find.text('National ID'), findsOneWidget);
      expect(find.text('Driving licence'), findsOneWidget);
      expect(find.widgetWithText(ConsoleSmallBadge, 'Waiting'), findsOneWidget);
      expect(find.widgetWithText(ConsoleSmallBadge, 'Approved'), findsOneWidget);

      // Approving the pending one goes to the document endpoint, not the application's.
      await tester.tap(find.byTooltip('Approve this document'));
      await tester.pumpAndSettle();
      expect(
        adapter.calls.any((String c) =>
            c.contains('POST') && c.contains('/a1/documents/d1/approve')),
        isTrue,
      );
    });

    testWidgets('refusing a paper requires the reason the applicant will read',
        (WidgetTester tester) async {
      documentsJson = '[${_document(id: 'd1')}]';
      await pump(tester);

      await tester.tap(find.text('Rose & Crust Pizzeria'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refuse this document'));
      await tester.pumpAndSettle();

      // Dead until something is typed — the reason is the only way the applicant learns what to
      // upload instead.
      final Finder confirm = find.widgetWithText(ConsoleButton, 'Refuse document');
      expect(tester.widget<ConsoleButton>(confirm.hitTestable()).onPressed, isNull);

      await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'The photo is too blurred to read',
      );
      await tester.pumpAndSettle();
      await tester.tap(confirm.hitTestable());
      await tester.pumpAndSettle();

      expect(
        adapter.bodies.any((Object? b) =>
            b is Map && b['reason'] == 'The photo is too blurred to read'),
        isTrue,
      );
      expect(
        adapter.calls.any((String c) =>
            c.contains('POST') && c.contains('/a1/documents/d1/reject')),
        isTrue,
      );
    });

    testWidgets('warns before an unverified address is approved',
        (WidgetTester tester) async {
      await pump(tester);

      await tester.tap(find.text('Waffle Wonder'));
      await tester.pumpAndSettle();

      // Approving one of these sends the account — and how to sign in — to whoever actually owns
      // that inbox.
      expect(find.textContaining('never verified'), findsOneWidget);
    });
  });

  group('the columns nothing feeds', () {
    testWidgets('are drawn and left empty rather than filled with a number',
        (WidgetTester tester) async {
      await pump(tester);

      expect(find.text('Products'), findsOneWidget);
      expect(find.text('Orders'), findsOneWidget);
      // Two dashes per row, and not a zero anywhere: a partner with no counted products and a
      // partner whose products nobody counts are different facts.
      expect(find.byType(ConsoleNoValue), findsNWidgets(4));
      expect(find.text('0'), findsNothing);
    });

    testWidgets('and say so once, under the table', (WidgetTester tester) async {
      await pump(tester);

      expect(find.byType(ConsoleInertNote), findsOneWidget);
      expect(find.text('Coming soon'), findsWidgets);
    });
  });

  testWidgets('the decided record survives the decision', (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.text('All Partners'));
    await tester.pumpAndSettle();

    // Somebody asking "why was this shop turned down" needs the answer to outlive the decision.
    await tester.tap(find.text('Salad & Co.'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Declined'), findsWidgets);
    expect(find.textContaining('No address'), findsOneWidget);
  });

  testWidgets('filters the directory by category', (WidgetTester tester) async {
    await pump(tester);

    // The values are the applicants' own answers, so the filter can only offer a category
    // something on this page actually is.
    await tester.tap(find.widgetWithText(ConsoleFilterButton, 'Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<int>, 'Pizza & Italian'));
    await tester.pumpAndSettle();

    expect(find.text('Rose & Crust Pizzeria'), findsOneWidget);
    expect(find.text('Waffle Wonder'), findsNothing);
  });

  /// Flutter fails a test on a layout overflow, so rendering at the widths the console is actually
  /// opened on is the cheapest check there is. The seven-column partner table is the widest thing
  /// in the Backoffice, so it is the one most likely to break a laptop window.
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

  testWidgets('searches the partners already loaded', (WidgetTester tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField).last, 'waffle');
    await tester.pumpAndSettle();

    expect(find.text('Waffle Wonder'), findsOneWidget);
    expect(find.text('Rose & Crust Pizzeria'), findsNothing);
  });
}
