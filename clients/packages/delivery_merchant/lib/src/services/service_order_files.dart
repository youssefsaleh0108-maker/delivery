/// A customer's files on a service order, as the provider's order detail lists and opens them.
///
/// An interface, not a client. The client that serves these files — the order attachment service's
/// `OrderAttachmentApi.forOrder` (`GET /api/orders/{id}/attachments`, readable by the order's shop,
/// its customer and support) — is being built on its own branch and is not in this one. So the detail
/// depends on the shape that call answers with, and the host hands over something that makes the
/// call. A host that hands over nothing gets no files section at all, rather than a section that can
/// never load.
library;

/// One file on an order, with a link that works for a short while. Mirrors `OrderAttachment`.
///
/// The link is short-lived on purpose — it is a customer's document in the hands of whoever holds it —
/// so the detail reads the list again for a fresh link when the one it holds has expired, rather than
/// keeping links for later.
class ServiceOrderFile {
  const ServiceOrderFile({
    required this.fileId,
    required this.contentType,
    required this.url,
    this.sizeBytes,
    this.urlExpiresAt,
  });

  final String fileId;

  /// `application/pdf`, `image/jpeg` or `image/png`: the only types an order takes.
  final String contentType;

  final String url;
  final int? sizeBytes;
  final DateTime? urlExpiresAt;

  bool get isImage => contentType.startsWith('image/');

  /// Whether [url] has stopped working by [now].
  bool isExpiredAt(DateTime now) {
    final DateTime? expiry = urlExpiresAt;
    return expiry != null && !now.isBefore(expiry);
  }
}

/// Lists a service order's files, each with a fresh link.
abstract interface class ServiceOrderFiles {
  /// The files on [orderId], each with a link that works for now. Throws when they cannot be read.
  Future<List<ServiceOrderFile>> forOrder(String orderId);
}
