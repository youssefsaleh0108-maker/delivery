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
  String storeId = 's1',
  String storeName = 'Abu Hassan Mini Market',
  String? orderId,
  String? orderShortId,
  String? orderKind,
}) =>
    <String, dynamic>{
      'id': id,
      'storeId': storeId,
      'storeName': storeName,
      'customerName': customerName,
      'yourSide': side,
      'open': open,
      'lastMessageAt': '2026-09-13T08:00:00Z',
      'lastSequence': 1,
      'unread': unread,
      'lastMessagePreview': preview,
      'lastMessageSide': previewSide,
      'orderId': orderId,
      'orderShortId': orderShortId,
      'orderKind': orderKind,
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

  group('the order a conversation is about', () {
    Map<String, dynamic> about({
      required String shortId,
      String? customerName = 'Tania K.',
      String storeName = 'Al Fakhry Press',
      String preview = 'Are the cards ready?',
    }) =>
        _thread(
          customerName: customerName,
          storeName: storeName,
          preview: preview,
          previewSide: 'CUSTOMER',
          orderId: '$shortId-9abc-4def-8000-000000000001',
          orderShortId: shortId,
          orderKind: 'SERVICE',
        );

    /// A server holding [thread]: the inbox lists [inbox] (the thread alone by default), and the
    /// conversation answers with the thread as it is kept.
    _FakeChat serving(Map<String, dynamic> thread, {List<Map<String, dynamic>>? inbox}) =>
        _FakeChat((RequestOptions r) {
          if (r.path == '/api/chat/shop-threads/inbox') {
            return (status: 200, body: inbox ?? <Map<String, dynamic>>[thread]);
          }
          if (r.method == 'GET') {
            return (
              status: 200,
              body: <String, dynamic>{'thread': thread, 'messages': <dynamic>[], 'more': false}
            );
          }
          return (status: 200, body: <String, dynamic>{'updated': 0});
        });

    test('is named by its short id as it came, kept left to right, and not named without an order', () {
      final ShopThread labelled = ShopThread.fromJson(about(shortId: '5f0c2a9e'));

      expect(shopThreadOrderLabel(labelled, en), en.svcChatOrderLabel('\u20665f0c2a9e\u2069'));
      expect(shopThreadOrderLabel(labelled, ar), ar.svcChatOrderLabel('\u20665f0c2a9e\u2069'));
      expect(shopThreadOrderLabel(ShopThread.fromJson(_thread()), en), isNull);
    });

    testWidgets('an inbox row names the order, and a row without one names none',
        (WidgetTester tester) async {
      final Map<String, dynamic> labelled = about(shortId: '5f0c2a9e');
      final _FakeChat chat = serving(labelled, inbox: <Map<String, dynamic>>[
        labelled,
        _thread(id: 't2', customerName: 'Rami S.', preview: 'Thanks!', previewSide: 'CUSTOMER'),
      ]);

      await pump(tester, ShopInboxScreen(api: chat.api));

      expect(find.text(shopThreadOrderLabel(ShopThread.fromJson(labelled), en)!), findsOneWidget);
      expect(find.textContaining(en.svcChatOrderLabel('').trim()), findsOneWidget,
          reason: 'Only the conversation opened about an order says so.');
    });

    testWidgets("the conversation's header names the order under the customer",
        (WidgetTester tester) async {
      final Map<String, dynamic> labelled = about(shortId: '5f0c2a9e');

      await pump(tester,
          ShopThreadScreen(api: serving(labelled).api, thread: ShopThread.fromJson(labelled)));

      expect(find.text('Tania K.'), findsOneWidget);
      expect(find.text(shopThreadOrderLabel(ShopThread.fromJson(labelled), en)!), findsOneWidget);
    });

    testWidgets("a conversation about no order says nothing about orders in its header",
        (WidgetTester tester) async {
      await pump(tester,
          ShopThreadScreen(api: serving(_thread()).api, thread: ShopThread.fromJson(_thread())));

      expect(find.text('Tania K.'), findsOneWidget);
      expect(find.textContaining(en.svcChatOrderLabel('').trim()), findsNothing);
    });

    testWidgets('a long name, a second shop and the order fit a 320dp inbox row, and its header',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      const String longName = 'Jean-Pierre Dupont-Aznavourian';
      const String longShop = 'Al Fakhry Press and Copy Centre of Greater Mar Mikhael';
      final Map<String, dynamic> labelled =
          about(shortId: '5f0c2a9e', customerName: longName, storeName: longShop);
      final _FakeChat chat = serving(labelled, inbox: <Map<String, dynamic>>[
        labelled,
        _thread(id: 't2', storeId: 's2', preview: 'Thanks!', previewSide: 'CUSTOMER'),
      ]);
      final String label = shopThreadOrderLabel(ShopThread.fromJson(labelled), en)!;

      await pump(tester, ShopInboxScreen(api: chat.api));
      expect(find.text(longShop), findsOneWidget);
      expect(find.text(label), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text(longName));
      await tester.pumpAndSettle();
      expect(find.byType(ShopThreadScreen), findsOneWidget);
      expect(find.text(label), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('in Arabic, the row and the header name the order in Arabic, right to left',
        (WidgetTester tester) async {
      final Map<String, dynamic> labelled =
          about(shortId: '12345678', customerName: 'تانيا ك.', preview: 'هل البطاقات جاهزة؟');
      final String label = shopThreadOrderLabel(ShopThread.fromJson(labelled), ar)!;

      await pump(tester, ShopInboxScreen(api: serving(labelled).api), locale: const Locale('ar'));
      expect(find.text(label), findsOneWidget);
      expect(Directionality.of(tester.element(find.text(label))), TextDirection.rtl);

      await tester.tap(find.text('تانيا ك.'));
      await tester.pumpAndSettle();
      expect(find.byType(ShopThreadScreen), findsOneWidget);
      expect(find.text(label), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
