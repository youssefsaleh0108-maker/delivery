import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'delivery_address.dart';
import 'order_placement.dart';
import 'service_order_screen.dart';
import 'service_order_words.dart';
import 'service_widgets.dart';
import 'services_kit.dart';
import 'store_state_mapping.dart';

/// A service provider's page (Figma 126:371), pushed from the Services tab, a category or a search.
///
/// The frame, less what the platform cannot back and plus what a pushed page needs:
///
/// * A back button over the cover; no Share button — there is no public page to share.
/// * The Verified Local badge only when back office granted it; the rating, or "New" for a shop
///   nobody has rated; the distance only when both the customer's address and the shop have a pin;
///   and "Open until 6:00 PM" from the shop's own closing time — or the state it is actually in.
/// * **Offers** with a price that says "From" only when it means it, what a pack is, and Order only
///   while the shop takes orders — a closed provider's offers still browse, as a shop's shelf does.
///   An offer that needs a file cannot be ordered until files can be sent, and says so.
/// * **Reviews**, paged from the shop's reviews; **About** with the description, address, the week's
///   hours and how the work reaches the customer.
class ServiceProviderScreen extends StatefulWidget {
  const ServiceProviderScreen({
    super.key,
    required this.kit,
    required this.storeId,
    this.preview,
  });

  final ServicesKit kit;
  final String storeId;

  /// The card the customer tapped, for the header while the page loads.
  final StoreCard? preview;

  @override
  State<ServiceProviderScreen> createState() => _ServiceProviderScreenState();
}

enum _Tab { offers, reviews, about }

class _ServiceProviderScreenState extends State<ServiceProviderScreen> {
  ServicesKit get _kit => widget.kit;

  Store? _store;
  List<Product> _offers = const <Product>[];
  bool _failed = false;

  _Tab _tab = _Tab.offers;

  final List<StoreReview> _reviews = <StoreReview>[];

  /// The last page of reviews read; -1 before the first.
  int _reviewPage = -1;
  int _reviewPages = 0;
  bool _reviewsLoading = false;
  bool _reviewsFailed = false;

  List<OpeningWindow>? _hours;
  bool _hoursAsked = false;

  @override
  void initState() {
    super.initState();
    _kit.addresses.addListener(_repaint);
    unawaited(_load());
  }

