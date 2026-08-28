import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeliveryOrder tiers', () {
    test('an EXPRESS order carries its tier and the snapshotted surcharge', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(<String, dynamic>{
        'id': 'o-1',
        'customerId': 'c-1',
        'merchantId': 'm-1',
        'status': 'PLACED',
        'totalAmount': 27.0,
        'subtotal': 20.0,
        'deliveryFee': 5.0,
        'deliveryFeeCharged': 5.0,
        'deliveryTier': 'EXPRESS',
        'expressSurcharge': 2.0,
        'deliveryAddress': 'Somewhere',
      });

      expect(order.deliveryTier, DeliveryTier.express);
      expect(order.expressSurcharge, 2.0);
    });

    // The premium is outside the base fee: waiving delivery must not erase the surcharge.
    test('a waived EXPRESS order still carries the surcharge', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(<String, dynamic>{
        'id': 'o-2',
        'customerId': 'c-1',
        'merchantId': 'm-1',
        'status': 'PLACED',
        'totalAmount': 22.0,
        'subtotal': 20.0,
        'deliveryFee': 5.0,
        'deliveryFeeCharged': 0.0,
        'deliveryFeeWaived': true,
        'deliveryTier': 'EXPRESS',
        'expressSurcharge': 2.0,
        'deliveryAddress': 'Somewhere',
      });

      expect(order.deliveryFeeWaived, isTrue);
      expect(order.deliveryFeeCharged, 0);
      expect(order.expressSurcharge, 2.0);
    });

    test('an order from before tiers existed reads as STANDARD with no surcharge', () {
      final DeliveryOrder order = DeliveryOrder.fromJson(<String, dynamic>{
        'id': 'o-3',
        'customerId': 'c-1',
        'merchantId': 'm-1',
        'status': 'DELIVERED',
        'totalAmount': 25.0,
        'deliveryAddress': 'Somewhere',
      });

      expect(order.deliveryTier, DeliveryTier.standard);
      expect(order.expressSurcharge, 0);
    });
  });

  group('TierTradeSeries', () {
    test('a zero-filled series round-trips with both tiers on every day', () {
      // Exactly what the server sends: complete, ascending, both tiers always present.
      const String body = '{"windowDays":2,"days":['
          '{"day":"2026-08-26","standard":{"orders":0,"delivered":0,"gross":0},'
          '"express":{"orders":0,"delivered":0,"gross":0}},'
          '{"day":"2026-08-27","standard":{"orders":10,"delivered":8,"gross":240.50},'
          '"express":{"orders":2,"delivered":2,"gross":61.00}}]}';

      final TierTradeSeries series =
          TierTradeSeries.fromJson(jsonDecode(body) as Map<String, dynamic>);

      expect(series.windowDays, 2);
      expect(series.days, hasLength(2));

      final TierTradeDay quiet = series.days.first;
      expect(quiet.standard.orders, 0);
      expect(quiet.express.gross, 0);
      expect(quiet.orders, 0);

      final TierTradeDay busy = series.days.last;
      expect(busy.day.year, 2026);
      expect(busy.day.month, 8);
      expect(busy.day.day, 27);
      expect(busy.standard.orders, 10);
      expect(busy.standard.delivered, 8);
      expect(busy.standard.gross, 240.50);
      expect(busy.express.orders, 2);
      expect(busy.express.gross, 61.00);
      // The whole-day getters are the tiers added up, for a chart that does not split.
      expect(busy.orders, 12);
      expect(busy.delivered, 10);
      expect(busy.gross, 301.50);
    });
  });

  group('Partner API keys', () {
    test('the mint response is the one shape that carries the secret', () {
      final PartnerApiKeyCreated created = PartnerApiKeyCreated.fromJson(<String, dynamic>{
        'id': 'k-1',
        'secret': 'ydk_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG',
        'keyPrefix': 'ydk_abcdefgh',
        'label': 'dispatch box',
        'createdAt': '2026-08-27T10:00:00Z',
      });

      expect(created.secret, startsWith('ydk_'));
      expect(created.keyPrefix, 'ydk_abcdefgh');
      expect(created.label, 'dispatch box');
    });

    test('a listing row holds no secret field at all and its nulls stay null', () {
      final PartnerApiKey key = PartnerApiKey.fromJson(<String, dynamic>{
        'id': 'k-2',
        'keyPrefix': 'ydk_XXXXXXXX',
        'label': null,
        'createdAt': '2026-08-27T10:00:00Z',
        'lastUsedAt': null,
        'revoked': false,
        'revokedAt': null,
      });

      expect(key.label, isNull);
      expect(key.lastUsedAt, isNull);
      expect(key.revoked, isFalse);
      expect(key.revokedAt, isNull);
    });

    test('a revoked key stays in the listing, flagged', () {
      final PartnerApiKey key = PartnerApiKey.fromJson(<String, dynamic>{
        'id': 'k-3',
        'keyPrefix': 'ydk_YYYYYYYY',
        'revoked': true,
        'revokedAt': '2026-08-27T11:00:00Z',
      });

      expect(key.revoked, isTrue);
      expect(key.revokedAt, isNotNull);
    });
  });

  group('ProviderProfile operating hours', () {
    test('hours round-trip: what came off the wire goes back on it unchanged', () {
      final Map<String, dynamic> wireHours = <String, dynamic>{
        'MONDAY': <String, dynamic>{'open': '08:00', 'close': '22:00'},
        'SATURDAY': <String, dynamic>{'open': '10:00', 'close': '14:00'},
      };
      final ProviderProfile profile = ProviderProfile.fromJson(<String, dynamic>{
        'providerId': 'p-1',
        'logoUrl': null,
        'dispatchRegions': <dynamic>['Beirut', 'Jounieh'],
        'operatingHours': wireHours,
        'updatedBy': 'kc-sub',
        'updatedAt': '2026-08-27T10:00:00Z',
      });

      // A day absent from the map is closed — five of the seven here.
      expect(profile.operatingHours, hasLength(2));
      expect(profile.operatingHours['MONDAY']!.open, '08:00');
      expect(profile.operatingHours['MONDAY']!.close, '22:00');
      expect(profile.operatingHours.containsKey('SUNDAY'), isFalse);

      // The PUT serialises to exactly the shape the GET produced.
      expect(
        jsonEncode(ProviderProfile.hoursToJson(profile.operatingHours)),
        jsonEncode(wireHours),
      );
    });

    test('the never-saved empty shape parses, and empty hours serialise to an empty object', () {
      final ProviderProfile profile = ProviderProfile.fromJson(<String, dynamic>{
        'providerId': 'p-2',
        'logoUrl': null,
        'dispatchRegions': <dynamic>[],
        'operatingHours': <String, dynamic>{},
        'updatedBy': null,
        'updatedAt': null,
      });

      expect(profile.dispatchRegions, isEmpty);
      expect(profile.operatingHours, isEmpty);
      expect(profile.updatedAt, isNull);
      expect(jsonEncode(ProviderProfile.hoursToJson(profile.operatingHours)), '{}');
    });
  });

  group('RiderPerformance', () {
    test('a rider with no work has a null rate, never zero or a hundred', () {
      final RiderPerformance perf = RiderPerformance.fromJson(<String, dynamic>{
        'riderId': 'r-1',
        'windowDays': 30,
        'claimed': 0,
        'delivered': 0,
        'cancelledAfterClaim': 0,
        'completionRate': null,
      });

      expect(perf.claimed, 0);
      expect(perf.completionRate, isNull);
    });

    test('a working rider carries the server-computed rate', () {
      final RiderPerformance perf = RiderPerformance.fromJson(<String, dynamic>{
        'riderId': 'r-2',
        'windowDays': 30,
        'claimed': 12,
        'delivered': 11,
        'cancelledAfterClaim': 1,
        'completionRate': 91.67,
      });

      expect(perf.completionRate, 91.67);
    });
  });

  group('HoursOnline', () {
    test('carries only the dates with time, and totals from the exact seconds', () {
      final HoursOnline hours = HoursOnline.fromJson(<String, dynamic>{
        'riderId': 'r-1',
        'zone': 'UTC',
        'from': '2026-08-21',
        'to': '2026-08-27',
        'days': <dynamic>[
          <String, dynamic>{
            'date': '2026-08-26',
            'secondsOnline': 3600,
            'hoursOnline': 1.00,
            'sessions': 1,
          },
          <String, dynamic>{
            'date': '2026-08-27',
            'secondsOnline': 5430,
            'hoursOnline': 1.51,
            'sessions': 2,
          },
        ],
      });

      expect(hours.zone, 'UTC');
      expect(hours.days, hasLength(2));
      expect(hours.totalSecondsOnline, 9030);
      expect(hours.days.last.sessions, 2);
    });

    test('a rider with no on-duty time is an empty list, not a row of zeros', () {
      final HoursOnline hours = HoursOnline.fromJson(<String, dynamic>{
        'riderId': 'r-2',
        'zone': 'UTC',
        'from': '2026-08-21',
        'to': '2026-08-27',
        'days': <dynamic>[],
      });

      expect(hours.days, isEmpty);
      expect(hours.totalSecondsOnline, 0);
    });
  });

  group('ActivityEntry', () {
    test('a Butler errand has no store name, and that is a fact, not a gap', () {
      final ActivityEntry entry = ActivityEntry.fromJson(<String, dynamic>{
        'occurredAt': '2026-08-27T10:15:30Z',
        'event': 'placed',
        'status': 'PLACED',
        'orderId': 'o-1',
        'storeName': null,
        'amount': 24.00,
      });

      expect(entry.event, ActivityEvent.placed);
      expect(entry.status, OrderStatus.placed);
      expect(entry.storeName, isNull);
      expect(entry.amount, 24.00);
    });

    test('an event this build does not know degrades to unknown, keeping its spelling', () {
      final ActivityEntry entry = ActivityEntry.fromJson(<String, dynamic>{
        'occurredAt': '2026-08-27T10:15:30Z',
        'event': 'refunded',
        'status': 'DELIVERED',
        'orderId': 'o-2',
        'storeName': 'Falafel King',
        'amount': 10.0,
      });

      expect(entry.event, ActivityEvent.unknown);
      expect(entry.eventWire, 'refunded');
    });
  });

  group('Suspension standing', () {
    test('a reinstatement row has no reason, and that is legitimate', () {
      final PartnerSuspensionRecord record = PartnerSuspensionRecord.fromJson(<String, dynamic>{
        'suspended': false,
        'lastChange': <String, dynamic>{
          'suspended': false,
          'reason': null,
          'reasonNote': 'appeal accepted',
          'actor': 'kc-admin',
          'at': '2026-08-27T09:00:00Z',
        },
        'history': <dynamic>[
          <String, dynamic>{
            'suspended': false,
            'reason': null,
            'reasonNote': 'appeal accepted',
            'actor': 'kc-admin',
            'at': '2026-08-27T09:00:00Z',
          },
          <String, dynamic>{
            'suspended': true,
            'reason': 'FRAUD',
            'reasonNote': null,
            'actor': 'kc-admin',
            'at': '2026-08-20T09:00:00Z',
          },
        ],
      });

      expect(record.suspended, isFalse);
      expect(record.lastChange!.reason, isNull);
      expect(record.history, hasLength(2));
      expect(record.history.last.reason, SuspensionReason.fraud);
    });

    test('a never-touched partner has no lastChange and an empty history', () {
      final PartnerSuspensionRecord record = PartnerSuspensionRecord.fromJson(<String, dynamic>{
        'suspended': false,
        'lastChange': null,
        'history': <dynamic>[],
      });

      expect(record.suspended, isFalse);
      expect(record.lastChange, isNull);
      expect(record.history, isEmpty);
    });
  });
}
