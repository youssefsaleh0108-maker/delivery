import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/rider_order_detail_screen.dart';

/// The gift panel on a rider's job detail, which opens from the Available board as well as from
/// Active.
///
/// On the board the server withholds who a gift is for and its card: the rider is browsing work,
/// not carrying it. The panel must then say it is a gift rather than print "Gift for" and nothing.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  DeliveryOrder job(Map<String, dynamic> gift) => DeliveryOrder.fromJson(<String, dynamic>{
        'id': 'order-gift-1',
        'customerId': 'customer-1',
        'merchantId': 'merchant-1',
        'riderId': null,
        'status': 'READY',
        'totalAmount': 50.5,
        'deliveryAddress': 'Mar Mikhael, Beirut',
        'paymentMethod': 'CARD',
        'paymentStatus': 'AUTHORIZED',
        'items': <dynamic>[],
        'availableActions': <dynamic>[],
        'gift': gift,
      });

  Future<void> pumpDetail(WidgetTester tester, DeliveryOrder order) async {
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
      home: RiderOrderDetailScreen(order: order, onAction: (OrderAction _) async {}),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('on the job board, a gift whose name was withheld is a wrapped gift and no more',
      (WidgetTester tester) async {
    await pumpDetail(
        tester,
        job(<String, dynamic>{
          'recipientName': null,
          'recipientPhone': null,
          'message': null,
          'wrap': true,
          'wrapFee': 3.0,
        }));

    expect(find.text(en.giftUnnamed), findsOneWidget);
    expect(find.text(en.giftForName('')), findsNothing);
    expect(find.text(en.giftWrapRequested), findsOneWidget);
  });

  testWidgets('carrying it, the rider sees who it is for', (WidgetTester tester) async {
    await pumpDetail(
        tester,
        job(<String, dynamic>{
          'recipientName': 'Mona (Mom)',
          'recipientPhone': '+96171234567',
          'message': 'Habibti Mom',
          'wrap': false,
          'wrapFee': 0,
        }));

    expect(find.text(en.giftForName('Mona (Mom)')), findsOneWidget);
    expect(find.text(en.giftUnnamed), findsNothing);
  });
}
