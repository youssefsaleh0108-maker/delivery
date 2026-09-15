import 'dart:async';
import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'offline_store.dart';

/// Where a queued checkout is in its life.
enum PendingOrderStatus {
  /// Saved, waiting for a connection. Sent automatically.
  queued,

  /// On the wire right now.
  sending,

  /// Stopped until the customer decides — see [PendingReview]. Never sent automatically.
  needsReview,

  /// The platform refused it (item gone, shop closed, below the minimum...). Never retried
  /// automatically; the customer can retry or discard.
  failed,
}

/// Why a queued checkout is waiting on the customer rather than being sent.
enum PendingReview {
  /// The server prices it differently from the total the customer agreed to.
  priceChanged,

  /// It has waited longer than [OrderOutbox.staleAfter]. A dinner order sent five hours late is
  /// not the order anybody wanted, so it is not sent without asking.
  stale,
}

/// One checkout the customer asked to place when the connection returns.
///
/// Wraps the exact [OrderSubmission] the checkout built — its idempotency key included — so every
/// send, after any number of reconnects and app restarts, is the same attempt the server
/// recognises. See [OrderOutbox] for the rules that keep it from being placed twice or lost.
///
/// It has no order number, because there is no order until the platform places it. It is named by
/// its shop and the time it was queued — never by a number the placed order would not carry.
@immutable
class PendingOrder {
  const PendingOrder({
    required this.submission,
    required this.expectedTotal,
    required this.storeName,
    required this.createdAt,
    this.storeId,
    this.splitUsd,
    this.confirmedAt,
    this.status = PendingOrderStatus.queued,
    this.review,
    this.newTotal,
    this.error,
    this.maybePlaced = false,
  });

  final OrderSubmission submission;

  /// The total the customer agreed to — what the checkout button said when they queued it, or the
  /// new total they confirmed after a price change. Sent as `expectedTotal`, so the server refuses
  /// to place at any other.
  ///
  /// Only ever a total the app can show is the server's own: checkout refuses to queue what it
  /// cannot price exactly as Order Manager will (an Express tier, an area whose fee it never
  /// learned), so a PRICE_CHANGED here means something really changed.
  final double expectedTotal;

  final String? storeId;

  /// Snapshotted for the card: a queued order has to name its shop with no connection to ask.
  final String storeName;

  /// The USD half of a cash split, recorded in the transfer ledger once the order exists.
  final double? splitUsd;

  /// When it was queued. The card shows it; staleness is measured from it until [confirmedAt].
  final DateTime createdAt;

  /// When the customer last said "yes, send it" — at a new price, or after it went stale. Staleness
  /// is measured from here when set.
  final DateTime? confirmedAt;

  final PendingOrderStatus status;
  final PendingReview? review;

  /// The server's total, when [review] is [PendingReview.priceChanged].
  final double? newTotal;

  /// The server's own sentence, when [status] is [PendingOrderStatus.failed]. Null means the
  /// caller shows its generic fallback.
  final String? error;

  /// True when a send of this checkout may have reached the platform with its answer lost — so the
  /// order may already exist ([OrderApi.mayHavePlaced]). Set when checkout's own try went
  /// unanswered before the customer queued it, when a send from here timed out, was cut off or
  /// hit a server error, and when the app stopped mid-send.
  ///
  /// Sending does not change: every send carries the one key, and a copy that already placed is
  /// answered with that order. What changes is what the customer may be told. Never "it hasn't
  /// been sent"; and discarding it removes only the phone's copy of what may be a real order on the
  /// Orders list, which the confirmation says.
  ///
  /// Cleared only by an answer proving nothing exists under the key: PRICE_CHANGED, or a
  /// business-rule refusal (422). Order Manager looks the key up before it decides either.
  final bool maybePlaced;

  String get key => submission.idempotencyKey;

