import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/rider_order_detail_screen.dart';

/// RECON-01: the rider's cash checklist on a split order asks for less than the order's cash.
///
/// Reproduced on dev on 2026-09-19 (deep test, order 42c91f1c): a 19.50 CASH order split with one
/// guest. The plan the rider's app reads (`/api/transfers/splits/for-order/{id}`) holds the host's
/// 14.50 as `HOST_ORDER` / PAID and the guest's 5.00 as `CASH_AT_DOOR`. The checklist counts only
/// CASH_AT_DOOR shares, so it says "Total Cash to Collect $5.00" and lists the host's 14.50 under
/// "Already paid digitally" — although the host pays with the order, and this order is paid in cash
/// at the door. Settlement then books CASH_COLLECTED 19.50 against the rider, who was told to take
/// 5.00. Wallet shares (WHISH / OMT / BOB) land in the same "already paid" list, and nothing on the
/// platform ever took that money: `SplitService.answer` only marks the share paid.
///
/// Fails until the checklist's total is the cash the order collects at this door.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  DeliveryOrder cashOrder() => DeliveryOrder.fromJson(<String, dynamic>{
        'id': '42c91f1c-4883-4620-9842-f8b190f8c429',
        'customerId': 'customer-1',
        'merchantId': 'merchant-1',
        'riderId': 'rider-1',
        'status': 'PICKED_UP',
        'totalAmount': 19.5,
        'subtotal': 19.5,
        'deliveryFee': 0,
        'deliveryAddress': 'Recon deep test, Hamra, Beirut',
        'paymentMethod': 'CASH',
        'paymentStatus': 'DUE',
        'items': <dynamic>[],
        'availableActions': <dynamic>[],
      });

  /// The plan exactly as dev returned it, names replaced.
  SplitApi planServer() {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        if (options.path.contains('/api/transfers/splits/for-order/')) {
          handler.resolve(Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: <String, dynamic>{
              'id': '459ce889-b98e-4673-b466-15be03d1f718',
              'hostUsername': 'host',
              'hostName': 'Host',
              'storeName': 'Recon',
              'orderId': '42c91f1c-4883-4620-9842-f8b190f8c429',
              'mode': 'EVEN',
              'status': 'PLACED',
              'totalUsd': 19.50,
              'rateUsed': 90000,
              'shares': <dynamic>[
                <String, dynamic>{
                  'id': 'share-host',
                  'username': 'host',
                  'name': 'Host',
                  'amountUsd': 14.50,
                  'itemsCount': null,
                  'status': 'PAID',
                  'method': 'HOST_ORDER',
                },
                <String, dynamic>{
                  'id': 'share-guest',
                  'username': null,
                  'name': 'Guest',
                  'amountUsd': 5.00,
                  'itemsCount': 1,
                  'status': 'PAID',
                  'method': 'CASH_AT_DOOR',
                },
              ],
            },
          ));
          return;
        }
        handler.reject(DioException(requestOptions: options, message: 'not in this test'));
      },
    ));
    return SplitApi(dio);
  }

  testWidgets('RECON-01: the checklist asks for the whole cash the order collects',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleController.supported,
      home: RiderOrderDetailScreen(
        order: cashOrder(),
        onAction: (OrderAction _) async {},
        splitApi: planServer(),
      ),
    ));
    await tester.pumpAndSettle();

    // The payout card's tag, which reads the order: 19.50 in cash.
    expect(find.text(en.collectCash('19.50')), findsOneWidget);

    // The checklist under it must agree with the tag and with the ledger (CASH_COLLECTED 19.50).
    expect(find.text(en.riderTotalCashCollect), findsOneWidget);
    final Finder totalRow = find.ancestor(
        of: find.text(en.riderTotalCashCollect), matching: find.byType(Row));
    final String shown = tester
        .widgetList<Text>(find.descendant(of: totalRow, matching: find.byType(Text)))
        .map((Text text) => text.data)
        .join(' ');
    expect(find.descendant(of: totalRow, matching: find.text(r'$19.50')), findsOneWidget,
        reason: 'the checklist total is the cash taken at this door, not only the friends\' '
            'part; it shows "$shown"');
    // And the host's own share, paid in cash with the order, is not "already paid digitally".
    expect(find.text(en.riderAlreadyPaid.toUpperCase()), findsNothing);
  });
}
