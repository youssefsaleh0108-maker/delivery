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
String applicationServerMessage(DeliveryStrings t, Object error) {
  if (error is DioException) {
    final Object? body = error.response?.data;
    if (body is Map && body['message'] is String) return body['message'] as String;
  }
  return t.thatDidNotGoThrough;
}

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
