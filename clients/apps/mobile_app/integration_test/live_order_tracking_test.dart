import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_app/main.dart' as app;
import 'package:mobile_app/src/customer_nav_bar.dart';
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/my_orders_screen.dart';
import 'package:mobile_app/src/order_details_screen.dart';

import 'support/backend.dart';
import 'support/journey.dart';

/// **The customer watches their order move, without touching the phone.**
///
/// <p>A customer places an order and then puts the phone down. Somewhere else a merchant accepts
/// it, makes it, and puts it on the counter; a rider picks it up and drives it over. The screen in
/// the customer's hand has to keep up with all of that on its own — and if it does not, the first
/// they hear of a delivered order is the knock at the door.
///
/// <p><strong>Why the other roles are driven over HTTP here and not through the UI.</strong> This
/// scenario is about ONE screen: whether `MyOrdersScreen`'s five-second poll turns a state change
/// made by somebody else into a change the customer can see. Putting the merchant and rider
/// through their own screens would prove the same transitions twice — `order_lifecycle_test.dart`
/// already does exactly that — while adding six more ways for this test to fail for reasons that
/// have nothing to do with what it is asking.
///
/// <p><strong>What makes this different from asserting a label exists.</strong> Every wait below
/// starts from the previous state still being on screen and ends with the next one. Nothing here
/// re-enters the tab, pulls to refresh, or rebuilds the screen: if the poll stopped, every
/// assertion after the first would time out with the stale label still showing.
///
/// ```
/// adb uninstall com.delivery.mobile_app
/// flutter test integration_test/live_order_tracking_test.dart -d <device> --flavor dev \
///   --dart-define=API_BASE_URL=https://api-dev.youdrop.shop \
///   --dart-define=KEYCLOAK_ISSUER=https://iam-dev.youdrop.shop/realms/delivery-platform
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final String tag = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();

  testWidgets('the order list keeps up with an order somebody else is moving',
      (WidgetTester tester) async {
    final String customerToken = await Backend.signIn('customer');
    final String merchantToken = await Backend.signIn('merchant');
    final String riderToken = await Backend.signIn('rider');
    final String backofficeToken = await Backend.signIn('backoffice');

    final Map<String, dynamic> store = await Backend.merchantStore(merchantToken);
    final Map<String, dynamic> product = await Backend.ensureSellableProduct(
      merchantToken,
      customerToken,
      store,
      name: 'Tracking Plate',
    );
    await Backend.clearMerchantCarrierPin(merchantToken);
    await Backend.putRiderBackInHouse(backofficeToken, Backend.subjectOf(riderToken));

    await app.main();
    await signIn(tester, 'customer', '100001', expectedShell: CustomerShell);

    // Placed AFTER the customer is already looking at the app, which is the only way to prove the
    // list learned about it rather than merely having been built with it.
    final Map<String, dynamic> order = await BusinessFlow.placeOrder(
      customerToken,
      productId: product['id'] as String,
      deliveryAddress: 'Flat $tag, Hamra, Beirut',
    );
    final String orderId = order['id'] as String;
    step('placed $orderId out of band, with the app open on the storefront');

    await tester.tap(find.descendant(
        of: find.byType(CustomerNavBar), matching: find.text(en.navOrders)));
    await pumpUntil(tester, find.byType(MyOrdersScreen), reason: 'The Orders tab did not build.');

    /// The newest order is the top card, and the top card is this run's — checked against the
    /// server rather than assumed, because on a shared environment somebody else's order arriving
    /// between the placement above and the read below would silently move the assertions onto it.
    final List<dynamic> mine = await Backend.myOrders(customerToken);
    expect((mine.first as Map<String, dynamic>)['id'], orderId,
        reason: 'Another order was placed on this account between the placement and this check, '
            'so the top card is no longer the one this scenario is about.');

    // firstOrNothing, never .first: inside a poll, Finder.first throws 'Bad state: No element'
    // on the frames before the list has loaded, so the wait dies on its first tick with a message
    // about iterables instead of waiting for the card it is about.
    Finder topCard() => find
        .descendant(of: find.byType(MyOrdersScreen), matching: find.byType(YdCard))
        .firstOrNothing;

    /// Waits for the top card's pill to read [status], having started from something else.
    Future<void> livesThrough(OrderStatus status) async {
      final String label = status.labelIn(en);
      await pumpUntil(
        tester,
        find.descendant(
          of: topCard(),
          matching: find.widgetWithText(CustomerStatusPill, label),
        ),
        timeout: const Duration(seconds: 90),
        reason: 'The order became ${status.name.toUpperCase()} on the server, but the customer\'s '
            'list never caught up to "$label". MyOrdersScreen polls /api/orders/mine every five '
            'seconds and nothing in this test refreshes it by hand, so a timeout here means the '
            'poll is not running, is not re-rendering, or is serving a cached page.',
      );
      step('the customer sees "$label"');
    }

    await livesThrough(OrderStatus.placed);

    await BusinessFlow.advance(merchantToken, orderId, 'accept');
    await livesThrough(OrderStatus.accepted);

    await BusinessFlow.advance(merchantToken, orderId, 'prepare');
    await livesThrough(OrderStatus.preparing);

    await BusinessFlow.advance(merchantToken, orderId, 'ready');
    await livesThrough(OrderStatus.ready);

    await BusinessFlow.advance(riderToken, orderId, 'claim');
    await BusinessFlow.advance(riderToken, orderId, 'pick-up');
    await livesThrough(OrderStatus.pickedUp);

    await BusinessFlow.advance(riderToken, orderId, 'deliver');

    // A delivered order leaves the live list for the Past tab, so the last hop is looked for
    // there rather than at the top of the same list.
    final Finder pastTab = find.descendant(
        of: find.byType(MyOrdersScreen), matching: find.text(en.custPastOrdersTab));
    if (pastTab.evaluate().isNotEmpty) {
      await tester.tap(pastTab.first);
      await pumpFor(tester, const Duration(milliseconds: 600));
    }
    await pumpUntil(
      tester,
      find.widgetWithText(CustomerStatusPill, OrderStatus.delivered.labelIn(en)),
      timeout: const Duration(seconds: 90),
      reason: 'The order was delivered but the customer\'s list never said so.',
    );
    step('the customer sees "${OrderStatus.delivered.labelIn(en)}"');

    // The tracking panel is drawn only while an order is live. Its disappearance is the screen
    // agreeing that the journey is over, rather than merely relabelling a pill.
    expect(find.text(en.custLiveMap), findsNothing,
        reason: 'The live tracking panel is still on screen for a delivered order. '
            'OrderTrackingPanel.build returns SizedBox.shrink() once the status is terminal, so '
            'this means the screen is still holding a pre-delivery snapshot.');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
