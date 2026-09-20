import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Closing an order a rider already has, on the wire (RECON-10).
///
/// The two decisions this carries — whether the shop is paid its share, whether the delivery is
/// paid for — are money the platform pays out on an order that never arrived, so the server refuses
/// a request that leaves either out rather than paying by default. These pin that the client always
/// sends both, that a screen cannot send this action down the generic path where they would be
/// dropped, and that what comes back reads as a cancellation with a stage.
void main() {
  Map<String, dynamic> orderJson({
    String status = 'CANCELLED',
    String? cancelStage = 'AFTER_PICKUP',
    bool compensateMerchant = true,
    bool compensateCarrier = false,
  }) =>
      <String, dynamic>{
        'id': 'order-1',
        'customerId': 'customer-1',
        'merchantId': 'm1',
        'riderId': 'rider-1',
        'status': status,
        'totalAmount': 19.50,
        'deliveryAddress': '12 Rose Street',
        'paymentMethod': 'CASH',
        'paymentStatus': 'FAILED',
        'items': <dynamic>[],
        'availableActions': <dynamic>[],
        'cancelReason': 'Customer refused it at the door',
        'cancelStage': cancelStage,
        'compensateMerchant': compensateMerchant,
        'compensateCarrier': compensateCarrier,
      };

  /// Records each request and answers it with the order, without opening a socket.
  ({OrderApi api, List<RequestOptions> sent}) server(Map<String, dynamic> answer) {
    final List<RequestOptions> sent = <RequestOptions>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway.test'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions o, RequestInterceptorHandler h) {
        sent.add(o);
        h.resolve(Response<dynamic>(requestOptions: o, statusCode: 200, data: answer));
      },
    ));
    return (api: OrderApi(dio), sent: sent);
  }

  test('sends the reason and both decisions, exactly as they were made', () async {
    final ({OrderApi api, List<RequestOptions> sent}) s = server(orderJson());

    final DeliveryOrder closed = await s.api.closeNotDelivered(
      'order-1',
      reason: 'Customer refused it at the door',
      compensateMerchant: true,
      compensateCarrier: false,
    );

    expect(s.sent.single.path, '/api/orders/order-1/close-not-delivered');
    expect(s.sent.single.method, 'POST');
    final Map<String, dynamic> body = s.sent.single.data as Map<String, dynamic>;
    expect(body['reason'], 'Customer refused it at the door');
    expect(body['compensateMerchant'], isTrue);
    // Never left out: the server refuses a request that does not say, and would otherwise be
    // asked to guess at money.
    expect(body.containsKey('compensateCarrier'), isTrue);
    expect(body['compensateCarrier'], isFalse);

    expect(closed.status, OrderStatus.cancelled);
    expect(closed.cancelStage, CancelStage.afterPickup);
    expect(closed.closedAfterPickup, isTrue);
    expect(closed.compensateMerchant, isTrue);
    expect(closed.compensateCarrier, isFalse);
  });

  test('cannot be sent down the generic action path, where the decisions would be dropped',
      () async {
    final ({OrderApi api, List<RequestOptions> sent}) s = server(orderJson());

    expect(
      () => s.api.act('order-1', OrderAction.closeNotDelivered, reason: 'refused'),
      throwsArgumentError,
    );
    expect(s.sent, isEmpty);
  });

  test('an ordinary cancellation reads as one, before pickup', () {
    final DeliveryOrder order = DeliveryOrder.fromJson(
        orderJson(cancelStage: 'BEFORE_PICKUP', compensateMerchant: false));

    expect(order.cancelStage, CancelStage.beforePickup);
    expect(order.closedAfterPickup, isFalse);
    expect(order.compensateMerchant, isFalse);
    expect(order.compensateCarrier, isFalse);
  });

  test('a server that says nothing about the stage leaves it unknown, and pays nobody', () {
    final Map<String, dynamic> json = orderJson()
      ..remove('cancelStage')
      ..remove('compensateMerchant')
      ..remove('compensateCarrier');

    final DeliveryOrder order = DeliveryOrder.fromJson(json);

    expect(order.cancelStage, isNull);
    expect(order.closedAfterPickup, isFalse);
    expect(order.compensateMerchant, isFalse);
    expect(order.compensateCarrier, isFalse);
  });

  test('a stage this build does not know reads as a plain cancellation rather than crashing', () {
    final DeliveryOrder order =
        DeliveryOrder.fromJson(orderJson(cancelStage: 'AT_THE_DOOR'));

    expect(order.cancelStage, isNull);
    expect(order.closedAfterPickup, isFalse);
  });

  test('the action the server offers on the road maps to its own route', () {
    expect(OrderAction.fromWire('CLOSE_NOT_DELIVERED'), OrderAction.closeNotDelivered);
    expect(OrderAction.closeNotDelivered.path, 'close-not-delivered');
    // An older build simply does not draw a button it does not know.
    expect(OrderAction.fromWire('SOMETHING_NEWER'), isNull);
  });
}
