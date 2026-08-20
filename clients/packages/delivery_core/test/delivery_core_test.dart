import 'dart:convert';

import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds an unsigned JWT with the given payload. Signature verification happens server-side; the
/// client only reads claims to decide which screen to show, which is exactly what this exercises.
String jwt(Map<String, dynamic> payload) {
  String segment(Map<String, dynamic> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${segment(<String, dynamic>{'alg': 'RS256'})}.${segment(payload)}.signature';
}

void main() {
  group('TokenRoles', () {
    test('reads realm roles', () {
      final String token = jwt(<String, dynamic>{
        'sub': 'user-1',
        'realm_access': <String, dynamic>{
          'roles': <String>['MERCHANT', 'offline_access'],
        },
      });

      expect(TokenRoles.parse(token), <DeliveryRole>{DeliveryRole.merchant});
    });

    test('ignores Keycloak built-in roles it does not know', () {
      final String token = jwt(<String, dynamic>{
        'realm_access': <String, dynamic>{
          'roles': <String>['offline_access', 'uma_authorization', 'default-roles-delivery'],
        },
      });

      expect(TokenRoles.parse(token), isEmpty);
    });

    test('a rider and a customer are distinguishable', () {
      final String rider = jwt(<String, dynamic>{
        'realm_access': <String, dynamic>{'roles': <String>['DELIVERY']},
      });
      final String customer = jwt(<String, dynamic>{
        'realm_access': <String, dynamic>{'roles': <String>['CUSTOMER']},
      });

      expect(TokenRoles.parse(rider).contains(DeliveryRole.delivery), isTrue);
      expect(TokenRoles.parse(customer).contains(DeliveryRole.delivery), isFalse);
    });

    test('reads the sub claim used for ownership checks', () {
      expect(TokenRoles.subject(jwt(<String, dynamic>{'sub': 'abc-123'})), 'abc-123');
    });

    // Regression guard for a real bug: Keycloak's `basic` client scope is what emits `sub`. Drop it
    // from a client's defaultClientScopes and tokens still carry realm roles — so role checks pass
    // — but every ownership check fails. Returning null here is correct; silently returning a
    // placeholder would be much worse.
    test('missing sub yields null rather than a fake id', () {
      final String token = jwt(<String, dynamic>{
        'realm_access': <String, dynamic>{'roles': <String>['MERCHANT']},
      });

      expect(TokenRoles.subject(token), isNull);
      expect(TokenRoles.parse(token), <DeliveryRole>{DeliveryRole.merchant});
    });

    test('malformed tokens do not throw', () {
      expect(TokenRoles.parse('not-a-jwt'), isEmpty);
      expect(TokenRoles.subject('a.b'), isNull);
      expect(TokenRoles.parse('a.!!!not-base64!!!.c'), isEmpty);
    });
  });

  group('AuthSession', () {
    test('is expired inside the 30s refresh margin', () {
      final AuthSession session = AuthSession(
        accessToken: 'x',
        refreshToken: null,
        expiresAt: DateTime.now().add(const Duration(seconds: 10)),
        roles: const <DeliveryRole>{},
        subject: null,
      );

      // Not literally expired yet, but close enough that a request would race the expiry.
      expect(session.isExpired, isTrue);
    });

    test('is not expired well before expiry', () {
      final AuthSession session = AuthSession(
        accessToken: 'x',
        refreshToken: null,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        roles: const <DeliveryRole>{},
        subject: null,
      );

      expect(session.isExpired, isFalse);
    });
  });

  group('Category', () {
    test('flatten preserves tree order and records depth', () {
      const Category tree = Category(
        id: '1',
        name: 'Food',
        children: <Category>[
          Category(id: '2', name: 'Bakery'),
          Category(id: '3', name: 'Restaurants'),
        ],
      );

      final List<({Category category, int depth})> flat =
          Category.flatten(<Category>[tree]);

      expect(flat.map((({Category category, int depth}) e) => e.category.name),
          <String>['Food', 'Bakery', 'Restaurants']);
      expect(flat.map((({Category category, int depth}) e) => e.depth),
          <int>[0, 1, 1]);
    });
  });
}
