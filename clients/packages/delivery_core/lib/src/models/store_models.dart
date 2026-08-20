/// Client-side mirrors of the Product Service storefront DTOs.
library;

/// What a store sells. Drives the vertical switcher at the top of the home screen.
enum StoreVertical {
  restaurant('RESTAURANT', 'Restaurants'),
  coffee('COFFEE', 'Coffee'),
  grocery('GROCERY', 'Groceries'),
  convenience('CONVENIENCE', 'Convenience'),
  pharmacy('PHARMACY', 'Pharmacy'),
  electronics('ELECTRONICS', 'Electronics'),
  flowersGifts('FLOWERS_GIFTS', 'Flowers & Gifts');

  const StoreVertical(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static StoreVertical fromWire(String? value) {
    return maybeFromWire(value) ?? StoreVertical.restaurant;
  }

  /// For fields where "no vertical" is a real answer rather than a missing one — a category is
  /// only tagged with a vertical if it represents one, and most do not.
  static StoreVertical? maybeFromWire(String? value) {
    for (final StoreVertical vertical in StoreVertical.values) {
      if (vertical.wireValue == value) {
        return vertical;
      }
    }
    return null;
  }
}

/// What the card says right now. Derived server-side from opening hours and the busy flag, so the
/// client never has to know the store's timezone to render it correctly.
enum StoreAvailability {
  open('OPEN', 'Open'),
  busy('BUSY', 'Busy'),
  closingSoon('CLOSING_SOON', 'Closing soon'),
  closed('CLOSED', 'Closed');

  const StoreAvailability(this.wireValue, this.label);

  final String wireValue;
  final String label;

  /// Whether a customer can put something in a basket. Busy and closing-soon shops still take
  /// orders — they are warnings, not refusals.
  bool get acceptsOrders => this != StoreAvailability.closed;

  static StoreAvailability fromWire(String? value) {
    for (final StoreAvailability availability in StoreAvailability.values) {
      if (availability.wireValue == value) {
        return availability;
      }
    }
    return StoreAvailability.closed;
  }
}

enum OfferKind {
  percentOff('PERCENT_OFF'),
  amountOff('AMOUNT_OFF'),
  freeDelivery('FREE_DELIVERY');

  const OfferKind(this.wireValue);

  final String wireValue;

  static OfferKind fromWire(String? value) {
    for (final OfferKind kind in OfferKind.values) {
      if (kind.wireValue == value) {
        return kind;
      }
    }
    return OfferKind.percentOff;
  }
}

class Offer {
  const Offer({
    required this.id,
    required this.kind,
    required this.title,
    this.storeId,
    this.subtitle,
    this.value,
    this.minSubtotal = 0,
    this.endsAt,
  });

  final String id;

  /// Null for a platform-wide promotion.
  final String? storeId;
  final OfferKind kind;
  final String title;
  final String? subtitle;
  final double? value;
  final double minSubtotal;
  final DateTime? endsAt;

  bool get isPlatformWide => storeId == null;

  /// The short form for a ribbon on a card, where there is room for about a dozen characters.
  String get badgeLabel => switch (kind) {
        OfferKind.percentOff => '${(value ?? 0).toStringAsFixed(0)}% off',
        OfferKind.amountOff => '${(value ?? 0).toStringAsFixed(2)} off',
        OfferKind.freeDelivery => 'Free delivery',
      };

  factory Offer.fromJson(Map<String, dynamic> json) => Offer(
        id: json['id'] as String,
        storeId: json['storeId'] as String?,
        kind: OfferKind.fromWire(json['kind'] as String?),
        title: json['title'] as String,
        subtitle: json['subtitle'] as String?,
        value: (json['value'] as num?)?.toDouble(),
        minSubtotal: (json['minSubtotal'] as num?)?.toDouble() ?? 0,
        endsAt: json['endsAt'] == null ? null : DateTime.parse(json['endsAt'] as String),
      );
}

/// The grid shape: everything a storefront card needs, and nothing it does not.
class StoreCard {
  const StoreCard({
    required this.id,
    required this.slug,
    required this.name,
    required this.vertical,
    required this.availability,
    this.tagline,
    this.tags = const <String>[],
    this.rating,
    this.ratingCount = 0,
    this.deliveryFee = 0,
    this.minOrder = 0,
    this.etaMinMinutes = 20,
    this.etaMaxMinutes = 40,
    this.logoUrl,
    this.coverUrl,
    this.favorite = false,
    this.topOffer,
  });

