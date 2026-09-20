import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/rider_home_screen.dart';
import 'package:mobile_app/src/rider_job_card.dart';
import 'package:mobile_app/src/rider_location_banner.dart';
import 'package:mobile_app/src/rider_location_disclosure.dart';
import 'package:mobile_app/src/rider_location_simulator.dart';
import 'package:mobile_app/src/rider_order_detail_screen.dart';

/// The rider app reports where the rider really is — to the one customer whose delivery they are
/// on — and says so when it cannot.
///
/// The screen used to random-walk a rider from London and, once real, put every fix on every
/// order in hand, so one customer's map drew the way to another's door. These pin what replaced
/// it: the phone's own fix, on the order whose leg the rider is on and no other; nothing at all
/// without the permission or with the app in the background; the rider told who sees their
/// location before the system asks for it; an honest banner with the one way out for each
/// refusal; the rider's own map on the phone's own reading; and no simulator anywhere a release
/// build can reach.
void main() {
  group('what is sent, and on which order', () {
    testWidgets('each fix goes on the one order whose leg the rider is on, with the phone\'s fix',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true, orders: <Map<String, dynamic>>[
        _order('o-ready', 'READY', address: _mar),
        _order('o-carried', 'PICKED_UP', address: _hamra),
      ]);
      await rig.pump(tester);
      await tester.pump(const Duration(seconds: 25));

      final List<_Call> pings = rig.gateway.pings;
      expect(pings, isNotEmpty);
      // The rider carries one customer's order: heading on with it, or to the other shop. Either
      // way the fix goes on the carried order — never on the other customer's, whose map must not
      // be shown the way to this door.
      expect(pings.map((_Call c) => c.path).toSet(), <String>{'/api/tracking/orders/o-carried/ping'});
      final Map<String, dynamic> body = pings.first.body!;
      expect(body['lat'], _Source.lat);
      expect(body['lng'], _Source.lng);
      expect(body['accuracyM'], 6);
      expect(body['recordedAt'], isA<String>());
      expect(rig.gateway.calls, isNot(contains('POST /api/tracking/riders/me/ping')),
          reason: 'An order ping is presence already; a second, order-less one is the same write.');
      await rig.dispose(tester);
    });

    testWidgets(
        'carrying orders to two doors: no customer is shown the rider until Start navigation '
        'says which', (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true, orders: <Map<String, dynamic>>[
        _order('o-a', 'PICKED_UP', address: _hamra, store: 'Shop A'),
        _order('o-b', 'PICKED_UP', address: _mar, store: 'Shop B'),
      ]);
      await rig.pump(tester);
      final DeliveryStrings t = rig.t(tester);

      expect(rig.gateway.pings.map((_Call c) => c.path).toSet(),
          <String>{'/api/tracking/riders/me/ping'},
          reason: 'On nobody\'s order: either could show one customer the other\'s door.');
      await tester.tap(find.text(t.riderTabActive).last);
      await tester.pump();
      expect(find.text(t.riderGpsLegUnknownTitle), findsOneWidget);

      // The rider opens B's order and asks for directions: that is where they are heading.
      await tester.tap(find.descendant(
          of: find.ancestor(
              of: find.text(t.riderOrderRef('o-b')), matching: find.byType(RiderTaskCard)),
          matching: find.text(t.riderViewDetails)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(t.riderStartNavigation), 200,
          scrollable: find
              .descendant(
                  of: find.byType(RiderOrderDetailScreen), matching: find.byType(Scrollable))
              .first);
      await tester.tap(find.text(t.riderStartNavigation));
      await tester.pump();
      Navigator.of(tester.element(find.byType(RiderOrderDetailScreen))).pop();
      await tester.pumpAndSettle();
      rig.gateway.log.clear();
      await tester.pump(const Duration(seconds: 11));

      expect(rig.gateway.pings.map((_Call c) => c.path).toSet(),
          <String>{'/api/tracking/orders/o-b/ping'});
      expect(find.text(t.riderGpsLegUnknownTitle), findsNothing);
      await rig.dispose(tester);
    });

    testWidgets('Navigate on an Active card says the same: that order is where the rider is going',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true, orders: <Map<String, dynamic>>[
        _order('o-a', 'PICKED_UP', address: _hamra),
        _order('o-b', 'PICKED_UP', address: _mar),
      ]);
      await rig.pump(tester);
      final DeliveryStrings t = rig.t(tester);
      await tester.tap(find.text(t.riderTabActive).last);
      await tester.pump();

      await tester.tap(find.descendant(
          of: find.ancestor(
              of: find.text(t.riderOrderRef('o-a')), matching: find.byType(RiderTaskCard)),
          matching: find.text(t.riderNavigate)));
      await tester.pump();
      rig.gateway.log.clear();
      await tester.pump(const Duration(seconds: 11));
      await rig.settle(tester);

      expect(rig.gateway.pings.map((_Call c) => c.path).toSet(),
          <String>{'/api/tracking/orders/o-a/ping'});
      await rig.dispose(tester);
    });

    testWidgets('on duty with nothing in hand, sends the order-less ping', (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true);
      await rig.pump(tester);

      expect(rig.gateway.calls, contains('POST /api/tracking/riders/me/ping'));
      await rig.dispose(tester);
    });

    testWidgets('off duty with nothing in hand: nothing asked, nothing sent, nothing shown',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: false);
      await rig.pump(tester);
      await tester.pump(const Duration(seconds: 30));

      expect(rig.source.asks, isEmpty, reason: 'No prompt for a rider nobody is watching.');
      expect(rig.gateway.pings, isEmpty);
      expect(find.byType(RiderLocationDisclosure), findsNothing);
      expect(find.byType(SoftNote), findsNothing);
      expect(find.text(rig.t(tester).riderGpsOffTitle), findsNothing);
      await rig.dispose(tester);
    });

    testWidgets('while sharing with orders in hand, the Active tab says who sees it, and when',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: false, orders: <Map<String, dynamic>>[
        _order('o-carried', 'PICKED_UP'),
      ]);
      await rig.pump(tester);
      final DeliveryStrings t = rig.t(tester);

      await tester.tap(find.text(t.riderTabActive).last);
      await tester.pump();

      expect(find.text(t.riderGpsSharingNote), findsOneWidget);
      await rig.dispose(tester);
    });
  });

  group('before the phone asks for the location', () {
    testWidgets('the rider reads who sees it, when, and for how long — then the system prompt',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true)..source.accessResult = RiderLocationAccess.denied;
      await rig.pump(tester);
      final DeliveryStrings t = rig.t(tester);

      expect(find.byType(RiderLocationDisclosure), findsOneWidget);
      for (final String line in <String>[
        t.riderGpsDisclosureTitle,
        t.riderGpsDisclosureCustomer,
        t.riderGpsDisclosureShop,
        t.riderGpsDisclosureCompany,
        t.riderGpsDisclosureSupport,
        t.riderGpsDisclosureWhen,
        t.riderGpsDisclosureKept,
      ]) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      expect(rig.source.asks, everyElement(isFalse),
          reason: 'No system prompt while the rider is still reading.');

      await tester.tap(find.text(t.riderGpsDisclosureContinue));
      await rig.settle(tester);

      expect(rig.source.asks.last, isTrue, reason: 'The prompt comes after the sheet.');
      expect(find.byType(RiderLocationDisclosure), findsNothing);
      expect(rig.gateway.pings, isNotEmpty);
      await rig.dispose(tester);
    });

    testWidgets('"Not now": no prompt and nothing sent; "Allow location" explains again first',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true, orders: <Map<String, dynamic>>[
        _order('o-carried', 'PICKED_UP'),
      ])
        ..source.accessResult = RiderLocationAccess.denied;
      await rig.pump(tester);
      final DeliveryStrings t = rig.t(tester);

      await tester.tap(find.text(t.riderGpsDisclosureNotNow));
      await rig.settle(tester);

      expect(rig.source.asks, everyElement(isFalse));
      expect(rig.gateway.pings, isEmpty);
      expect(rig.source.reads, 0, reason: 'No reading without the permission.');
      expect(find.text(t.riderGpsOffTitle), findsOneWidget);
      expect(find.text(t.riderGpsDeniedBody), findsOneWidget);

      await tester.tap(find.text(t.riderGpsAllow));
      await rig.settle(tester);
      expect(find.byType(RiderLocationDisclosure), findsOneWidget);

      await tester.tap(find.text(t.riderGpsDisclosureContinue));
      await rig.settle(tester);

      expect(rig.source.asks.last, isTrue);
      expect(rig.gateway.pings, isNotEmpty, reason: 'Allowed: the first fix goes at once.');
      expect(find.text(t.riderGpsOffTitle), findsNothing);
      await rig.dispose(tester);
    });
  });

  group('when the rider cannot be seen', () {
    testWidgets('denied for good: the banner opens this app\'s settings page, and no sheet',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true)..source.accessResult = RiderLocationAccess.deniedForever;
      await rig.pump(tester);
      final DeliveryStrings t = rig.t(tester);

      expect(find.byType(RiderLocationDisclosure), findsNothing,
          reason: 'Nothing will be asked, so there is nothing to explain first.');
      expect(find.text(t.riderGpsBlockedBody), findsOneWidget);
      await tester.tap(find.text(t.locOpenSettings));
      await tester.pump();

      expect(rig.source.appSettingsOpened, 1);
      expect(rig.gateway.pings, isEmpty);
      await rig.dispose(tester);
    });

    testWidgets('location switched off: the banner opens the location switch',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true)..source.accessResult = RiderLocationAccess.servicesOff;
      await rig.pump(tester);
      final DeliveryStrings t = rig.t(tester);

      expect(find.text(t.riderGpsServicesOffBody), findsOneWidget);
      await tester.tap(find.text(t.locTurnOn));
      await tester.pump();

      expect(rig.source.locationSettingsOpened, 1);

      // The same banner leads Active and Settings too — Settings being where going on duty is
      // what made the location needed in the first place.
      for (final String tab in <String>[t.riderTabActive, t.settings]) {
        await tester.tap(find.text(tab).last);
        await tester.pump();
        expect(find.text(t.riderGpsServicesOffBody), findsOneWidget, reason: 'On $tab');
      }
      await rig.dispose(tester);
    });

    testWidgets('approximate only: told why, sent to settings, nothing sent',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true)..source.accessResult = RiderLocationAccess.approximate;
      await rig.pump(tester);
      final DeliveryStrings t = rig.t(tester);

      expect(find.text(t.riderGpsApproximateTitle), findsOneWidget);
      expect(find.text(t.locOpenSettings), findsOneWidget);
      expect(rig.gateway.pings, isEmpty);
      await rig.dispose(tester);
    });

    testWidgets('no fix: no ping, and a banner with no button that could not work',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true)..source.noFix = true;
      await rig.pump(tester);
      final DeliveryStrings t = rig.t(tester);

      expect(rig.gateway.pings, isEmpty);
      expect(find.text(t.riderGpsNoFixTitle), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(RiderLocationBanner), matching: find.byType(YdPillButton)),
          findsNothing);
      await rig.dispose(tester);
    });

    // After an upgrade, or outside the service area, the platform can keep refusing what the
    // phone sends. The rider used to be left on "locating" while nobody saw them.
    testWidgets('fixes the platform keeps refusing: the banner says customers cannot see them',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true, orders: <Map<String, dynamic>>[
        _order('o-carried', 'PICKED_UP'),
      ])
        ..gateway.refuseWith = 'OUTSIDE_SERVICE_AREA';
      await rig.pump(tester);
      final DeliveryStrings t = rig.t(tester);
      expect(find.text(t.riderGpsNoFixTitle), findsNothing, reason: 'One refusal is a hiccup.');

      await tester.pump(const Duration(seconds: 21));
      await rig.settle(tester);

      expect(find.text(t.riderGpsNoFixTitle), findsOneWidget);
      expect(find.text(t.riderGpsClockTitle), findsNothing, reason: 'Not the clock.');
      await rig.dispose(tester);
    });
  });

  group('the rider\'s own map, and no position from anywhere but the phone', () {
    // The platform's last stored position for a rider who upgraded from the simulator is the
    // London walk. The map used to open there for the whole session. Now what the rider sees
    // and what the rider sends are both the phone's own reading, whatever the platform holds.
    testWidgets('the mini-map centres on the phone\'s fix, and every ping carries that fix',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true, storedAt: (lat: 51.5074, lng: -0.1278));
      await rig.pump(tester, settleAfter: false);

      // Caught on the frame it is first drawn: a test has no tile server, and the screen gives the
      // map up for its placeholder after a run of refused tiles.
      final (FlutterMap map, MarkerLayer markers) = await _firstMap(tester);
      expect(map.options.initialCenter.latitude, _Source.lat);
      expect(map.options.initialCenter.longitude, _Source.lng);
      expect(markers.markers.single.point.latitude, _Source.lat);
      expect(markers.markers.single.point.longitude, _Source.lng);

      await rig.settle(tester);
      await tester.pump(const Duration(seconds: 41));
      await rig.settle(tester);
      expect(rig.gateway.pings, hasLength(greaterThan(1)));
      for (final _Call ping in rig.gateway.pings) {
        expect((ping.body!['lat'], ping.body!['lng']), (_Source.lat, _Source.lng));
      }
      await rig.dispose(tester);
    });

    testWidgets('with no reading from the phone, the platform\'s stored point is never drawn',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true, storedAt: (lat: 51.5074, lng: -0.1278))
        ..source.noFix = true;
      await rig.pump(tester);

      expect(find.byType(FlutterMap), findsNothing);
      expect(find.text(rig.t(tester).riderMapNoFixYet), findsOneWidget);
      await rig.dispose(tester);
    });
  });

  group('foreground only', () {
    testWidgets('the background stops every reading and ping; coming back resumes without a prompt',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true, orders: <Map<String, dynamic>>[
        _order('o-carried', 'PICKED_UP'),
      ]);
      await rig.pump(tester);
      expect(rig.gateway.pings, isNotEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final int reads = rig.source.reads;
      final int pings = rig.gateway.pings.length;
      await tester.pump(const Duration(minutes: 3));

      expect(rig.source.reads, reads, reason: 'No GPS reading with the app in the background.');
      expect(rig.gateway.pings.length, pings, reason: 'No ping with the app in the background.');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await rig.settle(tester);

      expect(rig.gateway.pings.length, greaterThan(pings), reason: 'Sharing resumes on return.');
      expect(rig.source.asks.last, isFalse,
          reason: 'Back from the settings page is a check, not a second prompt.');
      await rig.dispose(tester);
    });

    testWidgets('the permission prompt itself (inactive) does not stop sharing',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true, orders: <Map<String, dynamic>>[
        _order('o-carried', 'PICKED_UP'),
      ]);
      await rig.pump(tester);
      final int reads = rig.source.reads;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 21));

      expect(rig.source.reads, greaterThan(reads));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await rig.dispose(tester);
    });
  });

  group('at 320 dp and a large font, in English and Arabic', () {
    for (final Locale locale in const <Locale>[Locale('en'), Locale('ar')]) {
      testWidgets('the banner fits in every state it can show (${locale.languageCode})',
          (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        for (final RiderLocationStatus status in RiderLocationStatus.values) {
          await tester.pumpWidget(_narrow(locale, ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              RiderLocationBanner(status: status, onAllow: () {}, onOpenSettings: () {}),
            ],
          )));
          expect(tester.takeException(), isNull, reason: '$status overflowed');
          expect(find.byType(Text).evaluate().isNotEmpty, status.hidesRider,
              reason: 'Drawn exactly for the states that hide the rider: $status');
        }
      });

      testWidgets('the sheet before the prompt fits, and reads in its language '
          '(${locale.languageCode})', (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_narrow(locale, const RiderLocationDisclosure()));

        expect(tester.takeException(), isNull);
        final DeliveryStrings t =
            DeliveryStrings.of(tester.element(find.byType(RiderLocationDisclosure)));
        await tester.scrollUntilVisible(find.text(t.riderGpsDisclosureNotNow), 100);
        expect(find.text(t.riderGpsDisclosureNotNow), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (locale.languageCode == 'ar') {
          expect(Directionality.of(tester.element(find.text(t.riderGpsDisclosureTitle))),
              TextDirection.rtl);
        }
      });

      // The two board tabs, without orders in hand. The active-task card and one row further down
      // Settings have narrow-screen overflows of their own that predate this work and are tracked
      // separately; the banner itself is pinned in every state by the test above, and the same
      // ListView padding is all Settings adds around it.
      testWidgets('the banner fits on the board tabs (${locale.languageCode})',
          (WidgetTester tester) async {
        final _Rig rig = _Rig(onDuty: true)..source.accessResult = RiderLocationAccess.servicesOff;
        await rig.pump(tester, size: const Size(320, 568), textScale: 1.3, locale: locale);
        final DeliveryStrings t = rig.t(tester);

        for (final String tab in <String>[t.riderTabAvailable, t.riderTabActive]) {
          await tester.tap(find.text(tab).last);
          await tester.pump();
          expect(find.text(t.riderGpsOffTitle), findsOneWidget, reason: 'On $tab');
          expect(tester.takeException(), isNull, reason: 'Overflow on $tab');
        }
        if (locale.languageCode == 'ar') {
          expect(
              Directionality.of(tester.element(find.text(t.riderGpsOffTitle))), TextDirection.rtl);
        }
        await rig.dispose(tester);
      });
    }
  });

  group('no simulated position in a build a rider installs', () {
    test('the simulator is built in one place, behind the compile-time debug guard', () {
      final List<String> constructions = <String>[];
      for (final File file in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final List<String> lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          if (lines[i].contains('SimulatedRiderLocationSource(') &&
              !lines[i].trimLeft().startsWith('///') &&
              !lines[i].contains('class SimulatedRiderLocationSource') &&
              !file.path.endsWith('rider_location_simulator.dart')) {
            constructions.add('${file.path}:${i + 1}');
            // The line above is the guard. kDebugMode is a compile-time false in profile and
            // release, so the branch — and the simulator — is compiled out of them.
            expect(lines[i - 1].trim(), 'if (kDebugMode && riderGpsSimulationRequested) {',
                reason: '${file.path}:${i + 1}');
          }
        }
      }
      expect(constructions, hasLength(1), reason: constructions.join(', '));
      expect(constructions.single, contains('main.dart'));
    });

    test('and refuses to run at all outside a debug build', () {
      expect(() => SimulatedRiderLocationSource.ensureDebugBuild(false),
          throwsA(isA<UnsupportedError>()));
      expect(() => SimulatedRiderLocationSource.ensureDebugBuild(true), returnsNormally);
    });

    test('is off unless a build asks for it', () {
      expect(riderGpsSimulationRequested, isFalse);
    });

    test('starts where it is told or nowhere, never at an invented city', () async {
      expect(SimulatedRiderLocationSource.parseOrigin('33.8938, 35.5018'),
          (lat: 33.8938, lng: 35.5018));
      expect(SimulatedRiderLocationSource.parseOrigin(''), isNull);
      expect(SimulatedRiderLocationSource.parseOrigin('95,35'), isNull);

      final SimulatedRiderLocationSource noShop =
          SimulatedRiderLocationSource(shopPin: () async => null);
      expect(await noShop.current(), isNull);

      final SimulatedRiderLocationSource atShop =
          SimulatedRiderLocationSource(shopPin: () async => (lat: 33.8938, lng: 35.5018));
      final RiderFix? first = await atShop.current();
      expect(first, isNotNull);
      expect((first!.latitude - 33.8938).abs(), lessThan(0.001));
      expect((first.longitude - 35.5018).abs(), lessThan(0.001));
    });
  });
}

