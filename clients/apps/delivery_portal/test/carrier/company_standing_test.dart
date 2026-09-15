import 'package:delivery_portal/src/carrier/company_standing.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'riders_harness.dart';

/// The company's standing: the delivery score that decides how much work arrives
/// ([CarrierScoreCard]), and the switch that stops it arriving ([CarrierAvailabilitySwitch]).
///
/// Both sat under the old "Riders Management" table and moved to the dashboard when the riders page
/// became an HR directory — Figma 112:413 has no place for them, and a company can lose neither.
/// The switch now lives in the dashboard's top bar; each loads on its own, so neither needs the
/// other to draw.
Future<void> _pump(
  WidgetTester tester,
  FleetStub stub, {
  Locale locale = const Locale('en'),
  double width = 1180,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(wrap(
    SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CarrierAvailabilitySwitch(api: stub.providerApi),
          CarrierScoreCard(api: stub.providerApi),
        ],
      ),
    ),
    locale: locale,
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the score and what it is made of', (WidgetTester tester) async {
    await _pump(tester, FleetStub());

    // The number alone is a verdict nobody can act on; the parts are the target.
    expect(find.text(en.howYouAreDoing), findsOneWidget);
    expect(find.text('84'), findsOneWidget);
    expect(find.text('96%'), findsOneWidget);
    expect(find.text('4m'), findsOneWidget);
    expect(find.text('18m'), findsOneWidget);
    expect(find.textContaining('decides how much work'), findsOneWidget);
  });

  testWidgets('a provisional score says so rather than looking earned',
      (WidgetTester tester) async {
    await _pump(tester, FleetStub(score: scoreJson(score: 70, provisional: true, completion: 1)));

    expect(find.text(en.tooEarlyToTell), findsOneWidget);
    expect(find.textContaining('benefit of the doubt'), findsOneWidget);
  });

  testWidgets('a carrier can stop taking orders, with what that means one hover away',
      (WidgetTester tester) async {
    final FleetStub stub = FleetStub();
    await _pump(tester, stub);

    expect(find.text(en.takingWork), findsOneWidget);
    expect(find.byTooltip(en.pauseExplanation), findsOneWidget);
    await tester.tap(find.widgetWithText(ConsoleButton, en.pauseNewOrders));
    await tester.pumpAndSettle();

    expect(stub.called('POST', '/my-company/pause'), isTrue);
    expect(find.text(en.pausedNoNewOrders), findsOneWidget);
  });

  testWidgets('a suspended carrier sees why, and is not offered a button that would fail',
      (WidgetTester tester) async {
    // Suspension is the platform's decision and a carrier cannot resume out of it. A button that
    // silently fails would be worse than no button.
    await _pump(
        tester, FleetStub(company: companyJson(status: 'SUSPENDED', canTakeWork: false)));

    expect(find.byTooltip(en.suspendedByPlatform), findsOneWidget);
    expect(find.widgetWithText(ConsoleButton, en.startTakingOrders), findsNothing);
    expect(find.widgetWithText(ConsoleButton, en.pauseNewOrders), findsNothing);
  });

  testWidgets('a score that could not be read still leaves the switch',
      (WidgetTester tester) async {
    await _pump(tester, FleetStub(failing: const <String, (int, Object?)>{
      '/my-company/score': (503, null),
    }));

    expect(find.text(en.howYouAreDoing), findsNothing);
    expect(find.widgetWithText(ConsoleButton, en.pauseNewOrders), findsOneWidget);
  });

  testWidgets('with no company to read there is no switch to draw, not a broken one',
      (WidgetTester tester) async {
    // The dashboard around the switch already says "not attached to a company yet".
    await _pump(tester, FleetStub(failing: const <String, (int, Object?)>{
      'GET =/my-company': (404, null),
    }));

    expect(find.byType(ConsoleButton), findsNothing);
    expect(find.byType(ConsoleStatusPill), findsNothing);
  });

  testWidgets('stays translated', (WidgetTester tester) async {
    await _pump(tester, FleetStub(), locale: const Locale('ar'));

    expect(find.text(ar.howYouAreDoing), findsOneWidget);
    expect(find.widgetWithText(ConsoleButton, ar.pauseNewOrders), findsOneWidget);
    expect(find.text(en.howYouAreDoing), findsNothing);
    expect(Directionality.of(tester.element(find.byType(CarrierScoreCard))), TextDirection.rtl);
  });

  for (final double width in <double>[1180, 764]) {
    testWidgets('lays out at a ${width.toInt()}px content column', (WidgetTester tester) async {
      await _pump(tester, FleetStub(), width: width);
      expect(tester.takeException(), isNull);
    });
  }
}
