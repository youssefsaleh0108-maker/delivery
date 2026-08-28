import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which URL each surface loads, and what happens when the small one is not there.
///
/// The measured problem: three product photos on one shop screen at 631 KB, 575 KB and 410 KB,
/// 2.0-2.9s each, drawn into an 80dp row thumbnail. The service now sends a 320px derivative
/// alongside each original, and these are the rules for picking between them.
///
/// The fallback is the interesting half. The service already substitutes the full-size URL per
/// image when a derivative is missing — every photo uploaded before thumbnailing existed, and any
/// whose generation failed — so the client's own fallback covers only the case the service cannot:
/// the field absent from the response altogether, which is what an older build of the service
/// returns.
void main() {
  Map<String, dynamic> productJson({
    List<String>? imageUrls,
    List<String>? imageThumbUrls,
  }) =>
      <String, dynamic>{
        'id': 'p-1',
        'merchantId': 'm-1',
        'name': 'Falafel wrap',
        'price': 6.5,
        'status': 'ACTIVE',
        'imageRefs': <String>['products/p-1/a.jpg'],
        if (imageUrls != null) 'imageUrls': imageUrls,
        if (imageThumbUrls != null) 'imageThumbUrls': imageThumbUrls,
      };

  Map<String, dynamic> storeJson({
    String? coverUrl,
    String? coverThumbUrl,
    String? logoUrl,
    String? logoThumbUrl,
  }) =>
      <String, dynamic>{
        'id': 's-1',
        'slug': 'my-shop',
        'name': 'My Shop',
        'vertical': 'RESTAURANT',
        'availability': 'OPEN',
        if (coverUrl != null) 'coverUrl': coverUrl,
        if (coverThumbUrl != null) 'coverThumbUrl': coverThumbUrl,
        if (logoUrl != null) 'logoUrl': logoUrl,
        if (logoThumbUrl != null) 'logoThumbUrl': logoThumbUrl,
      };

  group('Product images', () {
    test('parses the full-size and list-sized URLs as separate lists', () {
      final Product product = Product.fromJson(productJson(
        imageUrls: <String>['https://cdn/full-a.jpg', 'https://cdn/full-b.jpg'],
        imageThumbUrls: <String>['https://cdn/a-thumb.jpg', 'https://cdn/b-thumb.jpg'],
      ));

      expect(product.imageUrls, <String>['https://cdn/full-a.jpg', 'https://cdn/full-b.jpg']);
      expect(product.imageThumbUrls,
          <String>['https://cdn/a-thumb.jpg', 'https://cdn/b-thumb.jpg']);
    });

    test('a list row loads the derivative and a hero loads the original', () {
      final Product product = Product.fromJson(productJson(
        imageUrls: <String>['https://cdn/full-a.jpg'],
        imageThumbUrls: <String>['https://cdn/a-thumb.jpg'],
      ));

      expect(product.listImageUrl, 'https://cdn/a-thumb.jpg');
      expect(product.heroImageUrl, 'https://cdn/full-a.jpg');
    });

    /// An older service. The field is not merely empty, it is not in the payload at all.
    test('a response with no thumbnail field falls back to the full-size image', () {
      final Product product =
          Product.fromJson(productJson(imageUrls: <String>['https://cdn/full-a.jpg']));

      expect(product.imageThumbUrls, isEmpty);
      expect(product.listImageUrl, 'https://cdn/full-a.jpg');
    });

    /// What the service sends for an image that has no derivative: the same URL twice.
    test('a per-image fallback from the service reads as the full-size URL', () {
      final Product product = Product.fromJson(productJson(
        imageUrls: <String>['https://cdn/full-a.jpg'],
        imageThumbUrls: <String>['https://cdn/full-a.jpg'],
      ));

      expect(product.listImageUrl, 'https://cdn/full-a.jpg');
      expect(product.listImageUrl, product.heroImageUrl);
    });

    test('a product with no photos at all has nothing to load on either surface', () {
      final Product product = Product.fromJson(productJson());

      expect(product.listImageUrl, isNull);
      expect(product.heroImageUrl, isNull);
    });

    /// Not a broken tile: without a full-size URL beside it there is nothing to fall back to, but
    /// the accessor must still answer rather than throw on an empty list.
    test('an empty thumbnail list with no full-size images yields null, not a range error', () {
      final Product product = Product.fromJson(
          productJson(imageUrls: <String>[], imageThumbUrls: <String>[]));

      expect(product.listImageUrl, isNull);
    });

    test('the default constructor leaves the thumbnail list empty rather than null', () {
      const Product product = Product(
        id: 'p-1',
        merchantId: 'm-1',
        name: 'Falafel wrap',
        price: 6.5,
        status: ProductStatus.active,
        imageUrls: <String>['https://cdn/full-a.jpg'],
      );

      expect(product.imageThumbUrls, isEmpty);
      expect(product.listImageUrl, 'https://cdn/full-a.jpg');
    });
  });

  group('StoreCard artwork', () {
    test('parses both cover sizes', () {
      final StoreCard card = StoreCard.fromJson(storeJson(
        coverUrl: 'https://cdn/cover.jpg',
        coverThumbUrl: 'https://cdn/cover-thumb.jpg',
        logoUrl: 'https://cdn/logo.png',
        logoThumbUrl: 'https://cdn/logo-thumb.jpg',
      ));

      expect(card.coverUrl, 'https://cdn/cover.jpg');
      expect(card.coverThumbUrl, 'https://cdn/cover-thumb.jpg');
      expect(card.listCoverUrl, 'https://cdn/cover-thumb.jpg');
      expect(card.listLogoUrl, 'https://cdn/logo-thumb.jpg');
    });

    test('a grid falls back to the full-size cover when no derivative was sent', () {
      final StoreCard card = StoreCard.fromJson(storeJson(coverUrl: 'https://cdn/cover.jpg'));

      expect(card.coverThumbUrl, isNull);
      expect(card.listCoverUrl, 'https://cdn/cover.jpg');
    });

    test('a shop with no cover has nothing to load either way', () {
      final StoreCard card = StoreCard.fromJson(storeJson());

      expect(card.listCoverUrl, isNull);
      expect(card.listLogoUrl, isNull);
    });

    /// Starring a shop rebuilds the card. Losing the derivative there would make every favourite
    /// silently reload its full-size cover.
    test('toggling favourite keeps both cover sizes', () {
      final StoreCard card = StoreCard.fromJson(storeJson(
        coverUrl: 'https://cdn/cover.jpg',
        coverThumbUrl: 'https://cdn/cover-thumb.jpg',
      )).copyWith(favorite: true);

      expect(card.favorite, isTrue);
      expect(card.listCoverUrl, 'https://cdn/cover-thumb.jpg');
      expect(card.coverUrl, 'https://cdn/cover.jpg');
    });
  });

  group('Store artwork', () {
    test('parses both cover sizes and keeps the hero on the original', () {
      final Store store = Store.fromJson(storeJson(
        coverUrl: 'https://cdn/cover.jpg',
        coverThumbUrl: 'https://cdn/cover-thumb.jpg',
      ));

      expect(store.coverUrl, 'https://cdn/cover.jpg');
      expect(store.listCoverUrl, 'https://cdn/cover-thumb.jpg');
    });

    test('falls back to the full-size cover when no derivative was sent', () {
      final Store store = Store.fromJson(storeJson(coverUrl: 'https://cdn/cover.jpg'));

      expect(store.listCoverUrl, 'https://cdn/cover.jpg');
    });

    /// The shop page opens from a card and builds one back. Both sizes have to survive the trip,
    /// or the home grid loses its derivative the moment a shop is visited.
    test('the card built from a store carries both sizes through', () {
      final StoreCard card = Store.fromJson(storeJson(
        coverUrl: 'https://cdn/cover.jpg',
        coverThumbUrl: 'https://cdn/cover-thumb.jpg',
        logoUrl: 'https://cdn/logo.png',
        logoThumbUrl: 'https://cdn/logo-thumb.jpg',
      )).toCard();

      expect(card.coverUrl, 'https://cdn/cover.jpg');
      expect(card.coverThumbUrl, 'https://cdn/cover-thumb.jpg');
      expect(card.logoThumbUrl, 'https://cdn/logo-thumb.jpg');
    });

    test('copyWith keeps both sizes', () {
      final Store store = Store.fromJson(storeJson(
        coverUrl: 'https://cdn/cover.jpg',
        coverThumbUrl: 'https://cdn/cover-thumb.jpg',
      )).copyWith(favorite: true);

      expect(store.favorite, isTrue);
      expect(store.coverThumbUrl, 'https://cdn/cover-thumb.jpg');
    });
  });
}
