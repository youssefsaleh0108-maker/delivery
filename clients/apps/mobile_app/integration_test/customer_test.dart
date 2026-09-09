import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_app/main.dart' as app;
import 'package:mobile_app/src/one_time_code.dart';
import 'package:mobile_app/src/product_detail_screen.dart';
import 'package:mobile_app/src/sign_in_screen.dart';
import 'package:mobile_app/src/store_home_screen.dart';
import 'package:mobile_app/src/store_page_screen.dart';

// The customer's whole first session, against the real dev backend.
//
// test/ has widget tests for each of these screens, and integration_test/arabic_rtl_test.dart
// boots the app — but nothing in the repo yet proves the customer path END TO END: that a real
// Keycloak token comes back from the app's own two fields, that the role branch in main.dart
// reads it as a customer, that the storefront query answers, that a card carries an id the shop
// page can read a catalog from, and that a product row reaches a detail screen. Each of those is
// a seam between a screen and a service, and a seam is the one thing a widget test with a fake
// Dio cannot speak to. Every screen here waits on a live network call over the public internet,
// which is why every wait below is a bounded poll rather than a settle.
//
// HOW TO RUN IT. Four things, and skipping any of them turns a working app red or — worse — turns
// a broken one green:
//
//   1. Point the build at the dev environment. The defaults in main.dart are a LAN address
//      (192.168.10.24), and against a dead address every step here fails as a 20s Dio timeout
//      rather than as itself:
//        flutter test integration_test/customer_test.dart -d <device> \
//          --dart-define=API_BASE_URL=https://api-dev.youdrop.shop \
//          --dart-define=KEYCLOAK_ISSUER=https://iam-dev.youdrop.shop/realms/delivery-platform
//
//   2. Uninstall first — `adb uninstall com.delivery.mobile_app`. This is not hygiene, it is
//      correctness. AuthService.restore() reads `delivery.refresh_token` out of secure storage,
//      and a leftover token drops the app straight onto the shell with the whole sign-in half of
//      this journey never executed. The test would still pass. A leftover login also makes
//      _prefillLastLogin() fill the username in and _checkFingerprint() draw a "Continue as" card
//      above the fields, both of which change what is on screen.
//
//   3. Pre-grant push on Android 13+ — `adb shell pm grant com.delivery.mobile_app
//      android.permission.POST_NOTIFICATIONS`. _adoptSession() calls DeviceTokenRegistrar.register()
//      the instant the token lands, google-services.json is really present, so a system permission
//      dialog appears at exactly the moment this test is waiting for the home screen. It does not
//      swallow synthetic taps but it can stall frame production, which stalls the poll.
//
//   4. Expect it to be red whenever dev is down or mid-deploy. That is what a live-integration test
//      is; it should not gate a merge on the same footing as the unit suite.
//
// WHY THERE ARE NO KEYS IN THE FINDERS. There is not one widget Key in the client tree —
// `grep -rn "Key('"` over apps/ and packages/ returns only `containsKey(` — so every finder here is
// text, type, or a widget predicate. The two names this test needs (a shop's and a product's) are
// read off the rendered cards at runtime rather than hardcoded, because there are no fixtures on a
// live backend to hardcode against and a guessed name is a test that fails for the wrong reason.

// ---------------------------------------------------------------------------------- credentials

/// The dev realm's demo shopper. Overridable so a CI account can be used instead, but the default
/// is the documented one — see the demo logins in the dev environment notes.
const String _username = String.fromEnvironment('TEST_USERNAME', defaultValue: 'customer');

/// Six digits, and that matters: _submitCredentials() refuses anything whose length is not
/// PasscodePad.passcodeLength before it ever reaches the network.
const String _passcode = String.fromEnvironment('TEST_PASSCODE', defaultValue: '100001');

/// How many shops to try before giving up on finding a stocked one. See the loop in the test for
/// why this is not simply 1.
const int _shopsToTry = 3;

