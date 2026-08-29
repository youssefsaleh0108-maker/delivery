import 'package:delivery_portal/src/backoffice/settings_screen.dart';
import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// This page can redirect real SMS traffic and, from Phase 4, real money. The behaviour worth
/// pinning is not that it looks right — it is that it cannot offer a provider the backend has no
/// client for, cannot show a credential, and cannot switch anything without a confirmation.
///
/// Driven through a Dio with a replaced adapter rather than a fake API object, so the real
/// [ConnectorSettingsApi] and its JSON parsing are under test too.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body) => ResponseBody.fromString(
      body,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType]
      },
    );

const String _connectorsJson = '''
[
  {"connectorType":"SMS","provider":"DEV_PASSTHROUGH",
   "availableProviders":["DEV_PASSTHROUGH","MONTYMOBILE","TWILIO"],
   "config":{"senderId":"Delivery"},"vaultPath":"secret/sms-connector",
   "maskedSecret":"********","secretRotatedAt":null,"active":true,
   "updatedBy":"system","updatedAt":"2026-08-09T10:00:00Z"},
  {"connectorType":"EMAIL","provider":"SMTP","availableProviders":["SMTP"],
   "config":{},"vaultPath":"secret/email-connector","maskedSecret":"********",
   "secretRotatedAt":null,"active":true,"updatedBy":"system",
   "updatedAt":"2026-08-09T10:00:00Z"}
]''';

/// What the approval gates answer with. This screen now carries them above the connectors, so the
/// stub has to hold up its end — the switches are covered in `auto_approval_test.dart`.
const String _autoApprovalJson = '''
{"rider":{"automatic":false,"source":"CONFIG"},
 "merchant":{"automatic":false,"source":"CONFIG"},
 "carrier":{"automatic":false,"source":"CONFIG"},
 "lastChangedBy":null,"lastChangedAt":null}''';

void main() {
  late _FakeAdapter adapter;
  late ConnectorSettingsApi api;
  late DeliveryRateApi rateApi;
  late AutoApprovalApi autoApprovalApi;

  setUp(() {
    adapter = _FakeAdapter((RequestOptions options) {
      if (options.path.contains('auto-approval')) return _json(_autoApprovalJson);
        if (options.path.contains('notification-rates')) {
        // The Phase 6 panel lives on this screen now, so the stub has to answer for it.
        return _json('[{"channel":"SMS","provider":"DEV_PASSTHROUGH","total":10,"sent":10,"failed":0,"inFlight":0,"successRate":100.0,"avgSecondsToSend":0.4,"windowHours":24}]');
      }
      if (options.path.endsWith('/history')) return _json('[]');
      if (options.method == 'PUT') {
        return _json('{"connectorType":"SMS","provider":"TWILIO",'
            '"availableProviders":["DEV_PASSTHROUGH","MONTYMOBILE","TWILIO"],'
            '"config":{},"vaultPath":"secret/sms-connector","maskedSecret":"********",'
            '"active":true,"updatedBy":"me","updatedAt":"2026-08-09T12:00:00Z"}');
      }
      return _json(_connectorsJson);
    });
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
    api = ConnectorSettingsApi(dio);
    rateApi = DeliveryRateApi(dio);
    autoApprovalApi = AutoApprovalApi(dio);
  });

  Future<void> pump(WidgetTester tester) async {
    // Desktop height, not just width. The Phase 6 delivery-rate panel and ramp control made each
    // connector card taller, and on the default 600px-high test surface the second card falls off
    // the bottom — the widgets exist but are never laid out, so finders miss them. The approval
    // section now sits above both, which pushes them down again.
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      home: Scaffold(
        body: SettingsScreen(
          api: api,
          rateApi: rateApi,
          autoApprovalApi: autoApprovalApi,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders a card per connector', (WidgetTester tester) async {
    await pump(tester);

    expect(find.text('SMS'), findsOneWidget);
    expect(find.text('EMAIL'), findsOneWidget);
  });

  testWidgets('labels a dev provider as dev and never as live', (WidgetTester tester) async {
    await pump(tester);

    // The single most important thing on the page: whether this connector is touching the outside
    // world right now.
    expect(find.text('Dev provider'), findsOneWidget);
    expect(find.text('Live provider'), findsOneWidget); // EMAIL/SMTP is a real relay.
  });

  testWidgets('shows that a credential exists without ever showing one',
      (WidgetTester tester) async {
    await pump(tester);

    expect(find.text('********'), findsNWidgets(2));
    // The Vault path is fine to show - it is where the secret lives, not the secret.
    expect(find.textContaining('secret/sms-connector'), findsOneWidget);
  });

  testWidgets('offers only the providers the server sent', (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();

    // Three SMS providers, and nothing invented by the client.
    expect(find.text('Twilio'), findsOneWidget);
    expect(find.text('MontyMobile'), findsOneWidget);
    expect(find.text('Firebase (FCM)'), findsNothing);
  });

  testWidgets('a fixed-provider connector cannot be changed', (WidgetTester tester) async {
    await pump(tester);

    // EMAIL has one provider. Disabled rather than hidden, so a reader can still see what it is.
    final DropdownButtonFormField<String> email = tester.widgetList<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    ).last;
    expect(email.onChanged, isNull);
  });

  testWidgets('switching to a live vendor asks first and warns about credentials',
      (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Twilio').last);
    await tester.pumpAndSettle();

    expect(find.text('Switch SMS provider?'), findsOneWidget);
    expect(find.textContaining('real recipients through a paid provider'), findsOneWidget);
    // Nothing has been sent yet — confirmation gates the call, not the other way round.
    expect(adapter.requests.where((RequestOptions r) => r.method == 'PUT'), isEmpty);
  });

  testWidgets('cancelling the confirmation changes nothing', (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Twilio').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(adapter.requests.where((RequestOptions r) => r.method == 'PUT'), isEmpty);
  });

  testWidgets('confirming sends the switch', (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Twilio').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go live'));
    await tester.pumpAndSettle();

    final Iterable<RequestOptions> puts =
        adapter.requests.where((RequestOptions r) => r.method == 'PUT');
    expect(puts, hasLength(1));
    expect(puts.single.path, '/api/settings/connectors/SMS');
    expect((puts.single.data as Map<String, dynamic>)['provider'], 'TWILIO');
  });
}
