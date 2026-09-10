import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_app/main.dart' as app;
import 'package:mobile_app/src/customer_nav_bar.dart';
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/my_orders_screen.dart';
import 'package:mobile_app/src/order_details_screen.dart';

import 'support/backend.dart';
import 'support/journey.dart';

/// **Changing your mind, and the window in which you still can.**
///
/// <p>A customer may cancel their own order right up until the merchant accepts it, and not one
/// moment after — at that point somebody has started cooking, and calling it off is a conversation
/// rather than a button. The server states that rule twice: the state machine allows
/// PLACED → CANCELLED, and a second check narrows it to the customer's own window, letting a
/// merchant or backoffice caller cancel anything the machine allows.
///
/// <p>This scenario walks both sides of that line. First an order is cancelled through the app the
/// way a person would, and the cancellation is confirmed against the ledger. Then a second order
/// is accepted by the merchant while the customer is looking at it, and the assertion is that the
/// app stops offering the button — because a client that offers an action the server will refuse
/// produces the worst kind of failure: one the person reads as the app being broken.
///
/// ```
/// adb uninstall com.delivery.mobile_app
/// flutter test integration_test/cancel_order_test.dart -d <device> --flavor dev \
///   --dart-define=API_BASE_URL=https://api-dev.youdrop.shop \
///   --dart-define=KEYCLOAK_ISSUER=https://iam-dev.youdrop.shop/realms/delivery-platform
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final String tag = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();

  testWidgets('an order can be called off before it is accepted, and not after',
      (WidgetTester tester) async {
    final String customerToken = await Backend.signIn('customer');
    final String merchantToken = await Backend.signIn('merchant');

    final Map<String, dynamic> store = await Backend.merchantStore(merchantToken);
    final Map<String, dynamic> product = await Backend.ensureSellableProduct(
      merchantToken,
      customerToken,
      store,
      name: 'Cancel Plate',
    );

    await app.main();
    await signIn(tester, 'customer', '100001', expectedShell: CustomerShell);

    // firstOrNothing, never .first: inside a poll, Finder.first throws 'Bad state: No element'
    // on the frames before the list has loaded, so the wait dies on its first tick with a message
    // about iterables instead of waiting for the card it is about.
    Finder topCard() => find
        .descendant(of: find.byType(MyOrdersScreen), matching: find.byType(YdCard))
        .firstOrNothing;

    Future<void> openOrders() async {
      await tester.tap(find.descendant(
          of: find.byType(CustomerNavBar), matching: find.text(en.navOrders)));
      await pumpUntil(tester, find.byType(MyOrdersScreen), reason: 'The Orders tab did not build.');
    }

    Future<String> placeOne(String what) async {
      final Map<String, dynamic> order = await BusinessFlow.placeOrder(
        customerToken,
        productId: product['id'] as String,
        deliveryAddress: '$what $tag, Hamra, Beirut',
      );
      step('placed ${(order['id'] as String).substring(0, 8)} — $what');
      return order['id'] as String;
    }

    // ============================================================ before acceptance: it works

    final String firstOrder = await placeOne('Cancelled');
    await openOrders();

    await pumpUntil(
      tester,
      find.descendant(
        of: topCard(),
        matching: find.widgetWithText(CustomerStatusPill, OrderStatus.placed.labelIn(en)),
      ),
      timeout: const Duration(seconds: 60),
      reason: 'The new order never reached the customer\'s list.',
    );

    final Finder cancelPill =
        find.descendant(of: topCard(), matching: find.widgetWithText(YdPillButton, en.cancel));
    expect(cancelPill, findsOneWidget,
        reason: 'A just-placed order offers no Cancel button. The pill is drawn only when the '
            'server includes CANCEL in the order\'s availableActions, so the server is not '
            'offering it either.');
    await tester.ensureVisible(cancelPill);
    await tester.pump();
    await tester.tap(cancelPill);

    await pumpUntil(tester, find.text(en.cancelThisOrder),
        timeout: const Duration(seconds: 15),
        reason: 'Tapping Cancel did not raise the confirmation dialog.');
    // Asked before it is done, and the wording says what the window is.
    expect(find.text(en.cancelBeforeAccepted), findsOneWidget);
    expect(find.widgetWithText(TextButton, en.keepIt), findsOneWidget,
        reason: 'There is no way out of the cancellation dialog.');

    await tester.tap(find.widgetWithText(ElevatedButton, en.cancelOrder));
    await tester.pump();

    // The Past tab, because a cancelled order is no longer live.
    final Finder pastTab = find.descendant(
        of: find.byType(MyOrdersScreen), matching: find.text(en.custPastOrdersTab));
    if (pastTab.evaluate().isNotEmpty) {
      await tester.tap(pastTab.first);
      await pumpFor(tester, const Duration(milliseconds: 600));
    }
    await pumpUntil(
      tester,
      find.widgetWithText(CustomerStatusPill, OrderStatus.cancelled.labelIn(en)),
      timeout: const Duration(seconds: 45),
      reason: 'The order was cancelled but never appeared as '
          '"${OrderStatus.cancelled.labelIn(en)}" on the Past tab. If a message read '
          '"${en.tooLateToCancel}" the merchant accepted it first, which is a data race on a '
          'shared environment rather than a client bug.',
    );
    step('the customer sees it as ${OrderStatus.cancelled.labelIn(en)}');

    // The screen said so; the server has to agree.
    expect((await Backend.order(customerToken, firstOrder))['status'], 'CANCELLED',
        reason: 'The customer\'s screen shows the order as cancelled but the server still has it '
            'live — the merchant would still be making it.');

    // ============================================================ after acceptance: it is gone

    final String secondOrder = await placeOne('Accepted');

    final Finder activeTab = find.descendant(
        of: find.byType(MyOrdersScreen), matching: find.textContaining(en.custActiveOrdersTab(0).split('(').first.trim()));
    if (activeTab.evaluate().isNotEmpty) {
      await tester.tap(activeTab.first);
      await pumpFor(tester, const Duration(milliseconds: 600));
    }
    await pumpUntil(
      tester,
      find.descendant(
        of: topCard(),
        matching: find.widgetWithText(CustomerStatusPill, OrderStatus.placed.labelIn(en)),
      ),
      timeout: const Duration(seconds: 60),
      reason: 'The second order never reached the list.',
    );
    expect(find.descendant(of: topCard(), matching: find.widgetWithText(YdPillButton, en.cancel)),
        findsOneWidget,
        reason: 'The second order should still be cancellable — it has not been accepted yet.');

    // The merchant accepts it while the customer is looking at the screen.
    await BusinessFlow.advance(merchantToken, secondOrder, 'accept');
    step('the merchant accepted it');

    await pumpUntil(
      tester,
      find.descendant(
        of: topCard(),
        matching: find.widgetWithText(CustomerStatusPill, OrderStatus.accepted.labelIn(en)),
      ),
      timeout: const Duration(seconds: 90),
      reason: 'The acceptance never reached the customer\'s list.',
    );

    // THE ASSERTION THIS SCENARIO EXISTS FOR. The server would now refuse a customer cancellation,
    // and the app has to stop offering it — otherwise the person taps a live button and is told
    // no, which reads as a broken app rather than as a rule.
    expect(
      find.descendant(of: topCard(), matching: find.widgetWithText(YdPillButton, en.cancel)),
      findsNothing,
      reason: 'The Cancel button is still on an accepted order. The server refuses a customer '
          'cancellation once the status is past PLACED, so this button can only ever produce an '
          'error — the app is offering an action it cannot perform.',
    );
    step('and the Cancel button is gone, as it should be');

    // Left tidy: an ACCEPTED order abandoned on a shared environment stalls the merchant queue for
    // whoever runs next. The merchant may still cancel what the customer no longer can.
    await BusinessFlow.advance(merchantToken, secondOrder, 'cancel');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
