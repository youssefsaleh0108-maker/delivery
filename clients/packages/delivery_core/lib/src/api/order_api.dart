import 'package:dio/dio.dart';

import '../models/catalog_models.dart';
import '../models/checkout_models.dart';
import '../models/gift_models.dart';
import '../models/order_models.dart';
import '../models/order_submission.dart';
import '../models/provider_models.dart';
import '../models/rating_models.dart';
import '../models/service_order_models.dart';
import '../models/summary_models.dart';

/// A service order's refusal as read off a 422.
typedef _Refusal = ({ServiceOrderRefusal refusal, String code, String? detail});

/// Client for the Order Manager and Order Tracking APIs (Phase 2).
///
/// Every method here maps to one endpoint. Note there is no client-side authorisation logic: which
/// list a role may read, and which transition it may make, is decided by the services. The client
/// renders what it is given — see [DeliveryOrder.availableActions].
class OrderApi {
  OrderApi(this._dio);

  final Dio _dio;

  // ---------------------------------------------------------------- customer

  /// The header that makes a retried placement safe. See [OrderSubmission].
  static const String idempotencyKeyHeader = 'Idempotency-Key';

  /// The code on the 503 Order Manager answers when it cannot read which service categories are open.
  static const String _servicesDirectoryUnavailable = 'SERVICES_DIRECTORY_UNAVAILABLE';

