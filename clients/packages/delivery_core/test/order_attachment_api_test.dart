import 'dart:convert';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// A customer's files on a service order, against recording adapters.
///
/// Pinned here: the verbs and paths order-manager's `OrderAttachmentController` serves; that a file's
/// bytes go to the presigned URL on a bare client carrying NO Authorization header and exactly the
/// ticket's Content-Type; that a design is sent byte for byte, never shrunk or re-encoded the way a
/// photo is, because a shop prints it; that a file the server would refuse — over 10 MB, an `.ai` — is
/// refused before a single request; that a half-made upload is taken back; and that a 422's code
/// arrives as a typed refusal a screen can put into words.
class _Recorder implements HttpClientAdapter {
  _Recorder(this.respond, {this.statusOf});

  final Object? Function(RequestOptions options) respond;

  /// The status to answer with; 200 when unset.
  final int Function(RequestOptions options)? statusOf;
  final List<RequestOptions> requests = <RequestOptions>[];
  final Map<String, Uint8List> bodies = <String, Uint8List>{};

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    if (requestStream != null) {
      final BytesBuilder sent = BytesBuilder();
      await for (final Uint8List chunk in requestStream) {
        sent.add(chunk);
      }
      bodies['${options.method} ${options.uri}'] = sent.takeBytes();
    }
    final Object? body = respond(options);
    final int status = statusOf?.call(options) ?? 200;
    if (body == null) return ResponseBody.fromString('', status);
    return ResponseBody.fromString(jsonEncode(body), status, headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const String _uploadUrl =
    'https://api-dev.youdrop.shop/order-attachments/uploads/2026-09-13/f.pdf?X-Amz-Signature=abc';

Map<String, dynamic> _ticket({int maxSizeBytes = 10 * 1024 * 1024, String type = 'application/pdf'}) =>
    <String, dynamic>{
      'fileId': 'file-1',
      'uploadUrl': _uploadUrl,
      'contentType': type,
      'expiresAt': '2026-09-13T09:10:00Z',
      'maxSizeBytes': maxSizeBytes,
    };

Map<String, dynamic> _confirmed() => <String, dynamic>{
      'fileId': 'file-1',
      'contentType': 'application/pdf',
      'sizeBytes': 2048,
      'status': 'UPLOADED',
      'createdAt': '2026-09-13T09:00:00Z',
      'attachedAt': null,
    };

Object? _server(RequestOptions o) {
  if (o.path.endsWith('/presign')) return _ticket();
  if (o.path.endsWith('/confirm')) return _confirmed();
  return null;
}

Matcher _refusedFor(AttachmentRefusal refusal) => throwsA(isA<AttachmentRefusedException>()
    .having((AttachmentRefusedException e) => e.refusal, 'refusal', refusal));

void main() {
  late _Recorder app;
  late _Recorder storage;

  OrderAttachmentApi apiWith(
    Object? Function(RequestOptions options) respond, {
    int Function(RequestOptions options)? statusOf,
    int storageStatus = 200,
  }) {
    app = _Recorder(respond, statusOf: statusOf);
    storage = _Recorder((RequestOptions o) => null, statusOf: (RequestOptions o) => storageStatus);
    final Dio dio = Dio(BaseOptions(
      baseUrl: 'http://gateway',
      headers: <String, dynamic>{'Authorization': 'Bearer app-token'},
    ))
      ..httpClientAdapter = app;
    return OrderAttachmentApi(dio, uploadClient: () => Dio()..httpClientAdapter = storage);
  }

  List<String> calls(_Recorder recorder) =>
      recorder.requests.map((RequestOptions r) => '${r.method} ${r.path}').toList();

  group('choosing a file', () {
    test('a PDF, a JPEG or a PNG is named by its extension in any case, and nothing else is', () {
      expect(OrderAttachmentApi.contentTypeForFileName('Business Card.PDF'), 'application/pdf');
      expect(OrderAttachmentApi.contentTypeForFileName('front.jpg'), 'image/jpeg');
      expect(OrderAttachmentApi.contentTypeForFileName('front.JPEG'), 'image/jpeg');
      expect(OrderAttachmentApi.contentTypeForFileName('logo.png'), 'image/png');
      for (final String name in <String>[
        'artwork.ai',
        'design.zip',
        'photo.webp',
        'vector.svg',
        'README',
        'trailing.',
      ]) {
        expect(OrderAttachmentApi.contentTypeForFileName(name), isNull, reason: name);
      }
    });

    test('the precheck refuses what the server would: over 10 MB, the wrong type, an empty file', () {
      const int tenMegabytes = 10 * 1024 * 1024;

      expect(OrderAttachmentApi.precheck(contentType: 'application/pdf', sizeBytes: tenMegabytes),
          isNull);
      expect(OrderAttachmentApi.precheck(contentType: 'application/pdf', sizeBytes: tenMegabytes + 1),
          AttachmentRefusal.tooLarge);
      expect(OrderAttachmentApi.precheck(contentType: 'application/postscript', sizeBytes: 1024),
          AttachmentRefusal.wrongType);
      expect(OrderAttachmentApi.precheck(contentType: 'image/png', sizeBytes: 0),
          AttachmentRefusal.empty);
      expect(OrderAttachmentApi.maxFilesPerOrder, 3);
    });
  });

  group('uploading', () {
    test('presigns, PUTs the bytes to storage on a bare client, then confirms', () async {
      final OrderAttachmentApi api = apiWith(_server);
      final Uint8List bytes = Uint8List.fromList(List<int>.generate(4096, (int i) => i % 251));

      final AttachmentUpload upload = await api.upload(bytes: bytes, contentType: 'application/pdf');

      expect(calls(app), <String>[
        'POST /api/orders/attachments/presign',
        'POST /api/orders/attachments/file-1/confirm',
      ]);
      expect(app.requests.first.data,
          <String, dynamic>{'contentType': 'application/pdf', 'sizeBytes': 4096});

      final RequestOptions put = storage.requests.single;
      expect(put.method, 'PUT');
      expect(put.uri.toString(), _uploadUrl);
      expect(put.headers.containsKey('Authorization'), isFalse);
      expect(put.headers[Headers.contentTypeHeader], 'application/pdf');
      expect(storage.bodies['PUT ${put.uri}'], bytes);

      expect(upload.fileId, 'file-1');
      expect(upload.status, AttachmentUploadStatus.uploaded);
      expect(upload.isReadyToOrder, isTrue);
      expect(upload.sizeBytes, 2048);
    });

    test('a large image goes up byte for byte — never shrunk or re-encoded, because a shop prints it',
        () async {
      // Three times the megabyte a product photo is squeezed under, and not a decodable image at all:
      // a photo upload would shrink the one and choke on the other. A design must arrive as chosen.
      final OrderAttachmentApi api = apiWith((RequestOptions o) =>
          o.path.endsWith('/presign') ? _ticket(type: 'image/png') : _confirmed());
      final Uint8List bytes =
          Uint8List.fromList(List<int>.generate(3 * 1024 * 1024, (int i) => (i * 7) % 256));

      await api.upload(bytes: bytes, contentType: 'image/png');

      expect(storage.bodies.values.single, bytes);
      expect(storage.requests.single.headers[Headers.contentTypeHeader], 'image/png');
      expect(app.requests.first.data,
          <String, dynamic>{'contentType': 'image/png', 'sizeBytes': bytes.length});
    });

    test('a file over 10 MB, or an Illustrator file, is refused before a single request', () async {
      final OrderAttachmentApi api = apiWith(_server);

      await expectLater(
        api.upload(bytes: Uint8List(10 * 1024 * 1024 + 1), contentType: 'application/pdf'),
        _refusedFor(AttachmentRefusal.tooLarge),
      );
      await expectLater(
        api.upload(bytes: Uint8List(1024), contentType: 'application/postscript'),
        _refusedFor(AttachmentRefusal.wrongType),
      );

      expect(app.requests, isEmpty);
      expect(storage.requests, isEmpty);
    });

    test('a ticket with a lower ceiling stops before the PUT, and takes the upload back', () async {
      final OrderAttachmentApi api = apiWith(
          (RequestOptions o) => o.path.endsWith('/presign') ? _ticket(maxSizeBytes: 1024) : null);

      await expectLater(
        api.upload(bytes: Uint8List(2048), contentType: 'application/pdf'),
        _refusedFor(AttachmentRefusal.tooLarge),
      );

      expect(storage.requests, isEmpty);
      expect(calls(app), <String>[
        'POST /api/orders/attachments/presign',
        'DELETE /api/orders/attachments/file-1',
      ]);
    });

    test('a PUT storage refuses takes the upload back and reports the failure as it came', () async {
      final OrderAttachmentApi api = apiWith(_server, storageStatus: 403);

      await expectLater(
        api.upload(bytes: Uint8List(2048), contentType: 'application/pdf'),
        throwsA(isA<DioException>()),
      );

      expect(calls(app), <String>[
        'POST /api/orders/attachments/presign',
        'DELETE /api/orders/attachments/file-1',
      ]);
    });

    test("the server's refusal arrives as its reason, with the detail kept for logs", () async {
      final OrderAttachmentApi api = apiWith(
        (RequestOptions o) => <String, dynamic>{
          'title': 'Attachment refused',
          'code': 'TOO_MANY_WAITING',
          'detail': 'You already have 10 files waiting to be ordered',
        },
        statusOf: (RequestOptions o) => 422,
      );

      await expectLater(
        api.presign(contentType: 'application/pdf', sizeBytes: 2048),
        throwsA(isA<AttachmentRefusedException>()
            .having((AttachmentRefusedException e) => e.refusal, 'refusal',
                AttachmentRefusal.tooManyWaiting)
            .having((AttachmentRefusedException e) => e.detail, 'detail',
                'You already have 10 files waiting to be ordered')),
      );
    });

    test('a file the server refuses once it arrived — too large, or not really its type — arrives as that '
        'reason, and is not taken back: the server has deleted it already', () async {
      for (final MapEntry<String, AttachmentRefusal> refused in <String, AttachmentRefusal>{
        'TOO_LARGE': AttachmentRefusal.tooLarge,
        'WRONG_TYPE': AttachmentRefusal.wrongType,
      }.entries) {
        final OrderAttachmentApi api = apiWith(
          (RequestOptions o) => o.path.endsWith('/presign')
              ? _ticket()
              : <String, dynamic>{'code': refused.key, 'detail': 'Refused once it arrived'},
          statusOf: (RequestOptions o) => o.path.endsWith('/confirm') ? 422 : 200,
        );

        await expectLater(
          api.upload(bytes: Uint8List(2048), contentType: 'application/pdf'),
          _refusedFor(refused.value),
        );

        expect(calls(app), <String>[
          'POST /api/orders/attachments/presign',
          'POST /api/orders/attachments/file-1/confirm',
        ]);
        expect(storage.requests.single.method, 'PUT');
      }
    });

    test('too many uploads started in the last few minutes is a reason of its own, before any byte moves',
        () async {
      final OrderAttachmentApi api = apiWith(
        (RequestOptions o) =>
            <String, dynamic>{'code': 'TOO_MANY_UPLOADS', 'detail': 'Try again in a few minutes'},
        statusOf: (RequestOptions o) => 422,
      );

      await expectLater(
        api.upload(bytes: Uint8List(2048), contentType: 'application/pdf'),
        _refusedFor(AttachmentRefusal.tooManyUploads),
      );

      expect(calls(app), <String>['POST /api/orders/attachments/presign']);
      expect(storage.requests, isEmpty);
    });

    test('a 404 is not a refusal, and passes through untouched', () async {
      final OrderAttachmentApi api = apiWith(
        (RequestOptions o) => <String, dynamic>{'title': 'Attachment not found', 'detail': 'No such file'},
        statusOf: (RequestOptions o) => 404,
      );

      await expectLater(api.confirm('file-9'), throwsA(isA<DioException>()));
    });

    test('a code or a status this build has never heard of reads as unknown, not as a guess', () {
      expect(AttachmentRefusal.fromWire('SOMETHING_NEW'), AttachmentRefusal.unknown);
      expect(AttachmentRefusal.fromWire(''), AttachmentRefusal.unknown);
      expect(AttachmentRefusal.fromWire(null), AttachmentRefusal.unknown);
      expect(AttachmentRefusal.fromWire('REQUIRED'), AttachmentRefusal.fileRequired);
      expect(AttachmentUploadStatus.fromWire('ARCHIVED'), AttachmentUploadStatus.unknown);
      expect(
        AttachmentUpload.fromJson(<String, dynamic>{..._confirmed(), 'status': 'ARCHIVED'}).isReadyToOrder,
        isFalse,
      );
    });
  });

  group("an order's files", () {
    test('are read per order, each with its short-lived download URL', () async {
      final OrderAttachmentApi api = apiWith((RequestOptions o) => <dynamic>[
            <String, dynamic>{
              'fileId': 'file-1',
              'contentType': 'application/pdf',
              'sizeBytes': 2048,
              'attachedAt': '2026-09-13T09:05:00Z',
              'url': 'https://api-dev.youdrop.shop/order-attachments/a.pdf?X-Amz-Signature=a',
              'urlExpiresAt': '2026-09-13T09:15:00Z',
            },
            <String, dynamic>{
              'fileId': 'file-2',
              'contentType': 'image/png',
              'sizeBytes': 4096,
              'attachedAt': '2026-09-13T09:05:00Z',
              'url': 'https://api-dev.youdrop.shop/order-attachments/b.png?X-Amz-Signature=b',
              'urlExpiresAt': null,
            },
          ]);

      final List<OrderAttachment> files = await api.forOrder('order-1');

      expect(calls(app), <String>['GET /api/orders/order-1/attachments']);
      expect(files, hasLength(2));
      expect(files.first.isPdf, isTrue);
      expect(files.first.sizeBytes, 2048);
      expect(files.first.url, 'https://api-dev.youdrop.shop/order-attachments/a.pdf?X-Amz-Signature=a');
      expect(files.first.isExpiredAt(DateTime.utc(2026, 9, 13, 9, 14)), isFalse);
      expect(files.first.isExpiredAt(DateTime.utc(2026, 9, 13, 9, 15)), isTrue);
      expect(files.last.isImage, isTrue);
      expect(files.last.isExpiredAt(DateTime.utc(2030)), isFalse);
    });

    test('an upload is taken back by its id', () async {
      final OrderAttachmentApi api =
          apiWith((RequestOptions o) => null, statusOf: (RequestOptions o) => 204);

      await api.remove('file-1');

      expect(calls(app), <String>['DELETE /api/orders/attachments/file-1']);
    });

    test('taking back a file already on an order is refused with that reason', () async {
      final OrderAttachmentApi api = apiWith(
        (RequestOptions o) => <String, dynamic>{'code': 'ALREADY_ATTACHED', 'detail': 'On an order'},
        statusOf: (RequestOptions o) => 422,
      );

      await expectLater(api.remove('file-1'), _refusedFor(AttachmentRefusal.alreadyAttached));
    });
  });
}
