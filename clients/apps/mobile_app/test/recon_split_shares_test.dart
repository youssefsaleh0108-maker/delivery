import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/friend_split_screen.dart';
import 'package:mobile_app/src/rider_order_detail_screen.dart';
import 'package:mobile_app/src/split_complete_screen.dart';
import 'package:mobile_app/src/split_status_screen.dart';

/// RECON-01 beyond the pinned checklist: a share is paid only when money moved.
///
/// The rider collects the ORDER's cash, whatever the plan says; a wallet "payment" the dev
/// simulator stood in for is labelled as one wherever it shows and never offered as if it took
/// money; and a promise reads as confirmed, not paid, on the host's screen.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  Widget app(Widget home) => MaterialApp(
        theme: DeliveryTheme.light(),
        localizationsDelegates: const <LocalizationsDelegate<Object>>[
          DeliveryStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: LocaleController.supported,
        home: home,
      );

  DeliveryOrder order({required double total, String payment = 'CASH'}) =>
      DeliveryOrder.fromJson(<String, dynamic>{
        'id': '42c91f1c-4883-4620-9842-f8b190f8c429',
        'customerId': 'customer-1',
        'merchantId': 'merchant-1',
        'riderId': 'rider-1',
        'status': 'PICKED_UP',
        'totalAmount': total,
        'subtotal': total,
        'deliveryFee': 0,
        'deliveryAddress': 'Recon deep test, Hamra, Beirut',
        'paymentMethod': payment,
        'paymentStatus': payment == 'CASH' ? 'DUE' : 'AUTHORIZED',
        'items': <dynamic>[],
        'availableActions': <dynamic>[],
      });

  Map<String, dynamic> share(String id, String? username, String name, double amount,
          String status, String? method, {bool simulated = false}) =>
      <String, dynamic>{
        'id': id,
        'username': username,
        'name': name,
        'amountUsd': amount,
        'status': status,
        'method': method,
        'simulated': simulated,
      };

  Map<String, dynamic> plan(List<Map<String, dynamic>> shares, {double total = 19.50}) =>
      <String, dynamic>{
        'id': 'plan-1',
        'hostUsername': 'host',
        'hostName': 'Host',
        'storeName': 'Recon',
        'orderId': '42c91f1c-4883-4620-9842-f8b190f8c429',
        'mode': 'EVEN',
        'status': 'PLACED',
        'totalUsd': total,
        'rateUsed': 90000,
        'shares': shares,
      };

  /// Answers every GET under the split API from [routes] (by path suffix), refuses the rest.
  SplitApi splitServer(Map<String, Object> routes) {
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        for (final MapEntry<String, Object> route in routes.entries) {
          if (options.path.endsWith(route.key)) {
            handler.resolve(Response<dynamic>(
                requestOptions: options, statusCode: 200, data: route.value));
            return;
          }
        }
        handler.reject(DioException(requestOptions: options, message: 'not in this test'));
      },
    ));
    return SplitApi(dio);
  }

  Future<void> pumpRider(WidgetTester tester, DeliveryOrder order, Map<String, dynamic> body) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(RiderOrderDetailScreen(
      order: order,
      onAction: (OrderAction _) async {},
      splitApi: splitServer(<String, Object>{'/for-order/${order.id}': body}),
    )));
    await tester.pumpAndSettle();
  }

  String totalShown(WidgetTester tester) {
    final Finder row =
        find.ancestor(of: find.text(en.riderTotalCashCollect), matching: find.byType(Row));
    return tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .map((Text text) => text.data)
        .join(' ');
  }

  group('the rider collects the order\'s cash', () {
    testWidgets('a simulated wallet share is still cash at this door, and says why',
        (WidgetTester tester) async {
      await pumpRider(tester, order(total: 19.5), plan(<Map<String, dynamic>>[
        share('s-host', 'host', 'Host', 14.50, 'COMMITTED', 'HOST_ORDER'),
        share('s-friend', 'friend', 'Friend', 5.00, 'COMMITTED', 'WHISH', simulated: true),
      ]));

      expect(totalShown(tester), contains(r'$19.50'));
      expect(find.text(en.splitSimulatedPayment(en.custWhishShort)), findsOneWidget);
      expect(find.text(r'$14.50'), findsOneWidget);
      expect(find.text(r'$5.00'), findsOneWidget);
      expect(find.text(en.riderAlreadyPaid.toUpperCase()), findsNothing);
    });

    testWidgets('a plan priced before the order shows the gap and still asks for the order',
        (WidgetTester tester) async {
      // EXPRESS chosen at checkout added 2.00 to a plan attached before the fix re-priced it.
      await pumpRider(tester, order(total: 21.5), plan(<Map<String, dynamic>>[
        share('s-host', 'host', 'Host', 14.50, 'PAID', 'HOST_ORDER'),
        share('s-guest', null, 'Guest', 5.00, 'PAID', 'CASH_AT_DOOR'),
      ]));

      expect(totalShown(tester), contains(r'$21.50'));
      expect(find.text(en.riderSplitOrderDifference), findsOneWidget);
      expect(find.text(r'+$2.00'), findsOneWidget);
    });

    testWidgets('a declined share nobody covered is still owed at the door',
        (WidgetTester tester) async {
      await pumpRider(tester, order(total: 19.5), plan(<Map<String, dynamic>>[
        share('s-host', 'host', 'Host', 14.50, 'COMMITTED', 'HOST_ORDER'),
        share('s-friend', 'friend', 'Friend', 5.00, 'DECLINED', null),
      ]));

      expect(totalShown(tester), contains(r'$19.50'));
      expect(find.text(en.custDeclinedChip), findsOneWidget);
    });

    testWidgets('the rider\'s own view of the plan (RECON-02) draws the same checklist',
        (WidgetTester tester) async {
      // What transfer-service now answers the order's rider: amounts and names, no usernames,
      // no host, and every share of a cash order as cash at this door.
      await pumpRider(tester, order(total: 19.5), <String, dynamic>{
        'id': 'plan-1',
        'orderId': '42c91f1c-4883-4620-9842-f8b190f8c429',
        'mode': 'EVEN',
        'status': 'PLACED',
        'totalUsd': 19.50,
        'rateUsed': 90000,
        'shares': <dynamic>[
          <String, dynamic>{'id': 's-host', 'name': 'Host', 'amountUsd': 9.50,
              'status': 'COMMITTED', 'method': 'CASH_AT_DOOR', 'simulated': false},
          <String, dynamic>{'id': 's-friend', 'name': 'Friend', 'amountUsd': 5.00,
              'status': 'COMMITTED', 'method': 'CASH_AT_DOOR', 'simulated': true,
              'simulatedMethod': 'WHISH'},
          <String, dynamic>{'id': 's-guest', 'name': 'Guest', 'amountUsd': 5.00,
              'status': 'COMMITTED', 'method': 'CASH_AT_DOOR', 'simulated': false},
        ],
      });

      expect(totalShown(tester), contains(r'$19.50'));
      expect(find.text('Host'), findsOneWidget);
      expect(find.text(r'$9.50'), findsOneWidget);
      expect(find.text(r'$5.00'), findsNWidgets(2));
      expect(find.text(en.riderSplitOrderDifference), findsNothing);
      // The door takes it in cash, and the wallet it stood in for is still named.
      expect(find.text(en.splitSimulatedPayment(en.custWhishShort)), findsOneWidget);
    });

    testWidgets('a wallet order draws no cash checklist: nothing is collected at the door',
        (WidgetTester tester) async {
      await pumpRider(tester, order(total: 19.5, payment: 'WALLET'), plan(<Map<String, dynamic>>[
        share('s-host', 'host', 'Host', 14.50, 'COMMITTED', 'HOST_ORDER'),
        share('s-friend', 'friend', 'Friend', 5.00, 'COMMITTED', 'CASH_AT_DOOR'),
      ]));

      expect(find.text(en.riderCashChecklist), findsNothing);
      expect(find.text(en.alreadyPaid), findsOneWidget);
    });
  });

  group('the invitee is offered only what can take a share', () {
    Map<String, dynamic> invitation() => plan(<Map<String, dynamic>>[
          share('s-host', 'host', 'Host', 14.50, 'COMMITTED', 'HOST_ORDER'),
          share('s-friend', 'friend', 'Friend', 5.00, 'PENDING', null),
        ])
          ..['status'] = 'COLLECTING';

    Future<void> pumpFriend(WidgetTester tester, List<Map<String, dynamic>> methods) async {
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(FriendSplitScreen(
        splitApi: splitServer(<String, Object>{'/splits/methods': methods}),
        plan: SplitPlan.fromJson(invitation()),
        myUsername: 'friend',
      )));
      await tester.pumpAndSettle();
    }

    testWidgets('on dev a wallet is offered as the test payment it is, and cash stays chosen',
        (WidgetTester tester) async {
      await pumpFriend(tester, <Map<String, dynamic>>[
        <String, dynamic>{'method': 'WHISH', 'simulated': true},
        <String, dynamic>{'method': 'CASH_AT_DOOR', 'simulated': false},
      ]);

      expect(find.text(en.custWhishShort), findsOneWidget);
      expect(find.text(en.splitSimulatedMethodNote), findsOneWidget);
      // Nobody is recommended a payment that moves no money.
      expect(find.text(en.custRecommendedChip.toUpperCase()), findsNothing);
      final Finder cashRow =
          find.ancestor(of: find.text(en.custCashAtDoor), matching: find.byType(InkWell));
      expect(find.descendant(of: cashRow, matching: find.byIcon(Icons.radio_button_checked)),
          findsOneWidget);
    });

    testWidgets('where no simulator stands in, only cash at the door is offered',
        (WidgetTester tester) async {
      await pumpFriend(tester, <Map<String, dynamic>>[
        <String, dynamic>{'method': 'CASH_AT_DOOR', 'simulated': false},
      ]);

      expect(find.text(en.custWhishShort), findsNothing);
      expect(find.text(en.custOmtShort), findsNothing);
      expect(find.text(en.custCashAtDoor), findsOneWidget);
    });
  });

  group('the host reads promises as confirmed, not paid', () {
    testWidgets('the status screen', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final SplitPlan ready = SplitPlan.fromJson(plan(<Map<String, dynamic>>[
        share('s-host', 'host', 'Host', 9.50, 'COMMITTED', 'HOST_ORDER'),
        share('s-guest', null, 'Guest', 5.00, 'COMMITTED', 'CASH_AT_DOOR'),
        share('s-friend', 'friend', 'Friend', 5.00, 'COMMITTED', 'OMT', simulated: true),
      ])
        ..['status'] = 'READY');
      await tester.pumpWidget(app(SplitStatusScreen(
        splitApi: splitServer(const <String, Object>{}),
        plan: ready,
        onReady: () {},
      )));
      await tester.pump();

      expect(find.text(en.custPaidChip.toUpperCase()), findsNothing);
      expect(find.text(en.splitConfirmedChip.toUpperCase()), findsNWidgets(2));
      expect(find.text(en.splitSimulatedChip.toUpperCase()), findsOneWidget);
      expect(find.text(en.splitWithTheOrder), findsOneWidget);
      expect(find.text(en.custCashAtDoor), findsOneWidget);
      expect(find.text(en.splitSimulatedPayment(en.custOmtShort)), findsOneWidget);
      expect(find.text(en.splitNConfirmed(3, 3)), findsOneWidget);
    });

    testWidgets('the completion screen: every share of a cash order is handed to the rider',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final SplitPlan placed = SplitPlan.fromJson(plan(<Map<String, dynamic>>[
        share('s-host', 'host', 'Host', 14.50, 'COMMITTED', 'HOST_ORDER'),
        share('s-friend', 'friend', 'Friend', 5.00, 'COMMITTED', 'WHISH', simulated: true),
      ]));
      await tester.pumpWidget(app(SplitCompleteScreen(plan: placed, onTrack: () {})));

      expect(find.text(en.custRiderCollectNote(r'$14.50', 'Host')), findsOneWidget);
      expect(find.text(en.custRiderCollectNote(r'$5.00', 'Friend')), findsOneWidget);
      expect(find.text(en.splitSimulatedPayment(en.custWhishShort)), findsOneWidget);
      expect(find.textContaining('HOST_ORDER'), findsNothing);

      await tester.pumpWidget(
          app(SplitCompleteScreen(plan: placed, cashOrder: false, onTrack: () {})));
      expect(find.text(en.custRiderCollectNote(r'$14.50', 'Host')), findsNothing);
    });
  });
}
