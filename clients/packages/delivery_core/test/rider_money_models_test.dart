import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CashOut states', () {
    Map<String, dynamic> cashOut(String status) => <String, dynamic>{
          'id': 'co-1',
          'riderRef': 'r-1',
          'amount': 42.5,
          'currency': 'USD',
          'status': status,
          'payoutNote': null,
          'requestedAt': '2026-08-27T09:00:00Z',
          'decidedBy': null,
          'decidedAt': null,
          'decisionNote': null,
          'paymentRef': null,
          'paidVia': null,
        };

    test('REQUESTED is open and holds money', () {
      final CashOut parsed = CashOut.fromJson(cashOut('REQUESTED'));
      expect(parsed.status, CashOutStatus.requested);
      expect(parsed.status.isOpen, isTrue);
      expect(parsed.decidedAt, isNull);
    });

    test('PAID and REJECTED are terminal', () {
      expect(CashOut.fromJson(cashOut('PAID')).status, CashOutStatus.paid);
      expect(CashOut.fromJson(cashOut('REJECTED')).status, CashOutStatus.rejected);
      expect(CashOutStatus.paid.isOpen, isFalse);
      expect(CashOutStatus.rejected.isOpen, isFalse);
    });

    // A status added server-side must never read as paid — money that never moved must not be
    // shown as having moved.
    test('an unknown status is unknown, not paid', () {
      final CashOut parsed = CashOut.fromJson(cashOut('ESCALATED'));
      expect(parsed.status, CashOutStatus.unknown);
      expect(parsed.status.isOpen, isFalse);
    });
  });

  group('RiderBalance', () {
    test('a negative available is preserved, not clamped', () {
      final RiderBalance balance = RiderBalance.fromJson(<String, dynamic>{
        'currency': 'USD',
        'balance': 10.0,
        'available': -5.0,
        'cashFloatHeld': 15.0,
        'minimumCashOut': 5.0,
        'payoutIsAutomated': false,
        'openCashOut': null,
      });

      expect(balance.available, -5.0);
      expect(balance.openCashOut, isNull);
      expect(balance.payoutIsAutomated, isFalse);
    });

    test('an open cash-out arrives nested and typed', () {
      final RiderBalance balance = RiderBalance.fromJson(<String, dynamic>{
        'currency': 'USD',
        'balance': 100.0,
        'available': 60.0,
        'cashFloatHeld': 40.0,
        'minimumCashOut': 5.0,
        'payoutIsAutomated': false,
        'openCashOut': <String, dynamic>{
          'id': 'co-2',
          'amount': 60.0,
          'currency': 'USD',
          'status': 'REQUESTED',
        },
      });

      expect(balance.openCashOut, isNotNull);
      expect(balance.openCashOut!.status, CashOutStatus.requested);
    });
  });

  group('RiderEarnings', () {
    test('parses the whole statement in one shape', () {
      final RiderEarnings earnings = RiderEarnings.fromJson(<String, dynamic>{
        'currency': 'USD',
        'zone': 'Asia/Beirut',
        'today': <String, dynamic>{'earnings': 12.0, 'tips': 2.0, 'total': 14.0, 'jobs': 3},
        'thisWeek': <String, dynamic>{'earnings': 80.0, 'tips': 6.5, 'total': 86.5, 'jobs': 19},
        'series': <dynamic>[
          <String, dynamic>{'day': '2026-08-26', 'earnings': 30.0, 'tips': 1.0, 'total': 31.0, 'jobs': 7},
          <String, dynamic>{'day': '2026-08-27', 'earnings': 12.0, 'tips': 2.0, 'total': 14.0, 'jobs': 3},
        ],
        'balance': <String, dynamic>{
          'currency': 'USD',
          'balance': 86.5,
          'available': 70.0,
          'cashFloatHeld': 16.5,
          'minimumCashOut': 5.0,
          'payoutIsAutomated': false,
          'openCashOut': null,
        },
      });

      expect(earnings.zone, 'Asia/Beirut');
      expect(earnings.today.total, 14.0);
      expect(earnings.series, hasLength(2));
      expect(earnings.series.first.day.day, 26);
      expect(earnings.balance.cashFloatHeld, 16.5);
    });
  });

  group('RiderJob payer', () {
    test('a carrier-payable line is never read as platform money', () {
      final RiderJob job = RiderJob.fromJson(<String, dynamic>{
        'orderId': 'o-9',
        'earned': 4.0,
        'tip': 0,
        'reimbursement': 0,
        'fleet': 'CARRIER',
        'payableBy': 'CARRIER',
        'deliveredAt': '2026-08-27T09:30:00Z',
      });
      expect(job.payableBy, EarningsPayer.carrier);
    });

    test('an unknown payer degrades to unknown, never to platform', () {
      final RiderJob job = RiderJob.fromJson(<String, dynamic>{
        'orderId': 'o-10',
        'earned': 4.0,
        'tip': 0,
        'reimbursement': 0,
        'payableBy': 'INSURER',
      });
      expect(job.payableBy, EarningsPayer.unknown);
    });
  });

  group('PromoQuote', () {
    test('a valid quote carries the canonical code and a typed kind', () {
      final PromoQuote quote = PromoQuote.fromJson(<String, dynamic>{
        'valid': true,
        'reason': 'OK',
        'message': 'The code was applied',
        'code': 'WELCOME10',
        'kind': 'PERCENT_OFF',
        'discount': 1.5,
      });

      expect(quote.valid, isTrue);
      expect(quote.reason, PromoQuoteReason.ok);
      expect(quote.kind, PromoKind.percentOff);
      expect(quote.discount, 1.5);
    });

    test('an invalid quote has a reason and nothing to render as money', () {
      final PromoQuote quote = PromoQuote.fromJson(<String, dynamic>{
        'valid': false,
        'reason': 'BELOW_MINIMUM',
        'message': 'Your basket is below the minimum for that code',
        'code': 'WELCOME10',
        'kind': null,
        'discount': 0,
      });

      expect(quote.valid, isFalse);
      expect(quote.reason, PromoQuoteReason.belowMinimum);
      expect(quote.kind, isNull);
      expect(quote.discount, 0);
    });

    test('a reason this build does not know degrades to unknown, not to applied', () {
      final PromoQuote quote = PromoQuote.fromJson(<String, dynamic>{
        'valid': false,
        'reason': 'SANCTIONED_REGION',
        'discount': 0,
      });
      expect(quote.reason, PromoQuoteReason.unknown);
      expect(quote.valid, isFalse);
    });
  });
}
