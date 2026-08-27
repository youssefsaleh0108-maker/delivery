import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/carrier/applicants_screen.dart';
import 'package:delivery_portal/src/shell/console_controls.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rider Onboarding Portal — Figma `carrier-onboarding` (3:3724).
///
/// The restyle moved a list of cards into a three-across grid and gave the decision buttons the
/// design's shapes. The thing that must not have moved is the wiring underneath: approving creates
/// an account and a fleet place, and turning somebody down still cannot happen without a reason
/// typed out, because they are sent it word for word.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.responses);

  final Map<String, Object> responses;
  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');

    final List<String> matches = responses.keys
        .where((String key) => options.path.contains(key))
        .toList()
      ..sort((String a, String b) => b.length.compareTo(a.length));

    if (matches.isEmpty) return ResponseBody.fromString('{}', 404);
    return ResponseBody.fromString(jsonEncode(responses[matches.first]), 200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType]
        });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _applicant({
  String id = 'a1',
  String name = 'Malik Faysal',
  String status = 'SUBMITTED',
  bool emailVerified = true,
  bool phoneVerified = false,
  String? phone = '+96170000000',
  String? rejectionReason,
}) =>
    <String, dynamic>{
      'id': id,
      'reference': 'REF-$id',
      'kind': 'CARRIER',
      'businessName': name,
      'contactName': name,
      'contactEmail': 'malik@example.com',
      'contactPhone': phone,
      'emailVerifiedAt': emailVerified ? '2026-08-16T09:30:00Z' : null,
      'phoneVerifiedAt': phoneVerified ? '2026-08-16T09:30:00Z' : null,
      'notes': null,
      'status': status,
      'createdAt': '2026-08-16T09:30:00Z',
      'decidedAt': null,
      'decidedBy': null,
      'rejectionReason': rejectionReason,
      'provisionedUserRef': null,
      'provisionedEntityId': null,
    };

Map<String, dynamic> _document({
  String id = 'd1',
  String kind = 'NATIONAL_ID',
  String status = 'PENDING',
  String? rejectionReason,
}) =>
    <String, dynamic>{
      'id': id,
      'kind': kind,
      'status': status,
      'rejectionReason': rejectionReason,
      'reviewerNote': null,
      'uploadedAt': '2026-08-16T10:00:00Z',
      'reviewedAt': null,
      'reviewedBy': null,
      'superseded': false,
      'viewUrl': 'http://files/$id',
    };

late _StubAdapter _adapter;

({OnboardingApi onboarding, DeliveryProviderApi provider, DocumentsApi documents}) _apis({
  List<Map<String, dynamic>>? applicants,
  List<Map<String, dynamic>>? documents,
}) {
  _adapter = _StubAdapter(<String, Object>{
    // Written out in full: the adapter matches the longest key a path contains, and a truncated
    // documents key would lose to the applicants-list key inside its own path.
    '/applications/for-company/p1/a1/documents/d1/approve': _document(status: 'APPROVED'),
    '/applications/for-company/p1/a1/documents/d1/reject':
        _document(status: 'REJECTED', rejectionReason: 'Too blurred'),
    '/applications/for-company/p1/a1/documents': documents ?? <Map<String, dynamic>>[],
    '/applications/for-company/p1/a2/documents': <Map<String, dynamic>>[],
    '/applications/for-company/p1/a3/documents': <Map<String, dynamic>>[],
    '/applications/for-company/p1/a1/approve': _applicant(status: 'PROVISIONED'),
    '/applications/for-company/p1/a1/reject':
        _applicant(status: 'REJECTED', rejectionReason: 'No licence'),
    '/applications/for-company/p1':
        applicants ?? <Map<String, dynamic>>[_applicant()],
    '/my-company': <String, dynamic>{
      'id': 'p1',
      'slug': 'swift',
      'name': 'Swift Couriers',
      'kind': 'EXTERNAL',
      'status': 'ACTIVE',
      'canTakeWork': true,
    },
  });
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = _adapter;
  return (
    onboarding: OnboardingApi(dio),
    provider: DeliveryProviderApi(dio),
    documents: DocumentsApi(dio),
  );
}

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('en'),
      theme: DeliveryTheme.light(),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

