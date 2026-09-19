import 'package:delivery_portal/src/carrier/fleet_roster.dart';
import 'package:delivery_portal/src/carrier/riders_directory_screen.dart';
import 'package:delivery_portal/src/shell/console_controls.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'riders_harness.dart';

/// The Riders HR directory — Figma `web-carrier-riders-directory` (112:413).
///
/// It superseded the "Riders Management" table on the same destination, so these carry that table's
/// tests forward — searching, the working-now view, Add Rider, opening a rider — beside what the
/// card grid added. The rule throughout: every figure comes from the service that owns it, a source
/// that failed is a dash rather than a zero, and a state the platform does not have is not drawn.
/// There is no "on break", a rider the presence roster says nothing about is not "offline", and a
/// standing that could not be read is not a clean one.
void main() {
  String kpi(WidgetTester tester, String label) =>
      tester.widget<ConsoleKpiCard>(find.widgetWithText(ConsoleKpiCard, label)).value;

  testWidgets('draws one card per rider, each fact from the service that owns it',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub());

    expect(find.text(en.carrRidersTitle), findsOneWidget);
    expect(find.widgetWithText(ConsoleButton, en.carrRidersManageProfile), findsNWidgets(2));

    // Nadia: her application's name, reference, region and vehicle; the order service's rating;
    // today's carrier-scoped count; presence off the roster.
    expect(find.text('Nadia Haddad'), findsOneWidget);
    expect(find.text('#REF-app-1'), findsOneWidget);
    expect(find.text('Beirut'), findsOneWidget);
    expect(find.text(en.carrRidersVehicleMotorcycle), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text(en.carrRidersDeliveredToday(3)), findsOneWidget);
    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusActive), findsOneWidget);

    // The rider the platform attached directly has no application: the short reference stands in
    // for a name and a badge, and the region and vehicle nobody recorded are dashes.
    expect(find.text('RIDER-BB'), findsOneWidget);
    expect(find.text('#RIDER-BB'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
  });

  testWidgets("a company rider's region is the company's, read as names rather than a list",
      (WidgetTester tester) async {
    await pumpDirectory(
        tester,
        FleetStub(applications: <Map<String, dynamic>>[
          applicationJson(
            id: 'app-1',
            name: 'Nadia Haddad',
            riderRef: nadia,
            // What the server records for a rider who applied to this company: its region, as a
            // list. An area an older app typed as well does not win over it.
            details: const <String, Object?>{
              'companyRegions': <String>['Achrafieh', 'Hamra'],
              'preferredArea': 'Verdun',
              'vehicleType': 'MOTORCYCLE',
            },
          ),
        ]));

    expect(find.text('Achrafieh, Hamra'), findsOneWidget);
    expect(find.text('[Achrafieh, Hamra]'), findsNothing);
    expect(find.text('Verdun'), findsNothing);
  });

  testWidgets('every rating and every standing comes from a fleet-wide read, never one per rider',
      (WidgetTester tester) async {
    // Six plus two per rider used to go out at once — more than eighty for forty riders — into the
    // gateway's per-address rate limit. However many riders, the load is the same seven reads.
    final FleetStub stub = FleetStub(riders: <String>[
      nadia,
      direct,
      for (int i = 0; i < 20; i++) 'rider-${i.toString().padLeft(8, '0')}',
    ]);
    await pumpDirectory(tester, stub);

    expect(stub.adapter.calls, hasLength(7));
    expect(stub.adapter.calls.where((String c) => c.contains('rating')),
        <String>['GET /api/delivery-providers/my-company/riders/ratings']);
    expect(stub.called('GET', '/suspension'), isFalse);
  });

  testWidgets('an unrated rider is New, never a zero, and absent from today\'s list is zero',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub());

    expect(find.text(en.carrRidersRatingNew), findsOneWidget);
    expect(find.text('0.0'), findsNothing);
    // The delivered-today endpoint leaves out riders who delivered nothing, by contract.
    expect(find.text(en.carrRidersDeliveredToday(0)), findsOneWidget);
  });

  testWidgets('a figure whose source failed is left off, not New and not zero',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub(failing: const <String, (int, Object?)>{
      '/my-company/riders/ratings': (503, null),
      '/riders/delivered-today': (503, null),
    }));

    expect(find.text('4.5'), findsNothing);
    // With the ratings unread, nobody is New: that would be a claim about riders nobody read.
    expect(find.text(en.carrRidersRatingNew), findsNothing);
    // "(0 today)" would be a number the platform does not have.
    expect(find.text(en.carrRidersDeliveredToday(0)), findsNothing);
    expect(find.text(en.carrRidersDeliveredToday(3)), findsNothing);
  });

  testWidgets('the presence cards count what the roster says, and how many it cannot place',
      (WidgetTester tester) async {
    await pumpDirectory(
      tester,
      FleetStub(
        riders: const <String>[nadia, direct, 'rider-cccccccc', 'rider-dddddddd', 'rider-eeeeeeee'],
        jobs: <Map<String, dynamic>>[jobJson(id: 'aaaaaaaa11')],
        roster: <Map<String, dynamic>>[
          presenceJson(nadia),
          presenceJson('rider-cccccccc', state: 'STALE'),
          presenceJson('rider-dddddddd', state: 'OFF_DUTY'),
        ],
      ),
    );

    expect(kpi(tester, en.carrRidersStatTotal), '5');
    expect(kpi(tester, en.carrRidersStatOnDuty), '1');
    // Declared on duty and gone quiet: signal lost, never relabelled a break.
    expect(kpi(tester, en.carrRidersStatSignalLost), '1');
    expect(kpi(tester, en.carrRidersStatOffline), '1');

    // Two riders the roster has no duty or location for, so it cannot place them either way. They
    // are counted in no card, and said where a reader would otherwise assume them.
    expect(find.text(en.carrRidersNoPresenceCount(2)), findsOneWidget);
    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusOffline), findsOneWidget);
    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusSignalLost), findsOneWidget);
  });

  testWidgets('a rider out on your job but missing from the roster is on a job, and on duty',
      (WidgetTester tester) async {
    // A rider's first job can be in hand before the roster places them.
    await pumpDirectory(tester, FleetStub());

    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusOnAJob), findsOneWidget);
    expect(kpi(tester, en.carrRidersStatOnDuty), '2');
    expect(find.text(en.carrRidersStatOfflineNote), findsOneWidget);
  });

  testWidgets('a roster that could not be read is a dash on every presence card, not "offline"',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub(failing: const <String, (int, Object?)>{
      '/tracking/riders/roster': (503, <String, dynamic>{'message': 'Fleet unavailable'}),
    }));

    expect(kpi(tester, en.carrRidersStatTotal), '2');
    for (final String label in <String>[
      en.carrRidersStatOnDuty,
      en.carrRidersStatSignalLost,
      en.carrRidersStatOffline,
    ]) {
      expect(kpi(tester, label), '—', reason: label);
      // A filter over an unknown would be a list of guesses.
      expect(tester.widget<ConsoleKpiCard>(find.widgetWithText(ConsoleKpiCard, label)).onTap,
          isNull,
          reason: label);
    }
    expect(find.text(en.carrRidersPresenceUnknown), findsNWidgets(3));

    // With no presence the badge falls back to the job board: the rider out on a job says so, and
    // nobody is called active or offline.
    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusOnAJob), findsOneWidget);
    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusActive), findsNothing);
    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusOffline), findsNothing);
  });

  testWidgets('a job board that could not be read does not invent "On a job" or "Offline"',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub(failing: const <String, (int, Object?)>{
      '/orders/carrier': (503, null),
    }));

    // The rider missing from the roster is out on a job, but with the board unread nothing says so
    // — and nothing may say otherwise. No badge, counted in no card, and the count said.
    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusOnAJob), findsNothing);
    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusOffline), findsNothing);
    expect(kpi(tester, en.carrRidersStatOnDuty), '1');
    expect(find.text(en.carrRidersNoPresenceCount(1)), findsOneWidget);
  });

  testWidgets('a suspension outranks presence', (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub(suspended: true));

    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusSuspended), findsOneWidget);
    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusActive), findsNothing);
  });

  testWidgets('a standing that could not be read outranks presence too, and says it is unknown',
      (WidgetTester tester) async {
    // Nadia is on duty. Were her standing unread and the badge to fall back to presence, a
    // suspended rider would read "Active" — the one guess this badge must never make.
    await pumpDirectory(tester, FleetStub(suspended: null));

    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusStandingUnknown),
        findsOneWidget);
    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusActive), findsNothing);
  });

  testWidgets('with the applications unread, no rider\'s standing is known and none is guessed',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub(failing: const <String, (int, Object?)>{
      'GET =/applications/for-company/p1': (503, null),
    }));

    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusStandingUnknown),
        findsNWidgets(2));
    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusActive), findsNothing);
    expect(find.widgetWithText(ConsoleStatusPill, en.carrRidersStatusOnAJob), findsNothing);
  });

  testWidgets('search narrows by name, by reference and by short reference',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub());
    final Finder search = find.byType(TextField).first;

    await tester.enterText(search, 'nadia');
    await tester.pumpAndSettle();
    expect(find.text('Nadia Haddad'), findsOneWidget);
    expect(find.text('RIDER-BB'), findsNothing);

    await tester.enterText(search, 'ref-app-1');
    await tester.pumpAndSettle();
    expect(find.text('Nadia Haddad'), findsOneWidget);
    expect(find.text('RIDER-BB'), findsNothing);

    await tester.enterText(search, 'rider-bb');
    await tester.pumpAndSettle();
    expect(find.text('RIDER-BB'), findsOneWidget);
    expect(find.text('Nadia Haddad'), findsNothing);

    await tester.enterText(search, 'nobody by this name');
    await tester.pumpAndSettle();
    expect(find.text(en.carrRidersNoMatch), findsOneWidget);
  });

  FleetStub twoHired() => FleetStub(
        riders: const <String>[nadia, direct, 'rider-cccccccc'],
        applications: <Map<String, dynamic>>[
          applicationJson(
            id: 'app-1',
            name: 'Nadia Haddad',
            riderRef: nadia,
            details: const <String, String>{'workRegion': 'Beirut', 'vehicleType': 'MOTORCYCLE'},
          ),
          // An older wizard's key for the region, and a wire in lower case.
          applicationJson(
            id: 'app-3',
            name: 'Omar Khoury',
            riderRef: 'rider-cccccccc',
            details: const <String, String>{'city': 'Tripoli', 'vehicleType': 'car'},
          ),
        ],
      );

  testWidgets('the zone filter offers only regions riders gave, and narrows to one',
      (WidgetTester tester) async {
    await pumpDirectory(tester, twoHired());

    await tester.tap(find.text(en.carrRidersZoneAll));
    await tester.pumpAndSettle();
    // On Omar's card, and in the menu. No zone that nobody is in is offered.
    expect(find.text('Tripoli'), findsNWidgets(2));
    await tester.tap(find.text('Tripoli').last);
    await tester.pumpAndSettle();

    expect(find.text(en.carrRidersZoneValue('Tripoli')), findsOneWidget);
    expect(find.text('Omar Khoury'), findsOneWidget);
    expect(find.text('Nadia Haddad'), findsNothing);
    // Nobody the platform attached directly gave a region, so they are not in it either.
    expect(find.text('RIDER-BB'), findsNothing);
  });

  // A company rider's region is the company's list of regions, which the card shows as one line.
  // The filter offered that line as one zone, which matched only riders with exactly that list.
  testWidgets("the zone filter offers each of a company rider's regions on its own, and finds them under each",
      (WidgetTester tester) async {
    await pumpDirectory(
        tester,
        FleetStub(
          riders: const <String>[nadia, direct, 'rider-cccccccc'],
          applications: <Map<String, dynamic>>[
            applicationJson(
              id: 'app-1',
              name: 'Nadia Haddad',
              riderRef: nadia,
              details: const <String, Object?>{
                'companyRegions': <String>['Achrafieh', 'Hamra'],
              },
            ),
            applicationJson(
              id: 'app-3',
              name: 'Omar Khoury',
              riderRef: 'rider-cccccccc',
              details: const <String, Object?>{
                'companyRegions': <String>['Hamra'],
              },
            ),
          ],
        ));

    await tester.tap(find.text(en.carrRidersZoneAll));
    await tester.pumpAndSettle();
    // The menu offers each region once; the card still reads as the list.
    expect(find.text('Achrafieh'), findsOneWidget);
    expect(find.text('Hamra'), findsNWidgets(2), reason: "Omar's card, and the menu");
    expect(find.text('Achrafieh, Hamra'), findsOneWidget, reason: "Nadia's card only");
    await tester.tap(find.text('Hamra').last);
    await tester.pumpAndSettle();

    expect(find.text(en.carrRidersZoneValue('Hamra')), findsOneWidget);
    expect(find.text('Nadia Haddad'), findsOneWidget);
    expect(find.text('Omar Khoury'), findsOneWidget);
    expect(find.text('RIDER-BB'), findsNothing);

    await tester.tap(find.text(en.carrRidersZoneValue('Hamra')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Achrafieh').last);
    await tester.pumpAndSettle();

    expect(find.text('Nadia Haddad'), findsOneWidget);
    expect(find.text('Omar Khoury'), findsNothing);
  });

  testWidgets('the vehicle filter narrows by the vehicle riders gave, in the reader\'s words',
      (WidgetTester tester) async {
    await pumpDirectory(tester, twoHired());

    await tester.tap(find.text(en.carrRidersVehicleAll));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.carrRidersVehicleCar).last);
    await tester.pumpAndSettle();

    expect(find.text(en.carrRidersVehicleValue(en.carrRidersVehicleCar)), findsOneWidget);
    expect(find.text('Omar Khoury'), findsOneWidget);
    expect(find.text('Nadia Haddad'), findsNothing);
  });

  testWidgets('a presence card filters the grid, as the old "Working now" tab did',
      (WidgetTester tester) async {
    await pumpDirectory(
      tester,
      FleetStub(
        jobs: <Map<String, dynamic>>[jobJson(id: 'aaaaaaaa11')],
        roster: <Map<String, dynamic>>[
          presenceJson(nadia),
          presenceJson(direct, state: 'OFF_DUTY'),
        ],
      ),
    );

    await tester.tap(find.widgetWithText(ConsoleKpiCard, en.carrRidersStatOnDuty));
    await tester.pumpAndSettle();
    expect(find.text('Nadia Haddad'), findsOneWidget);
    expect(find.text('RIDER-BB'), findsNothing);
    expect(find.text(en.carrRidersShowingOnly(en.carrRidersStatOnDuty)), findsOneWidget);

    await tester.tap(find.widgetWithText(ConsoleTintButton, en.carrRidersShowEveryone));
    await tester.pumpAndSettle();
    expect(find.text('RIDER-BB'), findsOneWidget);
  });

  testWidgets('Add Rider approves somebody who is actually waiting', (WidgetTester tester) async {
    // Riders reach a fleet by applying and being approved, so the design's primary button opens the
    // people waiting for exactly that, rather than a form nothing could submit.
    final FleetStub stub = FleetStub();
    await pumpDirectory(tester, stub);

    final Finder add = find.widgetWithText(ConsolePrimaryButton, en.carrRidersAddRider);
    expect(tester.widget<ConsolePrimaryButton>(add).onPressed, isNotNull);
    await tester.tap(add);
    await tester.pumpAndSettle();

    expect(find.text(en.carrRidersWaitingCount(1)), findsOneWidget);
    expect(find.text('Karim Aoun'), findsOneWidget);
    // Irreversible, so it is said before the button rather than after.
    expect(find.text(en.hiringAlsoCreatesTheirAccount), findsOneWidget);

    await tester.tap(find.widgetWithText(ConsoleButton, en.carrRidersApprove));
    await tester.pumpAndSettle();

    expect(stub.called('POST', '/for-company/p1/app-2/approve'), isTrue);
    expect(find.text(en.carrRidersOnYourFleet), findsOneWidget);
  });

  testWidgets('Add Rider is off, and says why, when applications could not be read',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub(failing: const <String, (int, Object?)>{
      'GET =/applications/for-company/p1': (503, null),
    }));

    final Finder add = find.widgetWithText(ConsolePrimaryButton, en.carrRidersAddRider);
    expect(tester.widget<ConsolePrimaryButton>(add).onPressed, isNull);
    expect(find.byTooltip(en.carrRidersAddRiderUnavailable), findsOneWidget);
    // And nobody is named from an application that did not arrive.
    expect(find.text('Nadia Haddad'), findsNothing);
    expect(find.text('RIDER-AA'), findsOneWidget);
  });

  testWidgets('Manage Profile opens that rider in place, and Back lands on the same search',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub());
    await tester.enterText(find.byType(TextField).first, 'nadia');
    await tester.pumpAndSettle();

    await openProfile(tester);
    expect(find.text(en.carrRidersProfileTitle), findsOneWidget);
    expect(find.text(en.carrRidersBadgeId(ltrIsolate('REF-app-1'))), findsOneWidget);

    await tester.tap(find.widgetWithText(ConsoleButton, en.carrRidersBackToDirectory));
    await tester.pumpAndSettle();
    expect(find.text(en.carrRidersTitle), findsOneWidget);
    expect(find.text('Nadia Haddad'), findsOneWidget);
    expect(find.text('RIDER-BB'), findsNothing);
  });

  testWidgets('the whole card opens the profile, the way a table row opened its drawer',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub());

    await tester.tap(find.text('RIDER-BB'));
    await tester.pumpAndSettle();

    expect(find.text(en.carrRidersProfileTitle), findsOneWidget);
    expect(find.text(en.carrRidersNoApplication), findsWidgets);
  });

  testWidgets('an empty fleet is called out, not left to be inferred', (WidgetTester tester) async {
    // A company with no riders looks available and can collect nothing — the most confusing way to
    // be sent no work.
    await pumpDirectory(tester, FleetStub(riders: const <String>[]));

    expect(find.text(en.noRidersBlurb), findsOneWidget);
  });

  testWidgets('belonging to no company reads as a gap, not a crash', (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub(failing: const <String, (int, Object?)>{
      'GET =/my-company': (404, null),
    }));

    expect(find.text(en.noCompanyYet), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets('reads in Arabic, right to left, with the labels translated',
      (WidgetTester tester) async {
    await pumpDirectory(tester, FleetStub(), locale: const Locale('ar'));

    expect(Directionality.of(tester.element(find.byType(RidersDirectoryScreen))),
        TextDirection.rtl);
    expect(find.text(ar.carrRidersTitle), findsOneWidget);
    expect(find.text(ar.carrRidersVehicleMotorcycle), findsOneWidget);
    expect(find.widgetWithText(ConsoleStatusPill, ar.carrRidersStatusActive), findsOneWidget);
    expect(find.text(en.carrRidersStatusActive), findsNothing);
    expect(find.text(en.carrRidersManageProfile), findsNothing);
  });

  testWidgets('on an Arabic card the reference still reads left to right, from the card\'s start',
      (WidgetTester tester) async {
    // Laid out right to left, "#REF-app-1" came out as "REF-app-1#" — not the reference the company
    // and the rider quote to each other.
    await pumpDirectory(tester, FleetStub(), locale: const Locale('ar'));

    final Finder reference = find.text('#REF-app-1');
    expect(reference, findsOneWidget);
    final Directionality direction = tester.widget<Directionality>(
        find.ancestor(of: reference, matching: find.byType(Directionality)).first);
    expect(direction.textDirection, TextDirection.ltr);
    // Still at the start edge of a right-to-left card.
    expect(tester.widget<Text>(reference).textAlign, TextAlign.right);
  });

  // What a 1440 / 1280 / 1024 window leaves the content column once the 260px rail has its share.
  // An overflow fails the test.
  for (final double width in <double>[1180, 1020, 764]) {
    testWidgets('lays out at a ${width.toInt()}px content column', (WidgetTester tester) async {
      await pumpDirectory(tester, FleetStub(), width: width);
      expect(tester.takeException(), isNull);
    });
  }
}