// -------------------------------------------------------------------------------------- waiting

/// Pumps a frame at a time until [finder] matches, and reports whether it did.
///
/// Deliberately not [WidgetTester.pumpAndSettle], and the reason is specific to these screens
/// rather than a style preference. StoreHomeScreen.initState starts a 2.8s hint timer and a 4s
/// banner timer that animates a PageController, and CustomerShell's IndexedStack builds all five
/// tabs eagerly, so MyOrdersScreen's 5s poll and NotificationInbox's 15s poll are running the
/// whole time too. There are quiet windows between all of that, so pumpAndSettle usually returns —
/// it just returns at a moment that has nothing to do with whether the data arrived, which is
/// exactly how a green-but-meaningless test happens. Polling asks the only question that matters.
Future<bool> _appearsWithin(
  WidgetTester tester,
  Finder finder,
  Duration timeout,
) async {
  const Duration step = Duration(milliseconds: 100);
  final int budget = timeout.inMilliseconds ~/ step.inMilliseconds;
  for (int i = 0; i < budget; i++) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      // One more frame once it exists, so anything read or tapped afterwards comes off a laid-out
      // tree rather than off the frame that introduced it.
      await tester.pump(step);
      return true;
    }
  }
  return false;
}

/// [_appearsWithin], but the timeout is a failure with a sentence saying what it means.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 45),
  required String reason,
}) async {
  if (await _appearsWithin(tester, finder, timeout)) return;
  fail('Timed out after ${timeout.inSeconds}s waiting for $finder. $reason');
}

/// The mirror image, for waiting out a route that is popping.
Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
  required String reason,
}) async {
  const Duration step = Duration(milliseconds: 100);
  final int budget = timeout.inMilliseconds ~/ step.inMilliseconds;
  for (int i = 0; i < budget; i++) {
    await tester.pump(step);
    if (finder.evaluate().isEmpty) {
      await tester.pump(step);
      return;
    }
  }
  fail('Timed out after ${timeout.inSeconds}s waiting for $finder to go away. $reason');
}

// -------------------------------------------------------------------------------------- finders

/// A [Text] drawn at exactly this size and weight.
///
/// Keying on a TextStyle is the price of having no keys, and it is precise here only because every
/// competing Text on these screens was checked: inside a storefront card the badge is 10 and the
/// meta line is 12, so 14/w700 is the shop name; inside a product row the description is 12 and the
/// price is a Text.rich carrying no style of its own, so 15/w700 is the product name. The cost is
/// that a designer moving 15 to 16 breaks this test with a confusing message rather than an obvious
/// one — which is the argument for keys, not against this finder.
Finder _labelAt(double size) => find.byWidgetPredicate(
      (Widget w) =>
          w is Text && w.style?.fontSize == size && w.style?.fontWeight == FontWeight.w700,
      description: 'Text at ${size}px w700',
    );

/// The storefront grid's cards, and only those.
///
/// YdCard appears exactly once in store_home_screen.dart, in _itemCard (the grid). The favourites
/// rail next to it draws CoverCard, which is a separate class in product_detail_screen.dart and not
/// a YdCard, so this cannot pick up a favourite by accident. Scoped to the screen because
/// CustomerShell keeps all five tabs alive in an IndexedStack.
Finder _shopCards() => find.descendant(
      of: find.byType(StoreHomeScreen),
      matching: find.byType(YdCard),
    );

/// The shop page's product rows, and only those.
///
/// Scoping to StorePageScreen is not enough on its own: YdCard is used three times in that file —
/// the product row, the Aisles grid and the Offers list. Requiring a 15/w700 name inside the card
/// is what separates them, because the aisle and offer cards both title at 14. That makes this
/// finder correct whatever TabBarView decides to build, rather than correct only because the
/// neighbouring tabs happen not to be built at rest.
Finder _productRows() => find.ancestor(
      of: find.descendant(of: find.byType(StorePageScreen), matching: _labelAt(15)),
      matching: find.byType(YdCard),
    );