  PendingOrder _with({
    PendingOrderStatus? status,
    double? expectedTotal,
    DateTime? confirmedAt,
    PendingReview? review,
    double? newTotal,
    String? error,
    bool? maybePlaced,
    bool clearReview = false,
    bool clearError = false,
  }) =>
      PendingOrder(
        submission: submission,
        expectedTotal: expectedTotal ?? this.expectedTotal,
        storeName: storeName,
        createdAt: createdAt,
        storeId: storeId,
        splitUsd: splitUsd,
        confirmedAt: confirmedAt ?? this.confirmedAt,
        status: status ?? this.status,
        review: clearReview ? null : (review ?? this.review),
        newTotal: clearReview ? null : (newTotal ?? this.newTotal),
        error: clearError ? null : (error ?? this.error),
        maybePlaced: maybePlaced ?? this.maybePlaced,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'submission': submission.toJson(),
        'expectedTotal': expectedTotal,
        'storeId': storeId,
        'storeName': storeName,
        'splitUsd': splitUsd,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'confirmedAt': confirmedAt?.toUtc().toIso8601String(),
        'status': status.name,
        'review': review?.name,
        'newTotal': newTotal,
        'error': error,
        'maybePlaced': maybePlaced,
      };

  factory PendingOrder.fromJson(Map<String, dynamic> json) => PendingOrder(
        submission: OrderSubmission.fromJson(json['submission'] as Map<String, dynamic>),
        expectedTotal: (json['expectedTotal'] as num).toDouble(),
        storeId: json['storeId'] as String?,
        storeName: json['storeName'] as String? ?? '',
        splitUsd: (json['splitUsd'] as num?)?.toDouble(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        confirmedAt: json['confirmedAt'] == null
            ? null
            : DateTime.parse(json['confirmedAt'] as String),
        status: PendingOrderStatus.values.firstWhere(
            (PendingOrderStatus s) => s.name == json['status'],
            orElse: () => PendingOrderStatus.queued),
        review: PendingReview.values
            .where((PendingReview r) => r.name == json['review'])
            .firstOrNull,
        newTotal: (json['newTotal'] as num?)?.toDouble(),
        error: json['error'] as String?,
        maybePlaced: json['maybePlaced'] as bool? ?? false,
      );
}

/// A queued checkout that has become a real order.
class OutboxPlaced {
  const OutboxPlaced(this.pending, this.order, {this.earlierAttempt = false});

  final PendingOrder pending;
  final DeliveryOrder order;

  /// True when [order] is not this checkout as queued but an earlier try of the same basket that
  /// went through before the customer changed it: the server refused the queued copy with
  /// IDEMPOTENCY_KEY_REUSED and named that order. Worth saying differently — what arrives is what
  /// the earlier try asked for.
  final bool earlierAttempt;
}

/// The checkout could not be written to the phone, so it was not queued.
class OutboxWriteException implements Exception {
  const OutboxWriteException([this.cause]);

  final Object? cause;

  @override
  String toString() => 'OutboxWriteException: $cause';
}

/// Checkouts the customer asked to place when the connection returns — kept on the phone, sent
/// when it can be, and never placed twice, never lost silently, never charged at a price the
/// customer did not see.
///
/// **Never placed twice.** Every send of an item is the same [OrderSubmission], carrying the same
/// idempotency key. Order Manager answers a repeat with the order the first copy placed, so an
/// item whose send was cut off — or whose success was not written down before the app died — is
/// simply sent again and comes back as the order that already exists.
///
/// **Never lost silently.** [enqueue] writes to the phone before it returns and throws if it
/// cannot, so checkout keeps the basket when the save fails. An item leaves the outbox only when
/// the server has placed it or the customer discards it. A send whose outcome is unknown (the
/// connection dropped, the answer never came) leaves it queued, not failed. An item found
/// mid-send after a restart goes back to queued — and its resend is safe for the same reason.
///
/// **Never called unsent when it may not be.** A send that may have reached the platform with its
/// answer lost marks the item [PendingOrder.maybePlaced], and from then on nothing says it was
/// never sent: the card says the outcome is being checked, and discarding it is confirmed as
/// removing only the phone's copy.
///
/// **Never at a price nobody saw.** Every send carries [PendingOrder.expectedTotal]. A different
/// server total comes back as PRICE_CHANGED, nothing is placed, and the item waits in
/// [PendingOrderStatus.needsReview] until the customer confirms the new total ([confirm]). The
/// same happens to an item older than [staleAfter]. Neither is ever re-sent on the customer's
/// behalf.
///
/// **Scoped to the signed-in person**, like the address book: another account on the same phone
/// neither sees nor sends someone else's queued order (which the server would otherwise place
/// under the wrong customer).
///
/// Sends oldest first. Stops at the first send that cannot reach the platform, and starts again
/// when [connectivity] says it is back; a server error or a slow answer is retried after
/// [retryDelay].
///
/// For flows built after this one (gifting, the multi-shop basket): queue one [PendingOrder] per
/// order, each wrapping the [OrderSubmission] that order's checkout sent and the total that order
/// will cost. Everything above then holds per order.
class OrderOutbox extends ChangeNotifier {
  OrderOutbox({
    required OrderApi api,
    required OfflineStore store,
    required String? ownerId,
    ValueListenable<bool>? connectivity,
    TransferApi? transfers,
    this.retryDelay = const Duration(seconds: 30),
    this.staleAfter = const Duration(hours: 2),
    DateTime Function()? now,
  })  : _api = api,
        _store = store,
        _ownerId = ownerId,
        _connectivity = connectivity,
        _transfers = transfers,
        _now = now ?? DateTime.now {
    _connectivity?.addListener(_onConnectivity);
  }

