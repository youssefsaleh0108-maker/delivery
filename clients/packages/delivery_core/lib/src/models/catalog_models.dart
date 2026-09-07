/// Client-side mirrors of the Product Service DTOs (Section 7).
library;

// One-way: the storefront models know nothing about the catalog, but a category can be tagged
// with the vertical it stands for.
import 'store_models.dart';

enum ProductStatus {
  draft('DRAFT'),
  active('ACTIVE'),
  archived('ARCHIVED');

  const ProductStatus(this.wireValue);

  final String wireValue;

  static ProductStatus fromWire(String? value) {
    for (final ProductStatus status in ProductStatus.values) {
      if (status.wireValue == value) {
        return status;
      }
    }
    return ProductStatus.draft;
  }
}

class Product {
  const Product({
    required this.id,
    required this.merchantId,
    required this.name,
    required this.price,
    required this.status,
    this.storeId,
    this.description,
    this.categoryId,
    this.imageRefs = const <String>[],
    this.imageUrls = const <String>[],
    this.imageThumbUrls = const <String>[],
    this.sku,
    this.barcode,
    this.inStock = true,
  });

  final String id;
  final String merchantId;

  /// The store this product sits in. Distinct from [merchantId]: that one says who may edit it,
  /// this one says where a customer finds it, and a merchant may run more than one shop.
  final String? storeId;
  final String name;
  final String? description;
  final double price;
  final String? categoryId;

  /// Object keys, used when removing an image.
  final List<String> imageRefs;

  /// Full-size loadable URLs for the same images, in the same order, resolved by the service.
  ///
  /// For detail surfaces — the product hero and its gallery. On a list row these are the reason a
  /// customer watches a placeholder for two seconds: they are the merchant's original upload,
  /// several hundred kilobytes each, drawn into an 80dp square.
  final List<String> imageUrls;

  /// The same images at 320px on the long edge, index-aligned with [imageUrls].
  ///
  /// For list surfaces. The service repeats the full-size URL here for any image that has no
  /// derivative, so an entry is never a dead link — see [listImageUrl]. Empty only when talking to
  /// a server that predates thumbnailing.
  final List<String> imageThumbUrls;

  final ProductStatus status;

  /// The merchant's own code for the item, unique within the store when set.
  ///
  /// Null on every product that predates the inventory work, which is all of them today — so no
  /// screen may assume it exists, and the till's scanner path treats "no such SKU" as an answer
  /// rather than an error.
  final String? sku;

  /// The code scanned at the till. Deliberately not unique: the same EAN legitimately appears in
  /// two different shops.
  final String? barcode;

  /// Whether inventory-service currently believes the item is sellable.
  ///
  /// READ-ONLY — it is a projection of a stock level, never something the product form writes, so
  /// it is absent from [toRequestJson]. Defaults to **true** when the server does not send it,
  /// because a product nobody has opted into stock tracking is always sellable, and an older
  /// service that has never heard of the field must not make an entire catalogue look sold out.
  final bool inStock;

  /// The photo a list row should load: small if there is one, the original if not.
  ///
  /// The server already substitutes the full-size URL per image when a derivative is missing. The
  /// fallback repeated here catches the other case — the field absent from the response
  /// altogether, which is what an older service returns — so an app built against this model
  /// cannot end up with a row that has no picture at all.
  String? get listImageUrl {
    if (imageThumbUrls.isNotEmpty) {
      return imageThumbUrls.first;
    }
    return imageUrls.isEmpty ? null : imageUrls.first;
  }

  /// The photo a hero or gallery should load: always the original.
  String? get heroImageUrl => imageUrls.isEmpty ? null : imageUrls.first;

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        merchantId: json['merchantId'] as String? ?? '',
        storeId: json['storeId'] as String?,
        name: json['name'] as String,
        description: json['description'] as String?,
        price: (json['price'] as num).toDouble(),
        categoryId: json['categoryId'] as String?,
        imageRefs: (json['imageRefs'] as List<dynamic>? ?? <dynamic>[]).cast<String>(),
        imageUrls: (json['imageUrls'] as List<dynamic>? ?? <dynamic>[]).cast<String>(),
        imageThumbUrls:
            (json['imageThumbUrls'] as List<dynamic>? ?? <dynamic>[]).cast<String>(),
        status: ProductStatus.fromWire(json['status'] as String?),
        sku: json['sku'] as String?,
        barcode: json['barcode'] as String?,
        inStock: json['inStock'] as bool? ?? true,
      );

  /// Note the absence of `merchantId` and `status`: the service derives the first from the token
  /// and moves the second only through explicit publish/archive calls.
  Map<String, dynamic> toRequestJson() => <String, dynamic>{
        'name': name,
        'description': description,
        'price': price,
        'categoryId': categoryId,
        // Optional. A merchant with a single store never needs to send it; the service
        // auto-provisions one and files the product there.
        if (storeId != null) 'storeId': storeId,
        // Both optional and both omitted when unset rather than sent as null: blank is stored as
        // absent so several untagged products do not collide on the store's unique SKU index.
        if (sku != null) 'sku': sku,
        if (barcode != null) 'barcode': barcode,
        // `inStock` is deliberately absent — it belongs to inventory-service, and a product form
        // that could write it would let a merchant mark a sold-out shelf as full.
      };
}

