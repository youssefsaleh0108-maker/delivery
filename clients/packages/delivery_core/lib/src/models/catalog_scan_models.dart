/// Merchant Blitz: a catalogue built from shelf photos.
///
/// Mirrors product-service's `CatalogScanController` (`/api/products/scans`). A scan holds a few
/// shelf photos and, once analysed, the lines a vision provider read off them; the merchant then
/// accepts each line as a DRAFT product, corrects it, or skips it. Nothing a scan does publishes
/// anything.
///
/// Every enum here follows the suite's enum contract: an unknown wire value becomes an explicit
/// `unknown` member rather than a guess, so a status this build has never heard of cannot be
/// mistaken for a real one — and the screen treats it as "stop polling, show a retry".
library;

/// Where a scan is in its short life.
enum CatalogScanStatus {
  uploading('UPLOADING'),
  analyzing('ANALYZING'),
  complete('COMPLETE'),
  failed('FAILED'),
  unknown('');

  const CatalogScanStatus(this.wireValue);

  final String wireValue;

  static CatalogScanStatus fromWire(String? value) {
    for (final CatalogScanStatus status in CatalogScanStatus.values) {
      if (status != CatalogScanStatus.unknown && status.wireValue == value) {
        return status;
      }
    }
    return CatalogScanStatus.unknown;
  }
}

/// Why a scan failed, as a code the screen words in the merchant's language.
enum ScanFailure {
  refused('REFUSED'),
  unreadablePhoto('UNREADABLE_PHOTO'),
  providerError('PROVIDER_ERROR'),
  busy('BUSY'),
  interrupted('INTERRUPTED'),
  unknown('');

  const ScanFailure(this.wireValue);

  final String wireValue;

  /// Null when the server sent none — a scan that has not failed has no reason.
  static ScanFailure? maybeFromWire(String? value) {
    if (value == null) return null;
    for (final ScanFailure failure in ScanFailure.values) {
      if (failure != ScanFailure.unknown && failure.wireValue == value) {
        return failure;
      }
    }
    return ScanFailure.unknown;
  }
}

/// What the merchant decided about one line.
enum ScanLineStatus {
  pending('PENDING'),
  accepted('ACCEPTED'),
  rejected('REJECTED'),
  unknown('');

  const ScanLineStatus(this.wireValue);

  final String wireValue;

  static ScanLineStatus fromWire(String? value) {
    for (final ScanLineStatus status in ScanLineStatus.values) {
      if (status != ScanLineStatus.unknown && status.wireValue == value) {
        return status;
      }
    }
    return ScanLineStatus.unknown;
  }
}

/// One shelf photo on a scan.
class ScanPhoto {
  const ScanPhoto({
    required this.fileId,
    required this.position,
    required this.uploaded,
    this.imageUrl,
  });

  factory ScanPhoto.fromJson(Map<String, dynamic> json) => ScanPhoto(
        fileId: json['fileId'] as String,
        position: (json['position'] as num?)?.toInt() ?? 0,
        uploaded: json['status'] == 'UPLOADED',
        imageUrl: json['imageUrl'] as String?,
      );

  final String fileId;
  final int position;

  /// Confirmed by the server. Only confirmed photos are read.
  final bool uploaded;

  /// Loadable once confirmed; null while the upload is pending.
  final String? imageUrl;
}

/// Where a line sits on its photo, as fractions of the photo's width and height.
class ScanBox {
  const ScanBox({required this.left, required this.top, required this.width, required this.height});

  /// Null for anything that is not a box that fits inside its photo — a tag is then simply not
  /// drawn, rather than drawn somewhere the product is not.
  static ScanBox? maybeFromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final double? left = (json['left'] as num?)?.toDouble();
    final double? top = (json['top'] as num?)?.toDouble();
    final double? width = (json['width'] as num?)?.toDouble();
    final double? height = (json['height'] as num?)?.toDouble();
    if (left == null || top == null || width == null || height == null) return null;
    if (left < 0 || top < 0 || width <= 0 || height <= 0) return null;
    if (left + width > 1.0001 || top + height > 1.0001) return null;
    return ScanBox(left: left, top: top, width: width, height: height);
  }

  final double left;
  final double top;
  final double width;
  final double height;
}

