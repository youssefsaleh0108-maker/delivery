import 'package:dio/dio.dart';

/// Whether a service is behind the gateway at all.
///
/// The platform is deployed in pieces. dev and qa run most of it but not all — pos-service,
/// inventory-service and reports-service are not there — and the edge answers every path it routes
/// nowhere with its own 404. A screen handed a live client cannot tell that from a shop with no
/// open shift or an empty stock list, so it draws a working page over a service that does not
/// exist, and the merchant meets a failure on every tap instead of one calm sentence at the top.
///
/// Read from the server, never from the environment's name: which services an environment runs is
/// the server's fact, and a client that hard-codes it is wrong the day one is deployed.
enum ServiceReach {
  /// Not asked yet. Screens draw as if the service were there — one round trip, not a guess.
  unknown,

  /// Something answered. Its answer may still have been a refusal or a failure; what matters here
  /// is that the path is routed, so the screen's ordinary error states are the truthful ones.
  present,

  /// The edge routes nothing there. No retry helps, and no state the service owns can be reached.
  absent;

  bool get isAbsent => this == ServiceReach.absent;
}

/// Whether [error] is the edge saying it routes nothing at that path, rather than a service of
/// ours answering "no such thing".
///
/// Every service here answers with JSON — RFC 9457 problem details, through each service's
/// `ApiExceptionHandler` — even for a 404. Traefik's own 404 for an unmatched route is
/// `text/plain`: `404 page not found`. So a 404 whose body is not JSON did not come from a service
/// at all, which is the one shape that means "not deployed".
///
/// Deliberately narrow. A timeout, a connection failure, a 502 or a 503 all mean something is
/// wrong that may right itself, and a screen that hid its own controls for those would tell a
/// merchant their till was decommissioned every time the network stuttered.
bool isServiceNotRouted(Object error) {
  if (error is! DioException) {
    return false;
  }
  final Response<dynamic>? response = error.response;
  if (response == null || response.statusCode != 404) {
    return false;
  }
  final String type =
      (response.headers.value(Headers.contentTypeHeader) ?? '').toLowerCase();
  // No content type at all is the edge too: our services always declare one.
  return !type.contains('json');
}

/// Asks whether a service is there, using a read the screen was going to make anyway.
///
/// Anything other than the edge's own 404 counts as [ServiceReach.present]: a 401, a 500 or a
/// timeout all prove the path is routed, and none of them is a reason to take a working page away.
Future<ServiceReach> probeServiceReach(Future<void> Function() read) async {
  try {
    await read();
    return ServiceReach.present;
  } catch (e) {
    return isServiceNotRouted(e) ? ServiceReach.absent : ServiceReach.present;
  }
}
