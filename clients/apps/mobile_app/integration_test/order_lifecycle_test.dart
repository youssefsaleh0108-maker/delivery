import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_merchant/delivery_merchant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_app/main.dart' as app;
import 'package:mobile_app/src/cart_screen.dart';
import 'package:mobile_app/src/checkout_screen.dart';
import 'package:mobile_app/src/customer_nav_bar.dart';
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/merchant_shell.dart';
import 'package:mobile_app/src/my_orders_screen.dart';
import 'package:mobile_app/src/order_details_screen.dart';
import 'package:mobile_app/src/product_detail_screen.dart';
import 'package:mobile_app/src/rider_home_screen.dart';
import 'package:mobile_app/src/rider_job_card.dart';
import 'package:mobile_app/src/rider_order_detail_screen.dart';
import 'package:mobile_app/src/store_home_screen.dart';
import 'package:mobile_app/src/store_page_screen.dart';

import 'support/backend.dart';
import 'support/journey.dart';

/// **One order, three people, one phone.** The business flow this whole platform exists for,
/// driven the way it actually happens: a customer buys something, a merchant makes it, a rider
/// carries it, and the customer sees it arrive.
///
/// <p><strong>Why this test and not another screen tour.</strong> The six integration tests before
/// this one all stop at the same place — they sign in, they navigate, they read. Every one of them
/// would still pass on a platform where no order could ever be delivered. That is not a
/// hypothetical: while this test was being written, the dev environment was in exactly that state.
/// Orders reached READY and stopped, because the demo rider had been left in an external carrier's
/// fleet by a suite that failed before its cleanup ran, and the job board is scoped to the rider's
/// fleet. Every screen was correct. Every existing test was green. No order could be delivered.
///
/// <p><strong>What is driven through the UI, and what is not.</strong> Every act a human performs
/// is a tap in this test: choosing the shop, adding to the basket, typing the address, placing the
/// order, accepting it, preparing it, marking it ready, claiming it, collecting it, delivering it.
/// The only things done over HTTP are the preconditions — a published product to buy and a rider
/// in the fleet dispatch routes to — and the corroboration afterwards, where the server is asked
/// whether it agrees with what the screens said. See [Backend].
///
/// <p><strong>Sign-out between roles is real, and it works.</strong> `AuthService.signOut()` nulls
/// the session, deletes the refresh token, clears the biometric stash and ends the Keycloak SSO
/// session; the Dio interceptor reads the session per request rather than caching a header; the
/// cart is a field of `_CustomerShellState`, itself keyed by subject. Nothing of role A survives
/// into role B — except `delivery.last_username`, which is kept on purpose and is exactly why
/// [signIn] clears the field before typing.
///
/// <p><strong>How to run it.</strong> The defines are not optional; without them the app talks to
/// a LAN address, Android blocks it as cleartext, and the failure reads as a wrong password.
///
/// ```
/// adb uninstall com.delivery.mobile_app
/// flutter test integration_test/order_lifecycle_test.dart -d <device> --flavor dev \
///   --dart-define=API_BASE_URL=https://api-dev.youdrop.shop \
///   --dart-define=KEYCLOAK_ISSUER=https://iam-dev.youdrop.shop/realms/delivery-platform
/// adb shell pm grant com.delivery.mobile_app android.permission.POST_NOTIFICATIONS
/// adb shell pm grant com.delivery.mobile_app android.permission.ACCESS_FINE_LOCATION
/// ```
///
/// The uninstall is part of the test: a stored session skips the sign-in screen entirely, and a
/// saved address skips the address sheet. The permission grants stop the Android dialogs — which
/// live outside the Flutter tree, where no assertion can see them — from landing over the app and
/// stalling frame production.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Stamped into the product name and the delivery address so this run's order is findable among
  /// a shared environment's history, on screens that show no order reference at all — the rider's
  /// offer card in particular renders the delivery address and never the order id.
  final String tag = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();

  /// Stable on purpose, and re-used run after run. A per-run product name looks tidier and is
  /// wrong: the shop page lists products lazily, so every extra fixture pushes the newest one
  /// further down a list the test then has to scroll, and after a handful of runs the demo shop is
  /// nothing but test data. [Backend.ensureSellableProduct] returns the existing one when the name
  /// already exists, so this creates exactly one product, once, forever.
  const String productName = 'Scenario Plate';

  /// The ADDRESS is what carries the run id, because it is what has to be unique: the rider's
  /// offer card renders the delivery address and no order reference at all, so it is the only
  /// handle a test has for picking its own job off a shared board.
  final String addressLine = 'Flat $tag, Hamra, Beirut';

  testWidgets('an order is bought, made, carried, and arrives', (WidgetTester tester) async {
    // ============================================================ the world, before anybody taps

    final String customerToken = await Backend.signIn('customer');
    final String merchantToken = await Backend.signIn('merchant');
    final String riderToken = await Backend.signIn('rider');
    final String backofficeToken = await Backend.signIn('backoffice');

    final Map<String, dynamic> store = await Backend.merchantStore(merchantToken);
    final String shopName = store['name'] as String;
    step('the merchant\'s own shop is "$shopName"');

    // Anything else and the merchant who signs in below cannot accept the order: the seeded
    // storefront shops belong to a synthetic account, and /accept checks order.isMerchant(caller).
    await Backend.ensureSellableProduct(
      merchantToken,
      customerToken,
      store,
      name: productName,
    );
    step('"$productName" is published and visible to a customer');

    // Both halves of "can the rider ever see this job". The merchant must not be pinned to a
    // carrier, and the rider must not be a member of one — either alone is enough to route the
    // order somewhere this rider cannot reach it, and the symptom is identical: an order that
    // reaches READY and stays there while the board stays empty.
    await Backend.clearMerchantCarrierPin(merchantToken);
    await Backend.putRiderBackInHouse(backofficeToken, Backend.subjectOf(riderToken));
    step('dispatch is unpinned and the rider is in the in-house fleet');

    // ============================================================ the customer buys something

    await app.main();
    await signIn(tester, 'customer', '100001', expectedShell: CustomerShell);

    await pumpUntil(tester, find.text(en.custActiveStoresNearby),
        reason: 'The storefront never finished loading.');

    // Searched for by name rather than picked off the top of the list: which shops the dev
    // catalogue happens to surface first is not something this test can know, and the ONLY shop
    // whose orders the merchant below can work is this one.
    final Finder searchField = find.descendant(
      of: find.descendant(of: find.byType(StoreHomeScreen), matching: find.byType(YdSearchField)),
      matching: find.byType(TextField),
    );
    Finder shopCard() => find
        .ancestor(
          of: find.descendant(
            of: find.byType(StoreHomeScreen),
            matching: find.byWidgetPredicate((Widget w) =>
                w is Text &&
                w.data == shopName &&
                w.style?.fontSize == 14 &&
                w.style?.fontWeight == FontWeight.w700),
          ),
          matching: find.byType(YdCard),
        );

    // Typed more than once if it has to be. The search debounces for 350ms and then calls
    // refresh(), which sets isLoadingFirstPage and REPLACES the grid with a spinner — so a query
    // that lands while the storefront's own first page is still arriving can be superseded, and
    // the box ends up holding text that was never sent. Re-typing is cheap; a 45-second wait on a
    // search that never happened is not.
    for (int attempt = 0; attempt < 3 && shopCard().evaluate().isEmpty; attempt++) {
      await tester.enterText(searchField, shopName);
      await pumpFor(tester, const Duration(milliseconds: 1500)); // debounce, then the re-query
      await appearsWithin(tester, shopCard(), const Duration(seconds: 20));
    }

    await pumpUntil(tester, shopCard(),
        reason: 'Searching for "$shopName" returned no card for it. The shop exists — the fixture '
            'above read it off /api/stores/mine — so either it is not on the public storefront or '
            'the search did not reach the server. On screen: ${describeScreen(tester)}');
    await tester.tap(shopCard().firstOrNothing);
    await pumpUntil(tester, find.byType(StorePageScreen),
        reason: 'Tapping the shop card did not open the shop.');
    step('opened $shopName');

    // The product ROW, deliberately not the round add button beside it. `AddButton` is disabled
    // whenever the server reports the shop as anything but open — and StoreAvailability.fromWire
    // defaults to CLOSED for an absent value — so on a shop with no availability set the add
    // button is permanently dead and a tap on it silently does nothing. The row has no such gate.
    final Finder productRow = find.descendant(
      of: find.byType(StorePageScreen),
      matching: find.text(productName),
    );

    // The shelf loads before the row can be looked for, and a row below the fold does not exist:
    // the list builds lazily, so `find.text` on an unbuilt item matches nothing whether the shop
    // has one product or fifty. Wait for the shelf, then scroll to the item.
    await pumpUntil(
      tester,
      find.descendant(of: find.byType(StorePageScreen), matching: find.byType(YdCard)),
      timeout: const Duration(seconds: 60),
      reason: 'The shop page never drew a single product card. If it reads '
          '"${en.nothingOnShelves}" the shop is genuinely empty, which contradicts the fixture.',
    );
    if (productRow.evaluate().isEmpty) {
      final Finder shelf = find
          .descendant(of: find.byType(StorePageScreen), matching: find.byType(Scrollable))
          .first;
      try {
        await tester.scrollUntilVisible(productRow, 250, scrollable: shelf,
            maxScrolls: 60, duration: const Duration(milliseconds: 40));
      } on StateError {
        // Swallowed so the assertion below reports what happened, rather than this reporting
        // that it ran out of scrolls.
      }
    }
    await pumpUntil(tester, productRow,
        timeout: const Duration(seconds: 30),
        reason: 'The shop page never listed "$productName", although the fixture confirmed a '
            'customer can see it through /api/stores/{id}/products. On screen: '
            '${describeScreen(tester)}');
    await tester.ensureVisible(productRow.first);
    await tester.pump();
    await tester.tap(productRow.first);

    await pumpUntil(tester, find.byType(ProductDetailScreen),
        reason: 'Tapping the product row did not open it. storeApi.productOptions(id) is awaited '
            'BEFORE the push, so a hanging options call stalls exactly here.');

    final Finder addToBasket = find.descendant(
      of: find.byType(ProductDetailScreen),
      matching: find.text(en.custAddToBasket),
    );
    await pumpUntil(tester, addToBasket,
        reason: 'The Add to Basket CTA never became available. If the screen instead reads '
            '"${en.selectRequiredOptions}" this product grew a required option group and the '
            'fixture needs to answer it.');
    await tester.ensureVisible(addToBasket);

    // The label is on screen before the button works. `canAdd` also requires the server-side price
    // to have come back — `_pricing` false, `_priceError` null, `_priced` non-null when the product
    // needs pricing — and only the REQUIRED-OPTIONS case changes the wording. So a tap the instant
    // the text appears lands on a live-looking, dead control, and the screen simply does not pop.
    await pumpUntil(
      tester,
      find.descendant(
        of: find.byType(ProductDetailScreen),
        matching: find.byWidgetPredicate(
          (Widget w) => w is Semantics && w.properties.button == true && w.properties.enabled == true,
          description: 'an enabled button on the product screen',
        ),
      ),
      timeout: const Duration(seconds: 45),
      reason: 'The Add to Basket CTA never became enabled — the price call has not come back. '
          'On screen: ${describeScreen(tester)}',
    );
    await tester.pump();
    await tester.tap(addToBasket);
    await pumpUntilGone(tester, find.byType(ProductDetailScreen),
        timeout: const Duration(seconds: 30),
        reason: 'Add to Basket did not pop the product screen, so the CTA was still disabled. '
            'On screen: ${describeScreen(tester)}');
    step('added "$productName" to the basket');

    // Back to the shell first. StorePageScreen is a PUSHED route and the shell — nav bar included
    // — sits underneath it, so tapping a tab from here finds nothing at all. The sticky basket bar
    // that appears once the cart is non-empty is the shop page's own way out: its onTap is a pop.
    //
    // Matched on the widget rather than on the label, because the bar RENAMES itself: when the
    // basket is under the shop's minimum order it renders `addToReachMinimumShort` instead of
    // "View basket" and its onTap is null. Finding it by type and then reading the label back is
    // what tells those two apart.
    final Finder basketBar = find.byType(StickyBasketBar);
    if (!await appearsWithin(tester, basketBar, const Duration(seconds: 45))) {
      fail('The basket bar never appeared on the shop page, so nothing reached the cart. '
          'On screen: ${describeScreen(tester)}');
    }
    final StickyBasketBar bar = tester.widget<StickyBasketBar>(basketBar);
    expect(bar.blockedReason, isNull,
        reason: 'The basket is under this shop\'s minimum order, so the bar reads '
            '"${bar.blockedReason}" and cannot be tapped. The fixture prices one item above the '
            'minimum, so the shop minimum has changed.');
    expect(bar.itemCount, greaterThan(0));

    // The InkWell, not the bar. StickyBasketBar wraps itself in a SafeArea and a Padding, so on a
    // phone with gesture navigation the widget's centre can sit in the bottom inset rather than
    // on the tappable surface — the tap lands on nothing and the page simply does not pop.
    final Finder basketTap =
        find.descendant(of: basketBar, matching: find.byType(InkWell)).firstOrNothing;
    expect(basketTap, findsOneWidget, reason: 'The basket bar has no tappable surface.');
    await tester.tap(basketTap);
    await pumpUntilGone(tester, find.byType(StorePageScreen),
        timeout: const Duration(seconds: 30),
        reason: 'The basket bar did not return the app to the shell.');

    await tester.tap(find.descendant(
        of: find.byType(CustomerNavBar), matching: find.text(en.navBasket)));
    await pumpUntil(tester, find.byType(CartScreen),
        reason: 'The Basket tab did not build.');

    final Finder proceed = find.widgetWithText(YdPillButton, en.custProceedToCheckout);
    expect(find.widgetWithText(YdPillButton, en.minimumNotReached), findsNothing,
        reason: 'The basket is under this shop\'s minimum order, so checkout is disabled. The '
            'fixture prices one item above the minimum, so this means the shop minimum changed.');
    await pumpUntil(tester, proceed, reason: 'The checkout button is not on the basket screen.');
    await tester.ensureVisible(proceed);
    await tester.pump();
    await tester.tap(proceed);
    await pumpUntil(tester, find.byType(CheckoutScreen),
        reason: 'Proceeding from the basket did not reach checkout.');

    // ------------------------------------------------------------ the address

    // A NEW address every run, even when the device already has some. There is no server-side
    // address book — DeliveryAddressStore is device-local secure storage keyed by the Keycloak
    // subject — so a fresh install starts with none and a re-run starts with every address the
    // previous runs typed. Either way this run needs its OWN tagged line on the order, because
    // the rider's offer card renders the delivery address and nothing else that identifies it.
    final Finder emptyStateCard = find.widgetWithText(YdCard, en.chooseAnAddress);
    final Finder addAnother = find.widgetWithText(InkWell, en.addANewAddress);
    final Finder openTheSheet =
        emptyStateCard.evaluate().isNotEmpty ? emptyStateCard : addAnother;
    expect(openTheSheet, findsWidgets,
        reason: 'Checkout offers no way to add an address: neither the '
            '"${en.chooseAnAddress}" empty state nor "${en.addANewAddress}" is on screen.');
    await tester.ensureVisible(openTheSheet.first);
    await tester.pump();
    await tester.tap(openTheSheet.first);
    await pumpUntil(tester, find.text(en.whereShouldWeBring),
        reason: 'The address sheet did not open.');

    await tester.enterText(
      find.byWidgetPredicate(
        (Widget w) => w is TextField && w.decoration?.hintText == en.addressHint,
        description: 'the address line field',
      ),
      addressLine,
    );
    await tester.pump();

    // The Area picker exists only where the deployment has zones configured, and where it does its
    // validator blocks saving until something is chosen. Branching on its presence rather than
    // assuming either way.
    final Finder zonePicker = find.byType(DropdownButtonFormField<String>);
    if (zonePicker.evaluate().isNotEmpty) {
      await tester.tap(zonePicker);
      await pumpFor(tester, const Duration(milliseconds: 600));
      final Finder anyZone = find.byType(DropdownMenuItem<String>).last;
      if (anyZone.evaluate().isNotEmpty) {
        await tester.tap(anyZone, warnIfMissed: false);
        await pumpFor(tester, const Duration(milliseconds: 400));
      }
    }

    // Deliberately no map pin. A pinned address turns on checkout's haversine radius guard, which
    // can refuse the order outright; with no pin that branch never runs.
    final Finder deliverHere = find.widgetWithText(ElevatedButton, en.deliverHere);
    await tester.ensureVisible(deliverHere);
    await tester.pump();
    await tester.tap(deliverHere);
    await pumpUntilGone(tester, find.text(en.whereShouldWeBring),
        timeout: const Duration(seconds: 30),
        reason: 'The address form did not validate. Look for "${en.addressTooShort}" or '
            '"${en.pickYourArea}" on the sheet.');

    // Present is not the same as chosen. On a device carrying addresses from earlier runs the new
    // one is one radio among several, and an order placed against the wrong one would carry an
    // address the rider step below can never find.
    final Finder thisRunsAddress = find.textContaining('Flat $tag');
    await pumpUntil(tester, thisRunsAddress,
        reason: 'The saved address never became a selectable card on checkout.');
    await tester.ensureVisible(thisRunsAddress.first);
    await tester.pump();
    await tester.tap(thisRunsAddress.first);
    await tester.pump();
    step('entered the delivery address');

    // ------------------------------------------------------------ speed, payment, and the order

    for (final Finder choice in <Finder>[
      find.widgetWithText(InkWell, en.deliveryTierStandard),
      find.widgetWithText(InkWell, en.custCashUsdLbp),
    ]) {
      if (choice.evaluate().isEmpty) continue;
      await tester.ensureVisible(choice.first);
      await tester.pump();
      await tester.tap(choice.first);
      await tester.pump();
    }

    // The pill's label carries the total, which the test cannot know, so it is matched on the
    // fixed half of the ICU string rather than on the whole rendered sentence.
    final String placePrefix = en.custPlaceOrderAmount('~').split('(').first.trim();
    final Finder place = find.byWidgetPredicate(
      (Widget w) => w is YdPillButton && w.label.startsWith(placePrefix),
      description: 'the Place Order pill',
    );
    await tester.ensureVisible(place.first);
    await tester.pump();
    await tester.tap(place.first);
    await pumpUntilGone(tester, find.byType(CheckoutScreen),
        timeout: const Duration(seconds: 120),
        reason: 'POST /api/orders never came back, or it was refused. Look for a SnackBar reading '
            '"${en.couldNotPlaceOrder}" or "${en.itemNoLongerAvailable}".');
    step('placed the order');

    // ------------------------------------------------------------ what did the server record?

    // The order id is read from the SERVER, not scraped off a toast that has four seconds to live.
    // Everything below needs it, and a missed toast would fail the run for a reason that has
    // nothing to do with the business flow.
    final Map<String, dynamic>? mine = await Backend.waitFor<Map<String, dynamic>>(
      () async {
        for (final dynamic o in await Backend.myOrders(customerToken)) {
          final Map<String, dynamic> order = o as Map<String, dynamic>;
          if ((order['deliveryAddress'] as String?)?.contains(tag) ?? false) return order;
        }
        return null;
      },
      timeout: const Duration(seconds: 60),
    );
    expect(mine, isNotNull,
        reason: 'The app said the order was placed, but no order carrying this run\'s address '
            '("$addressLine") is on /api/orders/mine. Nothing was actually created.');

    final String orderId = mine!['id'] as String;
    final String shortId = orderId.substring(0, 8);
    step('the order is $shortId');

    expect(mine['status'], 'PLACED');

    // And the customer's own screen agrees, in their own words.
    await tester.tap(find.descendant(
        of: find.byType(CustomerNavBar), matching: find.text(en.navOrders)));
    await pumpUntil(tester, find.byType(MyOrdersScreen), reason: 'The Orders tab did not build.');
    await pumpUntil(
      tester,
      find.widgetWithText(CustomerStatusPill, OrderStatus.placed.labelIn(en)),
      timeout: const Duration(seconds: 60),
      reason: 'The customer\'s own order list never showed the order as '
          '"${OrderStatus.placed.labelIn(en)}".',
    );
    step('the customer sees it as ${OrderStatus.placed.labelIn(en)}');

    await signOutCustomer(tester);

    // ============================================================ the merchant makes it

    await signIn(tester, 'merchant', '200002', expectedShell: MerchantShell);

    await tester.tap(find.descendant(
        of: find.byType(YdBottomNav), matching: find.text(en.navOrders)));
    await pumpUntil(tester, find.byType(OrdersScreen),
        reason: 'The merchant Orders tab did not build.');

    // The queue is bucketed, and each transition moves the row to a DIFFERENT tab: New holds
    // PLACED, Preparing holds ACCEPTED and PREPARING, Ready holds READY. So the walk is
    // tab → act → next tab, and asserting the row landed in the next bucket is what proves the
    // transition rather than the button merely having been pressed.
    Finder orderCard() =>
        find.ancestor(of: find.textContaining(shortId), matching: find.byType(YdCard));

    /// Scrolls the queue back to the top and selects one bucket.
    ///
    /// The scroll is not defensive. On a phone the queue is ONE CustomScrollView — header, tab
    /// strip and cards scroll together — so the ensureVisible that reached the previous action
    /// button has carried the tab strip off the top of the viewport, where its sliver is
    /// destroyed and no finder can reach it. Nothing is wrong with the screen; the test simply
    /// scrolled away from the control it needs next.
    Future<void> openBucket(String bucket) async {
      final Finder queue = find
          .descendant(of: find.byType(OrdersScreen), matching: find.byType(Scrollable))
          .firstOrNothing;
      for (int i = 0; i < 6; i++) {
        if (queue.evaluate().isEmpty) break;
        await tester.drag(queue, const Offset(0, 400));
        await tester.pump(const Duration(milliseconds: 60));
      }

      // textContaining, not text: a bucket with anything in it renders its label with a count
      // appended — "New (3)" — so an exact match finds the tab only while it is empty, which is
      // precisely when the test does not need it.
      final Finder tab = find.descendant(
        of: find.byType(OrdersScreen),
        matching: find.textContaining(bucket),
      );
      await pumpUntil(tester, tab,
          timeout: const Duration(seconds: 20),
          reason: 'The "$bucket" tab is not on the merchant queue. On screen: '
              '${describeScreen(tester)}');
      await tester.tap(tab.firstOrNothing);
      await pumpFor(tester, const Duration(milliseconds: 600));
    }

    Future<void> merchantDoes(String bucket, String action) async {
      await openBucket(bucket);
      await pumpUntil(tester, orderCard(),
          timeout: const Duration(seconds: 60),
          reason: 'Order #$shortId is not in the "$bucket" tab. The queue loads only the newest '
              'fifty orders, so on a busy dev shop an older order simply is not on this screen. '
              'On screen: ${describeScreen(tester)}');
      // Waited for, not asserted once. While a card is busy every button on it renders a
      // CircularProgressIndicator INSTEAD of its label, so a finder that looks the instant after
      // the previous tap sees a card with no buttons at all — and reports it as the order being
      // in the wrong state, which is the one thing it is not.
      final Finder button = find.descendant(
        of: orderCard().firstOrNothing,
        matching: find.widgetWithText(MerchantActionButton, action),
      );
      await pumpUntil(tester, button,
          timeout: const Duration(seconds: 45),
          reason: 'The "$action" button never appeared on order #$shortId. The client renders '
              'exactly the actions the server offers, so if the card is not merely busy then the '
              'order is not in the state this step expects. On screen: ${describeScreen(tester)}');
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();

      // Every failure on this screen is a SnackBar that auto-dismisses, and the row simply not
      // moving looks identical to a 403 or a 422. Checked on the frame right after the tap.
      expect(find.text(en.orderAlreadyMovedRefreshing), findsNothing,
          reason: 'The server refused "$action" on #$shortId because the order had already moved.');
      step('merchant: $action');
    }

    // The tab named here is where the order is BEFORE the action, which is not the tab named
    // after the action. The buckets hold statuses, not steps: New is PLACED, Preparing is
    // ACCEPTED *and* PREPARING, Ready is READY and PICKED_UP. So an accepted order and a
    // preparing one are worked from the same tab, and only "Mark ready" moves the card out of it.
    await merchantDoes(en.merchTabNew, OrderAction.accept.labelIn(en));
    await merchantDoes(en.stepPreparing, OrderAction.prepare.labelIn(en));
    await merchantDoes(en.stepPreparing, OrderAction.ready.labelIn(en));

    // And now it should have left. Asserting where the card LANDED is what proves the last
    // transition — the tap alone only proves a button was pressed.
    await openBucket(en.stepReady);
    await pumpUntil(tester, orderCard(),
        timeout: const Duration(seconds: 45),
        reason: 'Order #$shortId was marked ready but is not in the "${en.stepReady}" tab, so the '
            'card did not move and the merchant has no sign the shop\'s part is done.');
    step('the order is on the counter');

    expect((await Backend.order(merchantToken, orderId))['status'], 'READY',
        reason: 'The three taps landed but the order is not READY, so one of them did not take.');

    await signOutMerchant(tester);

    // ============================================================ the rider carries it

    await signIn(tester, 'rider', '300003', expectedShell: RiderHomeScreen);

    // The offer card renders the delivery address and never an order reference — which is why the
    // address carries this run's tag. Matching on it is the only way to be sure the job claimed
    // below is the one this test placed and not somebody else's order on a shared environment.
    final Finder offer =
        find.ancestor(of: find.textContaining(tag), matching: find.byType(RiderJobCard));

    // The board is ORDER BY placedAt ASC — OLDEST first — and the screen asks for thirty. Nothing
    // ever cleans up a READY order nobody collected, so every abandoned run of anything sits
    // ahead of this one and the newest job is at the BOTTOM. Waiting alone is not enough: the
    // card has to be scrolled to before it is built, and if the board has more than thirty stale
    // jobs on it this order is not on the page at all.
    if (!await appearsWithin(tester, offer, const Duration(seconds: 20))) {
      final Finder board = find
          .descendant(of: find.byType(RiderHomeScreen), matching: find.byType(Scrollable))
          .firstOrNothing;
      for (int i = 0; i < 4 && offer.evaluate().isEmpty; i++) {
        try {
          await tester.scrollUntilVisible(offer, 300, scrollable: board,
              maxScrolls: 40, duration: const Duration(milliseconds: 40));
        } on StateError {
          // Out of scrolls for now; the board refreshes every five seconds, so try again.
        }
        await pumpFor(tester, const Duration(seconds: 6));
      }
    }
    await pumpUntil(tester, offer,
        timeout: const Duration(minutes: 2),
        reason: 'Order #$shortId reached READY but never appeared on the rider\'s board. Two '
            'causes look identical from here. Either the board is scoped away from this rider — '
            'findAvailableFor returns only orders whose deliveryProviderId is the rider\'s own '
            'fleet or null, so a rider left in an external carrier sees nothing while the order '
            'sits on the counter forever — or the board is simply full: it is sorted oldest '
            'first, capped at thirty, and stale READY orders are never cleaned up, so a busy '
            'environment pushes new work off the end.');
    step('the job is on the rider\'s board');

    final Finder accept = find.descendant(
        of: offer.firstOrNothing,
        matching: find.widgetWithText(RiderButton, en.riderAcceptDelivery));
    expect(accept, findsOneWidget,
        reason: 'The job is on the board but offers no "${en.riderAcceptDelivery}" button. If a '
            '"${en.pendingBannerRider}" banner is showing, this account still carries APPLICANT '
            'and the server will refuse the claim with a 403 the app reports as a generic '
            'failure.');
    await tester.ensureVisible(accept);
    await tester.pump();
    await tester.tap(accept);

    // Claiming does not change the order's STATUS — it only sets riderId — so there is no status
    // change to wait on. The shell switching itself to the Active tab is what a successful claim
    // looks like, and a lost race shows only as a SnackBar that is gone before it can be read.
    await pumpUntil(tester, find.text(en.riderTabActive),
        reason: 'The rider shell did not move to the Active tab, so the claim did not succeed.');
    await pumpFor(tester, const Duration(seconds: 2));
    expect((await Backend.order(riderToken, orderId))['riderId'], isNotNull,
        reason: 'The board moved on but the order still has no rider, so another rider won the '
            'claim — or it never went through.');
    step('rider: claimed');

    // Both committing acts live on the detail screen, and it pops itself after each one, so this
    // is two separate visits rather than two taps.
    Future<void> riderDoes(String label) async {
      final Finder viewDetails = find.widgetWithText(RiderButton, en.riderViewDetails);
      await pumpUntil(tester, viewDetails,
          timeout: const Duration(seconds: 60),
          reason: 'No task card offering "${en.riderViewDetails}" is on the Active tab.');
      await tester.ensureVisible(viewDetails.first);
      await tester.pump();
      await tester.tap(viewDetails.first);
      await pumpUntil(tester, find.byType(RiderOrderDetailScreen),
          reason: 'The job did not open.');

      final Finder button = find.widgetWithText(RiderButton, label);
      expect(button, findsOneWidget,
          reason: 'The detail screen is not offering "$label". It holds a SNAPSHOT of the order '
              'taken when the card was tapped and never re-reads it, so this is a stale screen '
              'rather than a wrong state.');
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await pumpUntilGone(tester, find.byType(RiderOrderDetailScreen),
          timeout: const Duration(seconds: 60),
          reason: '"$label" did not pop the detail screen, so the action did not go through.');
      step('rider: $label');
    }

    await riderDoes(OrderAction.pickUp.labelIn(en));
    expect(
      await Backend.waitFor<bool>(() async =>
          (await Backend.order(riderToken, orderId))['status'] == 'PICKED_UP' ? true : null),
      isTrue,
      reason: 'The screen accepted "picked up" but the order is not PICKED_UP.',
    );

    await riderDoes(OrderAction.deliver.labelIn(en));
    expect(
      await Backend.waitFor<bool>(() async =>
          (await Backend.order(riderToken, orderId))['status'] == 'DELIVERED' ? true : null),
      isTrue,
      reason: 'The screen accepted "delivered" but the order is not DELIVERED.',
    );

    await signOutRider(tester);

    // ============================================================ and the customer sees it arrive

    await signIn(tester, 'customer', '100001', expectedShell: CustomerShell);
    await tester.tap(find.descendant(
        of: find.byType(CustomerNavBar), matching: find.text(en.navOrders)));
    await pumpUntil(tester, find.byType(MyOrdersScreen), reason: 'The Orders tab did not build.');

    // Past, not Active: a delivered order leaves the live list.
    final Finder pastTab = find.descendant(
        of: find.byType(MyOrdersScreen), matching: find.text(en.custPastOrdersTab));
    if (pastTab.evaluate().isNotEmpty) {
      await tester.tap(pastTab.first);
      await pumpFor(tester, const Duration(milliseconds: 600));
    }
    await pumpUntil(
      tester,
      find.widgetWithText(CustomerStatusPill, OrderStatus.delivered.labelIn(en)),
      timeout: const Duration(seconds: 60),
      reason: 'The order was delivered but the customer\'s own list never said so.',
    );
    step('the customer sees it as ${OrderStatus.delivered.labelIn(en)}');

    // ============================================================ does the ledger agree?

    final List<String> history = await Backend.historyOf(backofficeToken, orderId);
    expect(
      history.where((String s) => s != 'READY').toList(),
      <String>['PLACED', 'ACCEPTED', 'PREPARING', 'PICKED_UP', 'DELIVERED'],
      reason: 'The recorded history is not the journey these screens just performed. (READY is '
          'filtered because claiming writes a second READY entry without changing the status.)',
    );

    // Money is posted asynchronously off an order.delivered event, so this polls rather than
    // asserting into a race.
    final List<dynamic>? legs = await Backend.waitFor<List<dynamic>>(
      () async {
        final List<dynamic> found = await Backend.ledgerOf(backofficeToken, orderId);
        return found.isEmpty ? null : found;
      },
      timeout: const Duration(seconds: 90),
    );
    expect(legs, isNotNull,
        reason: 'The order was delivered but settlement posted no accounting legs for it. The '
            'customer paid and nobody was credited.');
    step('settled: ${legs!.map((dynamic l) => (l as Map<String, dynamic>)['leg']).join(', ')}');
  }, timeout: const Timeout(Duration(minutes: 25)));
}
