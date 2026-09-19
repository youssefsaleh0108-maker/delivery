import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/application_refusals.dart';

/// What the passcode step says when the server refuses it.
///
/// The partner wizard and the services signup both show "We could not set up your sign-in" followed
/// by [applicationServerMessage]. A rider met that followed by "That did not go through" because the
/// step could only answer a bare 500; now the server names what happened, and these are the names
/// the app must say in the reader's own language.
void main() {
  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  DioException answered(int status, Map<String, Object?> body) {
    final RequestOptions request =
        RequestOptions(path: '/api/onboarding/applications/ref-sam/account');
    return DioException(
      requestOptions: request,
      response: Response<dynamic>(requestOptions: request, statusCode: status, data: body),
      type: DioExceptionType.badResponse,
    );
  }

  test('an address that already has an account is named, in either language', () {
    final DioException refused = answered(422, <String, Object?>{
      'code': 'account-exists',
      'message': 'An account already uses this email address.',
    });

    expect(applicationServerMessage(en, refused), en.wizAccountExists);
    expect(applicationServerMessage(ar, refused), ar.wizAccountExists);
    // The coded path falls back to the same words, so either helper says it.
    expect(applicationRefusal(ar, refused), ar.wizAccountExists);
  });

  test('the platform failing is "try again in a minute", not "that did not go through"', () {
    final DioException unavailable = answered(503, <String, Object?>{
      'code': 'sign-in-unavailable',
      'message': 'Your sign-in could not be set up just now. Please try again in a minute.',
    });

    expect(applicationServerMessage(en, unavailable), en.wizAccountSignInUnavailable);
    expect(applicationServerMessage(ar, unavailable), ar.wizAccountSignInUnavailable);
    expect(applicationServerMessage(en, unavailable), isNot(en.thatDidNotGoThrough));
  });

  test('an uncoded refusal is still the server\'s own words, and a bare 500 the generic sentence', () {
    expect(
      applicationServerMessage(
          en, answered(422, <String, Object?>{'message': 'No application with that reference'})),
      'No application with that reference',
    );
    expect(
      applicationServerMessage(
          en, answered(500, <String, Object?>{'status': 500, 'error': 'Internal Server Error'})),
      en.thatDidNotGoThrough,
    );
  });

  test('a sign-in already made is named, and recognised as the one to sign in with', () {
    final DioException made = answered(422, <String, Object?>{
      'code': 'sign-in-exists',
      'message': 'That application already has a sign-in.',
    });

    expect(isSignInExists(made), isTrue);
    expect(applicationServerMessage(en, made), en.wizAccountSignInExists);
    expect(applicationServerMessage(ar, made), ar.wizAccountSignInExists);
    expect(applicationRefusal(ar, made), ar.wizAccountSignInExists);
    // Only that code: an address with somebody else's account must never be signed in to.
    expect(
        isSignInExists(answered(422, <String, Object?>{'code': 'account-exists', 'message': 'x'})),
        isFalse);
    expect(isSignInExists(StateError('offline')), isFalse);
  });

  test('an application that may not have a sign-in made says why, in either language', () {
    final DioException decided = answered(422, <String, Object?>{
      'code': 'application-decided',
      'message': 'This application has already been decided.',
    });
    final DioException changed = answered(422, <String, Object?>{
      'code': 'email-changed',
      'message': 'The email address on this application was changed after it was verified.',
    });

    expect(applicationServerMessage(en, decided), en.wizAccountApplicationDecided);
    expect(applicationServerMessage(ar, decided), ar.wizAccountApplicationDecided);
    expect(applicationServerMessage(en, changed), en.wizAccountEmailChanged);
    expect(applicationServerMessage(ar, changed), ar.wizAccountEmailChanged);
  });

  test('the Arabic is Arabic, not the English copied', () {
    expect(ar.wizAccountExists, isNot(en.wizAccountExists));
    expect(ar.wizAccountSignInUnavailable, isNot(en.wizAccountSignInUnavailable));
    expect(ar.wizAccountSignInExists, isNot(en.wizAccountSignInExists));
    expect(ar.wizAccountApplicationDecided, isNot(en.wizAccountApplicationDecided));
    expect(ar.wizAccountEmailChanged, isNot(en.wizAccountEmailChanged));
  });
}
