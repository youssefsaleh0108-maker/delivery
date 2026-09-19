import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/rider_home_screen.dart';
import 'package:mobile_app/src/rider_location_banner.dart';
import 'package:mobile_app/src/rider_location_simulator.dart';

/// The rider app reports where the rider really is — and says so when it cannot.
///
/// The screen used to random-walk a rider from London and ping only orders already picked up, so
/// every live marker and ETA in dev and qa was fiction. These pin what replaced it: the phone's own
/// fix on every claimed READY and PICKED_UP order, nothing at all without the permission or with
/// the app in the background, an honest banner with the one way out for each refusal, and no
/// simulator anywhere a release build can reach.
void main() {
  group('what is sent', () {
    testWidgets('pings every claimed READY and PICKED_UP order with the phone\'s real fix',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true, orders: <Map<String, dynamic>>[
        _order('o-ready', 'READY'),
        _order('o-carried', 'PICKED_UP'),
      ]);
      await rig.pump(tester);

      final List<_Call> pings = rig.gateway.pings;
      expect(pings.map((_Call c) => c.path), <String>[
        '/api/tracking/orders/o-ready/ping',
        '/api/tracking/orders/o-carried/ping',
      ]);
      final Map<String, dynamic> body = pings.first.body!;
      expect(body['lat'], _Source.lat);
      expect(body['lng'], _Source.lng);
      expect(body['accuracyM'], 6);
      expect(body['recordedAt'], rig.source.lastTakenAt!.toIso8601String());
      expect(rig.gateway.calls, isNot(contains('POST /api/tracking/riders/me/ping')),
          reason: 'An order ping is presence already; a second, order-less one is the same write.');
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
      expect(find.byType(SoftNote), findsNothing);
      expect(find.text(rig.t(tester).riderGpsOffTitle), findsNothing);
      await rig.dispose(tester);
    });

    testWidgets('while sharing with orders in hand, the Active tab says it is only while open',
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

  group('when the rider cannot be seen', () {
    testWidgets('denied: nothing is sent, and "Allow location" asks again',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true, orders: <Map<String, dynamic>>[
        _order('o-carried', 'PICKED_UP'),
      ])
        ..source.accessResult = RiderLocationAccess.denied;
      await rig.pump(tester);
      final DeliveryStrings t = rig.t(tester);

      expect(rig.gateway.pings, isEmpty);
      expect(rig.source.reads, 0, reason: 'No reading without the permission.');
      expect(find.text(t.riderGpsOffTitle), findsOneWidget);
      expect(find.text(t.riderGpsDeniedBody), findsOneWidget);

      rig.source.accessResult = RiderLocationAccess.granted;
      await tester.tap(find.text(t.riderGpsAllow));
      await rig.settle(tester);

      expect(rig.source.asks.last, isTrue);
      expect(rig.gateway.pings, isNotEmpty, reason: 'Allowed: the first fix goes at once.');
      expect(find.text(t.riderGpsOffTitle), findsNothing);
      await rig.dispose(tester);
    });

    testWidgets('denied for good: the banner opens this app\'s settings page',
        (WidgetTester tester) async {
      final _Rig rig = _Rig(onDuty: true)..source.accessResult = RiderLocationAccess.deniedForever;
      await rig.pump(tester);
      final DeliveryStrings t = rig.t(tester);

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
          await tester.pumpWidget(MaterialApp(
            theme: DeliveryTheme.light(),
            locale: locale,
            localizationsDelegates: DeliveryStrings.localizationsDelegates,
            supportedLocales: DeliveryStrings.supportedLocales,
            builder: (BuildContext context, Widget? child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  RiderLocationBanner(status: status, onAllow: () {}, onOpenSettings: () {}),
                ],
              ),
            ),
          ));
          expect(tester.takeException(), isNull, reason: '$status overflowed');
          expect(find.byType(Text).evaluate().isNotEmpty, status.hidesRider,
              reason: 'Drawn exactly for the states that hide the rider: $status');
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
    test('the London walk is gone from the app', () {
      final List<File> sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))
          .toList();
      expect(sources, isNotEmpty);
      for (final File file in sources) {
        final String text = file.readAsStringSync();
        expect(text.contains('51.5074'), isFalse, reason: file.path);
        expect(text.contains('-0.1278'), isFalse, reason: file.path);
      }
      expect(File('lib/src/rider_home_screen.dart').readAsStringSync().contains('Random'), isFalse,
          reason: 'Nothing on the rider screen invents a position any more.');
    });

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

Map<String, dynamic> _order(String id, String status) => <String, dynamic>{
      'id': id,
      'customerId': 'customer-$id',
      'merchantId': 'merchant-1',
      'riderId': 'rider-sub',
      'status': status,
      'totalAmount': 12.5,
      'storeName': 'Abu Hassan',
      'deliveryAddress': 'Hamra Street, Beirut',
      'placedAt': '2026-09-19T09:30:00Z',
    };

class _Call {
  _Call(this.method, this.path, this.body);

  final String method;
  final String path;
  final Map<String, dynamic>? body;
}

class _Gateway implements HttpClientAdapter {
  _Gateway({required this.onDuty, required this.orders});

  final bool onDuty;
  final List<Map<String, dynamic>> orders;
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
      // No lat/lng: the mini-map stays on its placeholder, so no tile is ever fetched.
      body = <String, dynamic>{
        'riderId': 'rider-sub',
        'dutyState': onDuty ? 'ON_DUTY' : 'OFF_DUTY',
        'state': onDuty ? 'STALE' : 'OFF_DUTY',
      };
    } else if (path.endsWith('/ping')) {
      status = 202;
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
  bool noFix = false;
  final List<bool> asks = <bool>[];
  int reads = 0;
  int appSettingsOpened = 0;
  int locationSettingsOpened = 0;
  DateTime? lastTakenAt;

  @override
  Future<RiderLocationAccess> access({required bool ask}) async {
    asks.add(ask);
    return accessResult;
  }

  @override
  Future<RiderFix?> current() async {
    reads++;
    if (noFix) return null;
    final DateTime now = DateTime.now().toUtc();
    lastTakenAt = now;
    return RiderFix(latitude: lat, longitude: lng, accuracyM: 6, takenAt: now);
  }

  @override
  Future<void> openAppSettings() async => appSettingsOpened++;

  @override
  Future<void> openLocationSettings() async => locationSettingsOpened++;
}

class _Rig {
  _Rig({required bool onDuty, List<Map<String, dynamic>> orders = const <Map<String, dynamic>>[]})
      : gateway = _Gateway(onDuty: onDuty, orders: orders);

  final _Gateway gateway;
  final _Source source = _Source();

  DeliveryStrings t(WidgetTester tester) =>
      DeliveryStrings.of(tester.element(find.byType(RiderHomeScreen)));

  Future<void> pump(WidgetTester tester,
      {Size size = const Size(400, 900), double textScale = 1.0, Locale? locale}) async {
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
    await settle(tester);
  }

  /// Lets the board and presence answer and the reporter ask, read and send: Dio's pipeline takes
  /// several turns of the event loop, all well inside the reporter's first ten-second tick.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }
}
