import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _inbox = '/api/chat/shop-threads/inbox';
const String _thread = '/api/chat/shop-threads/t1/messages';

/// App Notification's shop-thread endpoints, recording what was asked. [unread] is what the first
/// conversation reports; [failing] makes every answer a 503.
class _Chat {
  final List<RequestOptions> requests = <RequestOptions>[];
  int unread = 2;
  bool failing = false;

  late final ShopChatApi api = ShopChatApi(_dio());

  Dio _dio() {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        requests.add(options);
        final ({int status, Object? body}) answer = _answer(options);
        final Response<dynamic> response =
            Response<dynamic>(requestOptions: options, statusCode: answer.status, data: answer.body);
        if (answer.status >= 400) {
          handler.reject(DioException(
              requestOptions: options, type: DioExceptionType.badResponse, response: response));
        } else {
          handler.resolve(response);
        }
      },
    ));
    return dio;
  }

  ({int status, Object? body}) _answer(RequestOptions r) {
    if (failing) return (status: 503, body: null);
    if (r.path == _inbox) {
      return (
        status: 200,
        body: <dynamic>[_line('t1', 'Tania K.', unread), _line('t2', 'Hadi S.', 1)]
      );
    }
    if (r.path == _thread) {
      return (
        status: 200,
        body: <String, dynamic>{
          'thread': _line('t1', 'Tania K.', 0),
          'messages': <dynamic>[
            <String, dynamic>{
              'id': 'm1',
              'threadId': 't1',
              'storeId': 's1',
              'sequence': 1,
              'side': 'CUSTOMER',
              'mine': false,
              'text': 'Do you have halloumi?',
              'sentAt': '2026-09-13T08:00:00Z',
            },
          ],
          'more': false,
        }
      );
    }
    if (r.path == '/api/chat/shop-threads/t1/read') {
      return (status: 200, body: <String, dynamic>{'updated': 0});
    }
    return (status: 404, body: null);
  }

  int count(String path) => requests.where((RequestOptions r) => r.path == path).length;
}

Map<String, dynamic> _line(String id, String customer, int unread) => <String, dynamic>{
      'id': id,
      'storeId': 's1',
      'storeName': 'Abu Hassan Mini Market',
      'customerName': customer,
      'yourSide': 'SHOP',
      'open': true,
      'lastMessageAt': '2026-09-13T08:00:00Z',
      'lastSequence': 1,
      'unread': unread,
      'lastMessagePreview': 'Do you have halloumi?',
      'lastMessageSide': 'CUSTOMER',
    };

/// A socket that is connected and never says anything.
class _QuietSocket implements UserQueueSocket {
  @override
  final ValueNotifier<bool> connected = ValueNotifier<bool>(true);

  @override
  Stream<Map<String, dynamic>> subscribe(String destination) =>
      const Stream<Map<String, dynamic>>.empty();

  @override
  Future<void> close() async {}
}

/// The platform saying the app was hidden or shown — a browser tab switched away from, a phone put
/// in a pocket — through the same channel the engine uses.
Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
    (ByteData? _) {},
  );
  await _settleRequests(tester);
}

/// A pump that moves the clock. Dio finishes a request through timers, which a bare pump() — no
/// duration, so no time passes — never runs.
Future<void> _settleRequests(WidgetTester tester) => tester.pump(const Duration(milliseconds: 10));