// ---------------------------------------------------------------------------------------- rig

const String _hamra = 'Hamra Street, Beirut';
const String _mar = 'Mar Mikhael, Beirut';

/// The rider's mini-map and its marker layer, on the first frame the map is drawn.
Future<(FlutterMap, MarkerLayer)> _firstMap(WidgetTester tester) async {
  for (int i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 5));
    final Finder map = find.byType(FlutterMap);
    if (map.evaluate().isNotEmpty) {
      return (tester.widget<FlutterMap>(map), tester.widget<MarkerLayer>(find.byType(MarkerLayer)));
    }
  }
  fail('The mini-map was never drawn');
}

Widget _narrow(Locale locale, Widget child) => MaterialApp(
      theme: DeliveryTheme.light(),
      locale: locale,
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      builder: (BuildContext context, Widget? inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: inner!,
      ),
      home: Scaffold(body: child),
    );

Map<String, dynamic> _order(String id, String status,
        {String address = _hamra, String store = 'Abu Hassan'}) =>
    <String, dynamic>{
      'id': id,
      'customerId': 'customer-$id',
      'merchantId': 'merchant-1',
      'riderId': 'rider-sub',
      'status': status,
      'totalAmount': 12.5,
      'storeName': store,
      'deliveryAddress': address,
      'placedAt': '2026-09-19T09:30:00Z',
    };

