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

  /// Loadable URLs for the same images, in the same order, resolved by the service.
  final List<String> imageUrls;

  final ProductStatus status;

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
        status: ProductStatus.fromWire(json['status'] as String?),
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
  });

  final String id;
  final String name;
  final String? parentId;

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