  final String id;
  final String slug;
  final String name;
  final StoreVertical vertical;
  final String? tagline;
  final List<String> tags;
  final double? rating;
  final int ratingCount;
  final double deliveryFee;
  final double minOrder;
  final int etaMinMinutes;
  final int etaMaxMinutes;
  final StoreAvailability availability;
  final String? logoUrl;
  final String? coverUrl;
  final bool favorite;
  final Offer? topOffer;

  String get etaLabel => '$etaMinMinutes-$etaMaxMinutes min';

  /// "Free" reads better than "0.00" and is the thing a customer is actually scanning for.
  String get feeLabel => deliveryFee == 0 ? 'Free delivery' : '${deliveryFee.toStringAsFixed(2)} delivery';

  StoreCard copyWith({bool? favorite}) => StoreCard(
        id: id,
        slug: slug,
        name: name,
        vertical: vertical,
        availability: availability,
        tagline: tagline,
        tags: tags,
        rating: rating,
        ratingCount: ratingCount,
        deliveryFee: deliveryFee,
        minOrder: minOrder,
        etaMinMinutes: etaMinMinutes,
        etaMaxMinutes: etaMaxMinutes,
        logoUrl: logoUrl,
        coverUrl: coverUrl,
        favorite: favorite ?? this.favorite,
        topOffer: topOffer,
      );

  factory StoreCard.fromJson(Map<String, dynamic> json) => StoreCard(
        id: json['id'] as String,
        slug: json['slug'] as String? ?? '',
        name: json['name'] as String,
        vertical: StoreVertical.fromWire(json['vertical'] as String?),
        tagline: json['tagline'] as String?,
        tags: (json['tags'] as List<dynamic>? ?? <dynamic>[]).cast<String>(),
        rating: (json['rating'] as num?)?.toDouble(),
        ratingCount: json['ratingCount'] as int? ?? 0,
        deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
        minOrder: (json['minOrder'] as num?)?.toDouble() ?? 0,
        etaMinMinutes: json['etaMinMinutes'] as int? ?? 20,
        etaMaxMinutes: json['etaMaxMinutes'] as int? ?? 40,
        availability: StoreAvailability.fromWire(json['availability'] as String?),
        logoUrl: json['logoUrl'] as String?,
        coverUrl: json['coverUrl'] as String?,
        favorite: json['favorite'] as bool? ?? false,
        topOffer: json['topOffer'] == null
            ? null
            : Offer.fromJson(json['topOffer'] as Map<String, dynamic>),
      );
}

/// The full store, for its landing page.
class Store {
  const Store({
    required this.id,
    required this.slug,
    required this.name,
    required this.vertical,
    required this.availability,
    this.tagline,
    this.description,
    this.tags = const <String>[],
    this.rating,
    this.ratingCount = 0,
    this.deliveryFee = 0,
    this.minOrder = 0,
    this.etaMinMinutes = 20,
    this.etaMaxMinutes = 40,
    this.closesAt,
    this.logoUrl,
    this.coverUrl,
    this.address,
    this.favorite = false,
    this.offers = const <Offer>[],
  });

  final String id;
  final String slug;
  final String name;
  final StoreVertical vertical;
  final String? tagline;
  final String? description;
  final List<String> tags;
  final double? rating;
  final int ratingCount;
  final double deliveryFee;
  final double minOrder;
  final int etaMinMinutes;
  final int etaMaxMinutes;
  final StoreAvailability availability;

  /// Wall-clock closing time, "HH:mm:ss" as the server sends it. Null when shut.
  final String? closesAt;
  final String? logoUrl;
  final String? coverUrl;
  final String? address;
  final bool favorite;
  final List<Offer> offers;

  String get etaLabel => '$etaMinMinutes-$etaMaxMinutes min';

  /// Trims the seconds the server sends but nobody wants to read.
  String? get closesAtLabel {
    final String? raw = closesAt;
    if (raw == null) {
      return null;
    }
    final List<String> parts = raw.split(':');
    return parts.length >= 2 ? '${parts[0]}:${parts[1]}' : raw;
  }

