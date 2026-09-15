import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Back office's moderation of service offers on the client (product-service V36), and the hold an
/// offer's provider reads on it.
///
/// Pinned here:
/// - each call uses the verb, path, query and body `OfferModerationController` serves;
/// - a reason travels in the body and an actor never does, because the server names the actor from the
///   token;
/// - a filter that was not given is not sent;
/// - every block parses as the server writes it, and a state, an act or a value this build does not
///   know reads as unknown or absent rather than as a guess.
class _Recorder implements HttpClientAdapter {
  _Recorder(this.respond);

  final Object? Function(RequestOptions options) respond;
  final List<RequestOptions> requests = <RequestOptions>[];

  /// Each request's decoded JSON body, or null when it sent none.
  final List<Object?> bodies = <Object?>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    Object? body;
    if (requestStream != null) {
      final BytesBuilder sent = BytesBuilder();
      await for (final Uint8List chunk in requestStream) {
        sent.add(chunk);
      }
      final Uint8List bytes = sent.takeBytes();
      body = bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes));
    }
    bodies.add(body);
    return ResponseBody.fromString(jsonEncode(respond(options)), 200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}

const String _reason = 'Prints copies of official exam papers.';

const Map<String, dynamic> _hold = <String, dynamic>{
  'state': 'TAKEN_DOWN',
  'reason': _reason,
  'takenDownAt': '2026-09-14T09:30:00Z',
};

Map<String, dynamic> _offer({String status = 'ACTIVE', Object? moderation}) => <String, dynamic>{
      'id': 'offer-1',
      'merchantId': 'provider-1',
      'storeId': 'press-1',
      'name': 'Business card printing',
      'price': 15.0,
      'status': status,
      'service': <String, dynamic>{
        'pricingType': 'FIXED',
        'unitLabel': 'cards',
        'unitSize': 500,
        'turnaroundMinHours': 24,
        'turnaroundMaxHours': 48,
        'fulfilmentModes': 'PICKUP',
        'attachmentPolicy': 'NONE',
      },
      'fromPrice': 15.0,
      'moderation': moderation,
    };

Map<String, dynamic> _row({Map<String, dynamic>? offer}) => <String, dynamic>{
      'offer': offer ?? _offer(status: 'ARCHIVED', moderation: _hold),
      'storeId': 'press-1',
      'storeName': 'Al Fakhry Press',
      'serviceCategory': 'PRINTING',
      'storeStatus': 'ACTIVE',
    };

Map<String, dynamic> _act({String action = 'TAKE_DOWN', String? actorName = 'rana.ops'}) =>
    <String, dynamic>{
      'id': 'act-1',
      'productId': 'offer-1',
      'storeId': 'press-1',
      'action': action,
      'reason': _reason,
      'actorId': 'keycloak-sub-ops',
      'actorName': actorName,
      'createdAt': '2026-09-14T09:30:00Z',
    };

Map<String, dynamic> _page(List<Map<String, dynamic>> content, {int total = 0}) => <String, dynamic>{
      'content': content,
      'page': 0,
      'size': 20,
      'totalElements': total,
      'totalPages': 1,
    };

