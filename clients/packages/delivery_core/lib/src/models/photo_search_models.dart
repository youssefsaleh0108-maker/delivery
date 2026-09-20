import 'package:dio/dio.dart';

import 'catalog_models.dart';
import 'item_search_models.dart';

/// What the app may offer this account in the way of photo search —
/// `PhotoSearchDtos.PhotoCapabilitiesResponse`.
///
/// [photoSearch] is true only for a customer, while customer photo search is switched on and a real
/// reader is configured; the app draws its camera only then. Until the owner switches recognition on it
/// is false, and the customer never meets a camera that cannot work, nor sample results.
class PhotoSearchCapabilities {
  const PhotoSearchCapabilities({
    required this.photoSearch,
    required this.photosLeftToday,
    required this.maxPhotoBytes,
  });

  /// Nothing offered: what a failed read of the capabilities means too.
  static const PhotoSearchCapabilities none =
      PhotoSearchCapabilities(photoSearch: false, photosLeftToday: 0, maxPhotoBytes: 0);

  final bool photoSearch;

  /// The photo searches left over the rolling day; 0 when there is no photo search.
  final int photosLeftToday;

  /// The largest photo the server accepts.
  final int maxPhotoBytes;

  factory PhotoSearchCapabilities.fromJson(Map<String, dynamic> json) => PhotoSearchCapabilities(
        photoSearch: json['photoSearch'] == true,
        photosLeftToday: (json['photosLeftToday'] as num?)?.toInt() ?? 0,
        maxPhotoBytes: (json['maxPhotoBytes'] as num?)?.toInt() ?? 0,
      );
}

/// What a photo was read as — `PhotoSearchDtos.UnderstoodResponse`: the words, never the photo.
class PhotoUnderstanding {
  const PhotoUnderstanding({
    required this.isProduct,
    this.name,
    this.nameAr,
    this.brand,
    this.size,
    this.barcode,
  });

  /// False for a photo of no product; every other field is then null.
  final bool isProduct;
  final String? name;
  final String? nameAr;
  final String? brand;
  final String? size;

  /// A barcode whose check digit the server verified, or null.
  final String? barcode;

  /// The words to show and to search by, in the order the customer would recognise them: the name as
  /// on the pack, else its Arabic name, else the brand. Null when there are none.
  String? get label {
    for (final String? words in <String?>[name, nameAr, brand]) {
      if (words != null && words.trim().isNotEmpty) return words.trim();
    }
    return null;
  }

  factory PhotoUnderstanding.fromJson(Map<String, dynamic> json) => PhotoUnderstanding(
        isProduct: json['isProduct'] == true,
        name: json['name'] as String?,
        nameAr: json['nameAr'] as String?,
        brand: json['brand'] as String?,
        size: json['size'] as String?,
        barcode: json['barcode'] as String?,
      );
}

/// The first page of a search by photo — `PhotoSearchDtos.PhotoSearchResponse`: the item search's page,
/// with what the photo was read as.
///
/// The next pages are the text search's, asked with [nextQuery] ([StoreApi.searchItems]), so the photo
/// is sent once. [similar] is true when nothing matched the product itself and these shops sell the
/// same kind of thing.
class PhotoSearchPage extends ItemSearchPage {
  const PhotoSearchPage({
    required super.content,
    required super.page,
    required super.totalElements,
    required super.totalPages,
    super.truncated,
    super.candidateLimit,
    super.nearby,
    required this.understood,
    this.similar = false,
    this.nextQuery,
    this.photosLeftToday,
  });

  final PhotoUnderstanding understood;
  final bool similar;

  /// What was searched; null for a photo of no product, when there is nothing to page through.
  final ItemSearchQuery? nextQuery;

  /// The customer's photo searches left today, after this one. Null from a server that does not say.
  final int? photosLeftToday;

  factory PhotoSearchPage.fromJson(Map<String, dynamic> json) {
    final ItemSearchPage base = ItemSearchPage.fromJson(json);
    final Object? understood = json['understood'];
    final Object? next = json['nextQuery'];
    ItemSearchQuery? nextQuery;
    if (next is Map<String, dynamic>) {
      final Object? terms = next['terms'];
      final List<String> words = terms is List ? terms.whereType<String>().toList() : const <String>[];
      final String? barcode = next['barcode'] as String?;
      if (words.isNotEmpty || barcode != null) {
        nextQuery = ItemSearchQuery(terms: words, barcode: barcode);
      }
    }
    return PhotoSearchPage(
      content: base.content,
      page: base.page,
      totalElements: base.totalElements,
      totalPages: base.totalPages,
      truncated: base.truncated,
      candidateLimit: base.candidateLimit,
      nearby: base.nearby,
      understood: understood is Map<String, dynamic>
          ? PhotoUnderstanding.fromJson(understood)
          : const PhotoUnderstanding(isProduct: false),
      similar: json['similar'] == true,
      nextQuery: nextQuery,
      photosLeftToday: (json['photosLeftToday'] as num?)?.toInt(),
    );
  }
}

/// One of the merchant's own products a photo matched — `PhotoFindDtos.PhotoFindMatchResponse`.
class PhotoFindMatch {
  const PhotoFindMatch({required this.product, required this.matchedBy});

  final Product product;