  StoreCard toCard() => StoreCard(
        id: id,
        slug: slug,
        name: name,
        vertical: vertical,
        availability: availability,
        tagline: tagline,
        tags: tags,
        rating: rating,
        ratingCount: ratingCount,
        deliveryFee: deliveryFee,
        minOrder: minOrder,
        etaMinMinutes: etaMinMinutes,
        etaMaxMinutes: etaMaxMinutes,
        logoUrl: logoUrl,
        coverUrl: coverUrl,
        favorite: favorite,
        topOffer: offers.isEmpty ? null : offers.first,
      );

  Store copyWith({bool? favorite}) => Store(
        id: id,
        slug: slug,
        name: name,
        vertical: vertical,
        availability: availability,
        tagline: tagline,
        description: description,
        tags: tags,
        rating: rating,
        ratingCount: ratingCount,
        deliveryFee: deliveryFee,
        minOrder: minOrder,
        etaMinMinutes: etaMinMinutes,
        etaMaxMinutes: etaMaxMinutes,
        closesAt: closesAt,
        logoUrl: logoUrl,
        coverUrl: coverUrl,
        address: address,
        favorite: favorite ?? this.favorite,
        offers: offers,
      );

  factory Store.fromJson(Map<String, dynamic> json) => Store(
        id: json['id'] as String,
        slug: json['slug'] as String? ?? '',
        name: json['name'] as String,
        vertical: StoreVertical.fromWire(json['vertical'] as String?),
        tagline: json['tagline'] as String?,
        description: json['description'] as String?,
        tags: (json['tags'] as List<dynamic>? ?? <dynamic>[]).cast<String>(),
        rating: (json['rating'] as num?)?.toDouble(),
        ratingCount: json['ratingCount'] as int? ?? 0,
        deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
        minOrder: (json['minOrder'] as num?)?.toDouble() ?? 0,
        etaMinMinutes: json['etaMinMinutes'] as int? ?? 20,
        etaMaxMinutes: json['etaMaxMinutes'] as int? ?? 40,
        availability: StoreAvailability.fromWire(json['availability'] as String?),
        closesAt: json['closesAt'] as String?,
        logoUrl: json['logoUrl'] as String?,
        coverUrl: json['coverUrl'] as String?,
        address: json['address'] as String?,
        favorite: json['favorite'] as bool? ?? false,
        offers: (json['offers'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic o) => Offer.fromJson(o as Map<String, dynamic>))
            .toList(),
      );
}

/// One window in which a store is open.
///
/// [dayOfWeek] is ISO-8601 — 1 = Monday .. 7 = Sunday — matching both `java.time.DayOfWeek` and
/// Dart's `DateTime.weekday`, so no translation is needed on either side.
///
/// Times are "HH:mm" or "HH:mm:ss"; the server sends seconds, and either is accepted back.
class OpeningWindow {
  const OpeningWindow({
    required this.dayOfWeek,
    required this.opensAt,
    required this.closesAt,
  });

  final int dayOfWeek;
  final String opensAt;
  final String closesAt;

  static const List<String> dayNames = <String>[
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  String get dayName => dayNames[(dayOfWeek - 1).clamp(0, 6)];

  /// Trims the seconds the server sends but nobody wants to read or type.
  static String hhmm(String raw) {
    final List<String> parts = raw.split(':');
    return parts.length >= 2 ? '${parts[0]}:${parts[1]}' : raw;
  }

  String get opensAtLabel => hhmm(opensAt);

  String get closesAtLabel => hhmm(closesAt);

  /// The server parses a LocalTime, which needs seconds present.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'dayOfWeek': dayOfWeek,
        'opensAt': '${hhmm(opensAt)}:00',
        'closesAt': '${hhmm(closesAt)}:00',
      };

  factory OpeningWindow.fromJson(Map<String, dynamic> json) => OpeningWindow(
        dayOfWeek: json['dayOfWeek'] as int,
        opensAt: json['opensAt'] as String,
        closesAt: json['closesAt'] as String,
      );

  OpeningWindow copyWith({String? opensAt, String? closesAt}) => OpeningWindow(
        dayOfWeek: dayOfWeek,
        opensAt: opensAt ?? this.opensAt,
        closesAt: closesAt ?? this.closesAt,
      );
}

/// One aisle in a store, with how many things are actually in it.
class Aisle {
  const Aisle({required this.categoryId, required this.name, required this.productCount});

