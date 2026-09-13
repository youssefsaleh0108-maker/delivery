/// Client-side mirrors of the Product Service DTOs (Section 7).
library;

// One-way: the storefront models know nothing about the catalog, but a category can be tagged
// with the vertical it stands for.
import 'store_models.dart';

enum ProductStatus {
  draft('DRAFT'),
  active('ACTIVE'),

  /// A service offer its provider has taken off sale for now. Customers never see it and it cannot be
  /// ordered, but it keeps its photos, options and terms, so resuming it puts it back as it was. Only
  /// service offers are paused; a goods product is archived instead.
  paused('PAUSED'),
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
    this.giftFeatured = false,
    this.service,
    this.fromPrice,
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
  /// Whether the back office has put this product on the customer gift hub. Public curation: the
  /// hub itself shows every featured product.
  final bool giftFeatured;

  /// What a service offer promises: how it is priced, the pack, the turnaround, how the customer gets
  /// the work, and whether they send a file. Null for a goods product, and for every product from a
  /// server that predates services.
  final ServiceTerms? service;

  /// The least a customer can pay for one pack of a service offer, as the server worked it out: the
  /// price plus the cheapest choice each option group allows. What "From $15.00" shows.
  ///
  /// Null for a goods product. A screen without it shows [price], and never adds option deltas up
  /// itself: the catalogue owns that sum, and a second copy is a second thing that can disagree with
  /// what an order is charged.
  final double? fromPrice;

  /// Whether this is a service offer. Only a service shop's products are, and all of them are.
  bool get isServiceOffer => service != null;

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
        giftFeatured: json['giftFeatured'] as bool? ?? false,
        service: ServiceTerms.maybeFromJson(json['service']),
        fromPrice: _doubleOrNull(json['fromPrice']),
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
        // Required for a product in a service shop and refused for any other, so a goods form that
        // never set it sends nothing and keeps working unchanged.
        if (service != null) 'service': service!.toRequestJson(),
      };
}

/// How a service offer is priced. See [ServiceTerms].
enum ServicePricingType {
  /// One price for one pack of [ServiceTerms.unitSize] units: "500 cards, $15.00".
  fixed('FIXED'),

  /// One price for one unit, such as a square metre: "$8.00 per sqm". Always a pack of one.
  perUnit('PER_UNIT'),

  /// A starting price that required options add to: "From $15.00".
  from('FROM'),

  /// A pricing type this build does not know. Never read as one of the others, and never sent back
  /// (see [ServiceTerms.toRequestJson]).
  unknown(null);

  const ServicePricingType(this.wireValue);

  final String? wireValue;

  static ServicePricingType fromWire(Object? value) {
    for (final ServicePricingType type in values) {
      if (type.wireValue != null && type.wireValue == value) {
        return type;
      }
    }
    return ServicePricingType.unknown;
  }
}

/// How the customer gets a service offer's finished work.
enum ServiceFulfilment {
  /// Collected at the provider's shop.
  pickup('PICKUP'),

  /// Carried to the customer by YouDrop, on the shop's delivery terms.
  delivery('DELIVERY'),

  /// Either, chosen by the customer when ordering.
  both('BOTH'),

  /// A fulfilment this build does not know. It includes neither pickup nor delivery, so no screen
  /// offers the customer a way of getting the work that it cannot describe.
  unknown(null);

  const ServiceFulfilment(this.wireValue);

  final String? wireValue;

  bool get includesPickup => this == pickup || this == both;

  bool get includesDelivery => this == delivery || this == both;

  static ServiceFulfilment fromWire(Object? value) {
    for (final ServiceFulfilment fulfilment in values) {
      if (fulfilment.wireValue != null && fulfilment.wireValue == value) {
        return fulfilment;
      }
    }
    return ServiceFulfilment.unknown;
  }
}

/// Whether the customer sends a file with a service order: a design to print, a photo to enlarge.
enum ServiceAttachmentPolicy {
  none('NONE'),
  optional('OPTIONAL'),
  required('REQUIRED'),

  /// A policy this build does not know. Never read as one of the others, and never sent back.
  unknown(null);

