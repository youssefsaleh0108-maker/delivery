import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shop's half of the role switch: "Switch to shopping" in Settings.
///
/// A customer who became a services provider holds both roles, and the shop shell is where they land
/// by default. The row is how they get back to shopping. It follows the Settings rule for rows the
/// frame does not draw — drawn when the host hands over a callback, absent when it does not — and the
/// app hands one over only to an account that holds the customer role.
void main() {
  Future<void> pumpSettings(WidgetTester tester, {VoidCallback? onSwitchToShopping}) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: MerchantSettingsScreen(
        locale: LocaleController(read: () async => 'en', write: (String _) async {}),
        accountName: 'Rima Haddad',
        onSwitchToShopping: onSwitchToShopping,
        onSignOut: () {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  testWidgets('switches to shopping when the host wires it', (WidgetTester tester) async {
    int switched = 0;
    await pumpSettings(tester, onSwitchToShopping: () => switched++);

    await tester.tap(find.text(en.svcSwitchToShopping));
    await tester.pumpAndSettle();

    expect(switched, 1);
  });

  testWidgets('is absent, not disabled, when the host does not', (WidgetTester tester) async {
    await pumpSettings(tester);

    expect(find.text(en.svcSwitchToShopping), findsNothing);
    // Sign-out is still where it was.
    expect(find.text(en.merchbLogOutAccount), findsOneWidget);
  });
}
