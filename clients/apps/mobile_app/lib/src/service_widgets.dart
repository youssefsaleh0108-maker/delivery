import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'delivery_address.dart';
import 'service_order_words.dart';
import 'services_kit.dart';

/// The pieces the Services tab's screens share: a provider's card, an offer's card, and the few
/// sentences both say — what an offer costs, what a pack is, how far away a shop is.
///
/// Customer-side and in this app rather than the design system: every one of them speaks the
/// delivery_core models, which the design system deliberately does not know.

/// A service shop in a list, with how far it is from the customer when that is known.
class ServiceProviderEntry {
  const ServiceProviderEntry(this.store, {this.distanceMetres});

  final StoreCard store;

  /// Straight-line metres from the customer's pin; null when either end has no pin.
  final int? distanceMetres;
}

/// Service shops for a list: nearest first around the customer's pin when their address has one,
/// otherwise the listing itself — with no distance, because none is known.
///
/// [search] matches shop names and always reads the listing: the nearby search has no name filter.
Future<List<ServiceProviderEntry>> loadServiceProviders(
  ServicesKit kit, {
  ServiceCategory? category,
  String? search,
}) async {
  final DeliveryAddress? at = kit.addresses.selected;
  if (search == null && at != null && at.hasPoint) {
    final NearbyPage page = await kit.storeApi.nearby(at.latitude!, at.longitude!,
        vertical: StoreVertical.services, serviceCategory: category);
    return <ServiceProviderEntry>[
      for (final NearbyStore near in page.content)
        ServiceProviderEntry(near.store, distanceMetres: near.distanceMetres),
    ];
  }
  final Paged<StoreCard> page = await kit.storeApi
      .browse(vertical: StoreVertical.services, serviceCategory: category, search: search);
  return <ServiceProviderEntry>[
    for (final StoreCard store in page.content) ServiceProviderEntry(store),
  ];
}

/// The glyph for a service category. Scissors for tailoring, where the frame drew a circle-x that
/// reads as "close" or "error".
IconData serviceCategoryIcon(ServiceCategory category) => switch (category) {
      ServiceCategory.printing => Icons.print_outlined,
      ServiceCategory.tailoring => Icons.content_cut_rounded,
      ServiceCategory.repairs => Icons.build_outlined,
      ServiceCategory.photography => Icons.photo_camera_outlined,
      ServiceCategory.cleaning => Icons.cleaning_services_outlined,
      ServiceCategory.beauty => Icons.auto_awesome_outlined,
      ServiceCategory.tutoring => Icons.menu_book_outlined,
    };

/// "450 m" or "1.2 km" — straight-line, as the nearby search measures it.
String serviceDistanceLabel(int metres, DeliveryStrings t) => metres < 1000
    ? t.distanceM('$metres')
    : t.distanceKm((metres / 1000).toStringAsFixed(1));

/// The least one pack of an offer costs: the catalogue's `fromPrice` — the price plus the cheapest
/// choice each required group allows — or the price itself from a server that sends none.
double serviceOfferLeast(Product offer) => offer.fromPrice ?? offer.price;

/// What an offer costs as a customer should read it. "From $15.00" only when the price really does
/// start there — a FROM offer, or required options that add to it — and the plain price otherwise:
/// a fixed $15 offer that says "From" invites a customer to expect a surcharge that is not coming.
String serviceOfferPrice(Product offer, DeliveryStrings t) {
  final double least = serviceOfferLeast(offer);
  final bool startsThere =
      offer.service?.pricingType == ServicePricingType.from || least != offer.price;
  return startsThere ? t.svcFromPrice(svcUsd(least)) : svcUsd(least);
}

/// What one pack of an offer is — "Pack of 500 cards", "Per sqm" — which the frame buried in the
/// description; null for a single piece at a price.
String? serviceOfferUnit(Product offer, DeliveryStrings t) {
  final ServiceTerms? terms = offer.service;
  final String? unit = terms?.unitLabel;
  if (terms == null || unit == null) return null;
  if (terms.pricingType == ServicePricingType.perUnit) return t.svcPerUnit(unit);
  if (terms.unitSize > 1) return t.svcPackOf(svcCount(terms.unitSize), unit);
  return null;
}

/// A service shop on the Services tab (Figma 126:285's "near you" card): its cover, its name and
/// rating, and what it does, how far it is and where — each only when known.
class ServiceProviderCard extends StatelessWidget {
  const ServiceProviderCard({super.key, required this.entry, required this.onTap});

  final ServiceProviderEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final StoreCard store = entry.store;
    final String? cover = store.listCoverUrl;
    final int? metres = entry.distanceMetres;
    final List<String> about = <String>[
      if (store.serviceCategory != null) store.serviceCategory!.labelIn(t),
      if (metres != null) t.svcDistanceAway(serviceDistanceLabel(metres, t)),
      if ((store.neighborhood ?? '').isNotEmpty) store.neighborhood!,
    ];
    return YdCard.bordered(
      onTap: onTap,
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
            child: SizedBox(
              height: 130,
              child: cover == null
                  ? StoreMonogram(name: store.name, radius: 0)
                  : Image(
                      image: DeliveryImages.provider(cover),
                      fit: BoxFit.cover,
                      errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                          StoreMonogram(name: store.name, radius: 0),
                    ),
            ),
          ),
          const SizedBox(height: DeliverySpacing.sm + 2),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  store.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: DeliveryColors.ink),
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              // The storefront's own rating chip, so a shop's score looks the same on every card in
              // the app — the frames drew it in two different colours.
              RatingChip(
                rating: store.rating,
                ratingCount: store.ratingCount,
                unratedLabel: t.ratingNew,
                dense: true,
              ),
            ],
          ),
          if (about.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Text(
              about.join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: DeliveryColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// One offer (Figma 126:371's offer card): its photo, title, description, what a pack is, its price
/// with the LBP conversion when there is a rate, and Order when it can be ordered.
///
/// [onOrder] null draws no Order button — a closed shop's offers still browse. [note] says why an
/// offer cannot be ordered when that is not obvious.
class ServiceOfferCard extends StatelessWidget {
  const ServiceOfferCard({super.key, required this.offer, this.onOrder, this.onTap, this.note});

  final Product offer;
  final VoidCallback? onOrder;
  final VoidCallback? onTap;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String? unit = serviceOfferUnit(offer, t);
    final String? lbp = MarketRates.instance.lbp(serviceOfferLeast(offer));
    return YdCard.bordered(
      onTap: onTap,
      padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                child: SizedBox.square(
                  dimension: 80,
                  child: DeliveryProductImage(url: offer.listImageUrl),
                ),
              ),
              const SizedBox(width: DeliverySpacing.md - 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      offer.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: DeliveryColors.ink),
                    ),
                    if ((offer.description ?? '').isNotEmpty)
                      Text(
                        offer.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: DeliveryColors.muted),
                      ),
                    if (unit != null)
                      Text(unit, style: const TextStyle(fontSize: 11.5, color: DeliveryColors.muted)),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                serviceOfferPrice(offer, t),
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: DeliveryColors.brand),
                              ),
                              if (lbp != null)
                                Text(lbp,
                                    style: const TextStyle(
                                        fontSize: 10.5, color: DeliveryColors.muted)),
                            ],
                          ),
                        ),
                        if (onOrder != null)
                          YdPillButton(
                            label: t.svcOrderCta,
                            expand: false,
                            size: YdPillButtonSize.compact,
                            onPressed: onOrder,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (note != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Text(note!, style: const TextStyle(fontSize: 11.5, color: DeliveryColors.muted)),
          ],
        ],
      ),
    );
  }
}
