import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The LBP line under every price is a conversion at the platform's rate, and the dekkane grid
/// lays it out itself — so the bare number and the finished string must be the same conversion.
Dio _rateServer(num? lbpPerUsd) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (RequestOptions options, RequestInterceptorHandler handler) => handler.resolve(
      Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{'lbpPerUsd': lbpPerUsd},
      ),
    ),
  ));
  return dio;
}

void main() {
  tearDown(() async => MarketRates.instance.load(_rateServer(0)));

  test('with no rate there is no second figure, in either form', () async {
    await MarketRates.instance.load(_rateServer(0));

    expect(MarketRates.instance.lbpRounded(3.5), isNull);
    expect(MarketRates.instance.lbp(3.5), isNull);
  });

  test('the bare figure is the finished string\'s number, rounded to the thousand', () async {
    await MarketRates.instance.load(_rateServer(89500));

    // 3.50 x 89,500 = 313,250, and no note smaller than a thousand exists to be owed.
    expect(MarketRates.instance.lbpRounded(3.5), 313000);
    expect(MarketRates.instance.lbp(3.5), '313,000 LBP');
    expect(MarketRates.instance.lbpRounded(0.8), 72000);
  });
}
