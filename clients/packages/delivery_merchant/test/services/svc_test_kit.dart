import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the provider screens' tests share: a service order as Order Manager sends one, fakes for the
/// clients those screens call, the platform's LBP rate, and the net that catches English on an
/// Arabic screen.

/// A service order exactly as `DeliveryOrder.fromJson` reads the wire, so every test goes through the
/// parsing the app does. Ids are digits up front, so a short id carries no Latin letter.
DeliveryOrder svcOrder({
  String id = '11111111-0000',
  String status = 'PLACED',
  String fulfilment = 'PICKUP',
  String? customer = 'Jean-Pierre D.',
  String product = 'Business Card Printing',
  String? unitLabel = 'cards',
  int unitSize = 500,
  int packs = 2,
  String? options = 'Matte finish',
  double subtotal = 15,
  double? total,
  List<String> actions = const <String>['ACCEPT', 'CANCEL'],
  Duration placedAgo = const Duration(minutes: 10),
  DateTime? estimatedReadyAt,
  DateTime? uncollectedCancellableAt,
  String? cancelReason,
  String? instructions,
  String? prompt,
  int? turnaroundMin = 24,
  int? turnaroundMax = 48,
  String address = '',
  String? riderId,
}) {
  return DeliveryOrder.fromJson(<String, dynamic>{
    'id': id,
    'customerId': 'customer-sub',
    'merchantId': 'merchant-sub',
    'status': status,
    'kind': 'SERVICE',
    'fulfilment': fulfilment,
    'serviceCategory': 'PRINTING',
    'customerDisplayName': customer,
    'subtotal': subtotal,
    'totalAmount': total ?? subtotal,
    'deliveryAddress': address,
    'paymentMethod': 'CASH',
    if (riderId != null) 'riderId': riderId,
    'availableActions': actions,
    'placedAt': DateTime.now().subtract(placedAgo).toUtc().toIso8601String(),
    if (estimatedReadyAt != null) 'estimatedReadyAt': estimatedReadyAt.toUtc().toIso8601String(),
    if (uncollectedCancellableAt != null)
      'uncollectedCancellableAt': uncollectedCancellableAt.toUtc().toIso8601String(),
    'cancelReason': cancelReason,
    'items': <Map<String, dynamic>>[
      <String, dynamic>{
        'productId': 'offer-1',
        'productName': product,
        'unitPrice': subtotal / packs,
        'qty': packs,
        'lineTotal': subtotal,
        'optionsSummary': options,
        'service': <String, dynamic>{
          'unitLabel': unitLabel,
          'unitSize': unitSize,
          'pricingType': 'FIXED',
          'turnaroundMinHours': turnaroundMin,
          'turnaroundMaxHours': turnaroundMax,
          'attachmentPolicy': 'OPTIONAL',
          'instructionsPrompt': prompt,
          'instructions': instructions,
        },
      },
    ],
  });
}

/// Order Manager for the provider screens: the queue it holds, and a record of every call made.
class FakeServiceOrders extends OrderApi {
  FakeServiceOrders(this.orders) : super(Dio());

  List<DeliveryOrder> orders;

  /// Thrown by the queue read while set.
  Object? failList;

  /// Holds the queue read until completed.
  Completer<void>? holdList;

  /// Holds each queue read on a completer of its own, added to [heldLists] in the order the reads
  /// began, so a test can answer a later read before an earlier one.
  bool holdEachList = false;
  final List<Completer<void>> heldLists = <Completer<void>>[];

  /// Answers every state whatever was asked, as an Order Manager from before the status filter does.
  bool ignoresStatus = false;

  /// Holds the order read, and the order's actions, until completed.
  Completer<void>? holdRead;
  Completer<void>? holdAct;

  OrderKind? lastKind;

  /// Every queue read as `page STATUS,STATUS` — `0 PLACED,ACCEPTED` — in the order they were made.
  final List<String> lists = <String>[];

  final List<String> calls = <String>[];