  /// Sends one checkout attempt.
  ///
  /// Always carries [OrderSubmission.idempotencyKey], so this is safe to call again with the
  /// **same** submission whenever an earlier call's outcome is unknown — a timeout, a dropped
  /// connection, an app killed mid-request. The server answers a repeat with the order the first
  /// copy placed ([OrderPlaced.replayed]), never with a second one.
  ///
  /// [expectedTotal] is the total the customer agreed to. When given, the server refuses to place
  /// at any other and this returns [OrderPriceChanged] with the new one; nothing is placed, and the
  /// same submission may be sent again once the customer has confirmed the new total. The live
  /// checkout sends none — the customer is looking at the screen and the confirmation shows the
  /// server's total — while the offline outbox always does, because its customer is not.
  ///
  /// [OrderAlreadyPlaced] means this attempt's key had already placed an order for a different
  /// basket; read that order and show it.
  ///
  /// A service order is placed here too, with its fulfilment, files and instructions in the
  /// submission, and everything above holds for it. What only a service order can meet comes back as
  /// an outcome as well: [ServiceOrderRefused] for a rule it broke — a file included — and
  /// [ServicesDirectoryUnavailable] when the server could not read which categories are open. Neither
  /// placed anything. Only for a submission that names its [OrderSubmission.fulfilment], as every
  /// service order does: a basket's answers are thrown whatever code they carry.
  ///
  /// Everything else — 422 (item gone, shop closed, below the minimum), 402 (payment declined),
  /// 400, and any network failure — is thrown as a `DioException`, exactly as before.
  Future<PlaceOrderResult> place(OrderSubmission submission, {double? expectedTotal}) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        '/api/orders',
        data: submission.toBody(expectedTotal: expectedTotal),
        options: Options(
            headers: <String, dynamic>{idempotencyKeyHeader: submission.idempotencyKey}),
      );
      return OrderPlaced(
        DeliveryOrder.fromJson(response.data as Map<String, dynamic>),
        // 201 is a new order; 200 is this attempt's earlier order, answered to a retry.
        replayed: response.statusCode == 200,
      );
    } on DioException catch (e) {
      final Object? body = e.response?.data;
      if (e.response?.statusCode == 409 && body is Map<String, dynamic>) {
        switch (body['code']) {
          case 'PRICE_CHANGED':
            return OrderPriceChanged(
              total: (body['total'] as num).toDouble(),
              expectedTotal: (body['expectedTotal'] as num).toDouble(),
            );
          case 'IDEMPOTENCY_KEY_REUSED':
            return OrderAlreadyPlaced(body['orderId'] as String);
        }
      }
      // A service order's own answers, and only a service order's: every one names how the customer
      // gets it. A basket is thrown whatever its code, exactly as before service orders — one holding
      // a service offer is refused with a service code (ONE_SERVICE_AT_A_TIME, OFFER_NOT_ORDERABLE,
      // NOT_GIFTABLE on a gift), and the checkouts that send baskets show Order Manager's own sentence
      // from the exception, the only explanation they have. SHOP_REFUSED and the rest, and codes this
      // build does not know, stay thrown for a service order too.
      if (submission.fulfilment != null) {
        final _Refusal? refused = _refusalOf(e, anyCode: false);
        if (refused != null) {
          return ServiceOrderRefused(
              refusal: refused.refusal, code: refused.code, detail: refused.detail);
        }
        if (_directoryUnavailable(e)) {
          return const ServicesDirectoryUnavailable();
        }
      }
      rethrow;
    }
  }

  /// Whether a [place] that threw may nonetheless have placed the order.
  ///
  /// **True for every failure with no answer but one.** Dio raises a connect timeout before a byte
  /// of the request has left, so that one proves nothing was placed. Everything else without a
  /// response can follow a request the server received: a receive timeout plainly does, and a
  /// "connection error" is what Dio calls both a refused socket and a connection that closed
  /// while the answer was awaited — which the phone cannot tell apart.
  ///
  /// **True for a server or gateway error (5xx).** A gateway gives up on a placement that goes on
  /// to commit (504), and a proxy answers for an upstream it lost mid-request (502).
  ///
  /// **False for any other answer.** The platform refused the request, and the refusal left nothing
  /// behind.
  ///
  /// What follows from true, for every checkout built on [place] (live, queued, gift, multi-shop):
  /// the attempt keeps its key; trying again resends the SAME [OrderSubmission], which the server
  /// answers with the order if there is one; and nothing tells the customer the order "did not go
  /// through".
  static bool mayHavePlaced(DioException e) {
    final int? status = e.response?.statusCode;
    if (status != null) return status >= 500;
    return e.type != DioExceptionType.connectionTimeout;
  }

  /// What a basket would cost if it were checked out now, shop by shop — `POST /api/orders/quote`.
  ///
  /// A dry run: nothing is placed, held or redeemed. See [BasketQuote] for why a screen shows these
  /// figures instead of adding up its own. CUSTOMER only.
  Future<BasketQuote> quote(BasketQuestion question) async {
    final Response<dynamic> response =
        await _dio.post<dynamic>('/api/orders/quote', data: question.toBody());
    return BasketQuote.fromJson(response.data as Map<String, dynamic>);
  }

  /// What one service would cost if it were ordered now — `POST /api/orders/quote`, asked with a
  /// [BasketQuestion.service]: one line of packs, and how the customer gets the work.
  ///
  /// The service order screen's total, priced by the path its placement takes: no fee on a pickup,
  /// the area's on a delivery, any waiver and the code. [ServiceQuoted.shop] is the shop's line.
  ///
  /// What a service order can never be comes back as [ServiceQuoteRefused] with placement's own
  /// codes — Express, a way of getting the work the offer is not sold with, a closed category — and
  /// a code this build does not know is still a refusal ([ServiceOrderRefusal.unknown]). An
  /// unreadable services directory is [ServiceQuoteUnavailable]. Anything else is thrown. CUSTOMER
  /// only.
  Future<ServiceQuoteResult> quoteService(BasketQuestion question) async {
    try {
      return ServiceQuoted(await quote(question));
    } on DioException catch (e) {
      final _Refusal? refused = _refusalOf(e, anyCode: true);
      if (refused != null) {
        return ServiceQuoteRefused(
            refusal: refused.refusal, code: refused.code, detail: refused.detail);
      }
      if (_directoryUnavailable(e)) {
        return const ServiceQuoteUnavailable();
      }
      rethrow;
    }
  }

  /// Sends one checkout attempt for a basket from several shops — `POST /api/orders/checkout`.
  ///
  /// The same [OrderSubmission] a single placement sends, with every shop's lines in the one list:
  /// Order Manager groups them by shop itself and places one order per shop, all of them or none.
  /// Every rule of [place] holds. The key goes on every retry, and a repeat is answered with every
  /// order the first copy placed ([CheckoutPlaced.replayed]); [expectedTotal] is the whole
  /// checkout's — which the live checkout always sends, as the quote its customer is looking at, and
  /// confirms with them again on [CheckoutPriceChanged]; a key that already placed something else
  /// comes back as [CheckoutAlreadyPlaced];
  /// and [mayHavePlaced] reads a thrown send exactly as it reads one from [place].
  ///
  /// A shop that refuses — closed, not delivering to the area, under its minimum — is a 422 whose
  /// `detail` names the shop, thrown as a `DioException` like every other refusal.
  Future<PlaceCheckoutResult> placeCheckout(OrderSubmission submission,
      {double? expectedTotal}) async {
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        '/api/orders/checkout',
        data: submission.toBody(expectedTotal: expectedTotal),
        options: Options(
            headers: <String, dynamic>{idempotencyKeyHeader: submission.idempotencyKey}),
      );
      final Map<String, dynamic> body = response.data as Map<String, dynamic>;
      return CheckoutPlaced(
        checkoutId: body['checkoutId'] as String?,
        orders: (body['orders'] as List<dynamic>)
            .map((dynamic e) => DeliveryOrder.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        totalAmount: (body['totalAmount'] as num).toDouble(),
        // 201 is a new checkout; 200 is this attempt's earlier one, answered to a retry.
        replayed: response.statusCode == 200,
      );
    } on DioException catch (e) {
      final Object? body = e.response?.data;
      if (e.response?.statusCode == 409 && body is Map<String, dynamic>) {
        switch (body['code']) {
          case 'PRICE_CHANGED':
            return CheckoutPriceChanged(
              total: (body['total'] as num).toDouble(),
              expectedTotal: (body['expectedTotal'] as num).toDouble(),
            );
          case 'IDEMPOTENCY_KEY_REUSED':
            return CheckoutAlreadyPlaced(body['orderId'] as String);
        }
      }
      rethrow;
    }
  }

  /// What a gift checkout needs before an order exists — `GET /api/orders/gift-terms`: what
  /// wrapping costs, and the methods a gift can be paid with here (never cash, possibly none).
  Future<GiftTerms> giftTerms() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/orders/gift-terms');
    return GiftTerms.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Paged<DeliveryOrder>> mine({int page = 0, int size = 20}) =>
      _page('/api/orders/mine', page, size);

  // ---------------------------------------------------------------- merchant

  /// The shop's orders, newest first.
  ///
  /// [kind] and [fulfilment] narrow it — a merchant running a goods shop and a services shop under
  /// one account asks for [OrderKind.service], a counter for [Fulfilment.pickup] — and with neither
  /// it is the list it always was. Never [OrderKind.unknown] or [Fulfilment.unknown], which name
  /// nothing the server can filter by and are refused here, before anything is sent.
  ///
  /// [statuses] narrows it to orders in any of those states, sent as a repeated `status`. A queue
  /// asks for its live states this way, because they are not the newest orders: a services shop's
  /// job can run for weeks behind a page of orders finished since. An Order Manager from before the
  /// filter ignores it and answers every state, so a caller that names statuses still checks the
  /// status of what comes back.
  Future<Paged<DeliveryOrder>> forMerchant({
    int page = 0,
    int size = 20,
    OrderKind? kind,
    Fulfilment? fulfilment,
    Iterable<OrderStatus>? statuses,
  }) =>
      _page('/api/orders/merchant', page, size, extra: <String, dynamic>{
        ...?_narrowedBy(kind, fulfilment),
        if (statuses != null && statuses.isNotEmpty)
          'status': statuses.map((OrderStatus s) => s.wire).toSet().toList(growable: false),
      });

  /// How the shop is trading, day by day. MERCHANT only, and always about the caller's own shop.
  Future<MerchantSummary> merchantSummary({int days = 14}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
        '/api/orders/merchant/summary', queryParameters: <String, dynamic>{'days': days});
    return MerchantSummary.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- service orders: the provider

  /// The customer collected their pickup at the counter: READY to DELIVERED —
  /// `POST /api/orders/{id}/collected`. MERCHANT only, and only the caller's own order.
  ///
  /// [ServiceOrderRefusal.notCollectable] when the order is not a pickup waiting at the counter —
  /// most often because another device there already marked it collected: read the order again.
  Future<ServiceOrderActionResult> collected(String orderId) =>
      _serviceStep(() => _dio.post<dynamic>('/api/orders/$orderId/collected'));

  /// Declines a new service order for [reason]: the shop's cancel, sent as the picklist's code
  /// (`PROVIDER_DECLINED: TOO_BUSY`), which the customer's screen says in their own language.
  ///
  /// Only a new order is declined. The same call on an order accepted meanwhile — by another device
  /// at the counter, say — is refused as [ServiceOrderRefusal.notDeclinable] (or, by a server that
  /// predates that code, as [ServiceOrderRefusal.reservedCancelReason]): read it again.
  /// [DeclineReason.unknown] names no reason and is refused here, before anything is sent.
  Future<ServiceOrderActionResult> decline(String orderId, DeclineReason reason) {
    if (reason == DeclineReason.unknown) {
      throw ArgumentError.value(reason, 'reason', 'A decline names a reason from the picklist');
    }
    return _serviceStep(() => _dio.post<dynamic>(
          '/api/orders/$orderId/cancel',
          data: <String, dynamic>{'reason': reason.cancelReason},
        ));
  }

  /// Cancels a pickup its customer never collected: the shop's cancel, sent as `NOT_COLLECTED`, with
  /// the shop's [note] after it when it gives one.
  ///
  /// Only once the customer's time is up ([DeliveryOrder.canCancelAsNotCollected]); sooner is refused
  /// as [ServiceOrderRefusal.uncollectedTooSoon], and the order's
  /// [DeliveryOrder.uncollectedCancellableAt] says from when it may be sent.
  ///
  /// A [note] longer than [notCollectedNoteMaxLength] is cut to fit and ends in "…" — cut rather than
  /// refused. Order Manager takes a cancel reason of 500 characters at most and answers a longer one
  /// with a 400, and no screen can promise to stay under that: a text field's limit counts the
  /// characters a reader sees, while the server counts UTF-16 code units, two or more for an emoji. A
  /// cut note loses its end; a refused one would lose the cancel. The cut never splits an emoji.
  Future<ServiceOrderActionResult> cancelNotCollected(String orderId, {String? note}) {
    final String words = _fitNote(note?.trim() ?? '');
    return _serviceStep(() => _dio.post<dynamic>(
          '/api/orders/$orderId/cancel',
          data: <String, dynamic>{
            'reason': words.isEmpty
                ? DeliveryOrder.notCollectedCancelReason
                : '${DeliveryOrder.notCollectedCancelReason}: $words',
          },
        ));
  }

  /// The most of a shop's own words [cancelNotCollected] sends: the 500 characters Order Manager
  /// takes for a cancel reason (`CancelRequest`), less the `NOT_COLLECTED: ` before them. A note
  /// field's limit, so the shop sees where its words stop.
  static const int notCollectedNoteMaxLength =
      _cancelReasonMaxLength - '${DeliveryOrder.notCollectedCancelReason}: '.length;

  /// The longest cancel reason Order Manager takes, in UTF-16 code units: `String.length`, in Dart
  /// and in Java alike.
  static const int _cancelReasonMaxLength = 500;

  /// [words] as they fit after `NOT_COLLECTED: `: unchanged when they do, otherwise cut and ended
  /// with an ellipsis — never between the two code units of one character.
  static String _fitNote(String words) {
    if (words.length <= notCollectedNoteMaxLength) {
      return words;
    }
    // One unit is the ellipsis's.
    int end = notCollectedNoteMaxLength - 1;
    final int last = words.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) {
      // The first half of a pair whose second half is past the cut: it goes with it.
      end -= 1;
    }
    return '${words.substring(0, end).trimRight()}…';
  }

  // ---------------------------------------------------------------- rider

  /// READY orders no rider has claimed. Oldest first — the longest wait goes out next.
  Future<Paged<DeliveryOrder>> available({int page = 0, int size = 20}) =>
      _page('/api/orders/available', page, size);

  /// The rider's own orders, narrowed to the states the caller actually renders.
  ///
  /// Unfiltered this returns a rider's entire history — which is what the home screen's
  /// five-second poll was downloading, lines and all, to show one live job; 83% of a measured
  /// response was thrown away on arrival. Asking for the states in use costs the same round trip
  /// and a fraction of the work at both ends.
  Future<Paged<DeliveryOrder>> assigned({
    int page = 0,
    int size = 20,
    Iterable<OrderStatus>? statuses,
  }) =>
      _page('/api/orders/assigned', page, size,
          extra: statuses == null || statuses.isEmpty
              ? null
              : <String, dynamic>{
                  'status':
                      statuses.map((OrderStatus s) => s.wire).toList(growable: false),
                });

  // ---------------------------------------------------------------- backoffice

  /// Everything the caller's delivery company has carried or is carrying. CARRIER only.
  Future<Paged<DeliveryOrder>> forCarrier({int page = 0, int size = 20}) =>
      _page('/api/orders/carrier', page, size);

  /// What the company has earned and what the work in flight is worth. CARRIER only.
  Future<CarrierEarnings> carrierEarnings() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/orders/carrier/earnings');
    return CarrierEarnings.fromJson(response.data as Map<String, dynamic>);
  }

  /// The same company's work day by day, for the dashboard. CARRIER only.
  Future<CarrierSummary> carrierSummary({int days = 14}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
        '/api/orders/carrier/summary', queryParameters: <String, dynamic>{'days': days});
    return CarrierSummary.fromJson(response.data as Map<String, dynamic>);
  }

  /// The whole platform's orders, newest first, narrowed by whatever is given — "every pickup waiting
  /// at a counter" is [OrderStatus.ready], [OrderKind.service], [Fulfilment.pickup]. BACKOFFICE only.
  Future<Paged<DeliveryOrder>> all({
    OrderStatus? status,
    OrderKind? kind,
    Fulfilment? fulfilment,
    int page = 0,
    int size = 20,
  }) =>
      _page('/api/orders', page, size, extra: <String, dynamic>{
        if (status != null) 'status': status.wire,
        ...?_narrowedBy(kind, fulfilment),
      });

  Future<OrderStats> stats() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/orders/stats');
    return OrderStats.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- shared

  Future<DeliveryOrder> read(String orderId) async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/orders/$orderId');
    return DeliveryOrder.fromJson(response.data as Map<String, dynamic>);
  }

  /// Every step the order has taken, oldest first — `GET /api/orders/{id}/history`, readable by
  /// whoever may read the order. A step this build cannot place on a timeline is left out.
  Future<List<OrderStatusChange>> statusHistory(String orderId) async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/orders/$orderId/history');
    final Object? rows = response.data;
    if (rows is! List) {
      return const <OrderStatusChange>[];
    }
    return rows
        .map(OrderStatusChange.maybeFromJson)
        .whereType<OrderStatusChange>()
        .toList(growable: false);
  }

  /// Applies one of the actions the server offered on this order.
  ///
  /// Driven by [OrderAction] rather than a free-text path so a screen cannot invent a transition
  /// the service never advertised.
  Future<DeliveryOrder> act(String orderId, OrderAction action, {String? reason}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/orders/$orderId/${action.path}',
      data: action == OrderAction.cancel
          ? <String, dynamic>{'reason': reason ?? ''}
          : null,
    );
    return DeliveryOrder.fromJson(response.data as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------- tracking

  /// The rider's latest position, or null when nothing has been reported yet.
  ///
  /// 204 means "you may watch this, but there is no fix yet" — distinct from 404, which means the
  /// order is unknown or not yours.
  Future<RiderPosition?> currentPosition(String orderId) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/tracking/orders/$orderId',
      options: Options(validateStatus: (int? s) => s != null && s < 300),
    );
    if (response.statusCode == 204 || response.data == null) {
      return null;
    }
    return RiderPosition.fromJson(response.data as Map<String, dynamic>);
  }

  /// Reports this rider's position on one of their orders. Fire-and-forget: a dropped ping is
  /// replaced by the next one.
  ///
  /// [recordedAt] is when the phone took the fix. The server refuses a fix dated in the future or
  /// more than a minute old, and one that is too imprecise or too far from the last — a 422 whose
  /// body names the `reason`. Sent in UTC so the server never has to guess the phone's offset.
  Future<void> ping(String orderId, double lat, double lng,
      {double? accuracyM, DateTime? recordedAt}) async {
    await _dio.post<dynamic>(
      '/api/tracking/orders/$orderId/ping',
      data: <String, dynamic>{
        'lat': lat,
        'lng': lng,
        if (accuracyM != null) 'accuracyM': accuracyM,
        if (recordedAt != null) 'recordedAt': recordedAt.toUtc().toIso8601String(),
      },
    );
  }

  Future<List<RiderPosition>> trackHistory(String orderId) async {
    final Response<dynamic> response =
        await _dio.get<dynamic>('/api/tracking/orders/$orderId/history');
    return (response.data as List<dynamic>)
        .map((dynamic e) => RiderPosition.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------- rider ratings

  /// Rates the rider on a delivered order. CUSTOMER only; the service then decides whether this
  /// order was the caller's, delivered, and not already rated — 409 when it was.
  ///
  /// [stars] is 1–5; [text] is optional and stripped of markup server-side.
  Future<RiderRatingEntry> rateRider(String orderId, int stars, {String? text}) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/api/orders/$orderId/rating',
      data: <String, dynamic>{
        'score': stars,
        if (text != null && text.isNotEmpty) 'comment': text,
      },
    );
    return RiderRatingEntry.fromJson(response.data as Map<String, dynamic>);
  }

  /// What the caller left on their own order, or null when they have not rated it — how the
  /// screen knows to show stars already given rather than offer to rate again.
  Future<RiderRatingEntry?> orderRating(String orderId) async {
    try {
      final Response<dynamic> response =
          await _dio.get<dynamic>('/api/orders/$orderId/rating');
      return RiderRatingEntry.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  /// A rider's aggregate — the number next to their name on a tracking screen. Open to any
  /// authenticated caller; carries no comments and no individual scores.
  ///
  /// Render [RiderStanding.average] null as "new", never as zero.
  Future<RiderStanding> riderRating(String riderId) async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/riders/$riderId/rating');
    return RiderStanding.fromJson(response.data as Map<String, dynamic>);
  }

  /// A rider's own standing, addressed by their token rather than an id they would have to know
  /// the spelling of. DELIVERY only.
  Future<RiderStanding> myRiderRating() async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/riders/me/rating');
    return RiderStanding.fromJson(response.data as Map<String, dynamic>);
  }

  /// The written comments about a rider. BACKOFFICE only — free text about a named individual is
  /// not part of the public score.
  Future<Paged<RiderRatingComment>> riderRatingComments(String riderId,
      {int page = 0, int size = 20}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/api/riders/$riderId/rating/comments',
      queryParameters: <String, dynamic>{'page': page, 'size': size},
    );
    return Paged<RiderRatingComment>.fromJson(
        response.data as Map<String, dynamic>, RiderRatingComment.fromJson);
  }

  // ---------------------------------------------------------------- internals

  Future<Paged<DeliveryOrder>> _page(String path, int page, int size,
      {Map<String, dynamic>? extra}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      path,
      queryParameters: <String, dynamic>{'page': page, 'size': size, ...?extra},
    );
    return Paged<DeliveryOrder>.fromJson(
      response.data as Map<String, dynamic>,
      (Map<String, dynamic> json) => DeliveryOrder.fromJson(json),
    );
  }

  /// The kind and fulfilment filters as the server spells them; null when neither is given.
  static Map<String, dynamic>? _narrowedBy(OrderKind? kind, Fulfilment? fulfilment) {
    if (kind == OrderKind.unknown) {
      throw ArgumentError.value(kind, 'kind', 'A kind this app does not know cannot be filtered by');
    }
    if (fulfilment == Fulfilment.unknown) {
      throw ArgumentError.value(
          fulfilment, 'fulfilment', 'A fulfilment this app does not know cannot be filtered by');
    }
    if (kind == null && fulfilment == null) {
      return null;
    }
    return <String, dynamic>{
      if (kind != null) 'kind': kind.wire,
      if (fulfilment != null) 'fulfilment': fulfilment.wire,
    };
  }

  /// A provider's step on a service order, with a refusal read off its 422 rather than thrown.
  Future<ServiceOrderActionResult> _serviceStep(Future<Response<dynamic>> Function() send) async {
    try {
      final Response<dynamic> response = await send();
      return ServiceOrderUpdated(DeliveryOrder.fromJson(response.data as Map<String, dynamic>));
    } on DioException catch (e) {
      final _Refusal? refused = _refusalOf(e, anyCode: true);
      if (refused == null) {
        rethrow;
      }
      return ServiceOrderActionRefused(
          refusal: refused.refusal, code: refused.code, detail: refused.detail);
    }
  }

  /// The refusal a 422 names in its `code`, or null when it names none.
  ///
  /// [anyCode] false keeps only the codes a service order is refused with, for a service order's
  /// placement, where everything else is thrown as a basket's refusals are. True reads any code — one
  /// this build does not know as [ServiceOrderRefusal.unknown] — for the calls only a service order
  /// makes.
  static _Refusal? _refusalOf(DioException e, {required bool anyCode}) {
    final Object? body = e.response?.data;
    if (e.response?.statusCode != 422 || body is! Map) {
      return null;
    }
    final Object? code = body['code'];
    if (code is! String || code.isEmpty) {
      return null;
    }
    final ServiceOrderRefusal? known = ServiceOrderRefusal.maybeFromWire(code);
    if (known == null && !anyCode) {
      return null;
    }
    final Object? detail = body['detail'];
    return (
      refusal: known ?? ServiceOrderRefusal.unknown,
      code: code,
      detail: detail is String ? detail : null,
    );
  }

  /// Whether this is the 503 that says the services directory could not be read — which Order
  /// Manager answers before pricing anything, unlike a gateway's 503.
  static bool _directoryUnavailable(DioException e) {
    final Object? body = e.response?.data;
    return e.response?.statusCode == 503 &&
        body is Map &&
        body['code'] == _servicesDirectoryUnavailable;
  }
}
