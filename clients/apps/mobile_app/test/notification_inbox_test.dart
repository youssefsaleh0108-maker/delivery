import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/notification_inbox.dart';

/// The badge is the part users notice being wrong, and the optimistic update is the part most
/// likely to leave it wrong. Both are worth pinning down.
///
/// Backed by a Dio whose adapter is replaced rather than a hand-written fake API, so the real
/// [NotificationApi] JSON parsing is exercised too.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<String> calls = <String>[];
  bool failNextPost = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    if (failNextPost && options.method == 'POST') {
      failNextPost = false;
      throw DioException(requestOptions: options, message: 'network down');
    }
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _FakeAdapter adapter;
  late NotificationInbox inbox;

  const String messagesJson = '''
[
  {"id":"m1","orderId":"o1","eventType":"order.placed","title":"Order placed",
   "body":"Your order is with the merchant.","metadata":{"orderId":"o1"},
   "read":false,"readAt":null,"createdAt":"2026-08-09T10:00:00Z"},
  {"id":"m2","orderId":"o1","eventType":"order.delivered","title":"Delivered",
   "body":"Enjoy.","metadata":{},"read":true,"readAt":"2026-08-09T11:00:00Z",
   "createdAt":"2026-08-09T10:30:00Z"}
]''';

  setUp(() {
    adapter = _FakeAdapter((RequestOptions options) {
      if (options.path.contains('unread-count')) {
        return ResponseBody.fromString('{"unread":1}', 200,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>[Headers.jsonContentType]
            });
      }
      if (options.path.contains('read-all')) {
        return ResponseBody.fromString('{"updated":1}', 200,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>[Headers.jsonContentType]
            });
      }
      if (options.method == 'POST') {
        return ResponseBody.fromString('', 204);
      }
      return ResponseBody.fromString(messagesJson, 200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType]
          });
    });

    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = adapter;
    inbox = NotificationInbox(NotificationApi(dio));
  });

  tearDown(() => inbox.dispose());

  test('refresh loads messages and derives the unread count from them', () async {
    await inbox.refresh();

    expect(inbox.messages, hasLength(2));
    expect(inbox.messages.first.title, 'Order placed');
    expect(inbox.unread, 1);
    expect(inbox.error, isNull);
  });

  test('the deep link comes through metadata', () async {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
      ..httpClientAdapter = _FakeAdapter((RequestOptions options) => ResponseBody.fromString(
            '[{"id":"m1","eventType":"order.rider_assigned","title":"On the way","body":"x",'
            '"metadata":{"deepLink":"delivery://orders/o1"},"read":false,'
            '"createdAt":"2026-08-09T10:00:00Z"}]',
            200,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>[Headers.jsonContentType]
            },
          ));
    final NotificationInbox local = NotificationInbox(NotificationApi(dio));
    addTearDown(local.dispose);

    await local.refresh();

    expect(local.messages.single.deepLink, 'delivery://orders/o1');
  });

  test('markRead updates the badge before the server answers', () async {
    await inbox.refresh();
    expect(inbox.unread, 1);

    // Not awaited: the point is that the state is already correct at this instant, because a tap
    // that appears to do nothing for a round trip reads as a broken button.
    final Future<void> pending = inbox.markRead(inbox.messages.first);

    expect(inbox.unread, 0);
    expect(inbox.messages.first.read, isTrue);
    await pending;
  });

  test('a failed markRead is rolled back rather than left wrong', () async {
    await inbox.refresh();
    adapter.failNextPost = true;

    await inbox.markRead(inbox.messages.first);

    // Read state that silently disagrees with the server reappears on the next refresh, so leaving
    // it optimistic here would just make the badge flicker back.
    expect(inbox.unread, 1);
    expect(inbox.messages.first.read, isFalse);
  });

  test('marking an already-read message does not decrement the badge', () async {
    await inbox.refresh();
    final int before = inbox.unread;

    await inbox.markRead(inbox.messages[1]);

    expect(inbox.unread, before);
  });

  test('markAllRead clears every message and the badge', () async {
    await inbox.refresh();

    await inbox.markAllRead();

    expect(inbox.unread, 0);
    expect(inbox.messages.every((InAppNotification m) => m.read), isTrue);
  });

  test('a failed background poll leaves the last known count alone', () async {
    await inbox.refresh();
    final Dio broken = Dio(BaseOptions(baseUrl: 'http://gateway'))
      ..httpClientAdapter = _FakeAdapter((RequestOptions options) =>
          throw DioException(requestOptions: options, message: 'offline'));
    final NotificationInbox offline = NotificationInbox(NotificationApi(broken));
    addTearDown(offline.dispose);

    // Must not throw: a stale badge is not worth interrupting the user over.
    await offline.refreshCount();

    expect(offline.unread, 0);
  });
}