Future<void> pump(
    WidgetTester tester,
    ({OnboardingApi onboarding, DeliveryProviderApi provider, DocumentsApi documents}) apis,
    {double width = 1180}) async {
  tester.view.physicalSize = Size(width, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_wrap(
    ApplicantsScreen(
      api: apis.onboarding,
      providerApi: apis.provider,
      documentsApi: apis.documents,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  testWidgets('is the design queue, with a real count on the chip', (WidgetTester tester) async {
    await pump(tester, _apis(applicants: <Map<String, dynamic>>[
      _applicant(id: 'a1'),
      _applicant(id: 'a2', name: 'Sami Al-Harbi'),
    ]));

    expect(find.text('Rider Onboarding Portal'), findsOneWidget);
    expect(find.text('Pending Verification Queue'), findsOneWidget);
    expect(find.text('2 Applications Left'), findsOneWidget);
  });

  testWidgets('the checklist shows the checks that exist and is honest about no uploads',
      (WidgetTester tester) async {
    // The first two rows are the verifications the application itself carries. The papers row is
    // real now — and for an applicant who uploaded nothing, it says so instead of inventing one.
    await pump(tester, _apis());

    expect(find.text('Onboarding documentation check'.toUpperCase()), findsOneWidget);
    expect(find.text('Email address verified'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Phone number verified'), findsOneWidget);
    expect(find.text('Pending Verification'), findsOneWidget);
    expect(find.text('Identity, vehicle and background documents'), findsOneWidget);
    expect(find.text('Not uploaded'), findsOneWidget);
    expect(find.byType(ConsoleComingSoonChip), findsNothing);
  });

  testWidgets('uploaded papers are reviewed in place', (WidgetTester tester) async {
    await pump(tester, _apis(documents: <Map<String, dynamic>>[
      _document(id: 'd1'),
      _document(id: 'd2', kind: 'DRIVING_LICENCE', status: 'APPROVED'),
    ]));

    // Each paper by its human name, with its own verdict badge.
    expect(find.text('National ID'), findsOneWidget);
    expect(find.text('Driving licence'), findsOneWidget);

    await tester.tap(find.byTooltip('Approve this document'));
    await tester.pumpAndSettle();

    expect(
      _adapter.calls.any((String c) =>
          c.contains('POST') && c.contains('/p1/a1/documents/d1/approve')),
      isTrue,
    );
  });

  testWidgets('refusing a paper cannot happen without the reason the applicant reads',
      (WidgetTester tester) async {
    await pump(tester, _apis(documents: <Map<String, dynamic>>[_document(id: 'd1')]));

    await tester.tap(find.byTooltip('Refuse this document'));
    await tester.pumpAndSettle();

    final Finder confirm = find.widgetWithText(ConsoleSoftButton, 'Refuse document');
    expect(tester.widget<ConsoleSoftButton>(confirm).onPressed, isNull);

    await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      'The photo is too blurred to read',
    );
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(
      _adapter.calls.any((String c) =>
          c.contains('POST') && c.contains('/p1/a1/documents/d1/reject')),
      isTrue,
    );
  });

  testWidgets('approving still creates the account and the fleet place',
      (WidgetTester tester) async {
    await pump(tester, _apis());

    // Said before the button is pressed, because approving is two irreversible things at once.
    expect(find.text(en.hiringAlsoCreatesTheirAccount), findsOneWidget);

    await tester.tap(find.widgetWithText(ConsolePrimaryButton, 'Approve Rider'));
    await tester.pumpAndSettle();

    expect(
        _adapter.calls.any((String c) =>
            c.contains('POST') && c.contains('/for-company/p1/a1/approve')),
        isTrue);
  });

  testWidgets('turning somebody down cannot happen without a reason',
      (WidgetTester tester) async {
    await pump(tester, _apis());

    await tester.tap(find.widgetWithText(ConsoleSoftButton, 'Reject Application'));
    await tester.pumpAndSettle();

    // The dialog's confirm is dead until something is typed — the reason is sent to the applicant
    // word for word, so an empty one would be a rejection with no explanation.
    final Finder confirm = find.widgetWithText(ConsoleSoftButton, en.turnDown);
    expect(tester.widget<ConsoleSoftButton>(confirm).onPressed, isNull);

    // Scoped to the dialog: the page's own search box is a TextField too.
    await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      'No licence',
    );
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(
        _adapter.calls.any(
            (String c) => c.contains('POST') && c.contains('/for-company/p1/a1/reject')),
        isTrue);
  });

  testWidgets('a decided applicant is a record, not a decision to make again',
      (WidgetTester tester) async {
    await pump(tester, _apis(applicants: <Map<String, dynamic>>[
      _applicant(status: 'REJECTED', rejectionReason: 'No licence'),
    ]));

    expect(find.byType(ConsoleStatusPill), findsOneWidget);
    expect(find.widgetWithText(ConsolePrimaryButton, 'Approve Rider'), findsNothing);
    expect(find.textContaining('No licence'), findsOneWidget);
  });

  // Three cards across at 1180, two at 1020, one at 764 — the grid reflows rather than squeezing a
  // card below the ~340 at which its checklist stops scanning. An overflow fails the test.
  for (final double width in <double>[1180, 1020, 764]) {
    testWidgets('lays out a full queue at a ${width.toInt()}px content column',
        (WidgetTester tester) async {
      await pump(
        tester,
        _apis(applicants: <Map<String, dynamic>>[
          _applicant(id: 'a1'),
          _applicant(id: 'a2', name: 'Sami Al-Harbi'),
          _applicant(id: 'a3', name: 'Robert Downey'),
        ]),
        width: width,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('three across at the design width, one across when there is no room',
      (WidgetTester tester) async {
    final List<Map<String, dynamic>> three = <Map<String, dynamic>>[
      _applicant(id: 'a1'),
      _applicant(id: 'a2', name: 'Sami Al-Harbi'),
      _applicant(id: 'a3', name: 'Robert Downey'),
    ];

    // Cards on the same row share a top edge, so the number of distinct tops is the number of rows.
    Set<double> rowTops() => find
        .byType(ConsoleSoftButton)
        .evaluate()
        .map((Element e) => tester.getTopLeft(find.byWidget(e.widget)).dy)
        .toSet();

    await pump(tester, _apis(applicants: three));
    expect(rowTops(), hasLength(1), reason: 'three across at the design width');

    await pump(tester, _apis(applicants: three), width: 764);
    // The grid reflows rather than squeezing three cards into a 700px column, where the checklist
    // rows would stop scanning.
    expect(rowTops().length, greaterThan(1));
  });
}
