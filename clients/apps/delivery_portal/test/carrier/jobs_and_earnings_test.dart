import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:delivery_portal/src/carrier/earnings_screen.dart';
import 'package:delivery_portal/src/carrier/jobs_screen.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two carrier pages the 2026-08 Figma set has no frame for.
///
/// Both were their own Scaffold with a crimson AppBar, which inside the new console rail would draw
/// a second header beside the rail that is already the chrome. They are rebuilt out of the console's
/// own components instead. These tests are the contract that survived that: the money on a job is
/// the carrier's fee and not the customer's total, earned and expected stay apart, and the "you
/// belong to no company yet" state still reads as a gap rather than as a crash.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body, {this.status = 200});

  final Object body;
  final int status;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString(jsonEncode(body), status, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

OrderApi _api(Object body, {int status = 200}) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway'))
    ..httpClientAdapter = _StubAdapter(body, status: status);
  return OrderApi(dio);
}

Map<String, dynamic> _job({
  required String id,
  String status = 'DELIVERED',
  bool waived = false,
}) =>
    <String, dynamic>{
      'id': id,
      'customerId': 'c1',
      'merchantId': 'm1',
      'riderId': 'rider-aaaaaaaa',
      'status': status,
      'totalAmount': 87.50,
      'deliveryAddress': '12 Bliss Street',
      'deliveryFee': 5.25,
      'carrierFeeWaived': waived,
      'storeName': 'Corner Shop',
      'contactPhone': '+100',
      'notes': null,
      'items': <dynamic>[],
      'availableActions': <dynamic>[],
      'placedAt': '2026-08-16T09:00:00Z',
      'deliveredAt': '2026-08-16T10:00:00Z',
      'cancelReason': null,
    };

Map<String, dynamic> _page(List<Map<String, dynamic>> jobs) => <String, dynamic>{
      'content': jobs,
      'page': 0,
      'size': 50,
      'totalElements': jobs.length,
      'totalPages': 1,
    };

Map<String, dynamic> _earnings({double savedByOffers = 0}) => <String, dynamic>{
      'delivered': 42,
      'active': 3,
      'earned': 460.0,
      'expected': 88.0,
      'savedByOffers': savedByOffers,
      'cutPercentage': 10.0,
      'windowDays': 30,
    };

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('en'),
      theme: DeliveryTheme.light(),
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        DeliveryStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

Future<void> pump(WidgetTester tester, Widget screen, {double width = 1180}) async {
  tester.view.physicalSize = Size(width, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_wrap(screen));
  await tester.pumpAndSettle();
}

void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));

  group('the job board', () {
    testWidgets('is a console table, not a page with its own app bar',
        (WidgetTester tester) async {
      await pump(tester, JobsScreen(api: _api(_page(<Map<String, dynamic>>[
        _job(id: 'aaaaaaaa11'),
      ]))));

      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(ConsoleTable), findsOneWidget);
      expect(find.text('#aaaaaaaa'), findsOneWidget);
    });

    testWidgets('shows the carrier fee, never the order total', (WidgetTester tester) async {
      // A carrier reading 87.50 would be reading the customer's number. Theirs is 5.25.
      await pump(tester, JobsScreen(api: _api(_page(<Map<String, dynamic>>[
        _job(id: 'aaaaaaaa11'),
      ]))));

      expect(find.text('5.25'), findsOneWidget);
      expect(find.text('87.50'), findsNothing);
    });

    testWidgets('a waived platform cut is visible to the company receiving it',
        (WidgetTester tester) async {
      await pump(tester, JobsScreen(api: _api(_page(<Map<String, dynamic>>[
        _job(id: 'aaaaaaaa11', waived: true),
      ]))));

      expect(find.text(en.savedByOffers), findsOneWidget);
    });

    testWidgets('filters down to one state without losing the count',
        (WidgetTester tester) async {
      await pump(tester, JobsScreen(api: _api(_page(<Map<String, dynamic>>[
        _job(id: 'aaaaaaaa11'),
        _job(id: 'bbbbbbbb22', status: 'CANCELLED'),
      ]))));

      expect(find.text('Showing 2 of 2 recent jobs.'), findsOneWidget);
      // Scoped to the pill row: "Cancelled" is also the status label on the row it filters to.
      await tester.tap(find.descendant(
        of: find.byType(ConsoleFilterPills),
        matching: find.text('Cancelled'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('#bbbbbbbb'), findsOneWidget);
      expect(find.text('#aaaaaaaa'), findsNothing);
      expect(find.text('Showing 1 of 2 recent jobs.'), findsOneWidget);
    });

    testWidgets('belonging to no company reads as a gap, not a crash',
        (WidgetTester tester) async {
      await pump(tester,
          JobsScreen(api: _api(<String, dynamic>{'message': 'no company'}, status: 404)));

      expect(find.text(en.noCompanyYet), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
    });
  });

  group('earnings', () {
    testWidgets('keeps earned and expected apart', (WidgetTester tester) async {
      // Different promises: one is money owed for finished work, the other only exists if every
      // rider out there completes. A single headline figure would flatter the number.
      await pump(tester, EarningsScreen(api: _api(_earnings())));

      expect(find.text('460.00'), findsOneWidget);
      expect(find.text('88.00'), findsOneWidget);
      expect(find.text(en.expectedNote), findsOneWidget);
      expect(find.byType(ConsoleKpiCard), findsNWidgets(4));
    });

    testWidgets('says nothing about offers when none was given', (WidgetTester tester) async {
      // A zero here would be a line about a benefit the company never received, which reads as a
      // benefit being withheld.
      await pump(tester, EarningsScreen(api: _api(_earnings())));

      expect(find.text(en.savedByOffers), findsNothing);
    });

    testWidgets('and says so when one was', (WidgetTester tester) async {
      await pump(tester, EarningsScreen(api: _api(_earnings(savedByOffers: 12.5))));

      expect(find.text(en.savedByOffers), findsOneWidget);
      expect(find.text('12.50'), findsOneWidget);
    });
  });

  for (final double width in <double>[1180, 1020, 764]) {
    testWidgets('both lay out at a ${width.toInt()}px content column',
        (WidgetTester tester) async {
      await pump(
        tester,
        JobsScreen(api: _api(_page(<Map<String, dynamic>>[_job(id: 'aaaaaaaa11')]))),
        width: width,
      );
      expect(tester.takeException(), isNull);

      await pump(tester, EarningsScreen(api: _api(_earnings(savedByOffers: 12.5))),
          width: width);
      expect(tester.takeException(), isNull);
    });
  }
}
