import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrderEta', () {
    test('an available estimate carries its numbers and no reason', () {
      final OrderEta eta = OrderEta.fromJson(<String, dynamic>{
        'orderId': 'o-1',
        'available': true,
        'reason': null,
        'leg': 'TO_DROPOFF',
        'remainingMetres': 1240.5,
        'remainingSeconds': 300,
        'estimatedArrival': '2026-08-27T10:15:00Z',
        'provider': 'HAVERSINE_DEV',
        'fixRecordedAt': '2026-08-27T10:10:00Z',
        'computedAt': '2026-08-27T10:10:01Z',
      });

      expect(eta.available, isTrue);
      expect(eta.reason, isNull);
      expect(eta.leg, EtaLeg.toDropoff);
      expect(eta.remainingMetres, 1240.5);
      expect(eta.remainingSeconds, 300);
      expect(eta.estimatedArrival, isNotNull);
      expect(eta.isStraightLine, isTrue);
    });

    test('an unavailable estimate carries a reason and null numbers', () {
      final OrderEta eta = OrderEta.fromJson(<String, dynamic>{
        'orderId': 'o-2',
        'available': false,
        'reason': 'NO_FIX',
        'leg': null,
        'remainingMetres': null,
        'remainingSeconds': null,
        'estimatedArrival': null,
        'provider': 'HAVERSINE_DEV',
        'fixRecordedAt': null,
        'computedAt': '2026-08-27T10:10:01Z',
      });

      expect(eta.available, isFalse);
      expect(eta.reason, EtaUnavailableReason.noFix);
      expect(eta.remainingMetres, isNull);
      expect(eta.remainingSeconds, isNull);
      expect(eta.estimatedArrival, isNull);
    });

    test('every server reason maps to its own value', () {
      expect(EtaUnavailableReason.fromWire('NO_FIX'), EtaUnavailableReason.noFix);
      expect(EtaUnavailableReason.fromWire('STALE_FIX'), EtaUnavailableReason.staleFix);
      expect(EtaUnavailableReason.fromWire('NO_DESTINATION'), EtaUnavailableReason.noDestination);
      expect(EtaUnavailableReason.fromWire('PROVIDER_UNAVAILABLE'),
          EtaUnavailableReason.providerUnavailable);
      expect(EtaUnavailableReason.fromWire('ORDER_COMPLETE'), EtaUnavailableReason.orderComplete);
    });

    // Regression guard for the honesty rule: a reason added server-side must degrade to
    // "unavailable", never crash the screen and never fabricate a number.
    test('a reason this build does not know reads as unknown, not a crash', () {
      final OrderEta eta = OrderEta.fromJson(<String, dynamic>{
        'orderId': 'o-3',
        'available': false,
        'reason': 'RIDER_ON_THE_MOON',
        'provider': 'MAPBOX',
      });

      expect(eta.reason, EtaUnavailableReason.unknown);
      expect(eta.available, isFalse);
      expect(eta.isStraightLine, isFalse);
    });

    // The reason field is only meaningful when unavailable; a server that sent both must not
    // produce a screen that renders a sentence beside a live countdown.
    test('a reason sent beside available=true is discarded', () {
      final OrderEta eta = OrderEta.fromJson(<String, dynamic>{
        'orderId': 'o-4',
        'available': true,
        'reason': 'NO_FIX',
        'provider': 'MAPBOX',
      });

      expect(eta.reason, isNull);
    });
  });

  group('RiderPresence', () {
    test('a stale rider is stale regardless of what they declared', () {
      final RiderPresence presence = RiderPresence.fromJson(<String, dynamic>{
        'riderId': 'r-1',
        'carrierId': null,
        'dutyState': 'ON_DUTY',
        'state': 'STALE',
        'dutyChangedAt': '2026-08-27T08:00:00Z',
        'lastSeenAt': '2026-08-27T08:05:00Z',
        'lat': 33.89,
        'lng': 35.5,
        'accuracyM': 12.0,
      });

      expect(presence.dutyState, DutyState.onDuty);
      expect(presence.state, PresenceState.stale);
      expect(presence.hasFix, isTrue);
    });

    test('a rider who never pinged has no fix rather than a fix at (0, 0)', () {
      final RiderPresence presence = RiderPresence.fromJson(<String, dynamic>{
        'riderId': 'r-2',
        'dutyState': 'OFF_DUTY',
        'state': 'OFF_DUTY',
      });

      expect(presence.hasFix, isFalse);
      expect(presence.lat, isNull);
      expect(presence.lastSeenAt, isNull);
    });
  });
}