  DeliveryOrder Function(String id, OrderAction action)? onAct;
  ServiceOrderActionResult Function(String id, DeclineReason reason)? onDecline;
  ServiceOrderActionResult Function(String id)? onCollected;
  ServiceOrderActionResult Function(String id, String? note)? onCancelNotCollected;

  int count(String call) => calls.where((String c) => c == call).length;

  /// What the trading summary answers; [summaryOf] by default.
  MerchantSummary? summary;
  Object? failSummary;

  /// The window the last summary read asked for.
  int? summaryDays;

  /// A summary with [weekOrders] orders placed in its window.
  static MerchantSummary summaryOf({int weekOrders = 12, int awaitingYou = 0}) =>
      MerchantSummary.fromJson(<String, dynamic>{
        'windowDays': 7,
        'days': <Object>[],
        'today': <String, dynamic>{'day': '2026-09-14', 'orders': 2},
        'yesterday': <String, dynamic>{'day': '2026-09-13', 'orders': 1},
        'window': <String, dynamic>{'orders': weekOrders, 'delivered': 9},
        'awaitingYou': awaitingYou,
      });

  @override
  Future<MerchantSummary> merchantSummary({int days = 14}) async {
    calls.add('summary $days');
    summaryDays = days;
    final Object? failure = failSummary;
    if (failure != null) throw failure;
    return summary ?? summaryOf();
  }

  @override
  Future<Paged<DeliveryOrder>> forMerchant({
    int page = 0,
    int size = 20,
    OrderKind? kind,
    Fulfilment? fulfilment,
    Iterable<OrderStatus>? statuses,
  }) async {
    calls.add('list');
    lastKind = kind;
    final List<OrderStatus> asked = statuses?.toList() ?? const <OrderStatus>[];
    lists.add('$page ${asked.map((OrderStatus s) => s.wire).join(',')}');
    // What the server holds when the read arrives, not when it answers — which a held read lets a test
    // choose.
    final List<DeliveryOrder> matching = <DeliveryOrder>[
      for (final DeliveryOrder order in orders)
        if (ignoresStatus || asked.isEmpty || asked.contains(order.status)) order,
    ];
    await holdList?.future;
    if (holdEachList) {
      final Completer<void> held = Completer<void>();
      heldLists.add(held);
      await held.future;
    }
    final Object? failure = failList;
    if (failure != null) throw failure;
    final int start = page * size;
    return Paged<DeliveryOrder>(
      content: start >= matching.length
          ? const <DeliveryOrder>[]
          : matching.sublist(start, math.min(start + size, matching.length)),
      page: page,
      totalElements: matching.length,
      totalPages: (matching.length + size - 1) ~/ size,
    );
  }

  @override
  Future<DeliveryOrder> read(String orderId) async {
    calls.add('read $orderId');
    await holdRead?.future;
    return orders.firstWhere((DeliveryOrder o) => o.id == orderId);
  }

  @override
  Future<DeliveryOrder> act(String orderId, OrderAction action, {String? reason}) async {
    calls.add('act ${action.wire} $orderId');
    await holdAct?.future;
    return onAct!(orderId, action);
  }

  @override
  Future<ServiceOrderActionResult> decline(String orderId, DeclineReason reason) async {
    calls.add('decline ${reason.wire} $orderId');
    return onDecline!(orderId, reason);
  }

  @override
  Future<ServiceOrderActionResult> collected(String orderId) async {
    calls.add('collected $orderId');
    return onCollected!(orderId);
  }

  @override
  Future<ServiceOrderActionResult> cancelNotCollected(String orderId, {String? note}) async {
    calls.add('notCollected $orderId ${note ?? ''}'.trim());
    return onCancelNotCollected!(orderId, note);
  }
}

/// Order Manager's attachment read for one order.
class FakeOrderFiles extends OrderAttachmentApi {
  FakeOrderFiles(this.files) : super(Dio());

  List<OrderAttachment> files;
  Object? fail;
  Completer<void>? hold;
  int reads = 0;

