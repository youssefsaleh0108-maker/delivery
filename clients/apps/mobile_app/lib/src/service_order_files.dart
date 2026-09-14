import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:file_selector/file_selector.dart';

/// A customer's files on a service order — the design a print shop is asked to print — as the
/// customer's screens need them: sent before the order is placed, taken back if the customer changes
/// their mind, and read again from the order once it is placed.
///
/// An interface over delivery_core's [OrderAttachmentApi] rather than the client itself, so the
/// screens keep a small vocabulary — an upload answers a file id, a refusal is a [ServiceFileRefused]
/// — and their tests can answer in-process. `OrderAttachmentFiles` is the adapter main.dart hands the
/// customer shell.
///
/// Refusals keep the attachment client's own type, [AttachmentRefusal]. Twelve of its codes are the
/// wire values [ServiceOrderRefusal] carries when a placement names a refused file, and the two read
/// in the same words (`attachmentRefusalMessage`). The thirteenth — too many uploads in a few minutes
/// — is an upload's alone: a placement never answers it, so it has no placement counterpart.
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

  /// Takes back an upload that is on no order yet: the file row's Remove. A refusal arrives as
  /// [ServiceFileRefused] — [AttachmentRefusal.alreadyAttached] for a file an order already carries.
  Future<void> remove(String fileId);

  /// The files on a placed order, each with a link that works for a few minutes — the customer's own
  /// "Your files". Read again right before one is opened: a link kept for later stops working.
  Future<List<OrderAttachment>> forOrder(String orderId);
}

/// A customer's file refused, before or after it was sent; [refusal] says why.
class ServiceFileRefused implements Exception {
  const ServiceFileRefused(this.refusal);

  final AttachmentRefusal refusal;

  @override
  String toString() => 'ServiceFileRefused(${refusal.name})';
}

/// How many files one order may carry: the attachment client's figure, which is order-manager's
/// `delivery.attachments.max-files-per-order`. The server enforces it at placement.
const int serviceFilesPerOrder = OrderAttachmentApi.maxFilesPerOrder;

/// The content type to declare for a picked file: the one the platform reported when it is one the
/// server takes, otherwise the one its name implies ([OrderAttachmentApi.contentTypeForFileName]) —
/// null for anything that is not a PDF, JPEG or PNG, which is then refused before any byte moves.
String? serviceFileContentType(String fileName, {String? reported}) {
  final String? declared = reported?.trim().toLowerCase();
  if (declared != null && OrderAttachmentApi.allowedContentTypes.contains(declared)) {
    return declared;
  }
  return OrderAttachmentApi.contentTypeForFileName(fileName);
}

/// What the server would refuse about a file, known without asking it; null when nothing is. The
/// order screen asks this the moment a file is picked, so an `.ai` design or a 40 MB scan is refused
/// in words at once rather than after an upload. A file of no type the server takes is
/// [AttachmentRefusal.wrongType]; the rest is [OrderAttachmentApi.precheck]'s answer.
AttachmentRefusal? precheckServiceFile({required String? contentType, required int sizeBytes}) =>
    contentType == null
        ? AttachmentRefusal.wrongType
        : OrderAttachmentApi.precheck(contentType: contentType, sizeBytes: sizeBytes);

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
