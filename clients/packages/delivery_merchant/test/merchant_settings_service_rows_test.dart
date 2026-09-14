import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings' rows to a services shop, for an owner who also runs a goods shop and so works in the
/// goods shell: Service orders and Service offers, each drawn only when the host hands over a way to
/// open it — an owner of one kind of shop has nowhere else to go, and a row that opens nothing would be
/// a dead control.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  Future<void> pumpSettings(
    WidgetTester tester, {
    VoidCallback? onServiceOrders,
    VoidCallback? onServiceOffers,
    Locale locale = const Locale('en'),
    Size size = const Size(390, 2400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      locale: locale,
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: MerchantSettingsScreen(
        locale: LocaleController(
            read: () async => locale.languageCode, write: (String _) async {}),
        accountName: 'Rima Haddad',
        onServiceOrders: onServiceOrders,
        onServiceOffers: onServiceOffers,
        onSignOut: () {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('each row opens its page when the host wires it', (WidgetTester tester) async {
    final List<String> opened = <String>[];
    await pumpSettings(
      tester,
      onServiceOrders: () => opened.add('orders'),
      onServiceOffers: () => opened.add('offers'),
    );

    await tester.tap(find.text(en.svcServiceOrdersRow));
    await tester.tap(find.text(en.svcServiceOffersRow));
    await tester.pumpAndSettle();

    expect(opened, <String>['orders', 'offers']);
  });

  testWidgets('the rows are absent, not disabled, when the host does not wire them',
      (WidgetTester tester) async {
    await pumpSettings(tester);

    expect(find.text(en.svcServiceOrdersRow), findsNothing);
    expect(find.text(en.svcServiceOffersRow), findsNothing);
    expect(find.text(en.merchbLogOutAccount), findsOneWidget);
  });

  testWidgets('the rows read in Arabic and fit a 320dp phone', (WidgetTester tester) async {
    await pumpSettings(
      tester,
      onServiceOrders: () {},
      onServiceOffers: () {},
      locale: const Locale('ar'),
      size: const Size(320, 2400),
    );

    expect(Directionality.of(tester.element(find.byType(MerchantSettingsScreen))),
        TextDirection.rtl);
    expect(tester.takeException(), isNull);
    expect(find.text(ar.svcServiceOrdersRow), findsOneWidget);
    expect(find.text(ar.svcServiceOffersRow), findsOneWidget);
  });
}
