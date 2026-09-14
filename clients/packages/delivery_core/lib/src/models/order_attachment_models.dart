/// Why a customer's file for a service order was refused — by [OrderAttachmentApi] before any byte
/// moved, or by order-manager's 422, whose `code` this is.
///
/// Screens put each into words in the customer's language; [unknown] is a code this build has never
/// heard of, which a screen shows as a plain failure rather than guessing at a reason.
enum AttachmentRefusal {
  /// Not a PDF, JPEG or PNG: as picked, or — found by the server at confirm — as stored, or as its
  /// bytes, whatever its name says. Refused at confirm, the upload is already deleted.
  wrongType('WRONG_TYPE'),

  /// No bytes at all.
  empty('EMPTY'),

  /// Over the size limit: as picked, or — found by the server at confirm — as it arrived. Refused at
  /// confirm, the upload is already deleted and its waiting slot free.
  tooLarge('TOO_LARGE'),

  /// The customer already holds as many uploads waiting for an order as the server allows.
  tooManyWaiting('TOO_MANY_WAITING'),

  /// The customer started as many uploads in the last few minutes as the server allows — taken-back ones
  /// included, because an upload link keeps working until it expires. One frees within minutes.
  tooManyUploads('TOO_MANY_UPLOADS'),

  /// The upload never arrived in full; send it again.
  notUploaded('NOT_UPLOADED'),

  /// No longer available — never ordered in time, or changed in storage since it was confirmed; send
  /// it again.
  expired('EXPIRED'),

  /// Already on an order.
  alreadyAttached('ALREADY_ATTACHED'),

  /// More files than one order may carry.
  tooManyFiles('TOO_MANY_FILES'),

  /// The same file twice on one order.
  duplicateFile('DUPLICATE_FILE'),

  /// The offer takes no files.
  notAccepted('NOT_ACCEPTED'),

  /// The offer needs a file, and none was sent.
  fileRequired('REQUIRED'),

  /// A file that is not the customer's own, or does not exist.
  unknownFile('UNKNOWN_FILE'),

  /// A code this build does not know.
  unknown('');

  const AttachmentRefusal(this.wire);

  /// The server's spelling.
  final String wire;

  /// The refusal a 422's `code` names; [unknown] for anything else.
  static AttachmentRefusal fromWire(Object? code) {
    for (final AttachmentRefusal refusal in values) {
      if (refusal != unknown && refusal.wire == code) {
        return refusal;
      }
    }
    return unknown;
  }
}

/// A customer's file refused; [refusal] says why.
class AttachmentRefusedException implements Exception {
  const AttachmentRefusedException(this.refusal, {this.detail});

  final AttachmentRefusal refusal;

  /// The server's English detail, when the server refused. For logs only — the words on a screen
  /// come from [refusal], in the customer's language.
  final String? detail;

  @override
  String toString() => detail == null
      ? 'AttachmentRefusedException(${refusal.name})'
      : 'AttachmentRefusedException(${refusal.name}: $detail)';
}

/// Where one of the customer's uploads stands.
enum AttachmentUploadStatus {
  /// An upload URL was issued; the upload is not confirmed.
  pending,

  /// Confirmed, and ready to go with an order.
  uploaded,

  /// On an order.
  attached,

  /// Gone: taken back, too large, not really its type, changed in storage since it was confirmed, or
  /// never ordered in time.
  deleted,

  /// A status this build does not know.
  unknown;

  static AttachmentUploadStatus fromWire(Object? value) => switch (value) {
        'PENDING' => pending,
        'UPLOADED' => uploaded,
        'ATTACHED' => attached,
        'DELETED' => deleted,
        _ => unknown,
      };
}

/// The first step's answer: a one-shot URL to PUT one file to.
class AttachmentUploadTicket {
  const AttachmentUploadTicket({
    required this.fileId,
    required this.uploadUrl,
    required this.contentType,
    required this.maxSizeBytes,
    this.expiresAt,
  });

  factory AttachmentUploadTicket.fromJson(Map<String, dynamic> json) => AttachmentUploadTicket(
        fileId: json['fileId'] as String,
        uploadUrl: json['uploadUrl'] as String,
        contentType: json['contentType'] as String,
        maxSizeBytes: (json['maxSizeBytes'] as num?)?.toInt() ?? 0,
        expiresAt: _instant(json['expiresAt']),
      );

  final String fileId;

  /// Used exactly as issued: its signature covers the host, the path and the query.
  final String uploadUrl;

  /// The Content-Type the PUT must carry — the one the server checked.
  final String contentType;

  /// The server's size ceiling in bytes; 0 when it sent none.
  final int maxSizeBytes;

  /// When the URL stops working; after that, ask for another.
  final DateTime? expiresAt;
}

/// One of the customer's own uploads, as the server now sees it.
class AttachmentUpload {
  const AttachmentUpload({
    required this.fileId,
    required this.contentType,
    required this.status,
    this.sizeBytes,
    this.createdAt,
    this.attachedAt,
  });

  factory AttachmentUpload.fromJson(Map<String, dynamic> json) => AttachmentUpload(
        fileId: json['fileId'] as String,
        contentType: json['contentType'] as String,
        status: AttachmentUploadStatus.fromWire(json['status']),
        sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
        createdAt: _instant(json['createdAt']),
        attachedAt: _instant(json['attachedAt']),
      );

  final String fileId;
  final String contentType;
  final AttachmentUploadStatus status;

  /// Measured by the server when the upload was confirmed; null before that.
  final int? sizeBytes;
  final DateTime? createdAt;
  final DateTime? attachedAt;

  /// Confirmed and on no order yet: this [fileId] can be sent with the order being placed.
  bool get isReadyToOrder => status == AttachmentUploadStatus.uploaded;
}

/// A file on an order, with a download URL that works until [urlExpiresAt].
///
/// The URL is short-lived on purpose — it is a customer's document in the hands of whoever holds it —
/// so a screen reads the list again when it needs the file rather than keeping a URL for later.
class OrderAttachment {
  const OrderAttachment({
    required this.fileId,
    required this.contentType,
    required this.url,
    this.sizeBytes,
    this.attachedAt,
    this.urlExpiresAt,
  });

  factory OrderAttachment.fromJson(Map<String, dynamic> json) => OrderAttachment(
        fileId: json['fileId'] as String,
        contentType: json['contentType'] as String,
        url: json['url'] as String,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
        attachedAt: _instant(json['attachedAt']),
        urlExpiresAt: _instant(json['urlExpiresAt']),
      );

  final String fileId;
  final String contentType;
  final String url;
  final int? sizeBytes;
  final DateTime? attachedAt;
  final DateTime? urlExpiresAt;

  bool get isPdf => contentType == 'application/pdf';

  bool get isImage => contentType.startsWith('image/');

  /// Whether [url] has stopped working by [now].
  bool isExpiredAt(DateTime now) {
    final DateTime? expiry = urlExpiresAt;
    return expiry != null && !now.isBefore(expiry);
  }
}

DateTime? _instant(Object? value) => value is String ? DateTime.tryParse(value) : null;
