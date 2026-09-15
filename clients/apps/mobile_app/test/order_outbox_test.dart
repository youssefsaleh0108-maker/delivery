import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/offline_store.dart';
import 'package:mobile_app/src/order_outbox.dart';

/// The outbox's three promises, each pinned against the way it would break.
///
/// **Never lost silently**: a checkout queued offline has to outlive the app being swiped away,
/// with nothing in memory — only what the device's own store kept. **Never placed twice**: every
/// send of it, after any number of dropped connections and restarts, carries the one key the
/// server recognises. **Never charged at a price nobody saw**: a changed total, a refusal and a
/// checkout that waited too long all stop and wait for the customer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String owner = 'customer-1';
  const String storageKey = 'delivery.outbox.$owner';
  final DateTime base = DateTime.utc(2026, 9, 12, 18);

  /// Lets the unawaited sends a connectivity change starts run to completion.
  Future<void> settle() => pumpEventQueue(times: 50);

  PendingOrder pending({
    PaymentMethod method = PaymentMethod.cash,
    double total = 12.40,
    DateTime? createdAt,
  }) =>
      PendingOrder(
        submission: OrderSubmission(
          items: <OrderLineSubmission>[(productId: 'p1', qty: 2, optionIds: const <String>[])],
          deliveryAddress: '12 Rose Street',
          deliveryZoneId: 'zone-hamra',
          paymentMethod: method,
        ),
        expectedTotal: total,
        storeId: 's1',
        storeName: 'Dekkane Abou Selim',
        // Queued just now, by the same clock the outbox reads — anything older is a stale checkout
        // that asks before it goes, which is its own case below.
        createdAt: createdAt ?? DateTime.now(),
      );

  /// A pickup print run with a file and instructions for the provider, as the service order screen
  /// builds one — or, with pieces left out, a submission carrying only some of those fields.
  OrderSubmission printRun({
    Fulfilment? fulfilment = Fulfilment.pickup,
    List<String> files = const <String>['file-1'],
    String? instructions = 'Leave a white border',
  }) =>
      OrderSubmission(
        items: <OrderLineSubmission>[(productId: 'offer-1', qty: 2, optionIds: const <String>[])],
        deliveryAddress: fulfilment == Fulfilment.pickup ? '' : '12 Rose Street',
        fulfilment: fulfilment,
        attachmentFileIds: files,
        serviceInstructions: instructions,
      );

  PendingOrder pendingService(OrderSubmission submission, {bool maybePlaced = false}) =>
      PendingOrder(
        submission: submission,
        expectedTotal: 31.50,
        storeId: 'press-1',
        storeName: 'Hamra Press',
        createdAt: DateTime.now(),
        maybePlaced: maybePlaced,
      );

  group('across an app restart', () {
    const MethodChannel secureStorage =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

    /// What the device keeps between runs: the platform side of flutter_secure_storage, answered
    /// in-process. Everything above the channel — [SecureOfflineStore], the plugin's Dart side —
    /// is the code the app actually ships.
    final Map<String, String> device = <String, String>{};

    setUp(() {
      device.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorage, (MethodCall call) async {
        final Map<Object?, Object?> args =
            (call.arguments as Map<Object?, Object?>?) ?? const <Object?, Object?>{};
        final String? key = args['key'] as String?;
        switch (call.method) {
          case 'write':
            device[key!] = args['value']! as String;
            return null;
          case 'read':
            return device[key];
          case 'delete':
            device.remove(key);
            return null;
          case 'containsKey':
            return device.containsKey(key);
          case 'readAll':
            return Map<String, String>.of(device);
          case 'deleteAll':
            device.clear();
            return null;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorage, null);
    });

    test('a checkout queued offline is still there after the app is closed, and is placed once, '
        'with its own key, when the connection returns', () async {
      final _Server server = _Server();
      final ValueNotifier<bool> online = ValueNotifier<bool>(false);
      final PendingOrder queued = pending();

      // First run: no connection. The customer queues their checkout and swipes the app away.
      final OrderOutbox firstRun = OrderOutbox(
          api: server.api, store: const SecureOfflineStore(), ownerId: owner, connectivity: online);
      await firstRun.load();
      await firstRun.enqueue(queued);
      firstRun.dispose();

      expect(device.keys, contains(storageKey));
      expect(server.placements, isEmpty);

      // Second run: a new process. Nothing in memory survived; only what the device kept.
      final OrderOutbox secondRun = OrderOutbox(
          api: server.api, store: const SecureOfflineStore(), ownerId: owner, connectivity: online);
      addTearDown(secondRun.dispose);
      await secondRun.load();

      final PendingOrder restored = secondRun.items.single;
      expect(restored.key, queued.key);
      expect(restored.status, PendingOrderStatus.queued);
      expect(restored.storeName, 'Dekkane Abou Selim');
      expect(restored.expectedTotal, 12.40);

      online.value = true;
      await settle();

      expect(server.placements, hasLength(1));
      expect(server.keys.single, queued.key);
      expect((server.placements.single.data as Map<String, dynamic>)['expectedTotal'], 12.4);
      expect(secondRun.items, isEmpty);
      expect(device.containsKey(storageKey), isFalse);
    });
  });

  group('never placed twice', () {
    test('a checkout the app died sending is sent again with the same key, and the server\'s '
        'replay of the order ends it', () async {
      final _MemoryStore store = _MemoryStore();
      final PendingOrder inFlight = pending();
      // Written as the app left it: on the wire, answer unknown.
      store.values[storageKey] = jsonEncode(<String, dynamic>{
        'items': <Object>[
          <String, dynamic>{...inFlight.toJson(), 'status': 'sending'},
        ],
      });
      final _Server server = _Server()..replies.add(_Server.replayed);
      final OrderOutbox outbox = OrderOutbox(
          api: server.api, store: store, ownerId: owner, connectivity: ValueNotifier<bool>(true));
      addTearDown(outbox.dispose);
      final List<OutboxPlaced> placed = <OutboxPlaced>[];
      outbox.placed.listen(placed.add);

      await outbox.load();
      await settle();

      expect(server.keys, <Object?>[inFlight.key]);
      expect(outbox.items, isEmpty);
      expect(placed.single.pending.key, inFlight.key);
    });

    test('a send that never reached the platform stays queued, and goes again with the same key',
        () async {
      final _Server server = _Server()..replies.add(_Server.unreachable);
      final ValueNotifier<bool> online = ValueNotifier<bool>(true);
      final OrderOutbox outbox =
          OrderOutbox(api: server.api, store: _MemoryStore(), ownerId: owner, connectivity: online);
      addTearDown(outbox.dispose);
      final PendingOrder queued = pending();

      await outbox.enqueue(queued);
      await settle();

      // Not failed, not dropped: its outcome is unknown, and waiting is the only honest state.
      expect(outbox.items.single.status, PendingOrderStatus.queued);
      expect(server.placements, hasLength(1));

      online.value = false;
      online.value = true;
      await settle();

      expect(server.keys, <Object?>[queued.key, queued.key]);
      expect(outbox.items, isEmpty);
    });

    test('an attempt whose key already placed an order ends as that order', () async {
      final _Server server = _Server()
        ..replies.add(_Server.refused(409, <String, dynamic>{
          'code': 'IDEMPOTENCY_KEY_REUSED',
          'orderId': 'order-earlier',
        }));
      final OrderOutbox outbox = OrderOutbox(
          api: server.api, store: _MemoryStore(), ownerId: owner, connectivity: ValueNotifier<bool>(true));
      addTearDown(outbox.dispose);
      final List<OutboxPlaced> placed = <OutboxPlaced>[];
      outbox.placed.listen(placed.add);

      await outbox.enqueue(pending());
      await settle();

      expect(server.placements, hasLength(1));
      expect(placed.single.order.id, 'order-earlier');
      expect(placed.single.earlierAttempt, isTrue);
      expect(outbox.items, isEmpty);
    });

    test('sends oldest first when the connection returns', () async {
      final _Server server = _Server();
      final ValueNotifier<bool> online = ValueNotifier<bool>(false);
      final OrderOutbox outbox =
          OrderOutbox(api: server.api, store: _MemoryStore(), ownerId: owner, connectivity: online);
      addTearDown(outbox.dispose);
      final List<PendingOrder> queued = <PendingOrder>[pending(), pending(), pending()];

      for (final PendingOrder p in queued) {
        await outbox.enqueue(p);
      }
      online.value = true;
      await settle();

      expect(server.keys, queued.map((PendingOrder p) => p.key).toList());
    });
  });

  group('never at a price nobody saw', () {
    test('a changed total stops it until the customer confirms, and then sends at that total',
        () async {
      final _Server server = _Server()
        ..replies.add(_Server.refused(409, <String, dynamic>{
          'code': 'PRICE_CHANGED',
          'total': 13.90,
          'expectedTotal': 12.40,
        }));
      final ValueNotifier<bool> online = ValueNotifier<bool>(true);
      final OrderOutbox outbox =
          OrderOutbox(api: server.api, store: _MemoryStore(), ownerId: owner, connectivity: online);
      addTearDown(outbox.dispose);
      final PendingOrder queued = pending();

      await outbox.enqueue(queued);
      await settle();

      final PendingOrder review = outbox.items.single;
      expect(review.status, PendingOrderStatus.needsReview);
      expect(review.review, PendingReview.priceChanged);
      expect(review.newTotal, 13.90);

      // Reconnecting, or anything else that drains, does not send it on the customer's behalf.
      online.value = false;
      online.value = true;
      await outbox.drain();
      await settle();
      expect(server.placements, hasLength(1));

      await outbox.confirm(queued.key);
      await settle();

      expect(server.keys, <Object?>[queued.key, queued.key]);
      expect((server.placements.last.data as Map<String, dynamic>)['expectedTotal'], 13.9);
      expect(outbox.items, isEmpty);
    });

    test('a refused order is not retried by itself, says why, and can be tried again', () async {
      final _Server server = _Server()
        ..replies.add(_Server.refused(
            422, <String, dynamic>{'detail': 'Dekkane Abou Selim is closed right now'}));
      final ValueNotifier<bool> online = ValueNotifier<bool>(true);
      final OrderOutbox outbox =
          OrderOutbox(api: server.api, store: _MemoryStore(), ownerId: owner, connectivity: online);
      addTearDown(outbox.dispose);
      final PendingOrder queued = pending();

      await outbox.enqueue(queued);
      await settle();

      expect(outbox.items.single.status, PendingOrderStatus.failed);
      expect(outbox.items.single.error, 'Dekkane Abou Selim is closed right now');

      online.value = false;
      online.value = true;
      await settle();
      expect(server.placements, hasLength(1));

      await outbox.retry(queued.key);
      await settle();

      expect(server.keys, <Object?>[queued.key, queued.key]);
      expect(outbox.items, isEmpty);
    });

    test('a checkout that waited too long asks before it goes', () async {
      DateTime clock = base;
      final _Server server = _Server();
      final ValueNotifier<bool> online = ValueNotifier<bool>(false);
      final OrderOutbox outbox = OrderOutbox(
        api: server.api,
        store: _MemoryStore(),
        ownerId: owner,
        connectivity: online,
        now: () => clock,
      );
      addTearDown(outbox.dispose);
      final PendingOrder queued = pending(createdAt: base);
      await outbox.enqueue(queued);

      // The connection comes back after dinner is long over.
      clock = base.add(outbox.staleAfter + const Duration(minutes: 1));
      online.value = true;
      await settle();

      expect(server.placements, isEmpty);
      expect(outbox.items.single.status, PendingOrderStatus.needsReview);
      expect(outbox.items.single.review, PendingReview.stale);

      await outbox.confirm(queued.key);
      await settle();

      expect(server.keys, <Object?>[queued.key]);
      expect(outbox.items, isEmpty);
    });

    test('a server error is tried again by itself, later, with the same key', () async {
      final _Server server = _Server()
        ..replies.add(_Server.refused(503, <String, dynamic>{'detail': 'down for a moment'}));
      final OrderOutbox outbox = OrderOutbox(
        api: server.api,
        store: _MemoryStore(),
        ownerId: owner,
        connectivity: ValueNotifier<bool>(true),
        retryDelay: const Duration(milliseconds: 10),
      );
      addTearDown(outbox.dispose);
      final PendingOrder queued = pending();

      await outbox.enqueue(queued);
      await settle();
      expect(outbox.items.single.status, PendingOrderStatus.queued);

      await Future<void>.delayed(const Duration(milliseconds: 40));
      await settle();

      expect(server.keys, <Object?>[queued.key, queued.key]);
      expect(outbox.items, isEmpty);
    });
  });

  group('never called unsent when it may not be', () {
    /// The request left and no answer came back: the order may or may not exist.
    void unanswered(RequestOptions o, RequestInterceptorHandler h) =>
        h.reject(DioException(requestOptions: o, type: DioExceptionType.receiveTimeout));

    OrderOutbox outboxOver(_Server server, {_MemoryStore? store, bool online = true}) {
      final OrderOutbox outbox = OrderOutbox(
        api: server.api,
        store: store ?? _MemoryStore(),
        ownerId: owner,
        connectivity: ValueNotifier<bool>(online),
        retryDelay: const Duration(milliseconds: 10),
      );
      addTearDown(outbox.dispose);
      return outbox;
    }

    test('a send whose answer never came is marked as maybe placed, and stays marked across a '
        'restart', () async {
      final _MemoryStore store = _MemoryStore();
      final _Server server = _Server()..replies.add(unanswered);
      final OrderOutbox firstRun = OrderOutbox(
        api: server.api,
        store: store,
        ownerId: owner,
        connectivity: ValueNotifier<bool>(true),
        // Not retried during the test: what is on the phone after the silence is the point.
        retryDelay: const Duration(hours: 1),
      );
      final PendingOrder queued = pending();

      await firstRun.enqueue(queued);
      await settle();

      expect(firstRun.items.single.status, PendingOrderStatus.queued);
      expect(firstRun.items.single.maybePlaced, isTrue);
      firstRun.dispose();

      final OrderOutbox secondRun = outboxOver(_Server(), store: store, online: false);
      await secondRun.load();

      expect(secondRun.items.single.key, queued.key);
      expect(secondRun.items.single.maybePlaced, isTrue);
    });

    test('so is a checkout the app stopped in the middle of sending', () async {
      final _MemoryStore store = _MemoryStore();
      final PendingOrder inFlight = pending();
      store.values[storageKey] = jsonEncode(<String, dynamic>{
        'items': <Object>[
          <String, dynamic>{...inFlight.toJson(), 'status': 'sending'},
        ],
      });
      final OrderOutbox outbox = outboxOver(_Server(), store: store, online: false);

      await outbox.load();

      expect(outbox.items.single.status, PendingOrderStatus.queued);
      expect(outbox.items.single.maybePlaced, isTrue);
    });

    test('a connection that was never made proves nothing left, and marks nothing', () async {
      final _Server server = _Server()
        ..replies.add((RequestOptions o, RequestInterceptorHandler h) =>
            h.reject(DioException(requestOptions: o, type: DioExceptionType.connectionTimeout)));
      final OrderOutbox outbox = outboxOver(server);

      await outbox.enqueue(pending());
      await settle();

      expect(server.placements, hasLength(1));
      expect(outbox.items.single.maybePlaced, isFalse);
    });

    test('a changed price clears the mark: Order Manager prices only what no key has placed',
        () async {
      final _Server server = _Server()
        ..replies.add(unanswered)
        ..replies.add(_Server.refused(409, <String, dynamic>{
          'code': 'PRICE_CHANGED',
          'total': 13.90,
          'expectedTotal': 12.40,
        }));
      final OrderOutbox outbox = outboxOver(server);

      await outbox.enqueue(pending());
      await settle();
      expect(outbox.items.single.maybePlaced, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 40));
      await settle();

      expect(server.placements, hasLength(2));
      expect(outbox.items.single.review, PendingReview.priceChanged);
      expect(outbox.items.single.maybePlaced, isFalse);
    });

    test('a business-rule refusal clears it too; a refusal from before the key is read does not',
        () async {
      Future<PendingOrder> refusedAfterSilence(int status) async {
        final _Server server = _Server()
          ..replies.add(unanswered)
          ..replies.add(_Server.refused(status, <String, dynamic>{'detail': 'refused'}));
        final OrderOutbox outbox = outboxOver(server);
        await outbox.enqueue(pending());
        await settle();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await settle();
        return outbox.items.single;
      }

      final PendingOrder ruleRefusal = await refusedAfterSilence(422);
      expect(ruleRefusal.status, PendingOrderStatus.failed);
      expect(ruleRefusal.maybePlaced, isFalse);

      // A malformed request is turned away before Order Manager looks the key up, so the earlier
      // silent send may still have placed it.
      final PendingOrder malformed = await refusedAfterSilence(400);
      expect(malformed.status, PendingOrderStatus.failed);
      expect(malformed.maybePlaced, isTrue);
    });
  });

  group('what may be queued, and by whom', () {
    test('only cash: a card hold cannot be decided offline, and its token is never written down',
        () async {
      final _MemoryStore store = _MemoryStore();
      final OrderOutbox outbox = OrderOutbox(
          api: _Server().api, store: store, ownerId: owner, connectivity: ValueNotifier<bool>(false));
      addTearDown(outbox.dispose);

      await expectLater(outbox.enqueue(pending(method: PaymentMethod.card)), throwsArgumentError);

      expect(outbox.items, isEmpty);
      expect(store.values, isEmpty);
    });

    test('never a service order: one is always cash, so its own fields are what stop it', () async {
      final _MemoryStore store = _MemoryStore();
      final _Server server = _Server();
      final OrderOutbox outbox = OrderOutbox(
          api: server.api, store: store, ownerId: owner, connectivity: ValueNotifier<bool>(true));
      addTearDown(outbox.dispose);

      for (final OrderSubmission submission in <OrderSubmission>[
        printRun(),
        printRun(fulfilment: Fulfilment.delivery, files: const <String>[], instructions: null),
        printRun(fulfilment: null, instructions: null),
        printRun(fulfilment: null, files: const <String>[]),
      ]) {
        await expectLater(outbox.enqueue(pendingService(submission)), throwsArgumentError,
            reason: '${submission.toJson()}');
      }

      expect(outbox.items, isEmpty);
      expect(store.values, isEmpty);
      await settle();
      expect(server.placements, isEmpty);
    });

    test('a checkout that cannot be written to the phone is not queued, and says so', () async {
      final _MemoryStore store = _MemoryStore()..failWrites = true;
      final OrderOutbox outbox = OrderOutbox(
          api: _Server().api, store: store, ownerId: owner, connectivity: ValueNotifier<bool>(false));
      addTearDown(outbox.dispose);

      await expectLater(outbox.enqueue(pending()), throwsA(isA<OutboxWriteException>()));

      expect(outbox.items, isEmpty);
    });

    test('another account on the same phone neither sees nor sends it', () async {
      final _MemoryStore store = _MemoryStore();
      final _Server server = _Server();
      final OrderOutbox mine = OrderOutbox(
          api: server.api, store: store, ownerId: owner, connectivity: ValueNotifier<bool>(false));
      await mine.enqueue(pending());
      mine.dispose();

      final OrderOutbox theirs = OrderOutbox(
          api: server.api,
          store: store,
          ownerId: 'customer-2',
          connectivity: ValueNotifier<bool>(true));
      addTearDown(theirs.dispose);
      await theirs.load();
      await settle();

      expect(theirs.items, isEmpty);
      expect(server.placements, isEmpty);
    });

    test('discarding removes it from the phone for good', () async {
      final _MemoryStore store = _MemoryStore();
      final OrderOutbox outbox = OrderOutbox(
          api: _Server().api, store: store, ownerId: owner, connectivity: ValueNotifier<bool>(false));
      addTearDown(outbox.dispose);
      final PendingOrder queued = pending();
      await outbox.enqueue(queued);

      await outbox.discard(queued.key);

      expect(outbox.items, isEmpty);
      expect(store.values, isEmpty);
    });
  });

  group('a service order found in the outbox all the same', () {
    /// What another build, or a bug, could have left on the phone. [OrderOutbox.enqueue] refuses a
    /// service order, so it is written straight to the store, as the app would find it on starting.
    Future<OrderOutbox> restoredWith(_Server server, PendingOrder item) async {
      final _MemoryStore store = _MemoryStore()
        ..values[storageKey] = jsonEncode(<String, dynamic>{
          'items': <Object>[item.toJson()],
        });
      final OrderOutbox outbox = OrderOutbox(
        api: server.api,
        store: store,
        ownerId: owner,
        connectivity: ValueNotifier<bool>(true),
        retryDelay: const Duration(milliseconds: 200),
      );
      addTearDown(outbox.dispose);
      await outbox.load();
      await settle();
      return outbox;
    }

    test('refused by a rule of its own, it fails with the server\'s words, and nothing says it may '
        'exist', () async {
      final _Server server = _Server()
        ..replies.add(_Server.refused(422, <String, dynamic>{
          'title': 'Attachment refused',
          'status': 422,
          'detail': 'One of the files has been deleted; upload it again',
          'code': 'EXPIRED',
        }));
      final PendingOrder item = pendingService(printRun(), maybePlaced: true);

      final OrderOutbox outbox = await restoredWith(server, item);

      expect(server.keys, <Object?>[item.key]);
      final PendingOrder failed = outbox.items.single;
      expect(failed.status, PendingOrderStatus.failed);
      expect(failed.error, 'One of the files has been deleted; upload it again');
      expect(failed.maybePlaced, isFalse);
    });

    test('an unreadable services directory puts it back in the queue unmarked, and it goes again '
        'later with the same key', () async {
      final _Server server = _Server()
        ..replies.add(_Server.refused(503, <String, dynamic>{
          'title': 'Temporarily unavailable',
          'status': 503,
          'code': 'SERVICES_DIRECTORY_UNAVAILABLE',
        }));
      final PendingOrder item = pendingService(printRun());

      final OrderOutbox outbox = await restoredWith(server, item);

      final PendingOrder waiting = outbox.items.single;
      expect(waiting.status, PendingOrderStatus.queued);
      // Unlike an unlabelled 503, this one proves nothing was placed, so nothing says it may have been.
      expect(waiting.maybePlaced, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 400));
      await settle();

      expect(server.keys, <Object?>[item.key, item.key]);
      expect(outbox.items, isEmpty);
    });
  });
}