/// One product a provider read off a photo, and what the merchant did with it.
class ScanLine {
  const ScanLine({
    required this.id,
    required this.name,
    required this.confidence,
    required this.status,
    this.photoFileId,
    this.brand,
    this.size,
    this.categoryId,
    this.priceGuess,
    this.price,
    this.box,
    this.productId,
  });

  factory ScanLine.fromJson(Map<String, dynamic> json) => ScanLine(
        id: json['id'] as String,
        photoFileId: json['photoFileId'] as String?,
        name: json['name'] as String? ?? '',
        brand: json['brand'] as String?,
        size: json['size'] as String?,
        categoryId: json['categoryId'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        priceGuess: (json['priceGuess'] as num?)?.toDouble(),
        price: (json['price'] as num?)?.toDouble(),
        box: ScanBox.maybeFromJson(json['box']),
        status: ScanLineStatus.fromWire(json['status'] as String?),
        productId: json['productId'] as String?,
      );

  final String id;
  final String? photoFileId;
  final String name;
  final String? brand;
  final String? size;
  final String? categoryId;

  /// 0 to 1: the provider's own certainty about the name.
  final double confidence;

  /// The provider's GUESS at a shelf price, in USD. Never a price the merchant set, and never sent
  /// back as one — the review screen offers it as a hint the merchant has to choose to use.
  final double? priceGuess;

  /// The price the merchant set, once they have.
  final double? price;

  final ScanBox? box;
  final ScanLineStatus status;

  /// The DRAFT product an accepted line became.
  final String? productId;

  /// Below this the screen marks a line as one to check.
  static const double doubtfulBelow = 0.6;

  bool get isDoubtful => confidence < doubtfulBelow;
}

/// A scan as the server reports it.
class CatalogScan {
  const CatalogScan({
    required this.id,
    required this.status,
    required this.photos,
    required this.lines,
    this.storeId,
    this.provider,
    this.sample = false,
    this.failure,
    this.maxPhotos = 6,
    this.attemptsLeft = 0,
    this.scansLeftToday,
  });

  factory CatalogScan.fromJson(Map<String, dynamic> json) => CatalogScan(
        id: json['id'] as String,
        storeId: json['storeId'] as String?,
        status: CatalogScanStatus.fromWire(json['status'] as String?),
        provider: json['provider'] as String?,
        sample: json['sample'] as bool? ?? false,
        failure: ScanFailure.maybeFromWire(json['failureCode'] as String?),
        maxPhotos: (json['maxPhotos'] as num?)?.toInt() ?? 6,
        attemptsLeft: (json['attemptsLeft'] as num?)?.toInt() ?? 0,
        scansLeftToday: (json['scansLeftToday'] as num?)?.toInt(),
        photos: ((json['photos'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic p) => ScanPhoto.fromJson(p as Map<String, dynamic>))
            .toList(),
        lines: ((json['items'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic l) => ScanLine.fromJson(l as Map<String, dynamic>))
            .toList(),
      );

  final String id;
  final String? storeId;
  final CatalogScanStatus status;

  /// Which provider produced the lines: `FAKE` or `CLAUDE`. Null until complete.
  final String? provider;

  /// True when the lines are sample data, not a reading of these photos. The screen must say so.
  final bool sample;

  final ScanFailure? failure;
  final int maxPhotos;
  final int attemptsLeft;

  /// Null when an older server did not say — the screen then shows nothing rather than a number.
  final int? scansLeftToday;

  final List<ScanPhoto> photos;
  final List<ScanLine> lines;

  List<ScanPhoto> get uploadedPhotos => photos.where((ScanPhoto p) => p.uploaded).toList();

  List<ScanLine> get pendingLines =>
      lines.where((ScanLine l) => l.status == ScanLineStatus.pending).toList();

  bool get canRetry => status == CatalogScanStatus.failed && attemptsLeft > 0;
}

/// One line the merchant is accepting, with the name, price and section they settled on.
class ScanLineDecision {
  const ScanLineDecision({
    required this.lineId,
    required this.name,
    required this.price,
    this.categoryId,
  });

  final String lineId;
  final String name;

  /// USD, at most two decimals — the review screen refuses anything else before it gets here.
  final double price;

  final String? categoryId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'itemId': lineId,
        'name': name,
        // Sent as the two-decimal string the merchant typed, so no binary float stands between the
        // field and the server's decimal column.
        'price': price.toStringAsFixed(2),
        if (categoryId != null) 'categoryId': categoryId,
      };
}