  const ServiceAttachmentPolicy(this.wireValue);

  final String? wireValue;

  static ServiceAttachmentPolicy fromWire(Object? value) {
    for (final ServiceAttachmentPolicy policy in values) {
      if (policy.wireValue != null && policy.wireValue == value) {
        return policy;
      }
    }
    return ServiceAttachmentPolicy.unknown;
  }
}

/// What a service offer promises, as product-service's `service` block carries it.
///
/// Parsed tolerantly: a term this build does not know reads as `unknown` rather than as a guess, and
/// a block that is not a block is no block at all. A number the server did not send stays null, so a
/// screen shows a dash rather than a turnaround nobody promised.
class ServiceTerms {
  const ServiceTerms({
    required this.pricingType,
    required this.fulfilmentModes,
    this.unitLabel,
    this.unitSize = 1,
    this.turnaroundMinHours,
    this.turnaroundMaxHours,
    this.attachmentPolicy = ServiceAttachmentPolicy.none,
    this.instructionsPrompt,
  });

  final ServicePricingType pricingType;

  /// What one unit is called: "cards", "sqm". Null for a single unit sold at a fixed price.
  final String? unitLabel;

  /// Units in one step of the quantity stepper. An order counts packs of this many, 1 to 99 packs.
  final int unitSize;

  /// How long the provider needs once they accept, in whole hours. The customer's estimated
  /// completion is the accept time plus [turnaroundMaxHours].
  final int? turnaroundMinHours;
  final int? turnaroundMaxHours;

  final ServiceFulfilment fulfilmentModes;
  final ServiceAttachmentPolicy attachmentPolicy;

  /// The question the provider puts to the customer beside the order's instructions.
  final String? instructionsPrompt;

  /// Whether every term is one this build knows, and so can be edited and saved back.
  bool get isEditable =>
      pricingType != ServicePricingType.unknown &&
      fulfilmentModes != ServiceFulfilment.unknown &&
      attachmentPolicy != ServiceAttachmentPolicy.unknown;

  /// The block, or null when [json] is not one: a goods product sends none.
  static ServiceTerms? maybeFromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final int? size = _intOrNull(json['unitSize']);
    return ServiceTerms(
      pricingType: ServicePricingType.fromWire(json['pricingType']),
      unitLabel: _textOrNull(json['unitLabel']),
      unitSize: size == null || size < 1 ? 1 : size,
      turnaroundMinHours: _intOrNull(json['turnaroundMinHours']),
      turnaroundMaxHours: _intOrNull(json['turnaroundMaxHours']),
      fulfilmentModes: ServiceFulfilment.fromWire(json['fulfilmentModes']),
      attachmentPolicy: ServiceAttachmentPolicy.fromWire(json['attachmentPolicy']),
      instructionsPrompt: _textOrNull(json['instructionsPrompt']),
    );
  }

  /// The block as product-service's ProductRequest takes it, replacing the offer's terms whole.
  ///
  /// Throws a [StateError] when a term is one this build does not know. There is nothing true to send
  /// for it: an absent file policy would be saved as "no file", quietly rewriting what the provider
  /// set with a newer app. A form checks [isEditable] first.
  Map<String, dynamic> toRequestJson() {
    if (!isEditable) {
      throw StateError('These service terms hold a value this app does not know, and saving them '
          'would overwrite it.');
    }
    return <String, dynamic>{
      'pricingType': pricingType.wireValue,
      'unitLabel': unitLabel,
      'unitSize': unitSize,
      'turnaroundMinHours': turnaroundMinHours,
      'turnaroundMaxHours': turnaroundMaxHours,
      'fulfilmentModes': fulfilmentModes.wireValue,
      'attachmentPolicy': attachmentPolicy.wireValue,
      'instructionsPrompt': instructionsPrompt,
    };
  }
}

int? _intOrNull(Object? value) => value is num ? value.toInt() : null;

double? _doubleOrNull(Object? value) => value is num ? value.toDouble() : null;

String? _textOrNull(Object? value) => value is String && value.trim().isNotEmpty ? value : null;

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
