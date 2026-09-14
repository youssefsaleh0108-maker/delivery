import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/order_attachment_files.dart';
import 'package:mobile_app/src/service_order_files.dart';

/// The customer's design files through the real attachment client, against recording adapters — the
/// pattern delivery_core's order_attachment_api_test uses — so what the service order screen's
/// uploads, Removes and "Your files" actually send is pinned end to end: the three steps of an upload
/// and the id it answers, a refusal from any step arriving as a [ServiceFileRefused] the screen can put
/// into words (too many uploads in a few minutes among them), and anything that is not a refusal
/// thrown as it is, never dressed up as one.
class _Recorder implements HttpClientAdapter {
  _Recorder(this.respond);

  /// The status and JSON body each request is answered with; a null body is an empty one.
  final (int, Object?) Function(RequestOptions options) respond;
  final List<RequestOptions> requests = <RequestOptions>[];
  final List<Uint8List> bodies = <Uint8List>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    if (requestStream != null) {
      final BytesBuilder sent = BytesBuilder();
      await for (final Uint8List chunk in requestStream) {
        sent.add(chunk);
      }
      bodies.add(sent.takeBytes());
    }
    final (int status, Object? body) = respond(options);
    if (body == null) return ResponseBody.fromString('', status);
    return ResponseBody.fromString(jsonEncode(body), status, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const String _uploadUrl = 'https://storage.test/order-attachments/uploads/f.pdf?X-Amz-Signature=abc';

/// A 422 as order-manager's ApiExceptionHandler writes an attachment refusal.
Map<String, dynamic> _refused(String code) => <String, dynamic>{
      'type': 'about:blank',
      'title': 'Attachment refused',
      'status': 422,
      'detail': 'The server says why, in English',
      'code': code,
    };

/// The attachment endpoints on a good day: a ticket, then a confirmation.
(int, Object?) _happy(RequestOptions o) {
  if (o.path.endsWith('/presign')) {
    return (200, <String, dynamic>{
      'fileId': 'file-1',
      'uploadUrl': _uploadUrl,
      'contentType': 'application/pdf',
      'expiresAt': '2026-09-14T09:10:00Z',
      'maxSizeBytes': 10 * 1024 * 1024,
    });
  }
  if (o.path.endsWith('/confirm')) {
    return (200, <String, dynamic>{
      'fileId': 'file-1',
      'contentType': 'application/pdf',
      'sizeBytes': 4,
      'status': 'UPLOADED',
      'createdAt': '2026-09-14T09:00:00Z',
    });
  }
  return (404, null);
}

Matcher _refusedAs(AttachmentRefusal refusal) => throwsA(isA<ServiceFileRefused>()
    .having((ServiceFileRefused e) => e.refusal, 'refusal', refusal));

void main() {
  late _Recorder app;
  late _Recorder storage;

  OrderAttachmentFiles files((int, Object?) Function(RequestOptions options) answer) {
    app = _Recorder(answer);
    storage = _Recorder((RequestOptions o) => (200, null));
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://gateway.test'))..httpClientAdapter = app;
    return OrderAttachmentFiles(
        OrderAttachmentApi(dio, uploadClient: () => Dio()..httpClientAdapter = storage));
  }

  // "%PDF": four bytes of a design.
  final Uint8List design = Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]);

  test('an upload is presigned, sent to storage byte for byte and confirmed, and answers its id',
      () async {
    final OrderAttachmentFiles subject = files(_happy);
    final List<int> sent = <int>[];

    final String fileId = await subject.upload(
        bytes: design, contentType: 'application/pdf', onProgress: (int bytes, int _) => sent.add(bytes));

    expect(fileId, 'file-1');
    expect(app.requests.map((RequestOptions r) => '${r.method} ${r.path}'), <String>[
      'POST /api/orders/attachments/presign',
      'POST /api/orders/attachments/file-1/confirm',
    ]);
    expect(app.requests.first.data, <String, dynamic>{'contentType': 'application/pdf', 'sizeBytes': 4});
    expect(storage.requests.single.method, 'PUT');
    expect(storage.requests.single.uri.host, 'storage.test');
    expect(storage.bodies.single, design);
    expect(sent, isNotEmpty, reason: 'the row\'s progress bar hears about the PUT');
  });

  test('a refusal from any step reaches the screen as the attachment client named it', () async {
    // Too many uploads in the last few minutes, refused at presign: no byte moves.
    OrderAttachmentFiles subject =
        files((RequestOptions o) => (422, _refused('TOO_MANY_UPLOADS')));
    await expectLater(subject.upload(bytes: design, contentType: 'application/pdf'),
        _refusedAs(AttachmentRefusal.tooManyUploads));
    expect(storage.requests, isEmpty);

    // Not really a PDF, found once the bytes are up.
    subject = files((RequestOptions o) =>
        o.path.endsWith('/confirm') ? (422, _refused('WRONG_TYPE')) : _happy(o));
    await expectLater(subject.upload(bytes: design, contentType: 'application/pdf'),
        _refusedAs(AttachmentRefusal.wrongType));

    // A kind of file the server never takes: refused before a single request.
    subject = files(_happy);
    await expectLater(subject.upload(bytes: design, contentType: 'application/zip'),
        _refusedAs(AttachmentRefusal.wrongType));
    expect(app.requests, isEmpty);
  });

  test('a failure that is not a refusal is thrown as it is', () async {
    final OrderAttachmentFiles subject =
        files((RequestOptions o) => (503, <String, dynamic>{'title': 'Service unavailable'}));

    await expectLater(subject.upload(bytes: design, contentType: 'application/pdf'),
        throwsA(isA<DioException>()));
  });

  test('Remove takes an upload back, and one an order already carries is refused in words',
      () async {
    OrderAttachmentFiles subject = files((RequestOptions o) => (204, null));
    await subject.remove('file-1');
    expect(app.requests.single.method, 'DELETE');
    expect(app.requests.single.path, '/api/orders/attachments/file-1');

    subject = files((RequestOptions o) => (422, _refused('ALREADY_ATTACHED')));
    await expectLater(subject.remove('file-1'), _refusedAs(AttachmentRefusal.alreadyAttached));
  });

  test('a placed order\'s files are read from the order, each with the link the server just made',
      () async {
    final OrderAttachmentFiles subject = files((RequestOptions o) => (200, <Map<String, dynamic>>[
          <String, dynamic>{
            'fileId': 'file-1',
            'contentType': 'application/pdf',
            'url': 'https://storage.test/f.pdf?sig=1',
            'sizeBytes': 2048,
            'attachedAt': '2026-09-14T09:05:00Z',
            'urlExpiresAt': '2026-09-14T09:15:00Z',
          },
        ]));

    final List<OrderAttachment> attached = await subject.forOrder('order-1');

    expect(app.requests.single.method, 'GET');
    expect(app.requests.single.path, '/api/orders/order-1/attachments');
    expect(attached.single.fileId, 'file-1');
    expect(attached.single.url, 'https://storage.test/f.pdf?sig=1');
    expect(attached.single.isPdf, isTrue);
  });
}