  static const String _keyPrefix = 'delivery.outbox.';

  final OrderApi _api;
  final OfflineStore _store;
  final String? _ownerId;
  final ValueListenable<bool>? _connectivity;
  final TransferApi? _transfers;
  final DateTime Function() _now;

  /// How long after a server error or an unanswered send the outbox tries again by itself.
  final Duration retryDelay;

  /// How long an item may wait before it needs the customer's say-so to be sent.
  final Duration staleAfter;

  List<PendingOrder> _items = <PendingOrder>[];
  Future<void> _ready = Future<void>.value();
  bool _draining = false;
  bool _drainAgain = false;
  Timer? _retry;
  bool _disposed = false;
  final StreamController<OutboxPlaced> _placed = StreamController<OutboxPlaced>.broadcast();

  String? get _storageKey => _ownerId == null ? null : '$_keyPrefix$_ownerId';

  /// Oldest first — the order they will be sent in.
  List<PendingOrder> get items => List<PendingOrder>.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;

  /// Each queued checkout the server placed, as it happens — for the "it went through" message.
  Stream<OutboxPlaced> get placed => _placed.stream;

  bool get _online => _connectivity?.value ?? true;

  /// Restores what was queued before the app last stopped, then sends it if it can.
  Future<void> load() => _ready = _load();

  Future<void> _load() async {
    final String? key = _storageKey;
    if (key == null) return;
    String? raw;
    try {
      raw = await _store.read(key);
    } catch (_) {
      raw = null;
    }
    if (raw == null || _disposed) return;
    try {
      final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
      _items = (json['items'] as List<dynamic>)
          .map((dynamic e) => PendingOrder.fromJson(e as Map<String, dynamic>))
          // Found mid-send: the app stopped with the answer unknown, so the order may exist. Sending
          // it again is safe — the key makes the server answer with the order if the first copy
          // placed it — but nothing may call it unsent any more.
          .map((PendingOrder p) => p.status == PendingOrderStatus.sending
              ? p._with(status: PendingOrderStatus.queued, maybePlaced: true)
              : p)
          .toList();
    } catch (_) {
      // Unreadable. Left where it is rather than overwritten by an empty list — and nothing new is
      // written over it until something is queued, which is the customer's own action.
      return;
    }
    notifyListeners();
    if (_online) unawaited(drain());
  }

  /// Queues a checkout. Returns once it is written to the phone; throws [OutboxWriteException]
  /// when it cannot be, in which case nothing is queued and the caller must keep the basket.
  ///
  /// A checkout whose own try went unanswered is queued with [PendingOrder.maybePlaced] already
  /// set — checkout knows, and the card must not say otherwise from the first moment.
  ///
  /// Cash only. A card or wallet hold needs the provider, and an instrument token is never written
  /// to disk ([OrderSubmission.toJson]) — so a queued card order could only ever fail later.
  ///
  /// Never a service order (owner default 13): a submission naming how the customer gets the work,
  /// files for the provider, or instructions. One is always cash, so the rule above lets it through;
  /// it is refused here, whatever screen built it. Sent hours later, its files may have expired and
  /// its shop closed. And because none is ever queued, nothing restored carries a fulfilment — one
  /// this build did not know would make [OrderSubmission.fromJson] refuse the whole outbox.
  Future<void> enqueue(PendingOrder order) async {
    final OrderSubmission submission = order.submission;
    if (submission.paymentMethod != PaymentMethod.cash) {
      throw ArgumentError.value(submission.paymentMethod, 'paymentMethod',
          'only cash checkouts can be queued');
    }
    if (submission.fulfilment != null ||
        submission.attachmentFileIds.isNotEmpty ||
        (submission.serviceInstructions?.trim().isNotEmpty ?? false)) {
      throw ArgumentError('A service order is never queued: it is placed online or not at all');
    }
    await _ready;
    if (_storageKey == null) throw const OutboxWriteException('no signed-in customer');
    final List<PendingOrder> before = _items;
    _items = <PendingOrder>[
      ..._items.where((PendingOrder p) => p.key != order.key),
      order,
    ];
    try {
      await _write();
    } catch (e) {
      _items = before;
      throw OutboxWriteException(e);
    }
    notifyListeners();
    if (_online) unawaited(drain());
  }

