import 'dart:convert';
import 'dart:io';

import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// PT-2 (portal deep test, 2026-09-19): the back-office Finance screen names a settlement row by
/// `SettlementLeg.label` and `SettlementStatus.label` (reconciliation_screen.dart, the ledger table
/// and the drawer title). Both enums fall back to `unknown` for a wire value they do not list, and
/// the accounting service sends values they do not list.
///
/// The lists below are `AccountingTransaction.Leg` and `AccountingTransaction.Status` in
/// services/accounting-service, as of decd784. When the service adds a value, add it here too: the
/// test is the reminder that the screen has to learn it.
///
/// These tests FAIL until the Dart enums learn the missing values. That is deliberate.
void main() {
  const List<String> serverLegs = <String>[
    'CUSTOMER_DEBIT',
    'CASH_COLLECTED',
    'MERCHANT_CREDIT',
    'GIFT_WRAP_CREDIT',
    'RIDER_CREDIT',
    'PROVIDER_CREDIT',
    'PLATFORM_COMMISSION',
    'PLATFORM_SUBSIDY',
    // Added with the reconciliation fixes: what the platform absorbs on an order closed after
    // pickup (RECON-10), and money it has paid out (RECON-11).
    'PLATFORM_LOSS',
    'CASH_REMITTANCE',
    'PAYOUT',
    'CUSTOMER_REFUND',
  ];
  const List<String> serverStatuses = <String>[
    'PENDING',
    'POSTED',
    'SETTLED_IN_CASH',
    'FAILED',
    'COMPENSATED',
    'ABANDONED',
  ];

  test('PT-2: every settlement leg the accounting service writes has a name on the Finance screen',
      () {
    final List<String> unnamed = <String>[
      for (final String wire in serverLegs)
        if (SettlementLeg.fromWire(wire) == SettlementLeg.unknown) wire,
    ];
    expect(unnamed, isEmpty,
        reason: 'these legs are listed as "Unknown" in the back-office ledger: $unnamed');
  });

  test('PT-2: every settlement status the accounting service writes has a name and a tile', () {
    final List<String> unnamed = <String>[
      for (final String wire in serverStatuses)
        if (SettlementStatus.fromWire(wire) == SettlementStatus.unknown) wire,
    ];
    expect(unnamed, isEmpty,
        reason: 'these statuses read as "Unknown", and cannot be filtered on: $unnamed');
  });

  test('PT-2: the rows dev is listing right now as unsettled are named', () async {
    // The live answer to GET /api/accounting/unsettled, sanitised (see the fixture's _about).
    final Map<String, dynamic> fixtures = jsonDecode(
            File('test/fixtures/live_dev_2026_09_19.json').readAsStringSync())
        as Map<String, dynamic>;
    final List<dynamic> rows = (fixtures['backoffice GET /api/accounting/unsettled?limit=20']
        as Map<String, dynamic>)['body'] as List<dynamic>;
    expect(rows, isNotEmpty);
    final List<AccountingTransaction> decoded = <AccountingTransaction>[
      for (final dynamic r in rows) AccountingTransaction.fromJson(r as Map<String, dynamic>),
    ];
    expect(
      decoded.where((AccountingTransaction t) => t.leg == SettlementLeg.unknown).length,
      0,
      reason: 'live legs: ${rows.map((dynamic r) => (r as Map<String, dynamic>)['leg']).toSet()}',
    );
  });
}