class _Call {
  _Call(this.method, this.path, this.body);

  final String method;
  final String path;
  final Map<String, dynamic>? body;
}

class _Gateway implements HttpClientAdapter {
  _Gateway({required this.onDuty, required this.orders, this.storedAt});

  final bool onDuty;
  final List<Map<String, dynamic>> orders;

  /// Where the platform last stored the rider, as presence answers it. Null: nowhere yet.
  final ({double lat, double lng})? storedAt;

  /// When set, every ping is refused with a 422 carrying this reason.
  String? refuseWith;

  final List<_Call> log = <_Call>[];

  List<String> get calls => log.map((_Call c) => '${c.method} ${c.path}').toList();

  List<_Call> get pings =>
      log.where((_Call c) => c.method == 'POST' && c.path.endsWith('/ping')).toList();

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    final Object? data = options.data;
    log.add(_Call(options.method, options.path,
        data is Map ? Map<String, dynamic>.from(data) : null));

    final String path = options.path;
    Object body = <String, dynamic>{};
    int status = 200;
    if (path == '/api/orders/assigned') {
      body = <String, dynamic>{'content': orders, 'totalElements': orders.length};
    } else if (path == '/api/orders/available') {
      body = <String, dynamic>{'content': <dynamic>[], 'totalElements': 0};
    } else if (path == '/api/tracking/riders/me/duty' && options.method == 'GET') {
      final ({double lat, double lng})? stored = storedAt;
      body = <String, dynamic>{
        'riderId': 'rider-sub',
        'dutyState': onDuty ? 'ON_DUTY' : 'OFF_DUTY',
        'state': onDuty ? 'STALE' : 'OFF_DUTY',
        if (stored != null) ...<String, dynamic>{
          'lat': stored.lat,
          'lng': stored.lng,
          'lastSeenAt': '2026-09-19T09:00:00Z',
        },
      };
    } else if (path.endsWith('/ping')) {
      final String? reason = refuseWith;
      if (reason != null) {
        status = 422;
        body = <String, dynamic>{'title': 'Location not recorded', 'reason': reason};
      } else {
        status = 202;
      }
    } else if (path == '/api/riders/me/rating') {
      status = 404;
    }
    return ResponseBody.fromString(jsonEncode(body), status, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// A phone in downtown Beirut. Stamped with the wall clock: the reporter never judges a fix's age
/// itself (the server does), so nothing here depends on the test's fake time.
class _Source extends RiderLocationSource {
  static const double lat = 33.8938;
  static const double lng = 35.5018;

  RiderLocationAccess accessResult = RiderLocationAccess.granted;

  /// What the system prompt leaves the permission at, when one is shown: the rider's answer.
  RiderLocationAccess afterPrompt = RiderLocationAccess.granted;

  bool noFix = false;
  final List<bool> asks = <bool>[];
  int reads = 0;
  int appSettingsOpened = 0;
  int locationSettingsOpened = 0;

  @override
  Future<RiderLocationAccess> access({required bool ask}) async {
    asks.add(ask);
    // Only a refusal that can still be asked about shows the prompt — as on a phone.
    if (ask && accessResult == RiderLocationAccess.denied) accessResult = afterPrompt;
    return accessResult;
  }

  @override
  Future<RiderFix?> current() async {
    reads++;
    if (noFix) return null;
    return RiderFix(latitude: lat, longitude: lng, accuracyM: 6, takenAt: DateTime.now().toUtc());
  }

  @override
  Future<void> openAppSettings() async => appSettingsOpened++;

  @override
  Future<void> openLocationSettings() async => locationSettingsOpened++;
}

class _Rig {
  _Rig({
    required bool onDuty,
    List<Map<String, dynamic>> orders = const <Map<String, dynamic>>[],
    ({double lat, double lng})? storedAt,
  }) : gateway = _Gateway(onDuty: onDuty, orders: orders, storedAt: storedAt);

  final _Gateway gateway;
  final _Source source = _Source();

  DeliveryStrings t(WidgetTester tester) =>
      DeliveryStrings.of(tester.element(find.byType(RiderHomeScreen)));

  Future<void> pump(WidgetTester tester,
      {Size size = const Size(400, 900),
      double textScale = 1.0,
      Locale? locale,
      bool settleAfter = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))..httpClientAdapter = gateway;
    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      locale: locale,
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: RiderHomeScreen(
        api: OrderApi(dio),
        butlerApi: ButlerApi(dio),
        trackingApi: TrackingApi(dio),
        locationSource: source,
        session: AuthSession(
          accessToken: 'token',
          refreshToken: null,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          roles: const <DeliveryRole>{DeliveryRole.delivery},
          subject: 'rider-sub',
        ),
        locale: LocaleController(read: () async => locale?.languageCode ?? 'en',
            write: (String _) async {}),
        onSignOut: () async {},
      ),
    ));
    if (settleAfter) await settle(tester);
  }

  /// Lets the board and presence answer and the reporter ask, read and send: Dio's pipeline takes
  /// several turns of the event loop, all well inside the reporter's first ten-second tick. A sheet
  /// sliding up or down takes a few of them too.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }
}
