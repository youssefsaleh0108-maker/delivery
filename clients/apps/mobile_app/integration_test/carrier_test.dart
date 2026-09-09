import 'dart:convert';
import 'dart:io';

import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_app/main.dart' as app;

// The carrier console, driven end to end: cold start, the app's own sign-in form, and then the
// three tabs a delivery company actually reads — the shell it lands on, the fleet roster, and the
// earnings breakdown.
//
// WHAT THIS FILE IS FOR, stated plainly, because the honest answer is narrower than "it tests the
// carrier console" and the difference matters to whoever reads a failure.
//
// The breakdown card used to be handed only the NET figure and the platform's rate, and computed a
// "total" and a commission back out of them — deducting the cut a second time from money it had
// already been taken from. provider_models.dart says so in its own doc comment, and the card now
// renders the server's grossEarned, commission and earned directly.
//
// The obvious test for that — "total minus commission equals net" — CANNOT CATCH IT. The old code
// rendered total = earned, commission = earned * rate, net = earned * (1 - rate). Those three
// reconcile exactly. A reconciliation assertion passed on the broken build and would pass again on
// the next build that breaks the same way, which makes it worth roughly nothing on its own. It is
// kept below as a cheap internal-consistency check and labelled as exactly that.
//
// The assertion that does the work is the one that compares the three rendered strings against the
// same payload the app was handed, fetched out of band from `/api/orders/carrier/earnings`. Under
// the old arithmetic the gross row would show the NET number and the green band would show the net
// with the cut taken off twice — two figures that differ from the server's by real money, and two
// assertions that fail loudly here while sailing through any amount of reconciliation.
//
// The roster half works the same way. The Fleet tab cannot be asked "did loading fail", because
// _load() wraps myRiders() in `.catchError((_) => <String>[])` — a 403, a 500 and a genuinely empty
// fleet all render the same sentence. So an assertion that the error state is absent would be
// vacuous by construction. What IS answerable, and is what a swallowed 403 would break, is whether
// the count on screen matches the count the endpoint returns for the same user.
//
// EVERYTHING HERE IS LIVE. Sign-in is one call to Keycloak; the shell then fans out six concurrent
// calls. Five of them are individually caught, so a partial outage degrades this screen quietly
// rather than failing it — the shell can render with an empty fleet and no earnings card and still
// look healthy. That is why the assertions below are written against the server's own answers
// rather than against the screen alone.

/// The backend under test, read the same way main.dart reads it.
///
/// Deliberately `String.fromEnvironment` with main.dart's own defaults rather than the dev URLs
/// written out, and that is not tidiness. The verification calls at the end of this test only mean
/// something if they hit the SAME backend the app hit; hard-coding a host here would let the app
/// talk to one environment and the check talk to another, and the test would then be comparing two
/// unrelated sets of numbers while looking perfectly green. One `--dart-define` now moves both.
const String _issuer = String.fromEnvironment(
  'KEYCLOAK_ISSUER',
  defaultValue: 'http://192.168.10.24:8180/realms/delivery-platform',
);
const String _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://192.168.10.24:8100',
);

/// The client id main.dart builds its AuthConfig with. Kept in step by hand because it is a
/// literal there too, not an environment value.
const String _clientId = 'mobile-app';

/// A demo login on the dev realm, and it must stay that.
///
/// This is a seeded account on a throwaway realm, which is the only reason a credential is sitting
/// in a repository at all. Anyone copying this file as the template for a QA or staging run has to
/// replace these — pointing it at an environment where this account is real would put a working
/// password in version control.
const String _carrierUsername = 'carrier';
const String _carrierPasscode = '500005';