  /// The customer confirmed the new total, or said a stale order should still go. Sends it.
  ///
  /// For a stale item that may already have been placed this is the safe way to find out: the
  /// same key is answered with the order if it exists, and places it only if it does not.
  Future<void> confirm(String key) async {
    final PendingOrder? item = _find(key);
    if (item == null || item.status != PendingOrderStatus.needsReview) return;
    await _update(item._with(
      status: PendingOrderStatus.queued,
      expectedTotal: item.review == PendingReview.priceChanged ? item.newTotal : null,
      confirmedAt: _now(),
      clearReview: true,
    ));
    await drain();
  }

  /// Tries a refused order once more — the shop may have reopened, the item come back.
  Future<void> retry(String key) async {
    final PendingOrder? item = _find(key);
    if (item == null || item.status != PendingOrderStatus.failed) return;
    await _update(item._with(status: PendingOrderStatus.queued, clearError: true));
    await drain();
  }

  /// Removes it from the phone for good. Refused while it is on the wire: its outcome is not known
  /// yet, and dropping it then could leave an order the customer believes they cancelled.
  ///
  /// It cancels nothing on the platform. For an item that [PendingOrder.maybePlaced], the order may
  /// already exist and stays on the Orders list — the card's confirmation says exactly that.
  Future<void> discard(String key) async {
    final PendingOrder? item = _find(key);
    if (item == null || item.status == PendingOrderStatus.sending) return;
    await _remove(key);
  }

  /// Sends every queued item it can, oldest first.
  Future<void> drain() async {
    await _ready;
    if (_draining) {
      _drainAgain = true;
      return;
    }
    _draining = true;
    try {
      do {
        _drainAgain = false;
        for (final PendingOrder item in List<PendingOrder>.of(_items)) {
          if (_disposed || !_online) return;
          final PendingOrder? current = _find(item.key);
          if (current == null || current.status != PendingOrderStatus.queued) continue;
          // Waited too long to go without asking — including an item that may already have been
          // placed. Its card says so, its "Send again" is answered with the order if it exists,
          // and its Discard is confirmed as removing only the phone's copy.
          if (_now().difference(current.confirmedAt ?? current.createdAt) > staleAfter) {
            await _update(current._with(
                status: PendingOrderStatus.needsReview, review: PendingReview.stale));
            continue;
          }
          if (!await _send(current)) break;
        }
      } while (_drainAgain && !_disposed);
    } finally {
      _draining = false;
    }
  }

