import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rating a shop after an order, against a recording adapter.
///
/// Pinned against product-service's `StoreController`: the verb, path and body `POST
/// /api/stores/{id}/reviews` takes (`ReviewRequest`: orderId, rating 1–5, optional comment) and the
/// `ReviewResponse` it answers with; that a rating nobody could give never leaves the phone; that the
/// server's 404 for an order it will not take a review of reaches the screen instead of being
/// swallowed; and that `GET /api/stores/reviews/order/{orderId}`'s 204 reads as "not reviewed" while
/// an answer that is not a review is never mistaken for one.
class _Server implements HttpClientAdapter {
  _Server(this.answer);

  /// The status and JSON body each request is answered with; a null body is an empty one.
  final (int, Object?) Function(RequestOptions options) answer;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    final (int status, Object? body) = answer(options);
    if (body == null) return ResponseBody.fromString('', status);
    return ResponseBody.fromString(jsonEncode(body), status, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

({StoreApi api, _Server server}) _stores((int, Object?) Function(RequestOptions options) answer) {
  final _Server server = _Server(answer);
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway.test'))..httpClientAdapter = server;
  return (api: StoreApi(dio), server: server);
}

/// A review as `StoreController.toReview` writes it for its author.
Map<String, dynamic> _stored({int rating = 5, String? comment = 'Crisp cards, on time'}) =>
    <String, dynamic>{
      'id': 'review-1',
      'storeId': 'press-1',
      'orderId': 'order-1',
      'rating': rating,
      'comment': comment,
      'createdAt': '2026-09-14T10:00:00Z',
      'mine': true,
    };

void main() {
  group('StoreApi.submitReview', () {
    test('posts the order, the stars and the trimmed comment, and reads the review stored', () async {
      final s = _stores((RequestOptions o) => (201, _stored()));

      final StoreReview review = await s.api
          .submitReview('press-1', orderId: 'order-1', rating: 5, comment: '  Crisp cards, on time ');

      final RequestOptions sent = s.server.requests.single;
      expect(sent.method, 'POST');
      expect(sent.path, '/api/stores/press-1/reviews');
      expect(sent.data, <String, dynamic>{
        'orderId': 'order-1',
        'rating': 5,
        'comment': 'Crisp cards, on time',
      });
      expect(review.id, 'review-1');
      expect(review.orderId, 'order-1');
      expect(review.rating, 5);
      expect(review.mine, isTrue);
    });

    test('a blank comment is not sent', () async {
      final s = _stores((RequestOptions o) => (201, _stored(rating: 4, comment: null)));

      await s.api.submitReview('press-1', orderId: 'order-1', rating: 4, comment: '   ');
      await s.api.submitReview('press-1', orderId: 'order-1', rating: 4);

      for (final RequestOptions sent in s.server.requests) {
        expect(sent.data, <String, dynamic>{'orderId': 'order-1', 'rating': 4});
      }
    });

    test('stars nobody could give are refused before any request', () async {
      final s = _stores((RequestOptions o) => (201, _stored()));

      expect(() => s.api.submitReview('press-1', orderId: 'order-1', rating: 0), throwsRangeError);
      expect(() => s.api.submitReview('press-1', orderId: 'order-1', rating: 6), throwsRangeError);
      expect(s.server.requests, isEmpty);
    });

    test('an order the server will not take a review of is its 404, not a silent success', () async {
      final s = _stores((RequestOptions o) => (404, <String, dynamic>{
            'title': 'Order not found',
            'status': 404,
            'detail': 'Order order-1 was not found among your delivered orders',
          }));

      await expectLater(
        s.api.submitReview('press-1', orderId: 'order-1', rating: 5),
        throwsA(isA<DioException>()
            .having((DioException e) => e.response?.statusCode, 'status', 404)),
      );
    });

    test('an answer that is not a review is an error, not a review', () async {
      final s = _stores((RequestOptions o) => (201, <String, dynamic>{'id': 'review-1'}));

      await expectLater(s.api.submitReview('press-1', orderId: 'order-1', rating: 5),
          throwsFormatException);
    });
  });

  group('StoreApi.myReviewForOrder', () {
    test('reads the caller\'s own review of the order', () async {
      final s = _stores((RequestOptions o) => (200, _stored(rating: 3)));

      final StoreReview? review = await s.api.myReviewForOrder('order-1');

      expect(s.server.requests.single.method, 'GET');
      expect(s.server.requests.single.path, '/api/stores/reviews/order/order-1');
      expect(review!.rating, 3);
      expect(review.mine, isTrue);
    });

    test('204 is "not reviewed yet"', () async {
      final s = _stores((RequestOptions o) => (204, null));

      expect(await s.api.myReviewForOrder('order-1'), isNull);
    });

    test('a 200 that is not a review is never read as "not reviewed"', () async {
      final s = _stores((RequestOptions o) => (200, <String, dynamic>{'rating': 9}));

      await expectLater(s.api.myReviewForOrder('order-1'), throwsFormatException);
    });
  });
}
