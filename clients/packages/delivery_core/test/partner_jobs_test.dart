import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The partner job board — the machine surface behind an `X-API-Key`.
///
/// Two things are protected here. The model: a job is trimmed on purpose, and the express surcharge
/// is absent from it because that money is the platform's, not the carrier's — there must be no
/// field to accidentally add to a payout. And the transport: the key travels, the bearer token
/// does NOT, because a stale session's `Authorization` header would be rejected by the JWT chain
/// before the key filter ever ran.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body);

  final String body;
  final List<RequestOptions> calls = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    calls.add(options);
    return ResponseBody.fromString(body, 200, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const String _board = '{"claimable":['
    '{"orderId":"o-1","status":"READY","deliveryTier":"EXPRESS","deliveryFee":3.25,'
    '"storeName":"Falafel King","deliveryAddress":"Hamra 12","contactPhone":"+9613000000",'
    '"placedAt":"2026-08-27T10:15:30Z"},'
    '{"orderId":"o-2","status":"READY","deliveryTier":"STANDARD","deliveryFee":2.00,'
    '"storeName":null,"deliveryAddress":"Gemmayze 3","contactPhone":null,'
    '"placedAt":"2026-08-27T10:20:00Z"}],'
    '"active":[{"orderId":"o-3","status":"PICKED_UP","deliveryTier":"STANDARD",'
    '"deliveryFee":2.50,"storeName":"Falafel King","deliveryAddress":"Achrafieh 9",'
    '"contactPhone":"+9613111111","placedAt":"2026-08-27T09:00:00Z"}]}';

void main() {
  group('PartnerJobs', () {
    test('both lists parse, with the errand keeping its null shop rather than a blank name', () {
      final PartnerJobs jobs = PartnerJobs.fromJson(<String, dynamic>{
        'claimable': <dynamic>[
          <String, dynamic>{
            'orderId': 'o-1',
            'status': 'READY',
            'deliveryTier': 'EXPRESS',
            'deliveryFee': 3.25,
            'storeName': 'Falafel King',
            'deliveryAddress': 'Hamra 12',
            'contactPhone': '+9613000000',
            'placedAt': '2026-08-27T10:15:30Z',
          },
          <String, dynamic>{
            'orderId': 'o-2',
            'status': 'READY',
            'deliveryTier': 'STANDARD',
            'deliveryFee': 2.00,
            'storeName': null,
            'deliveryAddress': 'Gemmayze 3',
            'contactPhone': null,
            'placedAt': '2026-08-27T10:20:00Z',
          },
        ],
        'active': <dynamic>[],
      });

      expect(jobs.claimable, hasLength(2));
      expect(jobs.active, isEmpty);

      final PartnerJob express = jobs.claimable.first;
      expect(express.deliveryTier, DeliveryTier.express);
      expect(express.status, OrderStatus.ready);
      // The BASE fee, which is what the company is paid from. A 3.25 here is 3.25 for the carrier —
      // the express premium is platform revenue and is not in this number, or anywhere on the shape.
      expect(express.deliveryFee, 3.25);
      expect(express.placedAt, isNotNull);

      final PartnerJob errand = jobs.claimable.last;
      expect(errand.storeName, isNull);
      expect(errand.contactPhone, isNull);
      expect(errand.deliveryTier, DeliveryTier.standard);
    });

    test('an empty board is two empty lists, not an error', () {
      final PartnerJobs jobs = PartnerJobs.fromJson(<String, dynamic>{
        'claimable': <dynamic>[],
        'active': <dynamic>[],
      });

      expect(jobs.claimable, isEmpty);
      expect(jobs.active, isEmpty);
    });
  });

  group('PartnerJobsApi', () {
    test('presents the key on X-API-Key and asks for the bearer token to be left off', () async {
      final _FakeAdapter adapter = _FakeAdapter(_board);
      final Dio dio = Dio(BaseOptions(baseUrl: 'https://gw.test'))
        ..httpClientAdapter = adapter;

      final PartnerJobs jobs = await PartnerJobsApi(dio).jobs(apiKey: 'ydk_abcdefgh0123');

      expect(adapter.calls, hasLength(1));
      expect(adapter.calls.single.path, '/api/partner/jobs');
      expect(adapter.calls.single.headers['X-API-Key'], 'ydk_abcdefgh0123');
      // The flag the auth interceptor reads. Without it a stale session's Authorization header
      // rides along and the JWT chain refuses a request the key alone would have served.
      expect(adapter.calls.single.extra[ApiClient.skipAuth], isTrue);

      expect(jobs.claimable, hasLength(2));
      expect(jobs.active.single.status, OrderStatus.pickedUp);
    });
  });
}