/// The phone's storage, in memory — with a switch for a disk that refuses to write.
class _MemoryStore implements OfflineStore {
  final Map<String, String> values = <String, String>{};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw const FileSystemLikeFailure();
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class FileSystemLikeFailure implements Exception {
  const FileSystemLikeFailure();
}

typedef _Reply = void Function(RequestOptions o, RequestInterceptorHandler h);

/// Order Manager, answered in-process: each placement gets the next scripted reply (a new order
/// once the script runs out), and a read of an order returns it.
class _Server {
  _Server() {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        if (o.method == 'POST' && o.path == '/api/orders') {
          placements.add(o);
          (replies.isEmpty ? created : replies.removeAt(0))(o, h);
          return;
        }
        if (o.method == 'GET' && o.path.startsWith('/api/orders/')) {
          h.resolve(Response<dynamic>(
              requestOptions: o,
              statusCode: 200,
              data: order(o.path.substring('/api/orders/'.length))));
          return;
        }
        h.reject(DioException(
          requestOptions: o,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(requestOptions: o, statusCode: 404),
        ));
      },
    ));
  }

  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway.test'));
  late final OrderApi api = OrderApi(dio);
  final List<RequestOptions> placements = <RequestOptions>[];
  final List<_Reply> replies = <_Reply>[];

  List<Object?> get keys =>
      placements.map((RequestOptions o) => o.headers[OrderApi.idempotencyKeyHeader]).toList();

  static Map<String, dynamic> order(String id) => <String, dynamic>{
        'id': id,
        'customerId': 'customer-1',
        'merchantId': 'm1',
        'riderId': null,
        'status': 'PLACED',
        'totalAmount': 12.40,
        'deliveryAddress': '12 Rose Street',
        'paymentMethod': 'CASH',
        'paymentStatus': 'DUE',
        'items': <dynamic>[],
        'availableActions': <dynamic>[],
      };

  static void created(RequestOptions o, RequestInterceptorHandler h) => h.resolve(
      Response<dynamic>(requestOptions: o, statusCode: 201, data: order('order-new')));

  static void replayed(RequestOptions o, RequestInterceptorHandler h) => h.resolve(
      Response<dynamic>(requestOptions: o, statusCode: 200, data: order('order-first')));

  static void unreachable(RequestOptions o, RequestInterceptorHandler h) =>
      h.reject(DioException(requestOptions: o, type: DioExceptionType.connectionError));

  static _Reply refused(int code, Map<String, dynamic> body) =>
      (RequestOptions o, RequestInterceptorHandler h) => h.reject(DioException(
            requestOptions: o,
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(requestOptions: o, statusCode: code, data: body),
          ));
}
