import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// The platform's one way to load a network image.
///
/// Every photo the apps show — covers, logos, product shots, avatars — arrives through a
/// PRESIGNED MinIO url, and a presigned url carries a signature that is different every time it
/// is minted. A cache keyed on the full url therefore misses on every catalog refresh, and the
/// same photo downloads again and again; on Lebanese mobile data that is both slowness and
/// burned bundles. This provider keys the cache on the url's ORIGIN + PATH — the object's stable
/// identity — so a photo downloads once and then reads from disk, whatever its query string says
/// today.
///
/// Use it wherever an [Image] takes a provider:
/// {@template delivery_images_usage}
/// ```dart
/// Image(image: DeliveryImages.provider(url), fit: BoxFit.cover, errorBuilder: ...)
/// ```
/// {@endtemplate}
///
/// The existing errorBuilder / frameBuilder patterns keep working unchanged — this swaps only
/// where the bytes come from. NOT for the object stores that reuse one path for changing content;
/// nothing in this platform does that (a re-uploaded image gets a new object key).
final class DeliveryImages {
  DeliveryImages._();

  static ImageProvider provider(String url) =>
      CachedNetworkImageProvider(url, cacheKey: stableKey(url));

  /// The url without its query — the object's identity, minus today's signature.
  static String stableKey(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return url;
    return uri.replace(query: '', fragment: '').toString();
  }
}
