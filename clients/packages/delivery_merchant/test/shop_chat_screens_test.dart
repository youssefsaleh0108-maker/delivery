import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for App Notification's shop-thread endpoints: each request is answered by [route] and
/// recorded, so a test can say both what the screen showed and what it asked for.
class _FakeChat {
  _FakeChat(this.route);

  final ({int status, Object? body}) Function(RequestOptions request) route;
  final List<RequestOptions> requests = <RequestOptions>[];

  late final ShopChatApi api = ShopChatApi(_dio());

  Dio _dio() {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        requests.add(options);
        final ({int status, Object? body}) answer = route(options);
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

  Iterable<RequestOptions> sent(String method, String path) =>
      requests.where((RequestOptions r) => r.method == method && r.path == path);
}

Map<String, dynamic> _thread({
  String id = 't1',
  String side = 'SHOP',
  bool open = true,
  String? customerName = 'Tania K.',
  int unread = 0,
  String? preview,
  String? previewSide,
}) =>
    <String, dynamic>{
      'id': id,
      'storeId': 's1',
      'storeName': 'Abu Hassan Mini Market',
      'customerName': customerName,
      'yourSide': side,
      'open': open,
      'lastMessageAt': '2026-09-13T08:00:00Z',
      'lastSequence': 1,
      'unread': unread,
      'lastMessagePreview': preview,
      'lastMessageSide': previewSide,
    };

Map<String, dynamic> _message(int sequence, String side, {required bool mine, required String text}) =>
    <String, dynamic>{
      'id': 'm$sequence',
      'threadId': 't1',
      'storeId': 's1',
      'sequence': sequence,
      'side': side,
      'mine': mine,
      'text': text,
      'sentAt': '2026-09-13T08:00:00Z',
    };

/// A customer's conversation with a shop, from both ends: the shop's inbox and thread, and the
/// customer's thread opened from a shop page. What is pinned is what each side may do — the shop
/// replies but cannot revive a quiet thread, the customer can — and that the words go where they
/// should: to the thread the screen holds, with an idempotency key, never re-sent as something else.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  Future<void> pump(WidgetTester tester, Widget home, {Locale locale = const Locale('en')}) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: home,
    ));
    await tester.pumpAndSettle();
  }

  group("the shop's inbox", () {
    testWidgets('lists each conversation with its customer, its last line and what is unread',
        (WidgetTester tester) async {
      final _FakeChat chat = _FakeChat((_) => (
            status: 200,
            body: <dynamic>[
              _thread(unread: 2, preview: 'Can you set one aside?', previewSide: 'CUSTOMER'),
              _thread(
                  id: 't2',
                  customerName: null,
                  open: false,
                  preview: 'Yes, fresh today',
                  previewSide: 'SHOP'),
            ]
          ));

      await pump(tester, ShopInboxScreen(api: chat.api));

      expect(find.text('Tania K.'), findsOneWidget);
      expect(find.text('Can you set one aside?'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text(en.chatShopCustomer), findsOneWidget,
          reason: 'A customer whose account has no name is "Customer" — never an id or a phone.');
      expect(find.text(en.chatShopYouPrefix('Yes, fresh today')), findsOneWidget);
      expect(find.text(en.chatShopQuietBadge), findsOneWidget);
      expect(chat.sent('GET', '/api/chat/shop-threads/inbox'), hasLength(1));
    });

    testWidgets('with nothing in it, says so and says how customers reach the shop',
        (WidgetTester tester) async {
      final _FakeChat chat = _FakeChat((_) => (status: 200, body: <dynamic>[]));

      await pump(tester, ShopInboxScreen(api: chat.api));

      expect(find.text(en.chatShopInboxEmpty), findsOneWidget);
      expect(find.text(en.chatShopInboxEmptySub), findsOneWidget);
    });

    testWidgets('that fails to load offers to try again, and trying again asks again',
        (WidgetTester tester) async {
      final _FakeChat chat = _FakeChat((_) => (status: 500, body: null));

      await pump(tester, ShopInboxScreen(api: chat.api));
      expect(find.text(en.chatShopInboxCouldNotLoad), findsOneWidget);

      await tester.tap(find.text(en.tryAgain));
      await tester.pumpAndSettle();
      expect(chat.sent('GET', '/api/chat/shop-threads/inbox'), hasLength(2));
    });
  });

  group('a conversation, from the shop', () {
    testWidgets("opens from the inbox, marks the customer's words read, and replies as the shop",
        (WidgetTester tester) async {
      final _FakeChat chat = _FakeChat((RequestOptions r) {
        if (r.path == '/api/chat/shop-threads/inbox') {
          return (
            status: 200,
            body: <dynamic>[
              _thread(unread: 1, preview: 'Do you have halloumi?', previewSide: 'CUSTOMER')
            ]
          );
        }
        if (r.method == 'GET' && r.path == '/api/chat/shop-threads/t1/messages') {
          return (
            status: 200,
            body: <String, dynamic>{
              'thread': _thread(),
              'messages': <dynamic>[
                _message(1, 'CUSTOMER', mine: false, text: 'Do you have halloumi?')
              ],
              'more': false,
            }
          );
        }
        if (r.path == '/api/chat/shop-threads/t1/read') {
          return (status: 200, body: <String, dynamic>{'updated': 1});
        }
        if (r.method == 'POST' && r.path == '/api/chat/shop-threads/t1/messages') {
          return (
            status: 201,
            body: _message(2, 'SHOP', mine: true, text: (r.data as Map<String, dynamic>)['text'] as String)
          );
        }
        return (status: 404, body: null);
      });

      await pump(tester, ShopInboxScreen(api: chat.api));
      await tester.tap(find.text('Tania K.'));
      await tester.pumpAndSettle();

      expect(find.byType(ShopThreadScreen), findsOneWidget);
      expect(find.text('Do you have halloumi?'), findsOneWidget);
      expect(
          (chat.sent('POST', '/api/chat/shop-threads/t1/read').single.data
              as Map<String, dynamic>)['upToSequence'],
          1);

      await tester.enterText(find.byType(TextField), 'Yes, fresh today');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      final Map<String, dynamic> body =
          chat.sent('POST', '/api/chat/shop-threads/t1/messages').single.data as Map<String, dynamic>;
      expect(body['text'], 'Yes, fresh today');
      expect(body['clientMessageId'], isNotNull,
          reason: 'A retry after a lost response must not post twice.');
      expect(find.text('Yes, fresh today'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Yes, fresh today')).dx,
          greaterThan(tester.getTopLeft(find.text('Do you have halloumi?')).dx),
          reason: "The shop's own words sit against the end, the customer's against the start.");
    });

    testWidgets('once the conversation has gone quiet, says why the shop cannot write — and offers no way round it',
        (WidgetTester tester) async {
      final _FakeChat chat = _FakeChat((RequestOptions r) => (
            status: 200,
            body: <String, dynamic>{'thread': _thread(open: false), 'messages': <dynamic>[], 'more': false}
          ));

      await pump(tester,
          ShopThreadScreen(api: chat.api, thread: ShopThread.fromJson(_thread(open: false))));

      expect(find.text(en.chatShopQuietMerchant), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text(en.chatShopReopen), findsNothing);
    });
  });

  group('a conversation, from the customer', () {
    testWidgets('opens the thread with the shop, and reopens it when it has gone quiet',
        (WidgetTester tester) async {
      int opens = 0;
      final _FakeChat chat = _FakeChat((RequestOptions r) {
        if (r.method == 'POST' && r.path == '/api/chat/stores/s1/thread') {
          opens++;
          return (status: 200, body: _thread(side: 'CUSTOMER'));
        }
        if (r.method == 'GET' && r.path == '/api/chat/shop-threads/t1/messages') {
          return (
            status: 200,
            body: <String, dynamic>{'thread': _thread(side: 'CUSTOMER'), 'messages': <dynamic>[], 'more': false}
          );
        }
        if (r.method == 'POST' && r.path == '/api/chat/shop-threads/t1/messages') {
          return (
            status: 409,
            body: <String, dynamic>{'title': 'Conversation closed', 'closedAt': '2026-09-13T08:00:00Z'}
          );
        }
        return (status: 404, body: null);
      });

      await pump(
          tester,
          ShopThreadScreen(
            api: chat.api,
            open: () => chat.api.openWithStore('s1'),
            title: 'Abu Hassan Mini Market',
          ));

      expect(opens, 1);
      expect(find.text('Abu Hassan Mini Market'), findsOneWidget);
      expect(find.text(en.chatShopEmptyCustomer), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Are you open on Sunday?');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(find.text(en.chatShopQuietCustomer), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text(en.chatShopReopen));
      await tester.pumpAndSettle();

      expect(opens, 2, reason: 'Reopen asks the server to open the thread again.');
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('sending too fast is explained rather than failing silently',
        (WidgetTester tester) async {
      final _FakeChat chat = _FakeChat((RequestOptions r) {
        if (r.method == 'GET') {
          return (
            status: 200,
            body: <String, dynamic>{'thread': _thread(side: 'CUSTOMER'), 'messages': <dynamic>[], 'more': false}
          );
        }
        return (status: 429, body: <String, dynamic>{'title': 'Slow down', 'retryAfterSeconds': 60});
      });

      await pump(tester,
          ShopThreadScreen(api: chat.api, thread: ShopThread.fromJson(_thread(side: 'CUSTOMER'))));
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(find.text(en.chatSlowDown), findsOneWidget);
    });
  });

  testWidgets('in Arabic, the conversation reads Arabic and runs right to left',
      (WidgetTester tester) async {
    final _FakeChat chat = _FakeChat((RequestOptions r) => (
          status: 200,
          body: <String, dynamic>{
            'thread': _thread(),
            'messages': <dynamic>[
              _message(1, 'CUSTOMER', mine: false, text: 'عندكم حلوم؟'),
              _message(2, 'SHOP', mine: true, text: 'نعم، طازج اليوم'),
            ],
            'more': false,
          }
        ));

    await pump(tester, ShopThreadScreen(api: chat.api, thread: ShopThread.fromJson(_thread())),
        locale: const Locale('ar'));

    expect(find.text(ar.chatShopHintMerchant), findsOneWidget);
    expect(tester.getTopLeft(find.text('نعم، طازج اليوم')).dx,
        lessThan(tester.getTopLeft(find.text('عندكم حلوم؟')).dx),
        reason: "In Arabic the shop's own words sit against the left.");
    expect(tester.takeException(), isNull);
  });
}