  final String categoryId;
  final String name;
  final int productCount;

  factory Aisle.fromJson(Map<String, dynamic> json) => Aisle(
        categoryId: json['categoryId'] as String,
        name: json['name'] as String,
        productCount: (json['productCount'] as num?)?.toInt() ?? 0,
      );
}

/// The filters on the storefront. A value object so the home screen can hold one piece of state
/// rather than five, and so "is anything filtered" is a single question.
class StoreFilters {
  const StoreFilters({
    this.vertical,
    this.search,
    this.maxDeliveryFee,
    this.maxEtaMinutes,
    this.minRating,
    this.offersOnly = false,
  });

  final StoreVertical? vertical;
  final String? search;
  final double? maxDeliveryFee;
  final int? maxEtaMinutes;
  final double? minRating;

  /// Applied client-side: "has a promotion" is a property of the offers attached to a card, not a
  /// column the storefront query can filter on.
  final bool offersOnly;

  bool get isActive =>
      maxDeliveryFee != null || maxEtaMinutes != null || minRating != null || offersOnly;

  int get activeCount => <bool>[
        maxDeliveryFee != null,
        maxEtaMinutes != null,
        minRating != null,
        offersOnly,
      ].where((bool on) => on).length;

  StoreFilters copyWith({
    StoreVertical? vertical,
    String? search,
    double? maxDeliveryFee,
    int? maxEtaMinutes,
    double? minRating,
    bool? offersOnly,
    bool clearVertical = false,
    bool clearSearch = false,
    bool clearFee = false,
    bool clearEta = false,
    bool clearRating = false,
  }) =>
      StoreFilters(
        vertical: clearVertical ? null : (vertical ?? this.vertical),
        search: clearSearch ? null : (search ?? this.search),
        maxDeliveryFee: clearFee ? null : (maxDeliveryFee ?? this.maxDeliveryFee),
        maxEtaMinutes: clearEta ? null : (maxEtaMinutes ?? this.maxEtaMinutes),
        minRating: clearRating ? null : (minRating ?? this.minRating),
        offersOnly: offersOnly ?? this.offersOnly,
      );

  StoreFilters cleared() => StoreFilters(vertical: vertical, search: search);
}

// ---------------------------------------------------------------------------- product options

/// A question asked about a product before it goes in the basket — "Choose Size", "Extras".
class OptionGroup {
  const OptionGroup({
    required this.id,
    required this.name,
    required this.minSelect,
    required this.maxSelect,
    required this.required,
    required this.singleChoice,
    this.options = const <ProductOptionChoice>[],
  });

  final String id;
  final String name;
  final int minSelect;
  final int maxSelect;
  final bool required;
  final bool singleChoice;
  final List<ProductOptionChoice> options;

  /// The rule, in words, under the group heading — "Required · choose 1", "Choose up to 2".
  String get rule {
    if (required && singleChoice) return 'Required · choose 1';
    if (required) return 'Required · choose $minSelect to $maxSelect';
    if (singleChoice) return 'Optional · choose 1';
    return 'Optional · choose up to $maxSelect';
  }

  factory OptionGroup.fromJson(Map<String, dynamic> json) => OptionGroup(
        id: json['id'] as String,
        name: json['name'] as String,
        minSelect: json['minSelect'] as int? ?? 0,
        maxSelect: json['maxSelect'] as int? ?? 1,
        required: json['required'] as bool? ?? false,
        singleChoice: json['singleChoice'] as bool? ?? true,
        options: (json['options'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic o) => ProductOptionChoice.fromJson(o as Map<String, dynamic>))
            .toList(),
      );
}

/// One answer within an [OptionGroup]. [priceDelta] is signed — "Small" may be negative.
class ProductOptionChoice {
  const ProductOptionChoice({
    required this.id,
    required this.name,
    this.priceDelta = 0,
    this.isDefault = false,
    this.available = true,
  });

  final String id;
  final String name;
  final double priceDelta;
  final bool isDefault;
  final bool available;

  /// "+1.25", "-1.50", or empty when it costs nothing extra.
  String get deltaLabel {
    if (priceDelta == 0) return '';
    final String sign = priceDelta > 0 ? '+' : '-';
    return '$sign${priceDelta.abs().toStringAsFixed(2)}';
  }

