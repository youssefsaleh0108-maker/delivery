import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/order_attachment_models.dart';

/// A customer's files on a service order — the design a print shop is asked to print — over
/// order-manager's attachment endpoints.
///
/// The flow the order screen drives: [precheck] a picked file the moment it is chosen, [upload] it —
/// presign, PUT the bytes straight to storage, confirm — and send the confirmed
/// [AttachmentUpload.fileId]s with the order; [remove] takes one back before ordering. The provider's
/// and back office's screens read an order's files with [forOrder].
///
/// Every refusal the server answers with a 422 arrives as an [AttachmentRefusedException]; one this
/// client can already see — the wrong type, over the size — is thrown before any byte moves.
class OrderAttachmentApi {
  OrderAttachmentApi(this._dio, {Dio Function()? uploadClient})
      : _uploadClient = uploadClient ?? Dio.new;

  final Dio _dio;

  /// Builds the client the file's bytes are PUT with. A fresh, bare Dio by default — see [upload] for
  /// why it must not be the app's own. Injectable so a test can see the PUT.
  final Dio Function() _uploadClient;

  /// How many files one order may carry: the owner's default, and order-manager's
  /// `delivery.attachments.max-files-per-order`. The server enforces it when the order is placed.
  static const int maxFilesPerOrder = 3;

  /// The largest file sent, 10 MB: order-manager's `delivery.attachments.max-size-bytes`. A ticket
  /// carries the server's own figure, which wins if the two ever differ.
  static const int maxSizeBytes = 10 * 1024 * 1024;

  /// PDF, JPEG or PNG: platform-storage's list for order attachments.
  static const List<String> allowedContentTypes = <String>[
    'application/pdf',
    'image/jpeg',
    'image/png',
  ];

  static const String _base = '/api/orders/attachments';

  /// The content type to declare for a picked file, from its name; null for any other kind of file,
  /// which [precheck] then refuses — an `.ai` or a `.zip` never gets an upload URL.
  static String? contentTypeForFileName(String fileName) {
    final int dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) {
      return null;
    }
    return switch (fileName.substring(dot + 1).toLowerCase()) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      _ => null,
    };
  }

  /// What the server would refuse about this file, known without asking it; null when nothing is.
  static AttachmentRefusal? precheck({required String contentType, required int sizeBytes}) {
    if (!allowedContentTypes.contains(contentType.trim().toLowerCase())) {
      return AttachmentRefusal.wrongType;
    }
    if (sizeBytes < 1) {
      return AttachmentRefusal.empty;
    }
    if (sizeBytes > maxSizeBytes) {
      return AttachmentRefusal.tooLarge;
    }
    return null;
  }

  /// Step 1: a one-shot URL to PUT one file of [sizeBytes] to.
  Future<AttachmentUploadTicket> presign({
    required String contentType,
    required int sizeBytes,
  }) async {
    final Response<dynamic> response = await _refusals(() => _dio.post<dynamic>(
          '$_base/presign',
          data: <String, dynamic>{'contentType': contentType, 'sizeBytes': sizeBytes},
        ));
    return AttachmentUploadTicket.fromJson(response.data as Map<String, dynamic>);
  }

  /// Step 3: the bytes landed. (Step 2 is the PUT, which never touches the backend.)
  Future<AttachmentUpload> confirm(String fileId) async {
    final Response<dynamic> response =
        await _refusals(() => _dio.post<dynamic>('$_base/$fileId/confirm'));
    return AttachmentUpload.fromJson(response.data as Map<String, dynamic>);
  }

  /// All three steps: refuse what [precheck] can see, presign, PUT the bytes, confirm. Returns the
  /// upload, ready to send with the order.
  ///
  /// The bytes go up exactly as chosen — no `ImagePrep`, unlike every photo upload in this package.
  /// This is a design a shop will print: shrinking or re-encoding it would quietly print a worse file
  /// than the customer picked. A file over the limit is refused instead, so the customer knows.
  ///
  /// When the upload cannot finish — the ticket's ceiling is lower than the file, or the PUT fails —
  /// the half-made upload is taken back, so it does not hold one of the customer's waiting slots
  /// until the server's sweep reaches it.
  ///
  /// [onSendProgress] reports the PUT, for the picker's progress bar.
  Future<AttachmentUpload> upload({
    required Uint8List bytes,
    required String contentType,
    ProgressCallback? onSendProgress,
  }) async {
    final AttachmentRefusal? refused = precheck(contentType: contentType, sizeBytes: bytes.length);
    if (refused != null) {
      throw AttachmentRefusedException(refused);
    }

    final AttachmentUploadTicket ticket =
        await presign(contentType: contentType, sizeBytes: bytes.length);
    if (ticket.maxSizeBytes > 0 && bytes.length > ticket.maxSizeBytes) {
      await _forget(ticket.fileId);
      throw const AttachmentRefusedException(AttachmentRefusal.tooLarge);
    }

    // A separate, bare Dio: S3-compatible storage rejects a presigned request that also carries an
    // Authorization header — two auth mechanisms on one request. The Content-Type is the ticket's,
    // the one the server checked; the URL is used exactly as issued, since its signature covers it.
    try {
      await _uploadClient().put<void>(
        ticket.uploadUrl,
        data: Stream<List<int>>.fromIterable(<List<int>>[bytes]),
        onSendProgress: onSendProgress,
        options: Options(headers: <String, dynamic>{
          'Content-Type': ticket.contentType,
          Headers.contentLengthHeader: bytes.length,
        }),
      );
    } on DioException {
      await _forget(ticket.fileId);
      rethrow;
    }

    return confirm(ticket.fileId);
  }

  /// Takes back an upload that is on no order yet — the picker's Remove. A file already on an order
  /// stays with it ([AttachmentRefusal.alreadyAttached]).
  Future<void> remove(String fileId) async {
    await _refusals(() => _dio.delete<dynamic>('$_base/$fileId'));
  }

  /// The files on an order, each with a download URL that works for a few minutes. For the order's
  /// customer, its provider, and back office — whose every read the server records. Anyone else,
  /// a rider included, is refused by the server.
  Future<List<OrderAttachment>> forOrder(String orderId) async {
    final Response<dynamic> response = await _dio.get<dynamic>('/api/orders/$orderId/attachments');
    return (response.data as List<dynamic>)
        .map((dynamic e) => OrderAttachment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------- internals

  /// A half-made upload nothing will use, taken back. Failure is ignored: the server sweeps it within
  /// a day regardless, and a second failure here must not hide the first.
  Future<void> _forget(String fileId) async {
    try {
      await _dio.delete<dynamic>('$_base/$fileId');
    } on DioException {
      // Swept by the server within a day either way.
    }
  }

  /// A 422 naming a refusal, as [AttachmentRefusedException]; any other failure unchanged.
  static Future<Response<dynamic>> _refusals(Future<Response<dynamic>> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final Object? body = e.response?.data;
      if (e.response?.statusCode == 422 && body is Map<String, dynamic> && body['code'] != null) {
        throw AttachmentRefusedException(
          AttachmentRefusal.fromWire(body['code']),
          detail: body['detail'] as String?,
        );
      }
      rethrow;
    }
  }
}
