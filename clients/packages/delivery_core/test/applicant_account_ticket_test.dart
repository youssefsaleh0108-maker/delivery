import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The open form's secret for its passcode step, as the client carries it.
///
/// The reference names an application and proves nothing — back office and a rider's delivery company
/// see it too — so the submission answers with an account-setup ticket as well, and the passcode step
/// sends that, or a fresh email proof in its place: in the body, never the path, which access logs
/// keep.
void main() {
  late _Recorder server;
  late OnboardingApi api;

  setUp(() {
    server = _Recorder();
    api = OnboardingApi(Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = server);
  });

  test('each way of applying answers with the reference and the ticket beside it', () async {
    server.answer = <String, Object?>{'reference': 'ref-1', 'accountTicket': 'ticket-1'};

    final ({String reference, String? accountTicket}) rider = await api.applyAsRider(
        name: 'Sam Salem', email: 'sam@example.test', emailVerificationToken: 'proof');
    final ({String reference, String? accountTicket}) shop = await api.applyAsMerchant(
        businessName: 'Sam Shakes', contactName: 'Sam Salem', email: 'sam@example.test',
        emailVerificationToken: 'proof');
    final ({String reference, String? accountTicket}) fleet = await api.applyAsCarrier(
        companyName: 'Swift', contactName: 'Sam Salem', email: 'sam@example.test',
        emailVerificationToken: 'proof');

    for (final ({String reference, String? accountTicket}) answer
        in <({String reference, String? accountTicket})>[rider, shop, fleet]) {
      expect(answer.reference, 'ref-1');
      expect(answer.accountTicket, 'ticket-1');
    }
  });

  test('a server older than the ticket answers without one, which reads as none', () async {
    server.answer = <String, Object?>{'reference': 'ref-1'};

    final ({String reference, String? accountTicket}) answer = await api.applyAsRider(
        name: 'Sam Salem', email: 'sam@example.test', emailVerificationToken: 'proof');

    expect(answer.reference, 'ref-1');
    expect(answer.accountTicket, isNull);
  });

  test('the passcode step carries the ticket in the body, and only what it was given', () async {
    await api.createApplicantAccount(
        reference: 'ref-1', password: '246810', accountTicket: 'ticket-1');

    expect(server.path, '/api/onboarding/applications/ref-1/account');
    expect(server.body, <String, dynamic>{'password': '246810', 'accountTicket': 'ticket-1'});
  });

  test('or the fresh email proof in its place', () async {
    await api.createApplicantAccount(
        reference: 'ref-1', password: '246810', emailVerificationToken: 'proof-2');

    expect(server.body, <String, dynamic>{
      'password': '246810',
      'emailVerificationToken': 'proof-2',
    });
  });
}

/// Records the last request and answers it with [answer].
class _Recorder implements HttpClientAdapter {
  Map<String, Object?> answer = <String, Object?>{};
  String? path;
  Map<String, dynamic>? body;

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? _, Future<void>? __) async {
    path = options.path;
    body = options.data as Map<String, dynamic>?;
    return ResponseBody.fromString(jsonEncode(answer), 201, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