  /// Sends one item. False means stop draining: the platform could not be reached, or answered
  /// in a way that says try later.
  Future<bool> _send(PendingOrder item) async {
    await _update(item._with(status: PendingOrderStatus.sending));
    try {
      final PlaceOrderResult result =
          await _api.place(item.submission, expectedTotal: item.expectedTotal);
      switch (result) {
        case OrderPlaced(order: final DeliveryOrder order):
          await _placedAs(item, order);
        case OrderAlreadyPlaced(orderId: final String orderId):
          // The key already placed an order for a different basket: an online try of this checkout
          // went through with its answer lost, and the customer changed the basket before queuing
          // it. That order is the one that exists, and placing this copy as well is the duplicate
          // the key prevents — so the item ends here, as that order.
          await _placedAs(item, await _api.read(orderId), earlierAttempt: true);
        case OrderPriceChanged(total: final double total):
          // Nothing exists under this key: Order Manager looks a key up before it prices anything.
          await _update(item._with(
              status: PendingOrderStatus.needsReview,
              review: PendingReview.priceChanged,
              newTotal: total,
              maybePlaced: false));
        case ServiceOrderRefused(detail: final String? detail):
          // Only ever the answer to a service order, which [enqueue] refuses. One found here all the
          // same is refused as any 422 is: before its key placed anything, so nothing exists under it.
          await _update(item._with(
              status: PendingOrderStatus.failed, error: detail, maybePlaced: false));
        case ServicesDirectoryUnavailable():
          // A service order's answer too, and a temporary one: back to queued with the same key.
          await _update(item._with(status: PendingOrderStatus.queued));
          _scheduleRetry();
          return false;
      }
      return true;
    } on DioException catch (e) {
      final int? code = e.response?.statusCode;
      final bool tryLater = ConnectivityService.outcomeUnknown(e) ||
          code == null ||
          code >= 500 ||
          code == 401 ||
          code == 408 ||
          code == 429;
      if (tryLater) {
        // Unknown or temporary. Back to queued with the same key; resending is safe. An answer
        // that never came, or a server error, may have followed a placement — and once that is
        // possible the item says so until an answer proves otherwise.
        await _update(item._with(
            status: PendingOrderStatus.queued,
            maybePlaced: item.maybePlaced || OrderApi.mayHavePlaced(e)));
        if (!ConnectivityService.isUnreachable(e)) _scheduleRetry();
        return false;
      }
      final Object? body = e.response?.data;
      await _update(item._with(
        status: PendingOrderStatus.failed,
        error: body is Map<String, dynamic> ? body['detail'] as String? : null,
        // A business-rule refusal is decided after the key is looked up, so it proves nothing was
        // placed under it. Any other refusal (a request the gateway rejected before Order Manager
        // saw it, say) says nothing about an earlier send, and leaves the flag as it was.
        maybePlaced: code == 422 ? false : null,
      ));
      return true;
    } catch (_) {
      // Something unexpected after the request left — a response that would not parse, say. The
      // order may well exist; the key makes finding out safe, so it goes back to queued.
      await _update(item._with(status: PendingOrderStatus.queued, maybePlaced: true));
      _scheduleRetry();
      return false;
    }
  }

  Future<void> _placedAs(PendingOrder item, DeliveryOrder order,
      {bool earlierAttempt = false}) async {
    await _remove(item.key);
    // The cash split, into the transfer ledger — best effort, exactly as checkout does it: the
    // order stands either way, and collection reads the ledger only when a row is there.
    final TransferApi? transfers = _transfers;
    if (transfers != null) {
      try {
        await transfers.initiate(
          orderId: order.id,
          method: 'CASH_ON_DELIVERY',
          amountUsd: order.totalAmount,
          splitUsd: item.splitUsd == null
              ? null
              : (item.splitUsd! > order.totalAmount ? order.totalAmount : item.splitUsd),
        );
      } catch (_) {
        // The ledger missed one intent; the order and its payment method stand.
      }
    }
    if (!_placed.isClosed) {
      _placed.add(OutboxPlaced(item, order, earlierAttempt: earlierAttempt));
    }
  }

  void _scheduleRetry() {
    if (_disposed) return;
    _retry?.cancel();
    _retry = Timer(retryDelay, () => unawaited(drain()));
  }

  void _onConnectivity() {
    if (_connectivity?.value ?? false) unawaited(drain());
  }

  PendingOrder? _find(String key) =>
      _items.where((PendingOrder p) => p.key == key).firstOrNull;

  Future<void> _update(PendingOrder item) async {
    if (_find(item.key) == null) return;
    _items = <PendingOrder>[
      for (final PendingOrder p in _items) p.key == item.key ? item : p,
    ];
    await _writeQuietly();
    if (!_disposed) notifyListeners();
  }

  Future<void> _remove(String key) async {
    _items = _items.where((PendingOrder p) => p.key != key).toList();
    await _writeQuietly();
    if (!_disposed) notifyListeners();
  }

  Future<void> _write() async {
    final String? key = _storageKey;
    if (key == null) return;
    if (_items.isEmpty) {
      await _store.delete(key);
      return;
    }
    await _store.write(
      key,
      jsonEncode(<String, dynamic>{
        'items': _items.map((PendingOrder p) => p.toJson()).toList(),
      }),
    );
  }

  /// A status write that fails is not a lost order: the worst case is that, after a restart, an
  /// item comes back as it was before — and every way back is safe (a resend is answered with the
  /// existing order). Only [enqueue]'s write must succeed.
  Future<void> _writeQuietly() async {
    try {
      await _write();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _connectivity?.removeListener(_onConnectivity);
    _placed.close();
    super.dispose();
  }
}
