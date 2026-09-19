import 'catalog_models.dart';
import 'store_models.dart';

/// What the customer item search looks for — `ItemSearchDtos.ItemSearchRequest` without the point.
///
/// [q] is what a customer typed. [terms] is how a caller that already has its words asks, such as the
/// name, Arabic name and brand a photo was read as; both fill the same three slots on the server, [q]
/// first. [barcode] is 8 to 14 digits, matched exactly. The server refuses a query with none of the
/// three, a term under two characters or with no word of two letters or digits once spelled its way
/// ("a.", [ItemSearchRefusal.tooShort]), or with more than five such words
/// ([ItemSearchRefusal.tooManyWords]).
class ItemSearchQuery {
  const ItemSearchQuery({this.q, this.terms = const <String>[], this.barcode});

  /// What a customer typed into a search box.
  const ItemSearchQuery.text(String this.q)
      : terms = const <String>[],
        barcode = null;

  final String? q;
  final List<String> terms;
  final String? barcode;

  /// The shortest word the server searches for. A box waits for this many characters before asking.
  static const int minLength = 2;

  /// The query as one line for a heading or an empty state: the typed text, else the first term, else
  /// the barcode.
  String get label => q ?? (terms.isNotEmpty ? terms.first : barcode ?? '');

  /// The request body, without the point, which [StoreApi.searchItems] adds. Absent parts are not sent.
  Map<String, dynamic> toJson() => <String, dynamic>{
        if (q != null) 'q': q,
        if (terms.isNotEmpty) 'terms': terms,
        if (barcode != null) 'barcode': barcode,
      };

  @override
  bool operator ==(Object other) =>
      other is ItemSearchQuery &&
      other.q == q &&
      other.barcode == barcode &&
      other.terms.length == terms.length &&
      Iterable<int>.generate(terms.length).every((int i) => other.terms[i] == terms[i]);

  @override
  int get hashCode => Object.hash(q, barcode, Object.hashAll(terms));
}

/// One shop in the item search, and what it sells that matched — `ItemSearchDtos.ShopItemsResponse`.
///
/// The card is the storefront's own, nested as the "near me" rail nests it ([NearbyStore]), so a
/// screen that draws a [StoreCard] draws this.
class ItemSearchGroup {
  const ItemSearchGroup({
    required this.store,
    required this.items,
    required this.matchedInStore,
    this.latitude,
    this.longitude,
    this.distanceMetres,
  });

  final StoreCard store;

  /// The shop's pin; null for a shop with none, which only a search without a point finds.
  final double? latitude;
  final double? longitude;

  /// Straight-line metres from the customer's pin, rounded; null when the search had no point. Say
  /// "away", never "drive": no route is computed.
  final int? distanceMetres;

  /// The shop's best matches, best first, at most three. Each price is the product's own as the server
  /// sent it, the same price the shop's shelf shows.
  final List<Product> items;

  /// How many of the shop's products matched, counting [items].
  final int matchedInStore;

  /// How many matches [items] leaves out: "N more in this shop". Never negative, whatever the server
  /// counted.
  int get moreInStore => matchedInStore > items.length ? matchedInStore - items.length : 0;

  /// The group, or null when [json] is not one this build can draw: no card with an id and a name, or
  /// no item it can read. One row this build cannot read is dropped rather than failing the page.
  static ItemSearchGroup? maybeFromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final Object? store = json['store'];
    if (store is! Map<String, dynamic> || store['id'] is! String || store['name'] is! String) {
      return null;
    }
    final Object? rows = json['items'];
    final List<Product> items = <Product>[
      if (rows is List)
        for (final Object? row in rows)
          if (_product(row) case final Product product) product,
    ];
    if (items.isEmpty) {
      return null;
    }
    final Object? matched = json['matchedInStore'];
    return ItemSearchGroup(
      store: StoreCard.fromJson(store),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      distanceMetres: (json['distanceMetres'] as num?)?.toInt(),
      items: items,
      matchedInStore: matched is num ? matched.toInt() : items.length,
    );
  }

  static Product? _product(Object? json) {
    if (json is! Map<String, dynamic> ||
        json['id'] is! String ||
        json['name'] is! String ||
        json['price'] is! num) {
      return null;
    }
    return Product.fromJson(json);
  }
}

/// A page of the item search — `ItemSearchDtos.ItemSearchPageResponse`: shops, and what the page can
/// honestly claim.
///
/// [truncated] is the one case in which "no shop sells it" is not the whole truth: more products
/// matched than one search reads, so the page covers the best [candidateLimit] matches only, and a
/// screen with nothing to show says so. [nearby] is false when the search had no point: no shop then
/// carries a distance, and the list is not in distance order.
class ItemSearchPage extends Paged<ItemSearchGroup> {
  const ItemSearchPage({
    required super.content,
    required super.page,
    required super.totalElements,
    required super.totalPages,
    this.truncated = false,
    this.candidateLimit,
    this.nearby = false,
  });

  final bool truncated;

  /// How many matching products one search reads. Null from a server that does not say.
  final int? candidateLimit;

  final bool nearby;

  factory ItemSearchPage.fromJson(Map<String, dynamic> json) {
    int count(String key) {
      final Object? value = json[key];
      return value is num ? value.toInt() : 0;
    }

    final Object? rows = json['content'];
    return ItemSearchPage(
      content: rows is List
          ? rows.map(ItemSearchGroup.maybeFromJson).whereType<ItemSearchGroup>().toList()
          : const <ItemSearchGroup>[],
      page: count('page'),
      totalElements: count('totalElements'),
      totalPages: count('totalPages'),
      truncated: json['truncated'] as bool? ?? false,
      candidateLimit: (json['candidateLimit'] as num?)?.toInt(),
      nearby: json['nearby'] as bool? ?? false,
    );
  }
}

/// A search the server refused as it was asked: a 400 whose `code` is one of `ItemSearchService`'s.
///
/// The same words asked again get the same answer, so a screen says what to change rather than
/// offering to try again: [tooShort] when no word has two letters or digits ("a.", "1 l"),
/// [tooManyWords] past five words, [tooLong] past 100 characters. [tooManyTerms] and [badBarcode] are
/// a caller's mistake. A busy server is not a refusal: its 429 and 503 stay the Dio errors they are,
/// and trying again a moment later works.
class ItemSearchRefusal implements Exception {
  const ItemSearchRefusal(this.code);

  /// The server's `code`, one of the constants below or a newer one this app does not know yet.
  final String code;

  static const String tooShort = 'SEARCH_TOO_SHORT';
  static const String tooLong = 'SEARCH_TOO_LONG';
  static const String tooManyTerms = 'SEARCH_TOO_MANY_TERMS';
  static const String tooManyWords = 'SEARCH_TOO_MANY_WORDS';
  static const String badBarcode = 'SEARCH_BAD_BARCODE';

  @override
  String toString() => 'ItemSearchRefusal($code)';
}