  /// [byBarcode] when the code was equal, [byName] otherwise.
  final String matchedBy;

  static const String byBarcode = 'BARCODE';
  static const String byName = 'NAME';

  bool get isBarcodeMatch => matchedBy == byBarcode;

  static PhotoFindMatch? maybeFromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final Object? product = json['product'];
    if (product is! Map<String, dynamic> || product['id'] is! String) return null;
    return PhotoFindMatch(
      product: Product.fromJson(product),
      matchedBy: json['matchedBy'] as String? ?? byName,
    );
  }
}

/// What a new product would start from when the photo is of something the shop does not have yet —
/// `PhotoFindDtos.PhotoFindSuggestionResponse`.
class PhotoFindSuggestion {
  const PhotoFindSuggestion({this.name, this.barcode, this.categoryId});

  final String? name;

  /// Null when a product in these shops already carries it: two products that scan the same at the
  /// till would be worse than none.
  final String? barcode;

  /// A section of the shop the photo's keywords named exactly, or null.
  final String? categoryId;

  factory PhotoFindSuggestion.fromJson(Map<String, dynamic> json) => PhotoFindSuggestion(
        name: json['name'] as String?,
        barcode: json['barcode'] as String?,
        categoryId: json['categoryId'] as String?,
      );
}

/// What a merchant's find by photo came to — `PhotoFindDtos.PhotoFindResponse`.
///
/// [sample] is true while the reader is not switched on: the lines are examples, not a reading of the
/// photo, and the sheet says so in Merchant Blitz's own words.
class PhotoFindResult {
  const PhotoFindResult({
    required this.provider,
    required this.sample,
    required this.understood,
    this.matches = const <PhotoFindMatch>[],
    this.suggestion,
    this.findsLeftToday,
  });

  final String provider;
  final bool sample;
  final PhotoUnderstanding understood;

  /// The merchant's own products that matched, best first, at most five.
  final List<PhotoFindMatch> matches;

  /// Null for a photo with no product in it.
  final PhotoFindSuggestion? suggestion;

  final int? findsLeftToday;

  factory PhotoFindResult.fromJson(Map<String, dynamic> json) {
    final Object? rows = json['matches'];
    final Object? understood = json['understood'];
    final Object? suggestion = json['suggestion'];
    return PhotoFindResult(
      provider: json['provider'] as String? ?? '',
      sample: json['sample'] == true,
      understood: understood is Map<String, dynamic>
          ? PhotoUnderstanding.fromJson(understood)
          : const PhotoUnderstanding(isProduct: false),
      matches: rows is List
          ? rows.map(PhotoFindMatch.maybeFromJson).whereType<PhotoFindMatch>().toList()
          : const <PhotoFindMatch>[],
      suggestion: suggestion is Map<String, dynamic>
          ? PhotoFindSuggestion.fromJson(suggestion)
          : null,
      findsLeftToday: (json['findsLeftToday'] as num?)?.toInt(),
    );
  }
}

/// A photo the server would not read or search, with the `code` it answered and what came with it.
///
/// Every refusal has words of its own on screen: a limit says how many a day, a busy reader asks for a
/// moment, an unavailable one hides the camera, and so on. A failure with no code — the network, a
/// server error — stays the [DioException] it is.
class PhotoSearchFailure implements Exception {
  const PhotoSearchFailure(this.code, {this.limit, this.scope, this.retryAfterSeconds});

  /// The server's `code`: one of the constants below, or a newer one this app does not know yet.
  final String code;

  /// For a limit: how many the limit allows.
  final int? limit;

  /// For a limit: [scopeDay], [scopeMinute] or [scopePlatform].
  final String? scope;

  /// For a limit or a busy reader: how long to wait.
  final int? retryAfterSeconds;

  static const String unavailable = 'PHOTO_SEARCH_UNAVAILABLE';
  static const String searchLimit = 'PHOTO_SEARCH_LIMIT';
  static const String findLimit = 'PHOTO_FIND_LIMIT';
  static const String busy = 'PHOTO_READER_BUSY';
  static const String tooLarge = 'PHOTO_TOO_LARGE';
  static const String wrongType = 'PHOTO_TYPE';
  static const String unreadable = 'PHOTO_UNREADABLE';
  static const String refused = 'PHOTO_REFUSED';
  static const String failed = 'PHOTO_READER_FAILED';

  static const String scopeDay = 'DAY';
  static const String scopeMinute = 'MINUTE';
  static const String scopePlatform = 'PLATFORM';

  /// Whether this is a limit, the customer's or the merchant's.
  bool get isLimit => code == searchLimit || code == findLimit;

  /// The failure a Dio error carries, or null when it carries no photo code.
  static PhotoSearchFailure? fromDio(DioException e) {
    final Object? body = e.response?.data;
    if (body is! Map) return null;
    final Object? code = body['code'];
    if (code is! String || !code.startsWith('PHOTO_')) return null;
    return PhotoSearchFailure(
      code,
      limit: (body['limit'] as num?)?.toInt(),
      scope: body['scope'] as String?,
      retryAfterSeconds: (body['retryAfterSeconds'] as num?)?.toInt(),
    );
  }

  @override
  String toString() => 'PhotoSearchFailure($code)';
}
