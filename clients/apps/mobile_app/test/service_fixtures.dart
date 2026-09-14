import 'dart:async';

import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the Services tab's screen tests share (Figma 126:285, 126:371, 126:437, 126:507): a server
/// that answers in-process, the app shell around a screen, and the wire shapes of a service shop, an
/// offer, a quote and a service order.
///
/// Not a test file (no `_test` suffix); the screens' tests import it.

/// What a route answers: a body for a 200, a [FakeReply] for any other status, a future of either —
/// or a thrown [DioException] for a request that never got an answer.
typedef FakeAnswer = FutureOr<Object?> Function(RequestOptions request);

/// A non-200 answer.
class FakeReply {
  const FakeReply(this.status, [this.data]);

  final int status;
  final Object? data;
}

/// A Dio whose requests never leave the test. Each is recorded, then answered by the route registered
/// for its method and path; an unregistered one is a 404.
///
/// An interceptor rather than a fake adapter, as checkout_test.dart explains: it resolves before any
/// socket is opened, and the assertions read the request as the client built it.
class FakeServer {
  FakeServer() {
    dio.interceptors.add(InterceptorsWrapper(onRequest: _answer));
  }

  final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
  final List<RequestOptions> requests = <RequestOptions>[];
  final Map<String, FakeAnswer> _routes = <String, FakeAnswer>{};

  void on(String method, String path, FakeAnswer answer) => _routes['$method $path'] = answer;

  List<RequestOptions> sent(String method, String path) => requests
      .where((RequestOptions r) => r.method == method && r.path == path)
      .toList(growable: false);

  Future<void> _answer(RequestOptions request, RequestInterceptorHandler handler) async {
    requests.add(request);
    final FakeAnswer? answer = _routes['${request.method} ${request.path}'];
    int status = 404;
    Object? body;
    if (answer != null) {
      try {
        final Object? reply = await answer(request);
        if (reply is FakeReply) {
          status = reply.status;
          body = reply.data;
        } else {
          status = 200;
          body = reply;
        }
      } on DioException catch (e) {
        handler.reject(e);
        return;
      }
    }
    final Response<dynamic> response =
        Response<dynamic>(requestOptions: request, statusCode: status, data: body);
    if (status >= 400) {
      handler.reject(DioException(
          requestOptions: request, response: response, type: DioExceptionType.badResponse));
    } else {
      handler.resolve(response);
    }
  }
}

/// A request that reached the server and got no answer back: the send may have placed an order.
DioException noAnswer(RequestOptions request) =>
    DioException(requestOptions: request, type: DioExceptionType.receiveTimeout);

/// The app around a screen under test, in [locale].
Widget svcApp(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
      theme: DeliveryTheme.light(),
      locale: locale,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supported,
      home: home,
    );

/// A phone of [size] logical pixels — tall by default, so a lazy list builds every row a test reads.
void phone(WidgetTester tester, {Size size = const Size(390, 2400)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// The service order every tracking test starts from; its short id is `abcd1234`.
const String svcOrderId = 'abcd1234-5678-4000-8000-000000000001';

Map<String, dynamic> serviceOrderJson({
  String status = 'PREPARING',
  String fulfilment = 'PICKUP',
  String storeName = 'Al Fakhry Press',
  String? cancelReason,
  String? estimatedReadyAt,
  List<String> actions = const <String>[],
  double subtotal = 15,
  double fee = 0,
  String? instructions,
  String? unitLabel = 'cards',
  int unitSize = 500,
  int packs = 1,
}) =>
    <String, dynamic>{
      'id': svcOrderId,
      'customerId': 'user-1',
      'merchantId': 'm1',
      'riderId': null,
      'status': status,
      'totalAmount': subtotal + fee,
      'subtotal': subtotal,
      'deliveryFee': fee,
      'deliveryFeeCharged': fee,
      'deliveryAddress': fulfilment == 'PICKUP' ? null : '12 Rose Street',
      'paymentMethod': 'CASH',
      'paymentStatus': 'DUE',
      'storeId': 's1',
      'storeName': storeName,
      'kind': 'SERVICE',
      'fulfilment': fulfilment,
      'serviceCategory': 'PRINTING',
      'cancelReason': cancelReason,
      'estimatedReadyAt': estimatedReadyAt,
      'placedAt': DateTime.now().toUtc().toIso8601String(),
      'availableActions': actions,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'productId': 'p1',
          'productName': 'Business Card Printing',
          'unitPrice': subtotal / packs,
          'qty': packs,
          'lineTotal': subtotal,
          'optionsSummary': 'Paper type: Matte',
          'service': <String, dynamic>{
            'pricingType': 'FIXED',
            'unitSize': unitSize,
            'unitLabel': unitLabel,
            'turnaroundMinHours': 24,
            'turnaroundMaxHours': 48,
            'attachmentPolicy': 'REQUIRED',
            'instructions': instructions,
          },
        },
      ],
    };

