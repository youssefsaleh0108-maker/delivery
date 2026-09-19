import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// RECON-14: the lira figure a customer is shown can differ from the one the platform records.
///
/// transfer-service fixes the lira face value of a cash split with exact decimals:
/// `MoneyTransfer.lbpFaceOf` = HALF_UP(usd × rate / 1000) × 1000. The apps convert with `double`
/// (`MarketRates.lbpRounded`, and the checkout's split card the same way), and at a halfway figure the
/// binary product falls just short: 1.15 × 90,000 is 103,499.99999999999 as a double, so the app
/// shows 103,000 LBP where the transfer ledger — and the rider — say 104,000. The same happens at
/// every cent amount whose lira product is an exact half-thousand and is not representable in binary.
///
/// Fails until the conversion is done in exact decimal (or integer cents) with HALF_UP, as the server
/// does.
Dio _rateServer(num lbpPerUsd) {
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

  test('RECON-14: the app converts 1.15 USD to the lira the transfer ledger records', () async {
    await MarketRates.instance.load(_rateServer(90000));

    // transfer-service: 1.15 × 90,000 = 103,500 → HALF_UP to the note → 104,000.
    expect(MarketRates.instance.lbpRounded(1.15), 104000);
    expect(MarketRates.instance.lbp(1.15), '104,000 LBP');
  });

  test('RECON-14: every cent from 0.01 to 20.00 converts as the server does', () async {
    await MarketRates.instance.load(_rateServer(90000));

    final List<String> wrong = <String>[];
    for (int cents = 1; cents <= 2000; cents++) {
      // The server's rule in integers: cents × rate / 100 lira, HALF_UP to the thousand.
      final int lira100 = cents * 90000; // hundredths of a lira
      final int server = ((lira100 + 50000) ~/ 100000) * 1000;
      final int? app = MarketRates.instance.lbpRounded(cents / 100);
      if (app != server) wrong.add('${(cents / 100).toStringAsFixed(2)}: app $app, server $server');
    }
    expect(wrong, isEmpty, reason: '${wrong.length} amounts differ, e.g. ${wrong.take(5)}');
  });
}