  factory ProductOptionChoice.fromJson(Map<String, dynamic> json) => ProductOptionChoice(
        id: json['id'] as String,
        name: json['name'] as String,
        priceDelta: (json['priceDelta'] as num?)?.toDouble() ?? 0,
        isDefault: json['isDefault'] as bool? ?? false,
        available: json['available'] as bool? ?? true,
      );
}

/// What a configured line costs, as priced by the catalog.
///
/// The client never adds the deltas itself — it asks. The catalog owns prices, and a second
/// implementation of the sum is a second thing that can disagree with the menu.
class PricedSelection {
  const PricedSelection({
    required this.basePrice,
    required this.unitPrice,
    this.options = const <ChosenOption>[],
  });

  final double basePrice;
  final double unitPrice;
  final List<ChosenOption> options;

  factory PricedSelection.fromJson(Map<String, dynamic> json) => PricedSelection(
        basePrice: (json['basePrice'] as num).toDouble(),
        unitPrice: (json['unitPrice'] as num).toDouble(),
        options: (json['options'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic o) => ChosenOption.fromJson(o as Map<String, dynamic>))
            .toList(),
      );
}

class ChosenOption {
  const ChosenOption({required this.groupName, required this.optionName, this.priceDelta = 0});

  final String groupName;
  final String optionName;
  final double priceDelta;

  String get summary => '$groupName: $optionName';

  factory ChosenOption.fromJson(Map<String, dynamic> json) => ChosenOption(
        groupName: json['groupName'] as String,
        optionName: json['optionName'] as String,
        priceDelta: (json['priceDelta'] as num?)?.toDouble() ?? 0,
      );
}

// ---------------------------------------------------------------------------- banners

/// What tapping a banner does.
enum BannerLinkKind {
  none('NONE'),
  store('STORE'),
  category('CATEGORY'),
  url('URL');

  const BannerLinkKind(this.wireValue);

  final String wireValue;

  static BannerLinkKind fromWire(String? value) {
    for (final BannerLinkKind kind in BannerLinkKind.values) {
      if (kind.wireValue == value) return kind;
    }
    return BannerLinkKind.none;
  }
}

/// A designed promotional banner on the home screen.
///
/// Distinct from [Offer]: an offer is a commercial rule the checkout applies, a banner is artwork
/// with a destination that changes no price.
class HomeBanner {
  const HomeBanner({
    required this.id,
    required this.title,
    required this.linkKind,
    this.subtitle,
    this.imageUrl,
    this.linkTarget,
    this.position = 0,
    this.active = true,
  });

  final String id;
  final String title;
  final String? subtitle;

  /// Null until artwork is uploaded; the client falls back to a brand gradient.
  final String? imageUrl;
  final BannerLinkKind linkKind;
  final String? linkTarget;
  final int position;

  /// Always true on the customer rail, which only ever returns live banners. It carries real
  /// information in the Backoffice list, which shows withdrawn ones too.
  final bool active;

  bool get isTappable => linkKind != BannerLinkKind.none && linkTarget != null;

  factory HomeBanner.fromJson(Map<String, dynamic> json) => HomeBanner(
        id: json['id'] as String,
        title: json['title'] as String,
        subtitle: json['subtitle'] as String?,
        imageUrl: json['imageUrl'] as String?,
        linkKind: BannerLinkKind.fromWire(json['linkKind'] as String?),
        linkTarget: json['linkTarget'] as String?,
        position: json['position'] as int? ?? 0,
        active: json['active'] as bool? ?? true,
      );
}

/// One chip in the home category strip: a name, an uploaded picture, and the vertical it filters by.
///
/// Replaces the hard-coded enum-plus-Material-icon strip. [vertical] is what the storefront query
/// actually filters on — stores carry a vertical, not a category — so the chip is presentation and
/// the filter stays typed.
class CategoryChip {
  const CategoryChip({
    required this.id,
    required this.name,
    required this.vertical,
    this.imageUrl,
  });

  final String id;
  final String name;
  final StoreVertical vertical;
  final String? imageUrl;

  factory CategoryChip.fromJson(Map<String, dynamic> json) => CategoryChip(
        id: json['id'] as String,
        name: json['name'] as String,
        vertical: StoreVertical.fromWire(json['vertical'] as String?),
        imageUrl: json['imageUrl'] as String?,
      );
}
