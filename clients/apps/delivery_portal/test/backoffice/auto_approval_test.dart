import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_portal/src/backoffice/auto_approval_panel.dart';
import 'package:delivery_portal/src/backoffice/onboarding_screen.dart';
import 'package:delivery_portal/src/backoffice/settings_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The three approval gates — the control that used to be an environment variable and a container
/// restart ("auto approval is not found in the portal to choose it").
///
/// What is worth pinning here is not that three switches draw. It is that the screen cannot tell an
/// operator something the server has not said: it cannot show a gate open that a save failed to
/// open, it cannot claim a person chose a value the deployment supplied, and it cannot invent a
/// source for a word it does not know. Every one of those lies would be read as "somebody decided
/// this on purpose", and the thing being decided is whether a stranger becomes a live rider.
///
/// Driven through a Dio with a replaced adapter rather than a fake API object, so the real
/// [AutoApprovalApi] and its JSON parsing are under test too.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<String> calls = <String>[];
  final List<Object?> bodies = <Object?>[];

  /// When set, a PUT waits on this before answering.
  ///
  /// The only way to observe the panel mid-save. Every other test here settles the frame, which
  /// means they all inspect the screen after the response has landed — and the property that
  /// matters most is about the window before it.
  Completer<void>? holdPuts;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    bodies.add(options.data);
    if (options.method == 'PUT' && holdPuts != null) {
      await holdPuts!.future;
    }
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, {int status = 200}) => ResponseBody.fromString(body, status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });

/// The contract's exact response shape, with each kind's source under its own control.
String _settings({
  bool rider = false,
  String riderSource = 'CONFIG',
  bool merchant = true,
  String merchantSource = 'PORTAL',
  bool carrier = false,
  String carrierSource = 'CONFIG',
  String? lastChangedBy = 'ops-sam',
  String? lastChangedAt = '2026-08-29T10:11:12Z',
}) =>
    '''
{"rider":{"automatic":$rider,"source":"$riderSource"},
 "merchant":{"automatic":$merchant,"source":"$merchantSource"},
 "carrier":{"automatic":$carrier,"source":"$carrierSource"},
 "lastChangedBy":${lastChangedBy == null ? 'null' : '"$lastChangedBy"'},
 "lastChangedAt":${lastChangedAt == null ? 'null' : '"$lastChangedAt"'}}''';

/// The connector half of the Settings screen, which is not what these tests are about.
const String _connectorsJson = '''
[{"connectorType":"EMAIL","provider":"SMTP","availableProviders":["SMTP"],
  "config":{},"vaultPath":"secret/email-connector","maskedSecret":"********",
  "secretRotatedAt":null,"active":true,"updatedBy":"system",
  "updatedAt":"2026-08-09T10:00:00Z"}]''';

