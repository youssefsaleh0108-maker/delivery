import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';

import 'service_order_files.dart';

/// [ServiceOrderFiles] over order-manager's attachment endpoints, through delivery_core's
/// [OrderAttachmentApi]: what main.dart hands the customer shell.
///
/// A thin adapter on purpose. The steps and their rules — refuse what can be seen before a byte
/// moves, presign, PUT the bytes to storage on a bare client, confirm, take back a half-made upload —
/// belong to the client, and are pinned by its own tests. This only turns the client's
/// [AttachmentRefusedException] into the screens' [ServiceFileRefused], keeping the refusal exactly
/// as the client named it. Every other failure — no connection, a 5xx — is thrown unchanged, so a
/// screen can still tell "refused" from "could not send".
class OrderAttachmentFiles implements ServiceOrderFiles {
  OrderAttachmentFiles(this._api);

  final OrderAttachmentApi _api;

  @override
  Future<String> upload({
    required Uint8List bytes,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) =>
      _refusals(() async {
        final AttachmentUpload done = await _api.upload(
          bytes: bytes,
          contentType: contentType,
          onSendProgress: onProgress,
        );
        return done.fileId;
      });

  @override
  Future<void> remove(String fileId) => _refusals(() => _api.remove(fileId));

  @override
  Future<List<OrderAttachment>> forOrder(String orderId) => _api.forOrder(orderId);

  static Future<T> _refusals<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on AttachmentRefusedException catch (e) {
      throw ServiceFileRefused(e.refusal);
    }
  }
}