  @override
  void dispose() {
    _kit.addresses.removeListener(_repaint);
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (_failed) setState(() => _failed = false);
    try {
      final (Store store, Paged<Product> page) =
          await (_kit.storeApi.read(widget.storeId), _kit.storeApi.products(widget.storeId, size: 50))
              .wait;
      if (!mounted) return;
      setState(() {
        _store = store;
        // A service shop's products are all offers; one without terms could not be ordered here.
        _offers = page.content.where((Product p) => p.isServiceOffer).toList(growable: false);
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _loadReviews() async {
    if (_reviewsLoading) return;
    setState(() {
      _reviewsLoading = true;
      _reviewsFailed = false;
    });
    try {
      final Paged<StoreReview> page =
          await _kit.storeApi.reviews(widget.storeId, page: _reviewPage + 1);
      if (!mounted) return;
      setState(() {
        _reviews.addAll(page.content);
        _reviewPage = page.page;
        _reviewPages = page.totalPages;
        _reviewsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reviewsLoading = false;
        _reviewsFailed = true;
      });
    }
  }

  Future<void> _loadHours() async {
    _hoursAsked = true;
    try {
      final List<OpeningWindow> hours = await _kit.storeApi.hours(widget.storeId);
      if (mounted) setState(() => _hours = hours);
    } catch (_) {
      // The hours are simply not drawn; the rest of About stands.
    }
  }

  void _select(_Tab tab) {
    setState(() => _tab = tab);
    if (tab == _Tab.reviews && _reviewPage < 0 && !_reviewsLoading) unawaited(_loadReviews());
    if (tab == _Tab.about && !_hoursAsked) unawaited(_loadHours());
  }

  /// An offer that needs a file, while this app cannot send one.
  bool _needsMissingFiles(Product offer) =>
      offer.service?.attachmentPolicy == ServiceAttachmentPolicy.required && _kit.files == null;

  bool _canOrder(Store store, Product offer) =>
      store.availability != StoreAvailability.closed &&
      (offer.service?.isEditable ?? false) &&
      !_needsMissingFiles(offer);

  void _order(Store store, Product offer) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ServiceOrderScreen(kit: _kit, store: store, offer: offer),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final Store? store = _store;
    if (store == null) {
      return Scaffold(
        backgroundColor: DeliveryColors.background,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SafeArea(
              bottom: false,
              child: YdScreenHeader(
                title: widget.preview?.name ?? '',
                onBack: () => Navigator.of(context).maybePop(),
                backSemanticLabel: t.back,
              ),
            ),
            Expanded(
              child: _failed
                  ? YdEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: t.couldNotLoadShop,
                      action: YdPillButton(
                        label: t.tryAgain,
                        expand: false,
                        size: YdPillButtonSize.compact,
                        onPressed: _load,
                      ),
                    )
                  : const Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          _hero(store, t),
          _identity(store, t),
          _tabBar(t),
          ...switch (_tab) {
            _Tab.offers => _offersTab(store, t),
            _Tab.reviews => _reviewsTab(t),
            _Tab.about => _aboutTab(store, t),
          },
          const SizedBox(height: DeliverySpacing.lg),
        ],
      ),
    );
  }

  Widget _hero(Store store, DeliveryStrings t) {
    final String? cover = store.coverUrl ?? store.coverThumbUrl;
    final double top = MediaQuery.paddingOf(context).top;
    return SizedBox(
      height: 150 + top,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (cover == null)
            StoreMonogram(name: store.name, radius: 0)
          else
            Image(
              image: DeliveryImages.provider(cover),
              fit: BoxFit.cover,
              errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                  StoreMonogram(name: store.name, radius: 0),
            ),
          PositionedDirectional(
            top: top + DeliverySpacing.sm,
            start: DeliverySpacing.md,
            child: YdBackButton(
              onPressed: () => Navigator.of(context).maybePop(),
              semanticLabel: t.back,
            ),
          ),
        ],
      ),
    );
  }

