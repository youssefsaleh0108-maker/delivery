import 'package:delivery_core/src/auth/pkce.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PKCE (RFC 7636)', () {
    // The official test vector from RFC 7636 Appendix B. This is the one check that proves the
    // hand-rolled web auth flow will actually be accepted by an identity provider — get the
    // encoding or the hash input wrong and Keycloak rejects the exchange with a generic error that
    // says nothing about which half is broken.
    test('S256 challenge matches the RFC Appendix B vector', () {
      const String verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      const String expectedChallenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

      expect(Pkce.challengeFor(verifier), expectedChallenge);
    });

    test('challenge carries no base64 padding', () {
      for (int i = 0; i < 20; i++) {
        expect(Pkce.challengeFor(Pkce.generateVerifier()), isNot(contains('=')));
      }
    });

    test('challenge is URL-safe base64 only', () {
      final RegExp urlSafe = RegExp(r'^[A-Za-z0-9\-_]+$');
      for (int i = 0; i < 20; i++) {
        expect(urlSafe.hasMatch(Pkce.challengeFor(Pkce.generateVerifier())), isTrue);
      }
    });

    test('verifier length stays inside the 43-128 character range', () {
      for (int i = 0; i < 20; i++) {
        final int length = Pkce.generateVerifier().length;
        expect(length, greaterThanOrEqualTo(43));
        expect(length, lessThanOrEqualTo(128));
      }
    });

    test('verifiers do not repeat', () {
      final Set<String> seen = <String>{
        for (int i = 0; i < 200; i++) Pkce.generateVerifier(),
      };
      expect(seen.length, 200);
    });

    test('state values are random and URL-safe', () {
      final RegExp urlSafe = RegExp(r'^[A-Za-z0-9\-_]+$');
      final Set<String> seen = <String>{
        for (int i = 0; i < 200; i++) Pkce.generateState(),
      };
      expect(seen.length, 200);
      expect(seen.every(urlSafe.hasMatch), isTrue);
    });

    test('the same verifier always yields the same challenge', () {
      final String verifier = Pkce.generateVerifier();
      expect(Pkce.challengeFor(verifier), Pkce.challengeFor(verifier));
    });
  });
}
