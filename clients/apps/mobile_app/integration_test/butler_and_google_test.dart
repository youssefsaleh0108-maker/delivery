import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_app/main.dart' as app;
import 'package:mobile_app/src/butler_request_details_screen.dart';
import 'package:mobile_app/src/butler_screen.dart';
import 'package:mobile_app/src/customer_nav_bar.dart';
import 'package:mobile_app/src/customer_shell.dart';
import 'package:mobile_app/src/sign_in_screen.dart';

import 'support/backend.dart';
import 'support/journey.dart';

/// The Butler errand page and the Google button, on a real phone against the dev backend.
///
/// <p>Both were built on widget tests with a fake Dio, which prove the screens draw what they are
/// handed. What they cannot prove is the seam this checks: that an errand a real shopper claimed
/// and priced on the real server opens from the real list, shows the server's own numbers, and
/// that Pay and Cancel change what the SERVER holds — read back over HTTP afterwards, not taken
/// from the screen's word for it.
///
/// <p><strong>What is arranged over HTTP, and why.</strong> The customer's own screens are the
/// subject here, so the two things somebody else does — a rider claiming the errand and quoting
/// its price — happen through [Backend] before the app starts. Everything the customer does is a
/// tap.
///
/// <p><strong>Google.</strong> The provider ships disabled until the owner creates an OAuth client
/// (docs/google-sign-in.md), and the app asks Keycloak whether it is available before offering it.
/// So on dev today the honest outcome of tapping Google is "coming soon", and that is what is
/// asserted — with the role question accepted instead if somebody has since switched it on, since
/// that is the other correct answer and the one this test should keep passing through.
///
/// <p>Run it like the other device scenarios — uninstall first, grant notifications and location,
/// point the build at dev:
/// ```
/// adb uninstall com.delivery.mobile_app
/// flutter test integration_test/butler_and_google_test.dart -d <device> --flavor dev \
///   --dart-define=API_BASE_URL=https://api-dev.youdrop.shop \
///   --dart-define=KEYCLOAK_ISSUER=https://iam-dev.youdrop.shop/realms/delivery-platform
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Stamped into both errands so this run's rows are findable among a shared account's history.
  final String tag = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
  final String buyWhat = 'Device check $tag: a phone charger and water';
  final String sendWhat = 'Device check $tag: an envelope of papers';
  final String dropoff = 'Flat $tag, Hamra, Beirut';

  /// The Butler tab is a scroll view with the request form above the list, and the list is not
  /// necessarily built until it is scrolled to. Drags the tab up until [target] exists.
  Future<void> scrollButlerTo(WidgetTester tester, Finder target) async {
    // The page's own list, not just "the first Scrollable": the header's search box and the
    // request form's fields each carry an EditableText Scrollable, and those come first in the
    // tree — dragging one of them scrolls a text field and leaves the page where it is.
    final Finder scrollable = find
        .descendant(
          of: find.descendant(of: find.byType(ButlerScreen), matching: find.byType(ListView)).first,
          matching: find.byType(Scrollable),
        )
        .first;
    for (int i = 0; i < 25 && target.evaluate().isEmpty; i++) {
      await tester.drag(scrollable, const Offset(0, -350));
      await pumpFor(tester, const Duration(milliseconds: 400));
    }
    await pumpUntil(tester, target,
        timeout: const Duration(seconds: 20),
        reason: 'Scrolled the whole Butler tab and never found $target.');
    await tester.ensureVisible(target.first);
    await pumpFor(tester, const Duration(milliseconds: 400));
  }

  /// [finder], but only inside the errand's details page.
  Finder onDetails(Finder finder) =>
      find.descendant(of: find.byType(ButlerRequestDetailsScreen), matching: finder);

  /// Polls the server until the errand reaches [status]. The screen saying so is not the proof.
  Future<Map<String, dynamic>> serverReaches(
      String token, String id, String status, WidgetTester tester) async {
    Map<String, dynamic> now = <String, dynamic>{};
    for (int i = 0; i < 30; i++) {
      now = await Backend.butlerRead(token, id);
      if (now['status'] == status) return now;
      await pumpFor(tester, const Duration(seconds: 1));
    }
    fail('Errand $id never reached $status on the server; it is ${now['status']}.');
  }

  testWidgets('a priced errand opens, gets paid, and an open one gets cancelled; Google answers',
      (WidgetTester tester) async {
    // ============================================================ the world, before anybody taps

    final String customerToken = await Backend.signIn('customer');
    final String riderToken = await Backend.signIn('rider');

    final Map<String, dynamic> buy = await Backend.butlerRequest(customerToken, <String, Object?>{
      'mode': 'BUY',
      'what': buyWhat,
      'sourceHint': 'Any pharmacy on Hamra Street',
      'budgetCap': 40,
      'dropoffAddress': dropoff,
    });
    final String buyId = buy['id'] as String;
    await Backend.butlerClaim(riderToken, buyId);
    await Backend.butlerQuote(riderToken, buyId, 22.40, receiptRef: 'R-$tag');
    final Map<String, dynamic> quoted = await Backend.butlerRead(customerToken, buyId);
    final String goods = (quoted['goodsCost'] as num).toStringAsFixed(2);
    final String total = (quoted['payableTotal'] as num).toStringAsFixed(2);
    step('a shopper claimed "$buyWhat" and quoted $goods, $total to pay');

    final Map<String, dynamic> send = await Backend.butlerRequest(customerToken, <String, Object?>{
      'mode': 'SEND',
      'what': sendWhat,
      'pickupAddress': 'Office 3, Achrafieh',
      'recipient': 'Rana',
      'dropoffAddress': dropoff,
    });
    final String sendId = send['id'] as String;
    step('"$sendWhat" is filed and waiting for a rider');

    // A run that fails half-way must not leave an open errand on the shared account.
    addTearDown(() async {
      await Backend.butlerCancelQuietly(customerToken, sendId);
      await Backend.butlerCancelQuietly(customerToken, buyId);
    });

    // ============================================================ the customer reads and pays

    await app.main();
    await signIn(tester, 'customer', '100001', expectedShell: CustomerShell);

    await tester.tap(find.descendant(
        of: find.byType(CustomerNavBar), matching: find.text(en.navButler)));
    await pumpUntil(tester, find.byType(ButlerScreen),
        reason: 'The Butler tab did not open.');

    // The priced errand is waiting on the customer, so it is the prominent quote card — and the
    // card is now a way in to the whole errand, not just two buttons.
    await scrollButlerTo(tester, find.text(buyWhat));
    await tester.tap(find.text(buyWhat).first);
    await pumpUntil(tester, find.byType(ButlerRequestDetailsScreen),
        timeout: const Duration(seconds: 20),
        reason: 'Tapping the quoted errand did not open its details page.');
    step('the quoted errand opened its details page');

    // The server's own numbers, on the page.
    expect(find.textContaining(goods), findsWidgets,
        reason: 'The details page does not show the goods cost the shopper quoted ($goods).');
    // Scoped to the page: the list underneath is still in the tree, and its quote card and task
    // rows carry pills with the same labels.
    final Finder pay = onDetails(find.widgetWithText(YdPillButton, en.payAmount(total)));
    await pumpUntil(tester, pay,
        timeout: const Duration(seconds: 20),
        reason: 'The details page does not offer "${en.payAmount(total)}" for a quoted errand.');
    await pumpFor(tester, const Duration(seconds: 3)); // held for the screen recording

    await tester.ensureVisible(pay);
    await tester.pump();
    await tester.tap(pay);
    await serverReaches(customerToken, buyId, 'APPROVED', tester);
    step('Pay on the details page approved it on the server');

    await pumpUntil(tester, onDetails(find.text(en.butlerTrackOrder)),
        timeout: const Duration(seconds: 30),
        reason: 'The errand is approved on the server but the page never offered Track order.');
    await pumpFor(tester, const Duration(seconds: 3));
    step('the page now offers Track order');

    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await pumpUntilGone(tester, find.byType(ButlerRequestDetailsScreen),
        reason: 'The details page did not close.');

    // ============================================================ cancelling asks first

    await scrollButlerTo(tester, find.text(sendWhat));
    await tester.tap(find.text(sendWhat).first);
    await pumpUntil(tester, find.byType(ButlerRequestDetailsScreen),
        timeout: const Duration(seconds: 20),
        reason: 'Tapping an unclaimed errand did not open its details page — before this change a '
            'row did nothing at all until the errand had been approved.');
    step('the unclaimed errand opened its details page too');

    final Finder cancel = onDetails(find.widgetWithText(YdPillButton, en.butlerCancelErrand));
    await pumpUntil(tester, cancel,
        timeout: const Duration(seconds: 20),
        reason: 'An errand nobody has claimed yet should be cancellable from its page.');
    await tester.ensureVisible(cancel);
    await tester.pump();
    await tester.tap(cancel);

    await pumpUntil(tester, find.text(en.butlerCancelConfirmTitle),
        timeout: const Duration(seconds: 10),
        reason: 'Cancel went ahead without asking first.');
    expect((await Backend.butlerRead(customerToken, sendId))['status'], 'REQUESTED',
        reason: 'The server already cancelled it while the confirmation was still on screen.');
    await pumpFor(tester, const Duration(seconds: 2));
    await tester.tap(find.text(en.butlerCancelConfirmYes));
    await serverReaches(customerToken, sendId, 'CANCELLED', tester);
    step('cancel asked first, then cancelled it on the server');
    await pumpFor(tester, const Duration(seconds: 3));

    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await pumpUntilGone(tester, find.byType(ButlerRequestDetailsScreen),
        reason: 'The details page did not close.');

    // ============================================================ Google, at the gate

    await signOutCustomer(tester);

    final Finder google = find.descendant(of: find.byType(SignInScreen), matching: find.text('Google'));
    await tester.ensureVisible(google);
    await tester.pump();
    await tester.tap(google);

    final Finder comingSoon = find.text(en.authSocialComingSoon('Google'));
    final Finder question = find.text(en.accountIntentSheetTitle);
    await pumpUntil(tester, find.byWidgetPredicate(
      (Widget w) => w is Text && (w.data == en.authSocialComingSoon('Google') ||
          w.data == en.accountIntentSheetTitle),
      description: 'either the "coming soon" note or the customer / rider / seller question',
    ),
        timeout: const Duration(seconds: 20),
        reason: 'Tapping Google did nothing visible at all — neither the question nor a note.');
    if (question.evaluate().isNotEmpty) {
      expect(find.text(en.accountIntentCustomer), findsOneWidget);
      expect(find.text(en.accountIntentRider), findsOneWidget);
      expect(find.text(en.accountIntentSeller), findsOneWidget);
      step('Google is live: it asked customer / rider / seller before opening any browser');
    } else {
      expect(comingSoon, findsOneWidget);
      step('Google is not configured on dev yet, and the button says so instead of failing');
    }
    await pumpFor(tester, const Duration(seconds: 3));
  });
}