void main() {
  group('the hold on a product', () {
    test('an offer back office took down carries the hold, the reason and when', () {
      final Product offer = Product.fromJson(_offer(status: 'ARCHIVED', moderation: _hold));

      expect(offer.isTakenDown, isTrue);
      expect(offer.moderation!.state, ProductModerationState.takenDown);
      expect(offer.moderation!.reason, _reason);
      expect(offer.moderation!.takenDownAt, DateTime.utc(2026, 9, 14, 9, 30).toLocal());
      expect(offer.status, ProductStatus.archived);
    });

    test('an offer nobody took down has no hold, whether the block is null, absent or not a block', () {
      final Map<String, dynamic> absent = _offer()..remove('moderation');
      for (final Map<String, dynamic> json in <Map<String, dynamic>>[
        _offer(),
        absent,
        _offer(moderation: 'TAKEN_DOWN'),
        _offer(moderation: <Object>['TAKEN_DOWN']),
      ]) {
        final Product offer = Product.fromJson(json);
        expect(offer.moderation, isNull);
        expect(offer.isTakenDown, isFalse);
      }
    });

    test('a hold in a state this build does not know is still a hold, and what it cannot read is absent',
        () {
      final Product offer = Product.fromJson(_offer(
        status: 'ARCHIVED',
        moderation: <String, dynamic>{'state': 'UNDER_REVIEW', 'reason': '   ', 'takenDownAt': 'last week'},
      ));

      expect(offer.isTakenDown, isTrue);
      expect(offer.moderation!.state, ProductModerationState.unknown);
      expect(offer.moderation!.reason, isNull);
      expect(offer.moderation!.takenDownAt, isNull);
    });

    test('the hold is never sent back when its provider saves the offer', () {
      final Map<String, dynamic> saved =
          Product.fromJson(_offer(status: 'ARCHIVED', moderation: _hold)).toRequestJson();

      expect(saved.containsKey('moderation'), isFalse);
      expect(saved.containsKey('status'), isFalse);
    });
  });

  group("back office's rows and trail", () {
    test('a row reads the offer with its hold, and the shop it sits in', () {
      final BackofficeServiceOffer row = BackofficeServiceOffer.fromJson(_row());

      expect(row.offer.name, 'Business card printing');
      expect(row.offer.isTakenDown, isTrue);
      expect(row.offer.service!.unitSize, 500);
      expect(row.storeId, 'press-1');
      expect(row.storeName, 'Al Fakhry Press');
      expect(row.serviceCategory, ServiceCategory.printing);
      expect(row.storeStatus, StoreListingStatus.active);
    });

    test("a shop it cannot name is not guessed: no category, a draft, and the offer's own shop id", () {
      final BackofficeServiceOffer row = BackofficeServiceOffer.fromJson(<String, dynamic>{
        'offer': _offer(),
        'storeName': '  ',
        'serviceCategory': 'KNITTING',
        'storeStatus': 'CLOSED_FOR_GOOD',
      });

      expect(row.storeId, 'press-1');
      expect(row.storeName, isNull);
      expect(row.serviceCategory, isNull);
      expect(row.storeStatus, StoreListingStatus.draft);
      expect(row.offer.isTakenDown, isFalse);
    });

    test('an act reads what was done, why, by whom and when', () {
      final OfferModerationAction act = OfferModerationAction.fromJson(_act());

      expect(act.id, 'act-1');
      expect(act.productId, 'offer-1');
      expect(act.storeId, 'press-1');
      expect(act.action, OfferModerationActionKind.takeDown);
      expect(act.reason, _reason);
      expect(act.actorId, 'keycloak-sub-ops');
      expect(act.actorName, 'rana.ops');
      expect(act.createdAt, DateTime.utc(2026, 9, 14, 9, 30).toLocal());
      expect(OfferModerationAction.fromJson(_act(action: 'RESTORE')).action,
          OfferModerationActionKind.restore);
    });

    test('an act this build does not know is unknown, never a take-down or a restore, and gaps read as empty',
        () {
      final OfferModerationAction act = OfferModerationAction.fromJson(
          <String, dynamic>{'action': 'DELETE', 'actorName': null, 'createdAt': 42});

      expect(act.action, OfferModerationActionKind.unknown);
      expect(act.id, isEmpty);
      expect(act.reason, isEmpty);
      expect(act.actorId, isEmpty);
      expect(act.actorName, isNull);
      expect(act.createdAt, isNull);
    });

    test("the filters, acts and states are exactly the server's", () {
      expect(ServiceOfferStatusFilter.values.map((ServiceOfferStatusFilter f) => f.wireValue),
          <String>['DRAFT', 'ACTIVE', 'PAUSED', 'ARCHIVED', 'TAKEN_DOWN']);
      expect(OfferModerationActionKind.values.map((OfferModerationActionKind k) => k.wireValue),
          <String?>['TAKE_DOWN', 'RESTORE', null]);
      expect(ProductModerationState.values.map((ProductModerationState s) => s.wireValue),
          <String?>['TAKEN_DOWN', null]);
    });
  });

  group('BackofficeCatalogApi', () {
    late _Recorder recorder;
    late BackofficeCatalogApi api;

    void answering(Object? Function(RequestOptions options) respond) {
      recorder = _Recorder(respond);
      api = BackofficeCatalogApi(
          Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = recorder);
    }

    test('the list asks for every service offer a page at a time, and sends no filter it was not given',
        () async {
      answering((_) => _page(<Map<String, dynamic>>[_row()], total: 1));

      final Paged<BackofficeServiceOffer> page = await api.serviceOffers();

      final RequestOptions sent = recorder.requests.single;
      expect(sent.method, 'GET');
      expect(sent.uri.path, '/api/products/services/all');
      expect(sent.uri.queryParameters, <String, String>{'page': '0', 'size': '20'});
      expect(page.totalElements, 1);
      expect(page.content.single.offer.isTakenDown, isTrue);
    });

    test("each filter travels in the server's words, and a blank search or shop is not sent", () async {
      answering((_) => _page(<Map<String, dynamic>>[]));

      await api.serviceOffers(
        status: ServiceOfferStatusFilter.takenDown,
        serviceCategory: ServiceCategory.printing,
        storeId: 'press-1',
        search: 'cards',
        page: 2,
        size: 50,
      );
      await api.serviceOffers(status: ServiceOfferStatusFilter.archived, storeId: '', search: '');

      expect(recorder.requests.first.uri.queryParameters, <String, String>{
        'status': 'TAKEN_DOWN',
        'serviceCategory': 'PRINTING',
        'storeId': 'press-1',
        'search': 'cards',
        'page': '2',
        'size': '50',
      });
      expect(recorder.requests.last.uri.queryParameters,
          <String, String>{'status': 'ARCHIVED', 'page': '0', 'size': '20'});
    });

    test('taking down and restoring post the reason alone to the offer, and read the offer back', () async {
      answering((RequestOptions options) =>
          options.path.endsWith('/take-down') ? _row() : _row(offer: _offer(status: 'PAUSED')));

      final BackofficeServiceOffer takenDown = await api.takeDown('offer-1', reason: _reason);
      final BackofficeServiceOffer restored =
          await api.restore('offer-1', reason: 'The provider replaced the designs.');

      expect(recorder.requests.map((RequestOptions r) => '${r.method} ${r.uri.path}'), <String>[
        'POST /api/products/offer-1/moderation/take-down',
        'POST /api/products/offer-1/moderation/restore',
      ]);
      expect(recorder.bodies, <Object?>[
        <String, dynamic>{'reason': _reason},
        <String, dynamic>{'reason': 'The provider replaced the designs.'},
      ]);
      expect(takenDown.offer.moderation!.reason, _reason);
      expect(restored.offer.isTakenDown, isFalse);
      expect(restored.offer.status, ProductStatus.paused);
    });

    test('the trail is read newest first, as the server lists it', () async {
      answering((_) => <Map<String, dynamic>>[_act(action: 'RESTORE', actorName: null), _act()]);

      final List<OfferModerationAction> trail = await api.moderationHistory('offer-1');

      expect(recorder.requests.single.method, 'GET');
      expect(recorder.requests.single.uri.path, '/api/products/offer-1/moderation');
      expect(trail.map((OfferModerationAction a) => a.action),
          <OfferModerationActionKind>[OfferModerationActionKind.restore, OfferModerationActionKind.takeDown]);
      expect(trail.first.actorName, isNull);
      expect(trail.last.actorName, 'rana.ops');
    });

    test('a trail that is not a list reads as no acts', () async {
      answering((_) => <String, dynamic>{'content': <Object>[]});

      expect(await api.moderationHistory('offer-1'), isEmpty);
    });
  });
}