/// Pumps a frame at a time until [finder] matches, or the deadline passes.
///
/// The same helper the Arabic journey uses, and for the same reason. Three screens on this path
/// draw an indefinite [CircularProgressIndicator] — the splash while the stored session is looked
/// for, the sign-in button while the token round trip is in flight, and the carrier shell while its
/// six calls land. A spinner schedules another frame forever, so [WidgetTester.pumpAndSettle] never
/// reaches the quiet frame it waits for and dies on its own timeout: the app works, the test fails,
/// and the message points at nothing. Polling asks the only question that matters — is the thing I
/// am waiting for on screen yet. pumpAndSettle is fine once the shell has loaded, and is used there.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 40),
  required String reason,
}) async {
  const Duration step = Duration(milliseconds: 100);
  final int budget = timeout.inMilliseconds ~/ step.inMilliseconds;
  for (int i = 0; i < budget; i++) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) {
      // One more frame once it exists, so anything read off it afterwards comes from a laid-out
      // tree rather than the frame that introduced it.
      await tester.pump(step);
      return;
    }
  }
  fail('Timed out after ${timeout.inSeconds}s waiting for $finder. $reason');
}

/// The amount rendered on the same row as [label].
///
/// Required, not a stylistic preference. The crimson hero card shows the summary window's money and
/// the breakdown's gross row shows `grossEarned`, and on the dev data those are the same number —
/// byte-identical strings, so `find.text` on the amount matches twice and picking either one is a
/// coin toss. The label is the only unambiguous handle on the tree, so every figure is read by
/// walking out from its label to the row that contains it.
///
/// Both shapes this is used on are Row > [Expanded > Text(label), Text(value)] — `_moneyRow` wraps
/// that in a Padding and the green net band wraps it in a Container. `find.ancestor` returns
/// ancestors closest-first, so `.first` is the money row rather than some outer layout Row, and
/// descendants come back in pre-order, so the value is last.
String _moneyBeside(WidgetTester tester, Finder label) {
  final Finder row = find.ancestor(of: label, matching: find.byType(Row)).first;
  final List<Text> texts = tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
      .toList();
  // A guard on the helper rather than on the app. If a third Text joins the row — a currency chip,
  // a caption under the label — "the last one" quietly stops meaning "the amount", and every
  // assertion built on this would start comparing the wrong string. Better to say so here.
  expect(texts.length, 2,
      reason: 'Expected a money row of exactly [label, value] but found ${texts.length} Texts: '
          '${texts.map((Text t) => t.data).toList()}. The row layout changed, so the value can no '
          'longer be identified by position and this helper needs updating.');
  return texts.last.data!;
}

/// A carrier access token, taken straight from Keycloak with the same grant the app uses.
///
/// Raw [HttpClient] rather than the app's own AuthService, deliberately: AuthService writes the
/// refresh token into the shared FlutterSecureStorage, so a second one here would clobber the
/// session the app is signed in with, mid-test. `dart:io` rather than package:http because http is
/// only a transitive dependency of this app — importing it would work today and break the day the
/// package that pulls it in drops it.
Future<String> _carrierAccessToken() async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request =
        await client.postUrl(Uri.parse('$_issuer/protocol/openid-connect/token'));
    request.headers
        .set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
    request.write(const <String, String>{
      'grant_type': 'password',
      'client_id': _clientId,
      'username': _carrierUsername,
      'password': _carrierPasscode,
      'scope': 'openid profile email',
    }
        .entries
        .map((MapEntry<String, String> e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&'));
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      fail('Could not get a carrier token from $_issuer (HTTP ${response.statusCode}). '
          'Without one the earnings and roster figures cannot be checked against the server, so '
          'the rest of this test would only be asserting that the screen agrees with itself.');
    }
    return (jsonDecode(body) as Map<String, dynamic>)['access_token'] as String;
  } finally {
    client.close();
  }
}