class Category {
  const Category({
    required this.id,
    required this.name,
    this.parentId,
    this.imageUrl,
    this.vertical,
    this.children = const <Category>[],
    this.storeId,
    this.position = 0,
    this.productCount = 0,
    this.activeCount = 0,
  });

  final String id;
  final String name;
  final String? parentId;

  /// Which shop owns this section, or null for a PLATFORM category.
  ///
  /// The platform taxonomy (`/api/categories`) is everybody's and always sends null here; a
  /// merchant's own sections carry their store's id. The product form lists the store's own first
  /// and the platform tree beneath, which is only possible because the two are distinguishable.
  final String? storeId;

  /// Display order within the store, ascending. Always 0 for platform categories, which are
  /// ordered by name — so a screen must not sort by this unless it is showing store sections.
  final int position;

  /// How many products sit in this section, in any status. The delete confirmation needs it: the
  /// server answers 409 rather than orphaning products, and saying so up front is kinder.
  final int productCount;

  /// The subset of [productCount] that customers can actually see.
  final int activeCount;

  /// Null until the Backoffice uploads artwork for it.
  final String? imageUrl;

  /// Set only on the categories that stand for a storefront vertical — the ones the customer
  /// app's home strip is built from. Null for the rest, which is most of them.
  final StoreVertical? vertical;
  final List<Category> children;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        name: json['name'] as String,
        parentId: json['parentId'] as String?,
        imageUrl: json['imageUrl'] as String?,
        vertical: StoreVertical.maybeFromWire(json['vertical'] as String?),
        children: (json['children'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic child) => Category.fromJson(child as Map<String, dynamic>))
            .toList(),
        // All four tolerate a server that has never heard of store-owned sections: it simply
        // returns platform categories, which is exactly what null/0 mean here.
        storeId: json['storeId'] as String?,
        position: (json['position'] as num?)?.toInt() ?? 0,
        productCount: (json['productCount'] as num?)?.toInt() ?? 0,
        activeCount: (json['activeCount'] as num?)?.toInt() ?? 0,
      );

  /// A shop's own section rather than a platform one.
  bool get isStoreOwned => storeId != null;

  /// For the optimistic drag on the categories screen: move the row locally, then persist the
  /// whole order, then revert to the server's list if that fails.
  Category copyWith({String? name, String? parentId, String? imageUrl, int? position}) =>
      Category(
        id: id,
        name: name ?? this.name,
        parentId: parentId ?? this.parentId,
        imageUrl: imageUrl ?? this.imageUrl,
        vertical: vertical,
        children: children,
        storeId: storeId,
        position: position ?? this.position,
        productCount: productCount,
        activeCount: activeCount,
      );

  /// Flattens the tree for a dropdown, indenting descendants so hierarchy stays legible.
  static List<({Category category, int depth})> flatten(
    List<Category> roots, [
    int depth = 0,
  ]) {
    final List<({Category category, int depth})> flat = <({Category category, int depth})>[];
    for (final Category category in roots) {
      flat.add((category: category, depth: depth));
      flat.addAll(flatten(category.children, depth + 1));
    }
    return flat;
  }
}

class Paged<T> {
  const Paged({
    required this.content,
    required this.page,
    required this.totalElements,
    required this.totalPages,
  });

  final List<T> content;
  final int page;
  final int totalElements;
  final int totalPages;

  factory Paged.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemFromJson,
  ) =>
      Paged<T>(
        content: (json['content'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic item) => itemFromJson(item as Map<String, dynamic>))
            .toList(),
        page: json['page'] as int? ?? 0,
        totalElements: json['totalElements'] as int? ?? 0,
        totalPages: json['totalPages'] as int? ?? 0,
      );
}