/// Reads the name off a card, rather than asserting against a name nobody has verified is there.
String _nameOn(WidgetTester tester, Finder card, double size) =>
    tester.widget<Text>(find.descendant(of: card, matching: _labelAt(size)).first).data!;

/// The name Text inside a card — the thing this test taps.
///
/// Tapping the name rather than the card's centre is deliberate. Both reach the same YdCard
/// InkWell (a Text absorbs nothing), but the name sits well away from the two controls that share
/// the card: the favourite heart in the storefront card's top corner, and the add button at the end
/// of a product row. A centre tap is fine today and stops being fine the first time a card's
/// geometry changes.
Finder _nameFinderOn(Finder card, double size) =>
    find.descendant(of: card, matching: _labelAt(size)).first;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'a customer signs in, opens a shop off the storefront and reaches a product',
      (WidgetTester tester) async {
    // Looked up rather than hand-typed, which is the pattern integration_test/arabic_rtl_test.dart
    // and test/arabic_rtl_test.dart both already use. A literal typed here would be a second copy
    // of the string table that nothing keeps in step with app_en.arb — and half of these carry an
    // em dash or an ICU plural, so a copy drifts silently.
    final DeliveryStrings t = lookupDeliveryStrings(const Locale('en'));

    // The real cold start. main() is async — it awaits Firebase.initializeApp inside its own
    // try/catch — and WidgetsFlutterBinding.ensureInitialized() inside it returns the integration
    // binding created above rather than making a second one.
    await app.main();

    // ------------------------------------------------------------------ the sign-in screen

    // SplashScreen holds for 1.9s before the gate is even built, and AuthService.restore() reads
    // secure storage behind it. Nothing is asserted about the splash itself: SplashScreen.hold
    // means it is normally on screen, but whether any given pump lands inside that window is a
    // race, and an assertion that depends on scheduler timing is not evidence of anything.
    //
    // _gate starts at _Gate.signIn, so a device with no stored session lands here directly — there
    // is no welcome screen to get past.
    await _pumpUntil(
      tester,
      find.byType(SignInScreen),
      reason: 'The app never reached the sign-in screen. The usual cause is a session left in '
          'secure storage by an earlier run or by manual use, which makes AuthService.restore() '
          'succeed and drops the app straight onto a signed-in shell — with everything this test '
          'is about to do to the login form never executed. Uninstall the app and run again.',
    );

    // NORMALISATION, and it is load-bearing rather than defensive. MaterialApp is handed
    // `locale: _locale.locale`, which is null until the saved preference resolves, and a null
    // locale means "follow the device" against [en, ar]. On an Arabic phone — or after a previous
    // test left 'ar' in secure storage under `delivery.locale` — every English finder below would
    // find nothing and the failure would read as a broken screen. The pill names the language you
    // would switch TO, so the literal 'English' on screen means the app is currently Arabic.
    if (find.text(t.english).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.language));
      await _pumpUntil(tester, find.text(t.authLogIn),
          reason: 'The app booted in Arabic and tapping the language pill did not return it to '
              'English.');
    }

    // Proof of which screen this is, in the words a person would use to recognise it. 'Log In' is
    // unique here: the footer pair says "Don't have an account?" / "Sign Up", and the social row
    // renders "or continue with" lowercased plus Google and Apple.
    expect(find.text(t.authLogIn), findsOneWidget);

    // The username field is the TextField inside the AuthField whose label is 'Email or Phone'.
    // AuthField draws that label as an AuthFieldLabel — a plain Text — above its TextField, which
    // is what makes widgetWithText reach it.
    await tester.enterText(
      find.descendant(
        of: find.widgetWithText(AuthField, t.authEmailOrPhone),
        matching: find.byType(TextField),
      ),
      _username,
    );

    // The passcode field is NOT an AuthField — _passwordField() builds a bare TextField under a
    // hand-rolled label row — so widgetWithText cannot reach it and it has to be identified by its
    // hint. Deliberately not find.byType(TextField).last: that is tree-order luck, and it silently
    // picks the wrong field the day a 'Continue as' card or another input joins the screen.
    await tester.enterText(
      find.byWidgetPredicate(
        (Widget w) => w is TextField && w.decoration?.hintText == t.authPasscodeHint,
        description: 'the passcode field',
      ),
      _passcode,
    );

    // The form lives in a SliverFillRemaining with a Spacer before the footer, so on a short device
    // the CTA can sit below the fold and a tap would miss it. AuthPrimaryButton is a Material and
    // an InkWell around a Text, not a button subclass, which is why it is matched by its label.
    final Finder logIn = find.widgetWithText(AuthPrimaryButton, t.authLogIn);
    await tester.ensureVisible(logIn);
    await tester.pump();
    await tester.tap(logIn);

    // ------------------------------------------------------------------ the token, and the role

    // THE assertion that the password grant worked and that main.dart read the role right. This is
    // one wait covering three separate things — Keycloak's token endpoint, the FCM permission round
    // trip that _adoptSession fires off, and the role branch — so it gets a long budget.
    //
    // Reaching StoreHomeScreen specifically is what proves the ROLE branch: a token carrying
    // carrier, delivery, merchant or a bare applicant claim would have landed on a different shell
    // entirely, and this finder would never match.
    if (!await _appearsWithin(
        tester, find.byType(StoreHomeScreen), const Duration(seconds: 90))) {
      // A credential failure should read as a credential failure rather than as a timeout, and
      // _submit() puts the server's own words on screen for exactly that reason.
      final Finder note = find.byType(AuthErrorNote);
      final String detail = note.evaluate().isEmpty
          ? 'No error note is showing, so the token call has not come back at all — check that '
              'KEYCLOAK_ISSUER was passed as a --dart-define and that the realm is up.'
          : 'The sign-in screen is still up, showing: '
              '"${tester.widget<AuthErrorNote>(note).message}"';
      fail('Signing in as $_username never reached the customer home tab. $detail');
    }

    // The greeting is drawn from session.displayName, which is decoded out of the JWT claims — so
    // this says a real token was issued and parsed, not merely that a screen mounted. Only the
    // fixed half is asserted: displayName falls back name -> preferred_username -> email ->
    // 'Account', and which claims this demo account carries is not something this test can know.
    // The fixed half is taken from the table with an empty name rather than typed out, so a change
    // to custHiName moves this assertion with it instead of stranding it.
    expect(find.textContaining(t.custHiName('').trim()), findsWidgets,
        reason: 'The customer home tab mounted without a greeting, which means the session it was '
            'handed has no display name — the token was accepted but not decoded as expected');

    // ------------------------------------------------------------------ the storefront

    // The strongest load gate on this screen, and the reason it is this string rather than a
    // spinner check: _feed() renders a CircularProgressIndicator INSTEAD of the section list while
    // (_stores.isLoadingFirstPage || _loadingRails), so this heading existing means /api/stores,
    // the favourites, the banners and the category chips have all answered. The heading only
    // degrades to a vertical's name once a chip is tapped, which has not happened.
    await _pumpUntil(
      tester,
      find.text(t.custActiveStoresNearby),
      timeout: const Duration(seconds: 60),
      reason: 'The storefront never finished loading. If the screen is showing '
          '"${t.couldNotLoadStorefront}" then /api/stores answered with an error; if it is still '
          'spinning, check API_BASE_URL was passed as a --dart-define.',
    );

    // An empty catalog is a legitimate server answer and it renders a specific empty state. Saying
    // so explicitly means "no shops on screen" can never be quietly read as "still loading".
    expect(find.text(t.noShopsMatch), findsNothing,
        reason: 'The dev storefront came back empty, so there is no shop for the rest of this '
            'journey to open. This is a data problem, not a client one');

    // REQUIRED, not belt-and-braces. The grid sits below the greeting header, the pinned search
    // bar, the category strip, the banner rail, the favourites rail and a section header, so on a
    // phone the first card is routinely past the viewport plus the default 250px cacheExtent and
    // _shopCards() legitimately returns nothing at offset 0 with the data present and correct.
    //
    // The scrollable is selected by its axis rather than by tree order: this screen also hosts four
    // horizontal rails and a PageView, and .first over a bare byType(Scrollable) picks whichever
    // one happens to be built first. Scrolling also drives _stores.loadMore().
    try {
      await tester.scrollUntilVisible(
        _shopCards().first,
        300,
        scrollable: find
            .descendant(
              of: find.byType(StoreHomeScreen),
              matching: find.byWidgetPredicate(
                (Widget w) => w is Scrollable && w.axisDirection == AxisDirection.down,
                description: 'the vertical storefront scrollable',
              ),
            )
            .first,
      );
    } on StateError {
      // dragUntilVisible gives up with a StateError naming the finder and nothing else. Swallowed
      // so the assertion immediately below is what actually reports, because it can say what an
      // empty grid MEANS.
    }

    // THE ANTI-VACUOUS GUARD for the whole second half. Zero cards means the dev catalog has no
    // published shop and everything below could only pass by asserting nothing; failing here, and
    // loudly, is the correct outcome.
    expect(_shopCards(), findsAtLeastNWidgets(1),
        reason: 'The storefront said it had shops but drew no cards after scrolling the feed to '
            'the end. Either the dev catalog has no published shop, or the grid stopped using '
            'YdCard — if _itemCard were switched to CoverCard this finder would go to zero and '
            'read exactly like missing data');

    // ------------------------------------------------------------------ into a shop

    // Walk the grid rather than trusting index 0. Which shop the server sorts first is not under
    // this test's control, and a shop with an empty catalog is a perfectly valid one — landing on
    // it would fail the product step with a message about a timeout when the real answer is "that
    // shop has nothing on its shelves". Trying a few in turn makes the claim honest: SOME shop in
    // the dev catalog opens to a browsable product. If none of them do, the loop still fails.
    String? shopName;
    String? productName;

    for (int attempt = 0; attempt < _shopsToTry; attempt++) {
      final Finder cards = _shopCards();
      // The grid is a SliverGrid with a builder delegate, so it only ever has the cards near the
      // viewport built. Running out of built cards is the end of what can be tried, not a failure
      // in itself — the failure comes after the loop.
      if (cards.evaluate().length <= attempt) break;

      final Finder card = cards.at(attempt);
      final Finder cardName = _nameFinderOn(card, 14);
      await tester.ensureVisible(cardName);
      await tester.pump();

      // Read the name BEFORE the tap, so the shop page's hero can be checked against the card that
      // was actually pressed rather than against whatever the page decides to show.
      final String candidate = _nameOn(tester, card, 14);
      await tester.tap(cardName);

      // _openStore pushes StorePageScreen synchronously — no network happens before the push — so
      // this is a short wait for a route transition, not for a server.
      await _pumpUntil(tester, find.byType(StorePageScreen),
          timeout: const Duration(seconds: 20),
          reason: 'Tapping the shop card "$candidate" did not open the shop page, so YdCard.onTap '
              'is no longer wired to _openStore.');

      // Proof that the tap opened the RIGHT shop. The hero renders card.name straight from the
      // `preview` the home screen passed, so this is evidence about navigation rather than about
      // the shop read — which only ever replaces the same name with itself.
      expect(
        find.descendant(of: find.byType(StorePageScreen), matching: find.text(candidate)),
        findsWidgets,
        reason: 'The shop page opened on a different shop than the card that was tapped',
      );

      // The first of the four hand-built tabs, drawn unconditionally. Deliberately not paired with
      // 'Everything' or the Aisles/Offers counts: that chip exists only `if (_aisles.isNotEmpty)`
      // and the counts are server data, so all three can be legitimately absent.
      expect(find.text(t.tabShop), findsWidgets);

      // THE assertion that /api/stores/{id}/products answered with content, and the reason this
      // whole journey needs a poll rather than a settle. _shopTab() tests `_products.isEmpty`
      // BEFORE _pagedProductList() gets a chance to test isLoadingFirstPage, and a PagedList is
      // empty while its first page is in flight — so "Nothing on the shelves yet" is genuinely on
      // screen during a normal, healthy load. A test that pumped once and asserted would read that
      // transient as the final answer.
      if (await _appearsWithin(tester, _productRows(), const Duration(seconds: 45))) {
        shopName = candidate;
        productName = _nameOn(tester, _productRows().first, 15);
        break;
      }

      // No rows inside the budget. Either this shop really is empty or its catalog call is very
      // slow; both are answered the same way — back out and try the next shop, and let the failure
      // after the loop speak if none of them work.
      await tester.tap(
        find.descendant(
          of: find.byType(StorePageScreen),
          matching: find.byIcon(Icons.chevron_left),
        ),
      );
      await _pumpUntilGone(tester, find.byType(StorePageScreen),
          reason: 'The shop page would not pop, so the rest of the storefront cannot be tried.');
    }

    expect(shopName, isNotNull,
        reason: 'None of the first $_shopsToTry shops on the dev storefront put a product row on '
            'screen. Either every one of them has an empty catalog — a data problem, and the '
            'shop page will be showing "${t.nothingOnShelves}" — or /api/stores/{id}/products is '
            'not answering');

    // ------------------------------------------------------------------ into a product

    final Finder row = _productRows().first;
    final Finder rowName = _nameFinderOn(row, 15);
    await tester.ensureVisible(rowName);
    await tester.pump();
    await tester.tap(rowName);

    // A settle here would be wrong twice over. _openProduct awaits storeApi.productOptions(id) — a
    // real round trip — BEFORE showProductDetail pushes anything, so for the length of that call
    // the screen is unchanged and a settle would return with nothing having happened. The route is
    // a full MaterialPageRoute, not a sheet, so this is the thing to wait for.
    await _pumpUntil(
      tester,
      find.byType(ProductDetailScreen),
      reason: 'Tapping the product row "$productName" in "$shopName" never opened the detail '
          'screen. The options call is awaited before the push, so a hanging '
          '/api/products/{id}/options stalls exactly here.',
    );

    // The YdScreenHeader title, rendered unconditionally.
    expect(find.text(t.custProductDetails), findsOneWidget);

    // The end of the journey, tied back to the row that was actually pressed — which is what stops
    // this being "some product screen opened". Matched on _sheet()'s 22px heading rather than on
    // the bare string, because _relatedProducts() draws other products' names in the same subtree
    // and a suggestion that happened to share a name would satisfy a plain find.text.
    expect(
      find.descendant(
        of: find.byType(ProductDetailScreen),
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is Text &&
              w.data == productName &&
              w.style?.fontSize == 22 &&
              w.style?.fontWeight == FontWeight.w700,
          description: 'the product heading "$productName"',
        ),
      ),
      findsOneWidget,
      reason: 'The detail screen opened on a different product than the row that was tapped',
    );

    // One piece of the screen's own content, chosen because _dualPriceCard() draws it
    // unconditionally. Deliberately NOT the CTA: _cta swaps 'Add to Basket' for
    // '${t.selectRequiredOptions}' whenever the product has an unanswered required option group,
    // which is server data this test cannot predict. Uppercased, because the card renders
    // `t.custDualPriceMode.toUpperCase()` rather than the ARB value as written.
    expect(find.text(t.custDualPriceMode.toUpperCase()), findsOneWidget);
  });
}