  @override
  Future<List<OrderAttachment>> forOrder(String orderId) async {
    reads++;
    await hold?.future;
    final Object? failure = fail;
    if (failure != null) throw failure;
    return files;
  }
}

/// The shop's conversations with its customers: an inbox with nobody in it, and "chat with the
/// customer" on an order, which answers a thread about that order unless a test has it refuse
/// ([failOpen]) or wait ([holdOpen]). Implemented rather than extended, so a call no test expected
/// fails here instead of reaching a real Dio.
class FakeShopChat implements ShopChatApi {
  FakeShopChat({this.customerName = 'Jean-Pierre D.'});

  /// Who the threads it opens are with, as the shop sees them.
  final String? customerName;

  /// Every order "chat with the customer" was asked about, in the order asked.
  final List<String> opened = <String>[];

  /// Thrown by [openForOrder] while set: a [ShopOrderChatClosedException], or a 404 or 503 as Dio
  /// throws them ([svcHttpError]).
  Object? failOpen;

  /// Holds [openForOrder] until completed.
  Completer<void>? holdOpen;

  final Map<String, ShopThread> _threads = <String, ShopThread>{};

  /// The thread the server opens for [orderId]: the shop's side, open, labelled with the order's
  /// first eight characters as its order screens print them.
  ShopThread threadFor(String orderId) => ShopThread(
        id: 'thread-$orderId',
        storeId: 'shop-1',
        storeName: 'Al Fakhry Press',
        customerName: customerName,
        yourSide: ShopThreadSide.shop,
        open: true,
        lastSequence: 0,
        unread: 0,
        orderId: orderId,
        orderShortId: orderId.length <= 8 ? orderId : orderId.substring(0, 8),
        orderKind: OrderKind.service,
      );

  @override
  Future<ShopThread> openForOrder(String orderId) async {
    opened.add(orderId);
    await holdOpen?.future;
    final Object? failure = failOpen;
    if (failure != null) throw failure;
    final ShopThread thread = threadFor(orderId);
    _threads[thread.id] = thread;
    return thread;
  }

  @override
  Future<List<ShopThread>> inbox() async => const <ShopThread>[];

  /// A conversation nobody has written in yet.
  @override
  Future<ShopThreadPage> messages(String threadId, {int afterSequence = 0}) async =>
      ShopThreadPage(thread: _threads[threadId]!, messages: const <ShopMessage>[], more: false);

  @override
  Future<int> markRead(String threadId, {required int upToSequence}) async => 0;

  @override
  Future<ShopThread> openWithStore(String storeId, {String? orderId}) =>
      throw UnimplementedError('a customer opens a thread with a shop; these screens are the shop\'s');

  @override
  Future<ShopMessage> send(String threadId, String text, {String? clientMessageId}) =>
      throw UnimplementedError('no provider screen test sends a message');
}

/// Sets the platform's LBP rate the way the app does, through `/api/market/config`.
Future<void> svcUseLbpRate(double rate) async {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = _RateAdapter(rate);
  await MarketRates.instance.load(dio);
}

class _RateAdapter implements HttpClientAdapter {
  _RateAdapter(this.rate);

  final double rate;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{'lbpPerUsd': rate}),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Pumps [child] as a host would: inside a Scaffold, in [locale], on a [size] screen.
Future<void> pumpSvc(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
  Size size = const Size(420, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: DeliveryTheme.light(),
    locale: locale,
    localizationsDelegates: DeliveryStrings.localizationsDelegates,
    supportedLocales: DeliveryStrings.supportedLocales,
    home: Scaffold(body: child),
  ));
  await tester.pump();
  await tester.pump();
}