/// `GET /api/orders/{id}/history` for the statuses given, oldest first.
List<Map<String, dynamic>> historyJson(List<String> statuses) => <Map<String, dynamic>>[
      for (final (int i, String status) in statuses.indexed)
        <String, dynamic>{
          'status': status,
          'changedAt': DateTime.utc(2026, 9, 14, 9, i).toIso8601String(),
          'changedBy': 'account-$i',
        },
    ];

/// A services shop, as both `GET /api/stores/{id}` and a storefront card carry it.
Map<String, dynamic> storeJson({
  String id = 's1',
  String name = 'Al Fakhry Press',
  String category = 'PRINTING',
  String availability = 'OPEN',
  String? closesAt = '18:00:00',
  double? rating = 4.8,
  int ratingCount = 56,
  bool verifiedLocal = true,
  String? tagline = 'Printing & Copywriting Services',
  String? description,
  String? address,
  double? latitude = 33.8959,
  double? longitude = 35.5155,
  String? neighborhood = 'Mar Mikhael',
}) =>
    <String, dynamic>{
      'id': id,
      'slug': id,
      'name': name,
      'vertical': 'SERVICES',
      'serviceCategory': category,
      'tagline': tagline,
      'description': description,
      'rating': rating,
      'ratingCount': ratingCount,
      'availability': availability,
      'status': 'ACTIVE',
      'closesAt': closesAt,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'neighborhood': neighborhood,
      'verifiedLocal': verifiedLocal,
    };

/// A service offer: a product with its `service` block.
Map<String, dynamic> offerJson({
  String id = 'p1',
  String? storeId = 's1',
  String name = 'Business Card Printing',
  String? description = 'Premium matte finish cards.',
  double price = 15,
  double? fromPrice,
  String pricingType = 'FIXED',
  int unitSize = 500,
  String? unitLabel = 'cards',
  String fulfilment = 'BOTH',
  String attachmentPolicy = 'NONE',
  String? instructionsPrompt,
}) =>
    <String, dynamic>{
      'id': id,
      'merchantId': 'm1',
      'storeId': storeId,
      'name': name,
      'description': description,
      'price': price,
      'status': 'ACTIVE',
      'fromPrice': fromPrice,
      'service': <String, dynamic>{
        'pricingType': pricingType,
        'unitSize': unitSize,
        'unitLabel': unitLabel,
        'turnaroundMinHours': 24,
        'turnaroundMaxHours': 48,
        'fulfilmentModes': fulfilment,
        'attachmentPolicy': attachmentPolicy,
        'instructionsPrompt': instructionsPrompt,
      },
    };

/// A page of [content], as every paged endpoint answers.
Map<String, dynamic> pageJson(List<Map<String, dynamic>> content) => <String, dynamic>{
      'content': content,
      'page': 0,
      'totalElements': content.length,
      'totalPages': content.isEmpty ? 0 : 1,
    };

/// `POST /api/orders/quote` for one service: priced, or refused by the shop with [refusal].
Map<String, dynamic> quoteJson({
  double subtotal = 15,
  double fee = 0,
  double discount = 0,
  String? refusal,
}) {
  final bool priced = refusal == null;
  final double total = subtotal + fee - discount;
  return <String, dynamic>{
    'shops': <Map<String, dynamic>>[
      <String, dynamic>{
        'storeId': 's1',
        'storeName': 'Al Fakhry Press',
        'refusal': refusal,
        'subtotal': priced ? subtotal : null,
        'deliveryFee': priced ? fee : null,
        'deliveryFeeCharged': priced ? fee : null,
        'discountAmount': priced ? discount : null,
        'totalAmount': priced ? total : null,
      },
    ],
    'placeable': priced,
    'subtotal': priced ? subtotal : null,
    'deliveryFeeCharged': priced ? fee : null,
    'discountAmount': priced ? discount : null,
    'totalAmount': priced ? total : null,
    'maxShops': 1,
  };
}