void main() {
  late _FakeAdapter adapter;
  late Dio dio;

  /// What the GET answers with. Set per test before pumping.
  late String getJson;

  /// What the PUT answers with, and with which status. A 500 is how a refused save is staged.
  late String putJson;
  late int putStatus;

  setUp(() {
    getJson = _settings();
    putJson = _settings();
    putStatus = 200;

    adapter = _FakeAdapter((RequestOptions options) {
      if (options.path.contains('auto-approval')) {
        return options.method == 'PUT'
            ? _json(putJson, status: putStatus)
            : _json(getJson);
      }
      if (options.path.contains('notification-rates')) {
        return _json('[{"channel":"EMAIL","provider":"SMTP","total":10,"sent":10,"failed":0,'
            '"inFlight":0,"successRate":100.0,"avgSecondsToSend":0.4,"windowHours":24}]');
      }
      if (options.path.endsWith('/history')) return _json('[]');
      if (options.path.contains('/applications')) return _json('[]');
      return _json(_connectorsJson);
    });
    dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(
        body: SettingsScreen(
          api: ConnectorSettingsApi(dio),
          rateApi: DeliveryRateApi(dio),
          autoApprovalApi: AutoApprovalApi(dio),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Switch switchFor(WidgetTester tester, String kind) =>
      tester.widget<Switch>(find.byKey(ValueKey<String>('auto-approval-$kind')));

  Future<void> toggle(WidgetTester tester, String kind) async {
    await tester.tap(find.byKey(ValueKey<String>('auto-approval-$kind')));
    await tester.pumpAndSettle();
  }

  Iterable<Map<String, dynamic>> puts() => adapter.bodies
      .whereType<Map<String, dynamic>>()
      .where((Map<String, dynamic> b) => b.containsKey('rider'));

  group('the switches', () {
    testWidgets('draws one per kind, in the state the server sent',
        (WidgetTester tester) async {
      await pumpSettings(tester);

      expect(find.text('Riders'), findsOneWidget);
      expect(find.text('Shops'), findsOneWidget);
      expect(find.text('Delivery companies'), findsOneWidget);

      expect(switchFor(tester, 'RIDER').value, isFalse);
      expect(switchFor(tester, 'MERCHANT').value, isTrue);
      expect(switchFor(tester, 'CARRIER').value, isFalse);
    });

    testWidgets('says what turning one on actually means', (WidgetTester tester) async {
      await pumpSettings(tester);

      // The consequence, in the operator's words rather than the platform's: nobody reads the
      // papers, and the papers are still there.
      expect(find.textContaining('without anyone reading their licence'), findsOneWidget);
      expect(find.textContaining('stop being a gate'), findsOneWidget);
      // A carrier signs for a fleet and a payout account, and that is worth a word of its own.
      expect(find.textContaining('signs for a fleet'), findsOneWidget);
    });

    testWidgets('distinguishes a value somebody chose from one the deployment supplied',
        (WidgetTester tester) async {
      await pumpSettings(tester);

      // Two CONFIG kinds and one PORTAL. The difference is the whole reason the response carries a
      // source: an operator reading "on" needs to know whether a person is answerable for it.
      expect(find.text('From deployment config'), findsNWidgets(2));
      expect(find.text('Set in the portal'), findsOneWidget);
    });

    testWidgets('names whoever last changed it', (WidgetTester tester) async {
      await pumpSettings(tester);

      expect(find.textContaining('Last changed by ops-sam'), findsOneWidget);
    });

    testWidgets('and says plainly when nobody has', (WidgetTester tester) async {
      getJson = _settings(
        merchant: false,
        merchantSource: 'CONFIG',
        lastChangedBy: null,
        lastChangedAt: null,
      );
      await pumpSettings(tester);

      // Not a blank line: "nobody has ever set this" and "the lookup failed" must not look the
      // same, and the first is the same fact as all three sources reading CONFIG.
      expect(find.textContaining('Never changed from the portal'), findsOneWidget);
      // Scoped to the panel — the connector cards further down the same page carry a "last changed
      // by" line of their own, about an entirely different record.
      expect(
        find.descendant(
          of: find.byType(AutoApprovalPanel),
          matching: find.textContaining('Last changed by'),
        ),
        findsNothing,
      );
    });

    testWidgets('renders a source it does not know by the server\'s own spelling',
        (WidgetTester tester) async {
      getJson = _settings(riderSource: 'FEATURE_FLAG');
      await pumpSettings(tester);

      // Degrades rather than throwing, and does not guess: calling an unknown source "Set in the
      // portal" would put a person's name on a decision nobody made.
      expect(find.text('FEATURE_FLAG'), findsOneWidget);
      expect(find.text('Set in the portal'), findsOneWidget); // merchant's, and only merchant's.
    });
  });

  group('saving', () {
    testWidgets('sends all three values, with the one that was touched changed',
        (WidgetTester tester) async {
      putJson = _settings(rider: true, riderSource: 'PORTAL');
      await pumpSettings(tester);

      await toggle(tester, 'RIDER');

      // The contract takes all three and no nulls, so the untouched kinds travel as they are —
      // sending `false` for a kind nobody thought about would close a gate behind their back.
      expect(puts(), hasLength(1));
      expect(puts().single, <String, dynamic>{
        'rider': true,
        'merchant': true,
        'carrier': false,
      });
      expect(
        adapter.calls.any((String c) => c == 'PUT /api/onboarding/admin/auto-approval'),
        isTrue,
      );
    });

    /// Switching a gate OFF, which is the direction that matters in an incident.
    testWidgets('sends false for a kind that was switched off', (WidgetTester tester) async {
      // merchant defaults to true in _settings, so tapping it is an ON -> OFF transition.
      putJson = _settings(merchant: false, merchantSource: 'PORTAL');
      await pumpSettings(tester);

      await toggle(tester, 'MERCHANT');

      expect(puts().single, <String, dynamic>{
        'rider': false,
        'merchant': false,
        'carrier': false,
      });
      expect(switchFor(tester, 'MERCHANT').value, isFalse);
    });

    /// The panel's central claim, asserted in the window where it is actually true.
    ///
    /// Every other save test settles the frame first, so all of them would still pass against an
    /// optimistic implementation that moved the thumb immediately and rolled it back on error —
    /// including the 403 and 500 ones. That implementation would show an operator an open gate that
    /// is not open, which is the one thing this screen must never do.
    testWidgets('the switch does not move until the server has answered',
        (WidgetTester tester) async {
      putJson = _settings(rider: true, riderSource: 'PORTAL');
      await pumpSettings(tester);
      expect(switchFor(tester, 'RIDER').value, isFalse);

      final Completer<void> inFlight = Completer<void>();
      adapter.holdPuts = inFlight;

      await tester.tap(find.byKey(const ValueKey<String>('auto-approval-RIDER')));
      await tester.pump(); // the save is away; deliberately NOT settled.

      // There is no rider thumb at all mid-save — a spinner stands where it was — so there is
      // nothing on screen that could be showing a value the server has not agreed to.
      expect(find.byKey(const ValueKey<String>('auto-approval-RIDER')), findsNothing);
      // And the other two cannot be moved meanwhile: the PUT carries all three, so a second change
      // against the record about to be replaced would write back a value nobody chose.
      expect(switchFor(tester, 'MERCHANT').onChanged, isNull);
      expect(switchFor(tester, 'CARRIER').onChanged, isNull);

      inFlight.complete();
      await tester.pumpAndSettle();

      expect(switchFor(tester, 'RIDER').value, isTrue);
      expect(switchFor(tester, 'MERCHANT').onChanged, isNotNull);
    });

    testWidgets('renders the response rather than what was sent', (WidgetTester tester) async {
      putJson = _settings(
        rider: true,
        riderSource: 'PORTAL',
        lastChangedBy: 'ops-nadia',
        lastChangedAt: '2026-08-29T11:00:00Z',
      );
      await pumpSettings(tester);

      await toggle(tester, 'RIDER');

      expect(switchFor(tester, 'RIDER').value, isTrue);
      // The source moved with it: this kind is now somebody's decision, not the deployment's.
      expect(find.text('Set in the portal'), findsNWidgets(2));
      expect(find.text('From deployment config'), findsOneWidget);
      expect(find.textContaining('Last changed by ops-nadia'), findsOneWidget);
    });

    testWidgets('a refused save leaves the switch showing what is running',
        (WidgetTester tester) async {
      putStatus = 500;
      putJson = '{"message":"Auto-approval is locked in this environment."}';
      await pumpSettings(tester);

      await toggle(tester, 'CARRIER');

      // The failure is said in the server's own words, twice over: a snackbar for the moment, and
      // a line in the card that is still there once it has gone.
      expect(find.text('Auto-approval is locked in this environment.'), findsNWidgets(2));
      // And the gate is still shut. A switch left sitting on the value that did not save is the
      // worst outcome available here — it reads as an open gate to the next person who looks.
      expect(switchFor(tester, 'CARRIER').value, isFalse);
    });

    testWidgets('a refused save does not disturb the other two kinds',
        (WidgetTester tester) async {
      putStatus = 403;
      putJson = '{"message":"Your account is not allowed to change this."}';
      await pumpSettings(tester);

      await toggle(tester, 'RIDER');

      expect(switchFor(tester, 'RIDER').value, isFalse);
      expect(switchFor(tester, 'MERCHANT').value, isTrue);
      expect(switchFor(tester, 'CARRIER').value, isFalse);
      // Nothing about the record changed, so the audit line must not claim it did.
      expect(find.textContaining('Last changed by ops-sam'), findsOneWidget);
    });

    testWidgets('a failed read says so instead of drawing three shut gates',
        (WidgetTester tester) async {
      adapter = _FakeAdapter((RequestOptions options) {
        if (options.path.contains('auto-approval')) return _json('{}', status: 503);
        if (options.path.contains('notification-rates')) return _json('[]');
        if (options.path.endsWith('/history')) return _json('[]');
        return _json(_connectorsJson);
      });
      dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
      await pumpSettings(tester);

      // Three switches drawn off means "every application is read by a person", which is a claim
      // about the platform that a failed request cannot support.
      expect(find.byType(Switch), findsNothing);
      expect(find.textContaining('Could not read whether'), findsOneWidget);
    });
  });

  group('the review queue', () {
    Future<void> pumpQueue(WidgetTester tester, {bool wired = true}) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: DeliveryTheme.light(),
        home: Scaffold(
          body: OnboardingScreen(
            api: OnboardingApi(dio),
            documentsApi: DocumentsApi(dio),
            autoApprovalApi: wired ? AutoApprovalApi(dio) : null,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('says which kinds are not waiting for a decision', (WidgetTester tester) async {
      getJson = _settings(rider: true, riderSource: 'PORTAL');
      await pumpQueue(tester);

      // The queue is empty in this fixture, which is exactly the moment a reviewer needs to be
      // told the difference between "nobody applied" and "nobody has to be read".
      expect(find.textContaining('Riders and Shops are approved automatically'), findsOneWidget);
      // Not "never appear here": the All Partners tab lists them, already approved. The line has to
      // survive being read on either tab, so it talks about waiting rather than about appearing.
      expect(find.textContaining('never waiting for a decision'), findsOneWidget);
      expect(find.textContaining('never appear here'), findsNothing);
      // Read-only: the switches stay on the page that owns them.
      expect(find.text('Changed in Settings › Approvals'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('and says so in the other direction too', (WidgetTester tester) async {
      getJson = _settings(merchant: false, merchantSource: 'CONFIG');
      await pumpQueue(tester);

      expect(find.textContaining('Nothing is approved automatically'), findsOneWidget);
    });

    testWidgets('draws no line at all when it could not be read',
        (WidgetTester tester) async {
      // Rather than the reassuring half of the sentence. "Every application is read by a person" is
      // a promise, and an unwired or unreachable settings endpoint is not evidence for it.
      await pumpQueue(tester, wired: false);

      expect(find.textContaining('approved automatically'), findsNothing);
      expect(find.text('Changed in Settings › Approvals'), findsNothing);
    });
  });
}
