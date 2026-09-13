import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/backoffice/moderation_screen.dart';
import 'package:delivery_portal/src/portal_shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Answer = ({int status, Object? body});

/// The Backoffice's neighbourhood chat moderation queue.
///
/// Pinned: every reported message shows what a moderator needs to decide (the room, the words even
/// once removed, why and how often it was reported, whether the author is muted); no decision is sent
/// without a reason the audit trail can keep; a mute is one of three bounded lengths sent as hours;
/// and the queue refreshes after each decision. And the page is on the Backoffice rail — and only
/// there — with the shop inbox on the merchant rail.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  late List<RequestOptions> requests;

  Map<String, dynamic> line({bool hidden = false, String? mutedUntil}) => <String, dynamic>{
        'messageId': 'm1',
        'roomId': 'r1',
        'roomName': 'Mar Mikhael',
        'authorHandle': 'h-hadi',
        'authorName': 'Hadi S.',
        'text': 'call me on 70 123 456',
        'sentAt': '2026-09-13T07:00:00Z',
        'hidden': hidden,
        'reportCount': 2,
        'reasons': <String>['PERSONAL_INFO', 'SPAM'],
        'firstReportedAt': '2026-09-13T07:05:00Z',
        'lastReportedAt': '2026-09-13T07:20:00Z',
        'authorMutedUntil': mutedUntil,
      };

  Dio serve(List<List<Map<String, dynamic>>> queues) {
    requests = <RequestOptions>[];
    int served = 0;
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        requests.add(options);
        final _Answer answer;
        if (options.method == 'GET' && options.path == '/api/chat/backoffice/moderation/reports') {
          final List<Map<String, dynamic>> queue = queues[served < queues.length ? served : queues.length - 1];
          served++;
          answer = (status: 200, body: queue);
        } else if (options.path.endsWith('/mute-author')) {
          answer = (status: 200, body: <String, dynamic>{'messageId': 'm1', 'mutedUntil': '2026-09-20T07:00:00Z'});
        } else if (options.path.endsWith('/hide')) {
          answer = (status: 200, body: <String, dynamic>{'messageId': 'm1', 'hiddenAt': '2026-09-13T08:00:00Z'});
        } else {
          answer = (status: 204, body: null);
        }
        handler.resolve(Response<dynamic>(requestOptions: options, statusCode: answer.status, data: answer.body));
      },
    ));
    return dio;
  }

  Iterable<RequestOptions> asked(String method, String path) =>
      requests.where((RequestOptions r) => r.method == method && r.path == path);

  Future<void> pump(WidgetTester tester, Dio dio) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: ModerationScreen(api: ChatModerationApi(dio)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows what a moderator decides on: room, words, reasons, how many reported',
      (WidgetTester tester) async {
    await pump(tester, serve(<List<Map<String, dynamic>>>[
      <Map<String, dynamic>>[line()]
    ]));

    expect(find.text(en.chatRoomTitle('Mar Mikhael')), findsOneWidget);
    expect(find.text('call me on 70 123 456'), findsOneWidget);
    expect(find.text(en.chatModerationReports(2)), findsOneWidget);
    expect(find.text(en.chatRoomReasonPersonalInfo), findsOneWidget);
    expect(find.text(en.chatRoomReasonSpam), findsOneWidget);
    expect(find.textContaining('Hadi S.'), findsOneWidget);
  });

  testWidgets('hiding refuses to send without a reason, then sends it and refreshes the queue',
      (WidgetTester tester) async {
    await pump(tester, serve(<List<Map<String, dynamic>>>[
      <Map<String, dynamic>>[line()],
      <Map<String, dynamic>>[],
    ]));

    await tester.tap(find.widgetWithText(FilledButton, en.chatModerationHide));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.chatModerationConfirm));
    await tester.pumpAndSettle();

    expect(find.text(en.chatModerationReasonTooShort), findsOneWidget);
    expect(asked('POST', '/api/chat/backoffice/moderation/messages/m1/hide'), isEmpty);

    await tester.enterText(find.byType(TextField), '  posted a phone number ');
    await tester.tap(find.text(en.chatModerationConfirm));
    await tester.pumpAndSettle();

    expect(
        (asked('POST', '/api/chat/backoffice/moderation/messages/m1/hide').single.data
            as Map<String, dynamic>)['reason'],
        'posted a phone number');
    expect(asked('GET', '/api/chat/backoffice/moderation/reports'), hasLength(2));
    expect(find.text(en.chatModerationEmpty), findsOneWidget);
  });

  testWidgets('a week-long mute is sent as 168 hours, with its reason', (WidgetTester tester) async {
    await pump(tester, serve(<List<Map<String, dynamic>>>[
      <Map<String, dynamic>>[line()]
    ]));

    await tester.tap(find.widgetWithText(OutlinedButton, en.chatModerationMute));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.chatModerationMute7d));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'repeated spam');
    await tester.tap(find.text(en.chatModerationConfirm));
    await tester.pumpAndSettle();

    final Map<String, dynamic> body =
        asked('POST', '/api/chat/backoffice/moderation/messages/m1/mute-author').single.data
            as Map<String, dynamic>;
    expect(body['hours'], 168);
    expect(body['reason'], 'repeated spam');
  });

  testWidgets('a removed message is marked removed and offers no hide; a muted author offers unmute',
      (WidgetTester tester) async {
    await pump(tester, serve(<List<Map<String, dynamic>>>[
      <Map<String, dynamic>>[line(hidden: true, mutedUntil: '2099-01-01T00:00:00Z')]
    ]));

    expect(find.text(en.chatModerationRemoved), findsOneWidget);
    expect(find.widgetWithText(FilledButton, en.chatModerationHide), findsNothing);
    expect(find.widgetWithText(OutlinedButton, en.chatModerationMute), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, en.chatModerationUnmute));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'appeal upheld');
    await tester.tap(find.text(en.chatModerationConfirm));
    await tester.pumpAndSettle();

    expect(asked('POST', '/api/chat/backoffice/moderation/messages/m1/unmute-author'), hasLength(1));
  });

  test('the queue is on the Backoffice rail, and the shop inbox on the merchant rail', () {
    bool offers(PortalArea area, String label) =>
        area.destinations.any((PortalDestination d) => d.label(en) == label);

    expect(offers(PortalArea.backoffice_, en.chatModerationTitle), isTrue);
    expect(offers(PortalArea.merchant_, en.chatModerationTitle), isFalse);
    expect(offers(PortalArea.carrier_, en.chatModerationTitle), isFalse);
    expect(offers(PortalArea.merchant_, en.chatShopInboxTitle), isTrue);
  });
}