/// A merchant's customer messages where nothing pushes them: the portal on the web holds no socket.
///
/// What is pinned is that a customer's words still reach the shop — a refresh button a mouse can
/// press, a gentle poll that stops while the tab is hidden or the list is covered — and that the
/// unread number on the way into the inbox is the inbox's own sum, kept through a failed read rather
/// than dropping to a zero the platform does not have.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: home,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('with no live feed, the inbox has a refresh button a mouse can press',
      (WidgetTester tester) async {
    final _Chat chat = _Chat();
    await pump(tester, ShopInboxScreen(api: chat.api, embedded: true));
    expect(chat.count(_inbox), 1);
    expect(find.text('2'), findsOneWidget);

    chat.unread = 5;
    await tester.tap(find.byTooltip(en.refresh));
    await tester.pumpAndSettle();

    expect(chat.count(_inbox), 2);
    expect(find.text('5'), findsOneWidget, reason: 'The list shows what the second read said.');
  });

  testWidgets('with no live feed, the inbox asks again every half-minute on screen, and never while hidden',
      (WidgetTester tester) async {
    final _Chat chat = _Chat();
    await pump(tester, ShopInboxScreen(api: chat.api, embedded: true));
    expect(chat.count(_inbox), 1);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(chat.count(_inbox), 2);

    await _lifecycle(tester, AppLifecycleState.hidden);
    await tester.pump(const Duration(minutes: 5));
    expect(chat.count(_inbox), 2, reason: 'Nobody is looking at a hidden tab.');

    await _lifecycle(tester, AppLifecycleState.resumed);
    expect(chat.count(_inbox), 3, reason: 'Coming back asks at once, not half a minute later.');
  });

  testWidgets('the inbox waits while a conversation is open over it, and asks again once uncovered',
      (WidgetTester tester) async {
    final _Chat chat = _Chat();
    await pump(tester, ShopInboxScreen(api: chat.api));
    await tester.tap(find.text('Tania K.'));
    await tester.pumpAndSettle();
    expect(find.byType(ShopThreadScreen), findsOneWidget);
    final int before = chat.count(_inbox);

    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    expect(chat.count(_inbox), before, reason: 'The list is covered; nobody can see it change.');
    expect(chat.count(_thread), greaterThan(1),
        reason: 'The open conversation keeps itself current instead.');

    Navigator.of(tester.element(find.byType(ShopThreadScreen))).pop();
    await tester.pumpAndSettle();

    expect(chat.count(_inbox), before + 1);
  });

  testWidgets('with a live feed there is neither a refresh button nor a poll: the feed does that job',
      (WidgetTester tester) async {
    final _Chat chat = _Chat();
    await pump(tester, ShopInboxScreen(api: chat.api, socket: _QuietSocket()));

    expect(find.byTooltip(en.refresh), findsNothing);
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    expect(chat.count(_inbox), 1);
  });

  testWidgets(
      'with no live feed, a conversation has a refresh button, catches up while on screen, and says when refreshing failed',
      (WidgetTester tester) async {
    final _Chat chat = _Chat();
    await pump(tester, ShopThreadScreen(api: chat.api, thread: ShopThread.fromJson(_line('t1', 'Tania K.', 0))));
    expect(chat.count(_thread), 1);
    expect(find.text('Do you have halloumi?'), findsOneWidget);

    await tester.tap(find.byTooltip(en.refresh));
    await tester.pumpAndSettle();
    expect(chat.count(_thread), 2);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(chat.count(_thread), 3);

    chat.failing = true;
    await tester.tap(find.byTooltip(en.refresh));
    await tester.pumpAndSettle();
    expect(find.text(en.chatShopCouldNotLoad), findsOneWidget,
        reason: 'Somebody who pressed refresh should learn it did not work.');
    expect(find.text('Do you have halloumi?'), findsOneWidget);
  });

  testWidgets("the unread number is the inbox's own sum, survives a failed read, and is asked only on screen",
      (WidgetTester tester) async {
    final _Chat chat = _Chat();
    await tester.pumpWidget(const SizedBox());
    final ShopUnreadCount unread = ShopUnreadCount(api: chat.api)..start();
    await _settleRequests(tester);
    expect(unread.value, 3);

    chat.failing = true;
    await tester.pump(ShopUnreadCount.defaultInterval);
    await _settleRequests(tester);
    expect(chat.count(_inbox), 2);
    expect(unread.value, 3, reason: 'A failed read is not "nothing unread".');

    await _lifecycle(tester, AppLifecycleState.hidden);
    await tester.pump(const Duration(minutes: 10));
    expect(chat.count(_inbox), 2);

    chat
      ..failing = false
      ..unread = 0;
    await _lifecycle(tester, AppLifecycleState.resumed);
    await _settleRequests(tester);
    expect(chat.count(_inbox), 3);
    expect(unread.value, 1);

    unread.dispose();
  });

  testWidgets("Settings' messages row carries the unread number, and none while it is unknown or zero",
      (WidgetTester tester) async {
    final ValueNotifier<int?> unread = ValueNotifier<int?>(null);
    Finder saying(int count) => find.byWidgetPredicate(
        (Widget w) => w is Semantics && w.properties.label == en.chatShopUnreadCount(count));

    await pump(
        tester,
        MerchantSettingsScreen(
          locale: LocaleController(read: () async => 'en', write: (String _) async {}),
          accountName: 'Abu Hassan',
          onShopMessages: () {},
          shopMessagesUnread: unread,
        ));
    expect(saying(3), findsNothing);

    unread.value = 3;
    await tester.pump();
    expect(saying(3), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    unread.value = 0;
    await tester.pump();
    expect(find.text('0'), findsNothing, reason: 'Nothing unread draws no number.');
  });
}