  Widget _identity(Store store, DeliveryStrings t) {
    return Container(
      color: DeliveryColors.white,
      padding: const EdgeInsetsDirectional.fromSTEB(
          DeliverySpacing.md, DeliverySpacing.md, DeliverySpacing.md, DeliverySpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  store.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800, color: DeliveryColors.ink, height: 1.2),
                ),
              ),
              if (store.verifiedLocal) ...<Widget>[
                const SizedBox(width: 6),
                Icon(Icons.verified_rounded,
                    size: 20, color: DeliveryColors.brand, semanticLabel: t.custVerifiedLocal),
              ],
            ],
          ),
          if ((store.tagline ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 2),
              child: Text(store.tagline!,
                  style: const TextStyle(fontSize: 14, color: DeliveryColors.muted)),
            ),
          const SizedBox(height: DeliverySpacing.sm),
          _meta(store, t),
        ],
      ),
    );
  }

  /// "★ 4.8 (56 reviews) • 0.5 km • Open until 6:00 PM", each part only when it is true.
  Widget _meta(Store store, DeliveryStrings t) {
    final DeliveryAddress? at = _kit.addresses.selected;
    final int? metres = at != null && at.hasPoint && store.hasPin
        ? distanceMetres(at.latitude!, at.longitude!, store.latitude!, store.longitude!).round()
        : null;
    final List<Widget> parts = <Widget>[
      Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RatingChip(rating: store.rating, unratedLabel: t.ratingNew, dense: true),
          if (store.rating != null && store.ratingCount > 0)
            Text(' (${t.svcReviewsCount(store.ratingCount)})',
                style: const TextStyle(fontSize: 12, color: DeliveryColors.muted)),
        ],
      ),
      if (metres != null)
        Text(serviceDistanceLabel(metres, t),
            style: const TextStyle(fontSize: 12, color: DeliveryColors.muted)),
      _availability(store, t),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: DeliverySpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final (int i, Widget part) in parts.indexed) ...<Widget>[
          if (i > 0) const Text('•', style: TextStyle(fontSize: 12, color: DeliveryColors.faint)),
          part,
        ],
      ],
    );
  }

  Widget _availability(Store store, DeliveryStrings t) {
    final String? closes = serviceClockLabel(context, store.closesAt);
    return switch (store.availability) {
      StoreAvailability.open when closes != null => Text(t.svcOpenUntil(closes),
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: DeliveryColors.brand)),
      _ => StoreStatePill(
          state: storeStateOf(store.availability),
          label: store.availability.labelIn(t),
          compact: true,
        ),
    };
  }

  Widget _tabBar(DeliveryStrings t) {
    Widget tab(_Tab value, String label) {
      final bool selected = _tab == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: InkWell(
            onTap: () => _select(value),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.md - 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? DeliveryColors.brand : DeliveryColors.border,
                    width: selected ? 3 : 1,
                  ),
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: selected ? DeliveryColors.brand : DeliveryColors.faint,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      color: DeliveryColors.white,
      child: Row(
        children: <Widget>[
          tab(_Tab.offers, t.svcOffers),
          tab(_Tab.reviews, t.reviews),
          tab(_Tab.about, t.svcTabAbout),
        ],
      ),
    );
  }

  static const EdgeInsetsGeometry _cardInsets = EdgeInsetsDirectional.fromSTEB(
      DeliverySpacing.md, DeliverySpacing.md, DeliverySpacing.md, 0);

  List<Widget> _offersTab(Store store, DeliveryStrings t) {
    final bool closed = store.availability == StoreAvailability.closed;
    return <Widget>[
      if (closed)
        Padding(
          padding: _cardInsets,
          child: YdCard.bordered(
            child: Row(
              children: <Widget>[
                const Icon(Icons.schedule_rounded, size: 18, color: DeliveryColors.muted),
                const SizedBox(width: DeliverySpacing.sm),
                Expanded(
                  child: Text(t.svcClosedNoOrders,
                      style: const TextStyle(fontSize: 13, color: DeliveryColors.ink)),
                ),
              ],
            ),
          ),
        ),
      if (_offers.isEmpty)
        YdEmptyState(icon: Icons.design_services_outlined, title: t.svcNoOffers)
      else
        for (final Product offer in _offers)
          Padding(
            padding: _cardInsets,
            child: ServiceOfferCard(
              offer: offer,
              onOrder: _canOrder(store, offer) ? () => _order(store, offer) : null,
              note: _needsMissingFiles(offer) ? t.svcNeedsFileUnavailable : null,
            ),
          ),
    ];
  }

  List<Widget> _reviewsTab(DeliveryStrings t) {
    if (_reviews.isEmpty) {
      if (_reviewsFailed) {
        return <Widget>[
          YdEmptyState(
            icon: Icons.cloud_off_rounded,
            title: t.svcCouldNotLoadReviews,
            action: YdPillButton(
              label: t.tryAgain,
              expand: false,
              size: YdPillButtonSize.compact,
              onPressed: _loadReviews,
            ),
          ),
        ];
      }
      if (_reviewPage < 0) {
        return const <Widget>[
          Padding(
            padding: EdgeInsets.all(DeliverySpacing.lg),
            child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
          ),
        ];
      }
      return <Widget>[YdEmptyState(icon: Icons.reviews_outlined, title: t.noReviewsYet)];
    }
    final bool more = _reviewPage + 1 < _reviewPages;
    return <Widget>[
      for (final StoreReview review in _reviews)
        Padding(padding: _cardInsets, child: _ReviewCard(review: review)),
      if (_reviewsFailed)
        Padding(
          padding: const EdgeInsetsDirectional.only(top: DeliverySpacing.md),
          child: Text(t.couldNotLoadMore,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: DeliveryColors.muted)),
        ),
      if (more || _reviewsFailed)
        Padding(
          padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
          child: Center(
            child: YdPillButton.secondary(
              label: t.svcLoadMore,
              expand: false,
              size: YdPillButtonSize.compact,
              busy: _reviewsLoading,
              onPressed: _reviewsLoading ? null : _loadReviews,
            ),
          ),
        ),
    ];
  }

  List<Widget> _aboutTab(Store store, DeliveryStrings t) {
    final bool pickup =
        _offers.any((Product o) => o.service?.fulfilmentModes.includesPickup ?? false);
    final bool delivery =
        _offers.any((Product o) => o.service?.fulfilmentModes.includesDelivery ?? false);
    final List<OpeningWindow>? hours = _hours;
    return <Widget>[
      Padding(
        padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if ((store.description ?? '').isNotEmpty) ...<Widget>[
              Text(store.description!,
                  style: const TextStyle(fontSize: 14, color: DeliveryColors.ink, height: 1.45)),
              const SizedBox(height: DeliverySpacing.md),
            ],
            if ((store.address ?? '').isNotEmpty || (store.neighborhood ?? '').isNotEmpty)
              _section(t.svcAboutAddress, <Widget>[
                if ((store.address ?? '').isNotEmpty) _plain(store.address!),
                if ((store.neighborhood ?? '').isNotEmpty) _plain(store.neighborhood!),
              ]),
            if (hours != null) _section(t.svcAboutHours, _hourRows(hours, t)),
            if (pickup || delivery)
              _section(t.svcAboutGetIt, <Widget>[
                if (pickup) _plain(t.svcPickupAtShop, icon: Icons.storefront_outlined),
                if (delivery) _plain(t.svcYouDropDelivery, icon: Icons.local_shipping_outlined),
              ]),
          ],
        ),
      ),
    ];
  }

  /// Monday to Sunday in the reader's language, each with its windows or "Closed".
  List<Widget> _hourRows(List<OpeningWindow> hours, DeliveryStrings t) {
    final DateFormat weekday = DateFormat.EEEE(Localizations.localeOf(context).toLanguageTag());
    return <Widget>[
      for (int day = DateTime.monday; day <= DateTime.sunday; day++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: <Widget>[
              Expanded(
                // 1 January 2024 was a Monday, so its day [day] is that weekday.
                child: Text(weekday.format(DateTime(2024, 1, day)),
                    style: const TextStyle(fontSize: 13, color: DeliveryColors.ink)),
              ),
              Text(
                _windowsOn(day, hours) ?? t.statusClosed,
                style: const TextStyle(fontSize: 13, color: DeliveryColors.muted),
              ),
            ],
          ),
        ),
    ];
  }

  String? _windowsOn(int day, List<OpeningWindow> hours) {
    final List<String> spans = <String>[
      for (final OpeningWindow window in hours.where((OpeningWindow w) => w.dayOfWeek == day))
        if ((serviceClockLabel(context, window.opensAt), serviceClockLabel(context, window.closesAt))
            case (final String opens, final String closes))
          '$opens – $closes',
    ];
    return spans.isEmpty ? null : spans.join(', ');
  }

  static Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.md),
        child: YdCard.bordered(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: DeliveryColors.ink)),
              const SizedBox(height: DeliverySpacing.sm),
              ...children,
            ],
          ),
        ),
      );

  static Widget _plain(String text, {IconData? icon}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 18, color: DeliveryColors.brand),
              const SizedBox(width: DeliverySpacing.sm),
            ],
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 13, color: DeliveryColors.ink)),
            ),
          ],
        ),
      );
}

/// One review: its stars, what the customer wrote, and when.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final StoreReview review;

  @override
  Widget build(BuildContext context) {
    final DateTime? at = review.createdAt;
    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            label: '★ ${review.rating}',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 1; i <= 5; i++)
                  Icon(
                    i <= review.rating ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 16,
                    color: DeliveryAccent.caution.color,
                  ),
              ],
            ),
          ),
          if (review.comment != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Text(review.comment!,
                style: const TextStyle(fontSize: 13, color: DeliveryColors.ink, height: 1.4)),
          ],
          if (at != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Text(MaterialLocalizations.of(context).formatMediumDate(at),
                style: const TextStyle(fontSize: 11, color: DeliveryColors.muted)),
          ],
        ],
      ),
    );
  }
}
