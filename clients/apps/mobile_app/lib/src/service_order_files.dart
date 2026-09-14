import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:file_selector/file_selector.dart';

/// A customer's file on its way to a service order — the design a print shop is asked to print —
/// as the order screen needs it: sent before the order is placed, and taken back if the customer
/// changes their mind.
///
/// An interface rather than delivery_core's `OrderAttachmentApi` because that client lives on its own
/// branch (feat/services-attachments) and had not merged into the base these screens were built on.
/// The merge connects the two with an adapter, and nothing else in the screens changes:
///
/// ```dart
/// class OrderAttachmentFiles implements ServiceOrderFiles {
///   OrderAttachmentFiles(this._api);
///   final OrderAttachmentApi _api;
///
///   @override
///   Future<String> upload({required Uint8List bytes, required String contentType,
///       void Function(int sent, int total)? onProgress}) async {
///     try {
///       final AttachmentUpload done = await _api.upload(
///           bytes: bytes, contentType: contentType, onSendProgress: onProgress);
///       return done.fileId;
///     } on AttachmentRefusedException catch (e) {
///       throw ServiceFileRefused(
///           ServiceOrderRefusal.maybeFromWire(e.refusal.wire) ?? ServiceOrderRefusal.unknown);
///     }
///   }
///
///   @override
///   Future<void> remove(String fileId) => _api.remove(fileId); // refusals mapped the same way
/// }
/// ```
///
/// and main.dart passes `serviceFiles: OrderAttachmentFiles(OrderAttachmentApi(_dio))` to
/// `CustomerShell`. Until then the shell has none, and an offer that needs a file is not offered for
/// ordering: a picker that cannot send anything would be a dead control, and the placement it led to
/// would be refused (ATTACHMENTS_UNAVAILABLE) anyway.
///
/// Refusals are typed as [ServiceOrderRefusal], whose file codes are the attachment service's own
/// wire values, so an upload's refusal and a placement's refusal of the same file read alike.
abstract interface class ServiceOrderFiles {
  /// Sends one file for an order not yet placed — presign, PUT the bytes, confirm — and answers the
  /// confirmed file id to place the order with.
  ///
  /// A refusal arrives as [ServiceFileRefused]. Anything else — a network failure — is thrown as it
  /// is. [onProgress] reports the bytes sent, for the row's progress bar.
  Future<String> upload({
    required Uint8List bytes,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  });

  /// Takes back an upload that is on no order yet: the file row's Remove.
  Future<void> remove(String fileId);
}

/// A customer's file refused, before or after it was sent; [refusal] says why.
class ServiceFileRefused implements Exception {
  const ServiceFileRefused(this.refusal);

  final ServiceOrderRefusal refusal;

  @override
  String toString() => 'ServiceFileRefused(${refusal.name})';
}

/// How many files one order may carry: the owner's default, and order-manager's
/// `delivery.attachments.max-files-per-order`. The server enforces it at placement.
const int serviceFilesPerOrder = 3;

/// The largest file sent, 10 MB: order-manager's `delivery.attachments.max-size-bytes`.
const int serviceFileMaxBytes = 10 * 1024 * 1024;

const Set<String> _allowedTypes = <String>{'application/pdf', 'image/jpeg', 'image/png'};

/// The content type to declare for a picked file: the one the platform reported when it is one the
/// server takes, otherwise the one its name implies — null for anything that is not a PDF, JPEG or
/// PNG, which is then refused before any byte moves. Mirrors `OrderAttachmentApi.contentTypeForFileName`.
String? serviceFileContentType(String fileName, {String? reported}) {
  final String? declared = reported?.trim().toLowerCase();
  if (declared != null && _allowedTypes.contains(declared)) return declared;
  final int dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return null;
  return switch (fileName.substring(dot + 1).toLowerCase()) {
    'pdf' => 'application/pdf',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    _ => null,
  };
}

/// What the server would refuse about a file, known without asking it; null when nothing is. The
/// order screen asks this the moment a file is picked, so an `.ai` design or a 40 MB scan is refused
/// in words at once rather than after an upload. Mirrors `OrderAttachmentApi.precheck`.
ServiceOrderRefusal? precheckServiceFile({required String? contentType, required int sizeBytes}) {
  if (contentType == null || !_allowedTypes.contains(contentType)) {
    return ServiceOrderRefusal.fileWrongType;
  }
  if (sizeBytes < 1) return ServiceOrderRefusal.fileEmpty;
  if (sizeBytes > serviceFileMaxBytes) return ServiceOrderRefusal.fileTooLarge;
  return null;
}

/// A file the customer picked: its name, its size, and a way to read it — read only once the file
/// has passed [precheckServiceFile], so a file too large to send is never loaded into memory.
class PickedServiceFile {
  const PickedServiceFile({
    required this.name,
    required this.sizeBytes,
    required this.readBytes,
    this.mimeType,
  });

  final String name;
  final int sizeBytes;

  /// What the platform says the file is; null on several platforms.
  final String? mimeType;
  final Future<Uint8List> Function() readBytes;
}

/// Opens the platform's file picker for a design.
typedef ServiceFilePicker = Future<PickedServiceFile?> Function();

/// The picker the app uses: file_selector, as the partner documents step does, narrowed to the types
/// the server takes. A cancelled pick is null.
Future<PickedServiceFile?> pickServiceFile() async {
  const XTypeGroup designs = XTypeGroup(
    label: 'PDF, JPG, PNG',
    extensions: <String>['pdf', 'jpg', 'jpeg', 'png'],
    mimeTypes: <String>['application/pdf', 'image/jpeg', 'image/png'],
  );
  final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[designs]);
  if (file == null) return null;
  return PickedServiceFile(
    name: file.name,
    sizeBytes: await file.length(),
    mimeType: file.mimeType,
    readBytes: file.readAsBytes,
  );
}
