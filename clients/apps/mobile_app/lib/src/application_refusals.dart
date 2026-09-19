import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';

/// What to say when an application is refused or does not go through, for every form that applies:
/// the partner wizard and the services signup (Figma 126:11).
///
/// One copy on purpose. The server names the refusals it knows with a `code`, and the app says those
/// in the reader's own language; two forms each keeping their own list is how one of them ends up
/// showing an Arabic-speaking applicant the English sentence for a refusal the other translates.

/// The server's own words where it has any — they are written to be acted on — and otherwise the
/// generic "that did not go through", for a failure that never reached a sentence.
///
/// The passcode step's refusals are said in the reader's language even here, because that step shows
/// the server's words — a failure reads "We could not set up your sign-in" and then this (the partner
/// wizard's `_messageFrom`, and the services signup): an address that already has an account
/// (`account-exists`), the platform failing to make one just now (`sign-in-unavailable`), which a
/// retry in a minute finishes, the sign-in already made (`sign-in-exists`, see [isSignInExists]), and
/// an application that may not have one made at all — decided already (`application-decided`), or
/// its email changed by support after it was verified (`email-changed`). Until the server named them
/// they were a bare 500 or the server's English, and a rider read "That did not go through" with
/// nothing to act on.
String applicationServerMessage(DeliveryStrings t, Object error) {
  switch (_codeOf(error)) {
    case 'account-exists':
      return t.wizAccountExists;
    case 'sign-in-unavailable':
      return t.wizAccountSignInUnavailable;
    case 'sign-in-exists':
      return t.wizAccountSignInExists;
    case 'application-decided':
      return t.wizAccountApplicationDecided;
    case 'email-changed':
      return t.wizAccountEmailChanged;
  }
  if (error is DioException) {
    final Object? body = error.response?.data;
    if (body is Map && body['message'] is String) return body['message'] as String;
  }
  return t.thatDidNotGoThrough;
}

/// Whether the passcode step was refused because the application's sign-in already exists: an
/// earlier try went through and its answer never arrived — a lost 201, or a 503 whose sign-in had in
/// fact been recorded.
///
/// Nothing is wrong, and making the sign-in again can never succeed, so the open forms treat this as
/// the sign-in made and go straight on to signing in with the passcode just chosen — the one the
/// sign-in was made with.
bool isSignInExists(Object error) => _codeOf(error) == 'sign-in-exists';

/// A refused application, in the reader's language wherever the server named the refusal.
///
/// A 502 always means the same thing on the signed-in path: the record is in and only the account's
/// roles are missing, so the same call, retried, finishes it. A code this build does not know — or a
/// refusal with none, such as the domain's own — falls back to [applicationServerMessage].
String applicationRefusal(DeliveryStrings t, Object error) {
  if (error is DioException) {
    if (error.response?.statusCode == 502) return t.wizAccountRolesRetry;
    switch (_codeOf(error)) {
      case 'already-partner':
        return t.accountAlreadyPartner;
      case 'other-application':
        return t.accountOtherApplication;
      case 'email-unverified':
        return t.accountEmailUnverified;
      case 'service-category-closed':
        return t.svcErrCategoryClosed;
      case 'service-category-missing':
        return t.svcErrCategoryMissing;
      case 'service-area-unknown':
        return t.svcErrAreaUnknown;
      case 'service-area-missing':
        return t.svcErrAreaMissing;
      case 'service-catalog-unavailable':
        return t.svcErrCatalogUnavailable;
    }
  }
  return applicationServerMessage(t, error);
}

/// Whether the server refused one of the services answers — something the applicant changes on the
/// form, rather than a failure they retry.
bool isServiceAnswerRefusal(Object error) => switch (_codeOf(error)) {
      'service-category-closed' ||
      'service-category-missing' ||
      'service-area-unknown' ||
      'service-area-missing' =>
        true,
      _ => false,
    };

/// Whether the server refused the account rather than this attempt: it already has an application of
/// another kind or for another business — a shop's, when services were asked for — or it already
/// trades as a partner. Sending the same form again can never change either, so a form offers a way
/// out instead of a retry.
bool isFinalAccountRefusal(Object error) => switch (_codeOf(error)) {
      'other-application' || 'already-partner' => true,
      _ => false,
    };

String? _codeOf(Object error) {
  if (error is! DioException) return null;
  final Object? body = error.response?.data;
  return body is Map && body['code'] is String ? body['code'] as String : null;
}