/// A GET against the same API the app is pointed at, as the carrier.
Future<Map<String, dynamic>> _getAsCarrier(String path, String token) async {
  final HttpClient client = HttpClient();
  try {
    final HttpClientRequest request =
        await client.getUrl(Uri.parse('$_apiBaseUrl$path'));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final HttpClientResponse response = await request.close();
    final String body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      fail('GET $path returned HTTP ${response.statusCode} for the carrier. The app swallows this '
          'failure and renders an empty or absent card, so the screen would look plausible while '
          'showing nothing. Body: $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

/// The app's own money formatting, so the expected strings are built the way the screen builds them.
String _dollars(num value) => '\$${value.toDouble().toStringAsFixed(2)}';

/// The amount inside a rendered money string, as a number.
///
/// Matches the dollars-and-cents run rather than stripping the punctuation out, because stripping
/// cannot tell a figure from anything else that survives the filter — and when it then fails, it
/// fails as a bare "Invalid double" naming neither the row nor the string it choked on. [what] is
/// the row's name so a mis-read says which figure it could not make sense of.
double _money(String rendered, String what) {
  final Match? match = RegExp(r'\d+\.\d{2}').firstMatch(rendered);
  if (match == null) {
    fail('The $what figure on the breakdown card does not read as money: "$rendered". Either the '
        'card stopped formatting it to two decimal places, or the label this was read from is no '
        'longer sitting in the same row as its amount.');
  }
  return double.parse(match.group(0)!);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'the carrier console shows its real fleet and the server\'s own earnings figures',
      (WidgetTester tester) async {
    // Looked up rather than hand-typed, following the Arabic journey next door. Two of the strings
    // this test drives carry characters that are easy to get wrong by eye and impossible to spot in
    // a diff — the sign-in hint ends in a real ellipsis (U+2026, not three dots) and the empty-fleet
    // sentence contains an em dash (U+2014). A literal that differs by one of those finds nothing
    // and reads like a broken screen.
    final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

    // The real cold start. WidgetsFlutterBinding.ensureInitialized() hands back the integration
    // binding created above, Firebase init runs inside main's own try/catch so a device with no
    // google-services.json only debugPrints, then runApp.
    await app.main();

    // Arrival is waited on through the language pill and NOT through anything localised, which is
    // the whole reason this step exists separately from the one below. Icons.language is drawn on
    // exactly two mobile screens — this one and Settings — and the other is behind a login, so
    // finding it means SignInScreen. Crucially it means that in any language, which a finder built
    // from an English string would not: if the device is sitting in Arabic, every English hint and
    // label on this screen is absent, and waiting on one of those would time out here — before the
    // normalisation that would have fixed it ever got a chance to run.
    await _pumpUntil(
      tester,
      find.byIcon(Icons.language),
      reason: 'Never reached the sign-in screen. The usual cause is a session left in secure '
          'storage by an earlier run or by manual use, which boots the app straight into a signed-in '
          'shell. Clear the app data (adb shell pm clear com.delivery.mobile_app) and run again.',
    );

    // NORMALISATION, and it is load-bearing. arabic_rtl_test.dart persists the chosen language to
    // secure storage under `delivery.locale`, and a run of it that failed before its teardown
    // leaves the device in Arabic; so does a phone whose own language is Arabic, since MaterialApp
    // follows the device until LocaleController resolves. Either would make every English finder
    // below miss, and the failure would read as a broken carrier screen rather than as a language
    // this test never asked for. The pill names the language you would switch TO, so the literal
    // 'English' being on screen means the app is currently Arabic — that reads the control's state,
    // not a translation, since a language is named in its own language in both ARB files.
    if (find.text(en.english).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.language));
      await _pumpUntil(tester, find.text(en.authLogIn),
          reason: 'The app booted in Arabic and tapping the language pill did not return it to '
              'English.');
    }

    // Proof of WHICH sign-in step we are on before typing into it. The screen has a second step
    // that swaps both fields for a passcode pad, and typing into that one would silently do
    // nothing. 'Log In' is unique here — the footer says 'Sign Up' and the social row says Google
    // and Apple.
    expect(find.text(en.authLogIn), findsOneWidget,
        reason: 'Not on the credentials step of the sign-in screen, so the fields below are not '
            'the ones this test thinks it is filling in.');

    // Identified by hint rather than by position, because position is exactly what is unstable
    // here: when the device has a fingerprint enrolment and a stashed session, the screen grows a
    // "Continue as ..." card above the fields, and find.byType(TextField).at(0) stops meaning the
    // username. AuthField renders a plain TextField carrying the hint in its decoration, so this
    // predicate holds whether or not _prefillLastLogin has already filled the box — which matching
    // the hint's rendered Text would not, since a filled field draws no hint at all.
    final Finder usernameField = find.byWidgetPredicate((Widget w) =>
        w is TextField && w.decoration?.hintText == en.authEmailOrPhoneHint);
    expect(usernameField, findsOneWidget,
        reason: 'The username field is not on the sign-in screen in English.');

    // A race guard, not a pause for effect. SignInScreen.initState fires _prefillLastLogin(), which
    // reads secure storage and then does `setState(() => _username.text = last)`. If that lands
    // after the username is typed it silently replaces it, sign-in fails as bad credentials, and it
    // does so intermittently — the worst possible failure to inherit. Giving it a second to resolve
    // first makes the clobber unlikely; the assertion after typing makes it impossible to miss.
    await tester.pump(const Duration(seconds: 1));

    await tester.enterText(usernameField, _carrierUsername);
    await tester.enterText(
        find.byWidgetPredicate((Widget w) =>
            w is TextField && w.decoration?.hintText == en.authPasscodeHint),
        _carrierPasscode);
    await tester.pump();

    // The other half of the prefill guard. If the stored username won the race, this turns an
    // unexplained "that username or password is not right" into a sentence naming the cause.
    expect(tester.widget<TextField>(usernameField).controller?.text, _carrierUsername,
        reason: 'The username field no longer holds what this test typed. _prefillLastLogin() '
            'resolved after enterText and overwrote it with the stored login, so the sign-in that '
            'follows would fail as bad credentials for a reason that has nothing to do with the '
            'carrier console.');

    // Straight to Keycloak's token endpoint — the password grant, no browser, no Custom Tab. The
    // button turns into a spinner from here, which is why the wait after it is a pump loop.
    await tester.tap(find.text(en.authLogIn));

    // Arrival in CarrierShell. The Fleet tab label is the cleanest evidence of it: the shell is the
    // only screen carrying it, and it is unambiguous even on the Dashboard tab, where the fleet
    // badge is 'FLEET' in capitals and the stat reads 'Riders on fleet'. Sixty seconds because this
    // covers the token round trip AND the shell's own six concurrent calls, all behind a full
    // screen spinner.
    await _pumpUntil(
      tester,
      find.text(en.carrFleetTab),
      timeout: const Duration(seconds: 60),
      reason: 'Signed in but never reached the carrier shell. Either the token round trip failed, '
          'or the account stopped resolving to the CARRIER branch in main.dart — an APPLICANT role '
          'alongside it would divert to the pending application screen instead.',
    );

    // The shell's single error state, and worth asserting precisely because it is so narrow. It is
    // gated on `_error != null && _company == null`, and myCompany() is the one call in _load() not
    // wrapped in catchError — so this fires only when the company lookup itself failed. It says
    // nothing whatsoever about the roster or the earnings; those are checked against the server
    // further down, which is the only place they can be checked honestly.
    expect(find.byType(YdEmptyState), findsNothing,
        reason: 'The carrier shell is showing its error state, which means the company lookup '
            'failed outright.');
    expect(find.text(en.somethingWentWrong), findsNothing);

    // ---------------------------------------------------------------- the server's own answers
    //
    // Taken NOW rather than at the end, and that ordering is the point. The app fetched its
    // earnings when the shell loaded, moments ago; reading the same endpoint here brackets that
    // fetch closely. The second read at the end of the test closes the bracket, and the two
    // together are what make comparing the screen to the server sound rather than a race — on a
    // dev backend where orders are still landing, a figure that moved between the app's read and
    // ours would otherwise look exactly like a rendering bug.
    final String token = await _carrierAccessToken();
    final Map<String, dynamic> earningsBefore =
        await _getAsCarrier('/api/orders/carrier/earnings', token);
    final Map<String, dynamic> roster =
        await _getAsCarrier('/api/delivery-providers/my-company/riders', token);
    final List<String> serverRiders = (roster['riders'] as List<dynamic>)
        .map((dynamic r) => r as String)
        .toList();

    // An environment precondition, said out loud rather than hidden in a conditional. If the demo
    // company genuinely has no riders then the roster assertions below are all satisfiable by a
    // screen that renders nothing at all, and this test would pass while proving nothing. Failing
    // here names that situation instead of quietly tolerating it.
    expect(serverRiders, isNotEmpty,
        reason: 'The carrier company has no riders on the server, so nothing about the Fleet tab '
            'can be distinguished from a fleet that failed to load. Seed a rider onto the demo '
            'company before running this.');

    // ---------------------------------------------------------------- fleet

    await tester.tap(find.text(en.carrFleetTab));
    // Safe now, and only now: the shell has loaded, so there is no indefinite spinner left, and
    // nothing on this tab animates forever.
    await tester.pumpAndSettle();

    expect(find.text(en.carrFleetManagement), findsOneWidget,
        reason: 'Tapping Fleet did not put the fleet tab on screen.');

    // THE roster assertion, and the reason it is phrased against the server rather than against a
    // number. _load() collapses every failure of myRiders() into an empty list — a 403 on the
    // company's own fleet, a 500, and an genuinely empty roster are indistinguishable once they
    // reach this screen, all three rendering the same "no riders yet" sentence. So "the roster did
    // not error" is not a question this UI can answer. "Does the count on screen equal the count
    // the endpoint returns for this user" is, and a swallowed 403 fails it immediately: the server
    // says N and the screen says 0.
    //
    // Built through carrShowingRiders() rather than written out, so the test pins neither today's
    // rider count nor today's wording.
    expect(find.text(en.carrShowingRiders(serverRiders.length)), findsOneWidget,
        reason: 'The fleet count on screen does not match the ${serverRiders.length} rider(s) the '
            'roster endpoint returns. The likeliest cause is myRiders() failing and being swallowed '
            'by its catchError, which empties the list without any visible error.');

    // Redundant on its own, meaningful next to the precondition above: we know the server has
    // riders, so this sentence being present would mean the screen lost them.
    expect(find.text(en.carrNoRiders), findsNothing,
        reason: 'The fleet tab is showing its empty-fleet copy even though the roster endpoint '
            'returned ${serverRiders.length} rider(s).');

    // A count can be right while the list underneath it is empty, so one actual card is checked by
    // identity rather than by tally. The card renders the rider ref uppercased, and truncated to
    // twelve characters with an ellipsis when it is longer — which every UUID ref is.
    final String firstRef = serverRiders.first;
    final String renderedRef = firstRef.length > 12
        ? '${firstRef.substring(0, 12).toUpperCase()}…'
        : firstRef.toUpperCase();
    expect(find.text(renderedRef), findsOneWidget,
        reason: 'The count line claims the fleet is populated but the card for rider $firstRef is '
            'not on screen, so the list and its heading disagree.');

    // ---------------------------------------------------------------- earnings

    // By icon rather than by label, and the reason is specific: this tab renders carrEarningsTab
    // BOTH as its own heading and as the nav label, so once it is open find.text('Earnings')
    // matches twice and tapping it becomes ambiguous. Icons.attach_money_rounded is this item's
    // icon and its activeIcon and appears nowhere else in the shell, so it stays unique either way.
    await tester.tap(find.byIcon(Icons.attach_money_rounded));
    await tester.pumpAndSettle();

    // The breakdown card sits below the hero card and the weekly bars, off screen on a phone.
    // Dragging UP — a downward drag would pull the RefreshIndicator and re-run _load(), throwing
    // away the snapshot this test is in the middle of checking.
    final Finder earningsList = find.byType(ListView);
    for (int i = 0;
        i < 40 && find.text(en.carrNetEarnings).evaluate().isEmpty;
        i++) {
      await tester.drag(earningsList, const Offset(0, -250));
      await tester.pump(const Duration(milliseconds: 50));
    }

    // The whole card lives behind `if (earnings != null)`, and carrierEarnings() is caught into
    // null — so a failing earnings endpoint deletes it silently and leaves a screen that still
    // looks fine. Failing here is the correct outcome, and the message says which of the two it is.
    expect(find.text(en.carrDeliveriesBreakdown), findsOneWidget,
        reason: 'The deliveries breakdown card is not on the earnings tab. Either it never '
            'rendered — carrierEarnings() failed and was caught into null, which removes the card '
            'entirely — or scrolling did not reach it.');

    // carrTotalRevenue is unique here only because the crimson hero card renders it through
    // toUpperCase() and find.text is exact. findsOneWidget is doing real work: drop that
    // toUpperCase in a refactor and this finder becomes ambiguous rather than wrong, and a test
    // that read "whichever matched first" would start comparing the hero's figure to the server's
    // gross and be right by luck.
    final Finder grossLabel = find.text(en.carrTotalRevenue);
    expect(grossLabel, findsOneWidget,
        reason: 'Expected exactly one "${en.carrTotalRevenue}" on the earnings tab. The hero card '
            'renders the same string uppercased; if it stopped doing that, this finder now matches '
            'the hero too and the figure read below cannot be trusted.');
    final String grossText = _moneyBeside(tester, grossLabel);

    // startsWith rather than the whole sentence, because the rate inside the parentheses is server
    // configuration and this test has no business pinning it. Note the ARB also carries a
    // parenthesis-free carrCommissionPaid, which this screen does not use.
    final String commissionPrefix =
        en.carrCommissionPct(0).split('(').first;
    final Finder commissionLabel = find.byWidgetPredicate((Widget w) =>
        w is Text && (w.data?.startsWith(commissionPrefix) ?? false));
    expect(commissionLabel, findsOneWidget,
        reason: 'Expected exactly one commission row on the breakdown card.');
    final String commissionText = _moneyBeside(tester, commissionLabel);

    final Finder netLabel = find.text(en.carrNetEarnings);
    expect(netLabel, findsOneWidget);
    final String netText = _moneyBeside(tester, netLabel);

    // ---------------------------------------------------------------- the assertion that matters

    // Closing the bracket opened before the fleet tab. If the payload is identical to the one taken
    // then, nothing moved while the screen was being read, and the app's snapshot — taken between
    // the two — must be the same one. That is what licenses comparing the rendered strings to it.
    final Map<String, dynamic> earningsAfter =
        await _getAsCarrier('/api/orders/carrier/earnings', token);
    for (final String field in const <String>['grossEarned', 'commission', 'earned']) {
      expect(earningsAfter[field], earningsBefore[field],
          reason: 'The carrier\'s $field changed on the server while this test was reading the '
              'screen (${earningsBefore[field]} -> ${earningsAfter[field]}), so the figures on '
              'screen cannot be compared to it. An order completed mid-run. Re-run against a '
              'quiesced environment — this is not a bug in the app.');
    }

    // THE REGRESSION GUARD. Three whole strings, each against the server's own field.
    //
    // Comparing the rendered STRING rather than a number parsed out of it is deliberate, and it is
    // what makes this catch two quite different kinds of breakage with one assertion. A figure that
    // is merely the wrong number — the arithmetic regression this file was written for, where the
    // gross row showed `earned` and the band showed the cut deducted twice — fails on the digits.
    // A figure that is not a number at all fails here too, in the same place, with the actual text
    // printed next to what it should have said. Anything that parses the amount out first can only
    // catch the first kind, and turns the second into a complaint about arithmetic.
    //
    // The commission row is asserted with its leading minus because that sign is how the card says
    // "deduction"; dropping it would flip the meaning of the row while leaving the digits intact.
    expect(grossText, _dollars(earningsBefore['grossEarned'] as num),
        reason: 'The breakdown\'s total revenue row is not showing the server\'s grossEarned. If '
            'the digits are simply wrong, the card is deriving the gross from `earned` again '
            'instead of being handed it. If what came back is not a number at all, the row is no '
            'longer interpolating its value.');
    expect(commissionText, '-${_dollars(earningsBefore['commission'] as num)}',
        reason: 'The commission row is not showing the server\'s commission. Wrong digits mean the '
            'card is computing it as net x rate rather than reading it, which is wrong for any '
            'order that carried a waived or discounted cut; text that is not a number means the '
            'row is not interpolating its value.');
    expect(netText, _dollars(earningsBefore['earned'] as num),
        reason: 'The net earnings band is not showing the server\'s earned. Wrong digits mean the '
            'platform\'s cut is being taken off a figure it had already been paid from, promising '
            'the carrier less than the ledger owes them; text that is not a number means the band '
            'is not interpolating its value.');

    // A CHEAP INTERNAL CHECK, AND NOTHING MORE — labelled so nobody mistakes it for the regression
    // guard, and deliberately last. The build this file was written against rendered total =
    // earned, commission = earned * rate, net = earned * (1 - rate); those reconcile exactly, so
    // this line passed on the broken screen and would pass again on the next build that breaks the
    // same way. It sits after the comparisons above so that when the card is wrong, the failure
    // reported first is the one that says WHAT the card should have shown, rather than a complaint
    // about arithmetic on figures that were never the right figures. It survives at all because a
    // card whose three numbers do not add up is worth knowing about for its own sake. The tolerance
    // covers three independent roundings to cents.
    expect(
        _money(grossText, 'total revenue') -
            _money(commissionText, 'commission') -
            _money(netText, 'net earnings'),
        closeTo(0, 0.02),
        reason: 'The three figures on the breakdown card do not add up: $grossText - '
            '$commissionText should equal $netText.');

    // ---------------------------------------------------------------- put the device back

    // Not tidiness. The session AuthService just wrote lives in FlutterSecureStorage and survives
    // an app restart, so leaving it there means the next run of this test boots straight into the
    // shell and fails at the sign-in screen it never sees. Signing out is what makes this file
    // re-runnable without `adb shell pm clear com.delivery.mobile_app` between runs; the assertion
    // afterwards is there because a teardown that quietly failed would leave exactly that landmine.
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    // Scrolled to rather than tapped where it sits, because it does not sit anywhere yet: the
    // settings tab is a ListView and the log out button is near the bottom of it, so on a phone it
    // is outside the viewport and outside the element tree until the list is dragged. Tapping a
    // finder that matches nothing throws, and the same upward drag used on the earnings tab brings
    // it into both.
    final Finder settingsList = find.byType(ListView);
    for (int i = 0;
        i < 40 && find.text(en.custLogOutAccount).evaluate().isEmpty;
        i++) {
      await tester.drag(settingsList, const Offset(0, -250));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text(en.custLogOutAccount), findsOneWidget,
        reason: 'Could not reach the log out button on the carrier settings tab, so this run will '
            'leave a signed-in session on the device.');

    // The loop above stops as soon as the button EXISTS, and existing is not the same as being
    // visible: a ListView builds a cache extent beyond the viewport, so the finder can start
    // matching while the button is still below the fold — and tapping something whose centre is off
    // screen is exactly the kind of failure that reads as "the button does nothing". This puts it
    // properly in view first.
    await tester.ensureVisible(find.text(en.custLogOutAccount));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.custLogOutAccount));
    await _pumpUntil(tester, find.text(en.authLogIn),
        reason: 'Signing out did not return the app to the sign-in screen. The carrier session is '
            'still in secure storage, so the next run of this test will boot past sign-in and fail '
            'on a missing field. Clear the app data before running it again.');
  });
}
