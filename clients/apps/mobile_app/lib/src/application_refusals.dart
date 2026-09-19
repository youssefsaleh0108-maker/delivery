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
///
/// And the step's own secret, which the reference no longer stands in for: none sent
/// (`sign-in-proof-missing` — an app older than the ticket, whose user is told to update), or one the
/// server would not take (`sign-in-proof-rejected`) — see [isSignInProofRefused], which the forms act
/// on before anything is shown.
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
    case 'sign-in-proof-missing':
      return t.wizAccountProofMissing;
    case 'sign-in-proof-rejected':
      return t.wizAccountProofRejected;
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

/// Whether the passcode step refused the secret that proves the application is the applicant's:
/// the account-setup ticket from the submission was wrong, spent or past its half hour, or no secret
/// was sent at all.
///
/// The reference in the path proves nothing — a rider's delivery company sees it too — so the open
/// forms answer this by proving the address again: a new code to the application's email, and its
/// proof sent in the ticket's place. Only that code does; any other refusal is shown as it is.
bool isSignInProofRefused(Object error) => switch (_codeOf(error)) {
      'sign-in-proof-rejected' || 'sign-in-proof-missing' => true,
      _ => false,
    };

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

// ---------------------------------------------------------------- rider company region
// The refusals about the delivery company a rider names (feat/rider-company-region). A block of
// their own, so they merge beside any other change to this file without touching it.

/// What to say when the server refused the delivery company a rider named, or could not check it,
/// in the reader's own language. Null for any other failure.
///
/// The partner wizard asks this before [applicationRefusal] or [applicationServerMessage], on the
/// open form and the signed-in path alike: on the open form these are the only refusals that carry a
/// code, and without this an Arabic-speaking rider would read the server's English.
String? riderCompanyRefusal(DeliveryStrings t, Object error) => switch (_codeOf(error)) {
      'company-not-hiring' => t.riderRegionCompanyNotHiring,
      'hiring-companies-unavailable' => t.riderRegionCompaniesUnavailable,
      _ => null,
    };

/// Whether the server refused the company itself: it is not taking riders, or never was. Sending the
/// same application again cannot change that; choosing another company, or YouDrop, can.
bool isCompanyNotHiring(Object error) => _codeOf(error) == 'company-not-hiring';

// ------------------------------------------------------------ end rider company region

String? _codeOf(Object error) {
  if (error is! DioException) return null;
  final Object? body = error.response?.data;
  return body is Map && body['code'] is String ? body['code'] as String : null;
}
