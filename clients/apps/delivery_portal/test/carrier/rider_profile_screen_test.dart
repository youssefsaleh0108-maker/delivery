import 'package:delivery_portal/src/carrier/rider_profile_screen.dart';
import 'package:delivery_portal/src/shell/console_controls.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'riders_harness.dart';

/// One rider's HR profile — Figma `web-carrier-rider-profile` (112:740), reached the way a
/// dispatcher reaches it: the directory's "Manage Profile".
///
/// It took over from the old table's rider drawer and its row actions, so it carries their tests —
/// presence, thirty days of work in this company's own scope, hours online, suspension — alongside
/// the design's additions built from what the platform actually records: papers, the rating's
/// histogram, the day-by-day chart and ending a contract. What the design draws with no source
/// behind it (an emergency contact, an on-time rate, a pay rate, a rank) is pinned as absent.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  String kpi(WidgetTester tester, String label) =>
      tester.widget<ConsoleKpiCard>(find.widgetWithText(ConsoleKpiCard, label)).value;

  testWidgets('identity is the rider\'s own application to this company',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub());
    await openProfile(tester);

    expect(find.text(en.carrRidersProfileTitle), findsOneWidget);
    expect(find.text('Nadia Haddad'), findsOneWidget);
    // The application's reference: the platform issues no badge numbers, and none is invented.
    expect(find.text(en.carrRidersBadgeId('REF-app-1')), findsOneWidget);
    expect(find.text('+96170000000'), findsOneWidget);
    expect(find.text('nadia@example.com'), findsOneWidget);
    // What the rider wizard took down, under the reader's own labels rather than its keys.
    expect(find.text(en.carrRidersDateOfBirth.toUpperCase()), findsOneWidget);
    expect(find.text('1998-03-14'), findsOneWidget);
    expect(find.text('LB-000123456'), findsOneWidget);
    // When she last went on or off duty, off the roster — the old rider drawer's "Changed".
    expect(find.text(en.carrRidersDutyChanged.toUpperCase()), findsOneWidget);
    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusActive), findsOneWidget);
    // Nothing on the platform records an emergency contact, so the design's row is not drawn.
    expect(find.textContaining('mergency'), findsNothing);
  });

  testWidgets('the thirty days are this company\'s, and completion is the server\'s',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub());
    await openProfile(tester);

    // Labelled as the rolling window the server counts, not "this month".
    expect(kpi(tester, en.carrRidersDeliveriesWindow(30)), '11');
    expect(find.text(en.carrRidersClaimedCaption(12, 1)), findsOneWidget);
    // In the design's on-time slot: nothing records when a delivery was due, so on-time cannot be
    // counted and is not drawn.
    expect(kpi(tester, en.carrRidersCompletionRate), '91.7%');
    expect(find.textContaining('On-time'), findsNothing);
    expect(kpi(tester, en.carrRidersDeliveredTodayLabel), '3');
  });

  testWidgets('a rider with nothing claimed shows a dash, never 0% or 100%',
      (WidgetTester tester) async {
    await pumpDirectory(
      tester,
      FleetStub(
        performance: performanceJson(
            claimed: 0, delivered: 0, cancelledAfterClaim: 0, completionRate: null),
      ),
    );
    await openProfile(tester);

    expect(kpi(tester, en.carrRidersCompletionRate), '—');
    expect(find.text(en.carrRidersNothingClaimed), findsOneWidget);
    expect(find.text('0.0%'), findsNothing);
    expect(find.text('100.0%'), findsNothing);
  });

  testWidgets('happy customers are counted from the stars, and an unrated rider is New',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub());
    await openProfile(tester);

    expect(kpi(tester, en.carrRidersAvgRating), '4.5 ★');
    // Three five-star ratings and one three: three of four are four stars or more.
    expect(find.text(en.carrRidersHappyCustomers(75)), findsOneWidget);

    await tester.tap(find.widgetWithText(ConsoleButton, en.carrRidersBackToDirectory));
    await tester.pumpAndSettle();
    await openProfile(tester, index: 1);

    expect(kpi(tester, en.carrRidersAvgRating), en.carrRidersRatingNew);
    expect(find.text(en.carrRidersNoRatingsYet), findsOneWidget);
    expect(find.textContaining('happy'), findsNothing);
  });

  testWidgets('the output chart draws every day of the window from a sparse series',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub());
    await openProfile(tester);

    final ConsoleBarChart chart = tester.widget<ConsoleBarChart>(find.byType(ConsoleBarChart));
    // 13 August to 11 September: thirty bars, though the server sent only the two days with work.
    expect(chart.bars, hasLength(30));
    expect(chart.bars[19].value, 4); // 1 September
    expect(chart.bars[21].value, 2); // 3 September
    expect(chart.bars.where((ConsoleBar b) => b.value == 0), hasLength(28));
    expect(find.text(en.carrRidersOutputNote('Asia/Beirut')), findsOneWidget);
  });

  testWidgets('a month with nothing delivered says so, rather than a row of hairlines',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub(daily: dailyJson(days: const <Map<String, dynamic>>[])));
    await openProfile(tester);

    expect(find.text(en.carrRidersOutputEmpty), findsOneWidget);
  });

  testWidgets('a chart that could not be read says so, and draws nothing',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub(failing: const <String, (int, Object?)>{
      '/performance/daily': (503, null),
    }));
    await openProfile(tester);

    expect(find.byType(ConsoleBarChart), findsNothing);
    expect(find.text(en.carrRidersCouldNotRead), findsOneWidget);
  });

  testWidgets('hours online: the week drawn whole, in the zone the server split it in',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub());
    await openProfile(tester);

    expect(find.text(en.carrRidersHoursTitle(7)), findsOneWidget);
    expect(find.text('${en.carrRidersHoursValue('1.50')} · ${en.carrRidersShifts(2)}'),
        findsOneWidget);
    // The endpoint sends only dates with time on them; the client draws the rest of the window.
    expect(find.text(en.carrRidersHoursValue('0.00')), findsOneWidget);
    expect(find.text(en.carrRidersHoursZone('UTC')), findsOneWidget);
  });

  testWidgets('papers: a verdict per kind, a replaced upload hidden, a missing one said',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub());
    await openProfile(tester);

    expect(find.text(en.carrRidersDocNationalId), findsOneWidget);
    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersDocVerified), findsOneWidget);
    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersDocWaiting), findsOneWidget);
    // The refused national ID was replaced by the verified one; its verdict is not about the paper
    // the rider rides on.
    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersDocRefused), findsNothing);
    // Nothing uploaded for the vehicle, and that is said rather than left out.
    expect(find.text(en.carrRidersDocVehicleRegistration), findsOneWidget);
    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersDocNotUploaded), findsOneWidget);
    // One paper has a signed link to open; the others have none to offer.
    expect(find.byTooltip(en.carrRidersDocOpen), findsOneWidget);
  });

  testWidgets('papers that could not be read say so', (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub(failing: const <String, (int, Object?)>{
      '/documents': (503, null),
    }));
    await openProfile(tester);

    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersDocVerified), findsNothing);
    expect(find.text(en.carrRidersCouldNotRead), findsOneWidget);
  });

  testWidgets('a rider the platform attached directly: no papers asked for, suspension explained',
      (WidgetTester tester) async {
    final FleetStub stub = FleetStub();
    await pumpDirectory(tester, stub);
    await openProfile(tester, index: 1);

    // In the identity card and the papers card.
    expect(find.text(en.carrRidersNoApplication), findsNWidgets(2));
    expect(stub.called('GET', '/documents'), isFalse);
    // The suspension endpoints are addressed to an application, and there is none.
    expect(find.text(en.carrRidersSuspendUnavailable), findsOneWidget);
    expect(find.widgetWithText(ConsoleSoftButton, en.carrRidersSuspendRider), findsNothing);
    // Ending the contract works on the rider's own reference, so it is still offered.
    expect(find.widgetWithText(ConsoleSoftButton, en.carrRidersTerminate), findsOneWidget);
    // Missing from the roster says nothing about duty, and is said as exactly that.
    expect(find.text(en.carrRidersNoPresenceYet), findsOneWidget);
    expect(find.text(en.carrRidersNoPresenceNote), findsOneWidget);
  });

  testWidgets('employment is what the platform records, and says what it does not',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub());
    await openProfile(tester);

    // The day this company approved her, then the day she applied.
    expect(find.text('Jul 4, 2026'), findsOneWidget);
    expect(find.text('Jul 1, 2026'), findsOneWidget);
    // The rest of what the wizard asked about the vehicle, under the reader's own labels.
    expect(find.text('Honda Wave'), findsOneWidget);
    expect(find.text(en.carrRidersVehicleYear.toUpperCase()), findsOneWidget);
    expect(find.text('2021'), findsOneWidget);
    expect(find.text(en.carrRidersPlateNumber.toUpperCase()), findsOneWidget);
    expect(find.text('B 123456'), findsOneWidget);
    // The application's keys are never printed raw as if they were labels, and the wizard's
    // plumbing — the map pin, who they applied to ride for — is not printed at all.
    expect(find.text('plateNumber'), findsNothing);
    expect(find.textContaining('33.89'), findsNothing);
    expect(find.text('Swift Couriers'), findsNothing);
    // No contract type, pay rate or zone assignment exists, and a rate nobody pays is not drawn.
    expect(find.text(en.carrRidersEmploymentNote), findsOneWidget);
  });

  testWidgets('suspending sends the typed reason the server insists on',
      (WidgetTester tester) async {
    final FleetStub stub = FleetStub();
    await pumpDirectory(tester, stub);
    await openProfile(tester);

    await _tapVisible(tester, find.widgetWithText(ConsoleSoftButton, en.carrRidersSuspendRider));

    final Finder confirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ConsoleSoftButton, en.carrRidersSuspendRider),
    );
    // Dead until a reason is chosen: "suspended" with no reason is not a record anybody can act on.
    expect(tester.widget<ConsoleSoftButton>(confirm).onPressed, isNull);

    await tester.tap(find.text(en.carrRidersChooseReason));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.carrRidersReasonPolicyViolation).last);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(stub.called('POST', '/for-company/p1/app-1/suspend'), isTrue);
    expect(stub.adapter.bodies.any((Object? b) => b is Map && b['reason'] == 'POLICY_VIOLATION'),
        isTrue);
    expect(find.text(en.carrRidersSuspendedToast('Nadia Haddad')), findsOneWidget);
  });

  testWidgets('a suspended rider reads as suspended and is offered reinstatement',
      (WidgetTester tester) async {
    final FleetStub stub = FleetStub(suspended: true);
    await pumpDirectory(tester, stub);
    await openProfile(tester);

    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusSuspended), findsOneWidget);
    await _tapVisible(
        tester, find.widgetWithText(ConsoleSoftButton, en.carrRidersReinstateRider));
    await tester.tap(find.widgetWithText(ConsolePrimaryButton, en.carrRidersReinstateRider));
    await tester.pumpAndSettle();

    expect(stub.called('POST', '/for-company/p1/app-1/unsuspend'), isTrue);
  });

  testWidgets('Terminate Contract says what happens, jobs in flight included, before sending',
      (WidgetTester tester) async {
    final FleetStub stub = FleetStub();
    await pumpDirectory(tester, stub);
    await openProfile(tester);

    await _tapVisible(tester, find.widgetWithText(ConsoleSoftButton, en.carrRidersTerminate));
    expect(find.text(en.carrRidersTerminateTitle('Nadia Haddad')), findsOneWidget);
    expect(find.text(en.carrRidersTerminateBody('Nadia Haddad')), findsOneWidget);
    expect(find.text(en.carrRidersTerminateJobs), findsOneWidget);
    expect(find.text(en.carrRidersTerminateMoney), findsOneWidget);

    // Cancel sends nothing.
    await tester.tap(find.text(en.cancel));
    await tester.pumpAndSettle();
    expect(stub.called('DELETE', '/my-company/riders/'), isFalse);

    await _tapVisible(tester, find.widgetWithText(ConsoleSoftButton, en.carrRidersTerminate));
    await tester.tap(find.widgetWithText(ConsoleSoftButton, en.carrRidersTerminateConfirm));
    await tester.pumpAndSettle();

    // Addressed to the caller's own company by the route itself: no company id is sent.
    expect(stub.called('DELETE', '/api/delivery-providers/my-company/riders/$nadia'), isTrue);
    // Back on the directory, which says what happened.
    expect(find.text(en.carrRidersTitle), findsOneWidget);
    expect(find.text(en.carrRidersTerminated('Nadia Haddad')), findsOneWidget);
  });

  testWidgets('a rider carrying your work is not released, and the page says why',
      (WidgetTester tester) async {
    final FleetStub stub = FleetStub(failing: <String, (int, Object?)>{
      'DELETE /my-company/riders/': (409, <String, dynamic>{
        'title': 'Rider still carrying',
        'detail': 'This rider is carrying 2 of your jobs.',
        'jobs': 2,
      }),
    });
    await pumpDirectory(tester, stub);
    await openProfile(tester);

    await _tapVisible(tester, find.widgetWithText(ConsoleSoftButton, en.carrRidersTerminate));
    await tester.tap(find.widgetWithText(ConsoleSoftButton, en.carrRidersTerminateConfirm));
    await tester.pumpAndSettle();

    expect(find.text(en.carrRidersTerminateCarrying(2)), findsOneWidget);
    // Nothing changed, so the profile stays.
    expect(find.text(en.carrRidersProfileTitle), findsOneWidget);
  });

  testWidgets('a rider already off the fleet is said, and the fleet is read again',
      (WidgetTester tester) async {
    final FleetStub stub = FleetStub(failing: <String, (int, Object?)>{
      'DELETE /my-company/riders/': (404, <String, dynamic>{
        'detail': 'No rider by that reference is on your fleet',
      }),
    });
    await pumpDirectory(tester, stub);
    await openProfile(tester);

    await _tapVisible(tester, find.widgetWithText(ConsoleSoftButton, en.carrRidersTerminate));
    await tester.tap(find.widgetWithText(ConsoleSoftButton, en.carrRidersTerminateConfirm));
    await tester.pumpAndSettle();

    expect(find.text(en.carrRidersNotOnFleet), findsOneWidget);
    expect(
      stub.adapter.calls
          .where((String c) => c == 'GET /api/delivery-providers/my-company/riders'),
      hasLength(2),
    );
  });

  testWidgets('a page about one rider, registered by the shell, opens from the profile and back',
      (WidgetTester tester) async {
    // The extension point attendance and payroll will use: a button per page, opened in place.
    await pumpDirectory(tester, FleetStub(), riderPages: <RiderPage>[
      RiderPage(
        icon: Icons.event_available_outlined,
        label: (_) => 'Attendance',
        build: (BuildContext context, RiderPageContext rider, VoidCallback onBack) => Column(
          children: <Widget>[
            Text('Attendance for ${rider.name}: '
                '${rider.riderId}, ${rider.companyId}, ${rider.application?.id}'),
            TextButton(onPressed: onBack, child: const Text('Back to the profile')),
          ],
        ),
      ),
    ]);
    await openProfile(tester);

    await _tapVisible(tester, find.widgetWithText(ConsoleButton, 'Attendance'));
    expect(find.text('Attendance for Nadia Haddad: rider-aaaaaaaa, p1, app-1'), findsOneWidget);

    await tester.tap(find.text('Back to the profile'));
    await tester.pumpAndSettle();
    expect(find.text(en.carrRidersProfileTitle), findsOneWidget);
  });

  testWidgets('reads in Arabic, right to left', (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub(), locale: const Locale('ar'));
    await openProfile(tester, strings: ar);

    expect(Directionality.of(tester.element(find.byType(RiderProfileScreen))),
        TextDirection.rtl);
    expect(find.text(ar.carrRidersProfileTitle), findsOneWidget);
    expect(find.text(ar.carrRidersDocNationalId), findsOneWidget);
    expect(find.widgetWithText(ConsoleSoftButton, ar.carrRidersTerminate), findsOneWidget);
    expect(find.text(en.carrRidersTerminate), findsNothing);
  });

  for (final double width in <double>[1180, 1020, 764]) {
    testWidgets('lays out at a ${width.toInt()}px content column', (WidgetTester tester) async {
      await pumpDirectory(tester, FleetStub(), width: width, height: 3200);
      await openProfile(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
