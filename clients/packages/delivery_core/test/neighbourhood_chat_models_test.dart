import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Neighbourhood rooms and shop threads as the app reads them, and the refusals the screens turn
/// into sentences instead of failures.
void main() {
  /// A server that answers every request with [status] and [body], recording what it was asked.
  Dio answering(int status, Object? body,
      {Map<String, List<String>> headers = const <String, List<String>>{},
      List<RequestOptions>? asked}) {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        asked?.add(options);
        final Response<dynamic> response = Response<dynamic>(
          requestOptions: options,
          statusCode: status,
          data: body,
          headers: Headers.fromMap(headers),
        );
        if (status >= 400) {
          handler.reject(DioException(
              requestOptions: options, type: DioExceptionType.badResponse, response: response));
        } else {
          handler.resolve(response);
        }
      },
    ));
    return dio;
  }

  group('a room message', () {
    test('reads an author as a handle and a name, and a removal as a tombstone', () {
      final RoomMessage said = RoomMessage.fromJson(<String, dynamic>{
        'id': 'm1',
        'roomId': 'r1',
        'sequence': 7,
        'authorHandle': 'h-tania',
        'authorName': 'Tania K.',
        'mine': false,
        'kind': 'TEXT',
        'text': 'Anyone know a good knefeh place?',
        'sentAt': '2026-09-13T07:02:00Z',
      });
      final RoomMessage removed = RoomMessage.fromJson(<String, dynamic>{
        'id': 'm2',
        'roomId': 'r1',
        'sequence': 8,
        'authorHandle': 'h-hadi',
        'authorName': null,
        'mine': false,
        'kind': 'HIDDEN',
        'text': null,
      });

      expect(said.isHidden, isFalse);
      expect(said.authorName, 'Tania K.');
      expect(said.sentAt, isNotNull);
      expect(removed.isHidden, isTrue);
      expect(removed.text, isNull);
    });

    test('a room reads its mute and its move date only when the server sends them', () {
      final NeighbourhoodRoom room = NeighbourhoodRoom.fromJson(<String, dynamic>{
        'id': 'r1',
        'zoneId': 'z1',
        'name': 'Mar Mikhael',
        'memberCount': 12,
        'lastSequence': 40,
        'yourHandle': 'h-me',
        'mutedUntil': '2099-01-01T00:00:00Z',
      });

      expect(room.memberCount, 12);
      expect(room.isMutedAt(DateTime.now()), isTrue);
      expect(room.moveBlockedUntil, isNull);
      expect(room.withMutedUntil(null).isMutedAt(DateTime.now()), isFalse);
    });

    test('a room reads whether its reader may post there', () {
      NeighbourhoodRoom read(String? posting) => NeighbourhoodRoom.fromJson(<String, dynamic>{
            'id': 'r1',
            'zoneId': 'z1',
            'name': 'Mar Mikhael',
            'memberCount': 3,
            'lastSequence': 0,
            'yourHandle': 'h',
            if (posting != null) 'posting': posting,
          });

      expect(read('OPEN').posting, RoomPosting.open);
      expect(read('NEEDS_DELIVERY').posting, RoomPosting.needsDelivery);
      expect(read('UNVERIFIED').posting, RoomPosting.unverified);
      expect(read(null).posting, RoomPosting.open,
          reason: 'A server that says nothing still refuses what it refuses; the refusal tells.');
      expect(read('NEEDS_DELIVERY').withMutedUntil(null).posting, RoomPosting.needsDelivery,
          reason: 'Clearing a mute must not quietly reopen a composer the server locked.');
      expect(read('OPEN').withPosting(RoomPosting.needsDelivery).posting, RoomPosting.needsDelivery);
    });
  });

  group('the room client', () {
    test('turns "your address has no area" into a reason the screen can act on', () async {
      final NeighbourhoodChatApi api = NeighbourhoodChatApi(answering(404,
          <String, dynamic>{'title': 'No neighbourhood', 'reason': 'NO_ZONE'}));

      expect(
        () => api.myRoom(),
        throwsA(isA<NoNeighbourhoodException>()
            .having((NoNeighbourhoodException e) => e.reason, 'reason', NoNeighbourhoodReason.noZone)),
      );
    });

    test('sends the area of the address, never a room', () async {
      final List<RequestOptions> asked = <RequestOptions>[];
      final NeighbourhoodChatApi api = NeighbourhoodChatApi(answering(200, <String, dynamic>{
        'id': 'r1',
        'zoneId': 'z1',
        'name': 'Mar Mikhael',
        'memberCount': 1,
        'lastSequence': 0,
        'yourHandle': 'h',
      }, asked: asked));

      await api.myRoom(zoneId: 'z1');

      expect(asked.single.path, '/api/chat/rooms/mine');
      expect(asked.single.queryParameters, <String, dynamic>{'zoneId': 'z1'});
    });

    test('a muted post arrives as a mute with its end, and a fast one as a wait', () async {
      final NeighbourhoodChatApi muted = NeighbourhoodChatApi(answering(403,
          <String, dynamic>{'title': 'Muted', 'mutedUntil': '2026-09-20T10:00:00Z'}));
      final NeighbourhoodChatApi hurried = NeighbourhoodChatApi(answering(429,
          <String, dynamic>{'title': 'Slow down'},
          headers: <String, List<String>>{
            'retry-after': <String>['42']
          }));

      await expectLater(
        muted.send('r1', 'hello'),
        throwsA(isA<RoomMutedException>()
            .having((RoomMutedException e) => e.mutedUntil, 'until', isNotNull)),
      );
      await expectLater(
        hurried.send('r1', 'hello'),
        throwsA(isA<ChatRateLimitedException>().having(
            (ChatRateLimitedException e) => e.retryAfter, 'retry', const Duration(seconds: 42))),
      );
    });

    test('a post refused for want of a delivery in the area arrives as that, not as a mute', () async {
      final NeighbourhoodChatApi api = NeighbourhoodChatApi(answering(403,
          <String, dynamic>{'title': 'Posting locked', 'reason': 'NEEDS_DELIVERY'}));

      await expectLater(api.send('r1', 'hello'), throwsA(isA<RoomPostingLockedException>()));
    });

    test('any other refusal stays the original error', () async {
      final NeighbourhoodChatApi api = NeighbourhoodChatApi(answering(404, <String, dynamic>{}));

      await expectLater(api.send('r1', 'hello'), throwsA(isA<DioException>()));
    });
  });

  group('a shop thread', () {
    test('reads which side the caller is on, and the inbox preview', () {
      final ShopThread thread = ShopThread.fromJson(<String, dynamic>{
        'id': 't1',
        'storeId': 's1',
        'storeName': 'Abu Hassan Mini Market',
        'customerName': 'Tania K.',
        'yourSide': 'SHOP',
        'open': true,
        'lastSequence': 3,
        'unread': 2,
        'lastMessagePreview': 'Can you set one aside?',
        'lastMessageSide': 'CUSTOMER',
      });

      expect(thread.yourSide, ShopThreadSide.shop);
      expect(thread.unread, 2);
      expect(thread.lastMessageSide, ShopThreadSide.customer);
    });

    test('a moderation line reads its reasons and mute', () {
      final ReportedRoomMessage line = ReportedRoomMessage.fromJson(<String, dynamic>{
        'messageId': 'm1',
        'roomId': 'r1',
        'roomName': 'Mar Mikhael',
        'authorHandle': 'h',
        'authorName': 'Hadi S.',
        'text': 'call me on 70 123 456',
        'hidden': false,
        'reportCount': 2,
        'reasons': <String>['PERSONAL_INFO', 'SPAM'],
        'authorMutedUntil': '2099-01-01T00:00:00Z',
      });

      expect(line.reasons, <RoomReportReason>[RoomReportReason.personalInfo, RoomReportReason.spam]);
      expect(line.authorMutedUntil, isNotNull);
    });
  });
}