/// Lets pending reads answer and the frames they cause be drawn.
Future<void> svcSettle(WidgetTester tester) async {
  for (int i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A service offer as Product Service sends it. Its photo is a stored key with no URL: publishing
/// counts it, and no test fetches an image over the network.
Product svcOffer({
  String id = 'offer-1',
  String name = 'Business Card Printing',
  ProductStatus status = ProductStatus.active,
  double price = 15,
  double? fromPrice,
  ServicePricingType pricing = ServicePricingType.fixed,
  String? unitLabel = 'cards',
  int unitSize = 500,
  ServiceFulfilment fulfilment = ServiceFulfilment.pickup,
  ServiceAttachmentPolicy files = ServiceAttachmentPolicy.optional,
  bool photo = true,
  int? turnaroundMin = 24,
  int? turnaroundMax = 48,
  String? prompt,
  bool takenDown = false,
  String? takenDownReason,
}) {
  return Product(
    id: id,
    merchantId: 'merchant-sub',
    storeId: 'shop-1',
    name: name,
    price: price,
    fromPrice: fromPrice,
    // Taken down is archived, as Product Service leaves it, with the hold beside it.
    status: takenDown ? ProductStatus.archived : status,
    moderation: takenDown
        ? ProductModeration(state: ProductModerationState.takenDown, reason: takenDownReason)
        : null,
    imageRefs: photo ? <String>['products/$id/photo.jpg'] : const <String>[],
    service: ServiceTerms(
      pricingType: pricing,
      fulfilmentModes: fulfilment,
      unitLabel: unitLabel,
      unitSize: unitSize,
      turnaroundMinHours: turnaroundMin,
      turnaroundMaxHours: turnaroundMax,
      attachmentPolicy: files,
      instructionsPrompt: prompt,
    ),
  );
}

/// A services shop as `GET /api/stores/mine` lists it.
Store svcShop({
  String id = 'shop-1',
  String name = 'Al Fakhry Press',
  bool verifiedLocal = false,
  double? rating,
  int ratingCount = 0,
  double? lat,
  double? lng,
  String? neighborhood = 'Mar Mikhael',
  String vertical = 'SERVICES',
}) {
  return Store.fromJson(<String, dynamic>{
    'id': id,
    'slug': 'shop-$id',
    'name': name,
    'vertical': vertical,
    'serviceCategory': vertical == 'SERVICES' ? 'PRINTING' : null,
    'verifiedLocal': verifiedLocal,
    'rating': rating,
    'ratingCount': ratingCount,
    'latitude': lat,
    'longitude': lng,
    'neighborhood': neighborhood,
  });
}

/// An HTTP refusal, as Dio throws one — with the `code` Product Service names some refusals by.
DioException svcHttpError(int status, {String? code}) {
  final RequestOptions request = RequestOptions(path: '/api');
  return DioException(
    requestOptions: request,
    response: Response<dynamic>(
      requestOptions: request,
      statusCode: status,
      data: <String, dynamic>{'title': 'refused', if (code != null) 'code': code},
    ),
  );
}

/// Product Service's catalogue for one provider: the offers it holds, and every call made.
class FakeOffers extends CatalogApi {
  FakeOffers(this.offers) : super(Dio());

  List<Product> offers;
  Object? failList;
  Completer<void>? holdList;
  Object? failCreate;
  Object? failUpdate;
  Object? failPublish;
  Object? failPause;
  Object? failResume;
  final List<String> calls = <String>[];

  /// What the next reads of one offer answer, in order, before the catalogue as it stands.
  final List<Product> nextReads = <Product>[];

  /// How many times one offer was read.
  int reads = 0;

  /// The request bodies of every create and update, as the app sends them.
  final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];

  Product _moved(String id, ProductStatus status) {
    final Product p = offers.firstWhere((Product o) => o.id == id);
    final Product moved = Product(
      id: p.id,
      merchantId: p.merchantId,
      storeId: p.storeId,
      name: p.name,
      description: p.description,
      price: p.price,
      fromPrice: p.fromPrice,
      status: status,
      imageRefs: p.imageRefs,
      service: p.service,
      moderation: p.moderation,
    );
    offers = <Product>[for (final Product o in offers) o.id == id ? moved : o];
    return moved;
  }

  @override
  Future<Paged<Product>> myProducts({
    String? storeId,
    ProductStatus? status,
    int page = 0,
    int size = 20,
  }) async {
    calls.add('mine ${status?.wireValue ?? 'ALL'} ${storeId ?? '-'} $size');
    await holdList?.future;
    final Object? failure = failList;
    if (failure != null) throw failure;
    final List<Product> found =
        offers.where((Product o) => status == null || o.status == status).toList();
    return Paged<Product>(
      content: found.length > size ? found.sublist(0, size) : found,
      page: 0,
      totalElements: found.length,
      totalPages: 1,
    );
  }

  @override
  Future<Product> read(String id) async {
    reads++;
    if (nextReads.isNotEmpty) return nextReads.removeAt(0);
    return offers.firstWhere((Product o) => o.id == id);
  }

  @override
  Future<Product> create(Product product) async {
    calls.add('create');
    sent.add(product.toRequestJson());
    final Object? failure = failCreate;
    if (failure != null) throw failure;
    final Product created = Product(
      id: 'offer-new',
      merchantId: 'merchant-sub',
      storeId: product.storeId,
      name: product.name,
      description: product.description,
      price: product.price,
      status: ProductStatus.draft,
      service: product.service,
    );
    offers = <Product>[...offers, created];
    return created;
  }

  @override
  Future<Product> update(String id, Product product) async {
    calls.add('update $id');
    sent.add(product.toRequestJson());
    final Object? failure = failUpdate;
    if (failure != null) throw failure;
    final Product current = offers.firstWhere((Product o) => o.id == id);
    final Product updated = Product(
      id: id,
      merchantId: current.merchantId,
      storeId: product.storeId,
      name: product.name,
      description: product.description,
      price: product.price,
      status: current.status,
      imageRefs: current.imageRefs,
      service: product.service,
      moderation: current.moderation,
    );
    offers = <Product>[for (final Product o in offers) o.id == id ? updated : o];
    return updated;
  }

  @override
  Future<Product> publish(String id) async {
    calls.add('publish $id');
    final Object? failure = failPublish;
    if (failure != null) throw failure;
    return _moved(id, ProductStatus.active);
  }

  @override
  Future<Product> pause(String id) async {
    calls.add('pause $id');
    final Object? failure = failPause;
    if (failure != null) throw failure;
    return _moved(id, ProductStatus.paused);
  }

  @override
  Future<Product> resume(String id) async {
    calls.add('resume $id');
    final Object? failure = failResume;
    if (failure != null) throw failure;
    return _moved(id, ProductStatus.active);
  }

  @override
  Future<Product> archive(String id) async {
    calls.add('archive $id');
    return _moved(id, ProductStatus.archived);
  }
}

/// The shops a provider owns, and no option groups on any offer.
class FakeStores extends StoreApi {
  FakeStores(this.stores) : super(Dio());

  List<Store> stores;
  Object? failMine;
  int mineReads = 0;

  @override
  Future<Paged<Store>> mine({int page = 0, int size = 20}) async {
    mineReads++;
    final Object? failure = failMine;
    if (failure != null) throw failure;
    return Paged<Store>(content: stores, page: 0, totalElements: stores.length, totalPages: 1);
  }

  @override
  Future<List<OptionGroup>> productOptions(String productId) async => const <OptionGroup>[];
}

/// A shop's delivery areas: none.
class FakeNoZones extends DeliveryZoneApi {
  FakeNoZones() : super(Dio());

  @override
  Future<List<ZoneCoverage>> coverage(String storeId) async => const <ZoneCoverage>[];
}

final RegExp _latin = RegExp('[A-Za-z]');

/// Every string on screen with a Latin letter in it, less [ignoring] — the merchant's own data, which
/// is theirs to write in any script.
List<String> svcLatinText(WidgetTester tester, {Set<String> ignoring = const <String>{}}) {
  return <String>[
    for (final Text text in tester.widgetList<Text>(find.byType(Text)))
      if (text.data case final String value)
        if (!ignoring.contains(value) && _latin.hasMatch(value)) value,
  ];
}
