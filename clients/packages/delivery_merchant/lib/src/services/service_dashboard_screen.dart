import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../order_detail_screen.dart';
import 'service_offer_form_screen.dart';
import 'service_offers_screen.dart';
import 'service_shop.dart';

/// A services shop's home — Figma `service-provider-dashboard` (126:51).
///
/// Who the shop is (its name, the Verified Local badge only when the back office set it, its area),
/// three figures, two quick actions, and its current offers with Pause and Resume.
///
/// Every figure is one the platform has, or a dash:
/// - Active offers is the catalogue's count of the shop's ACTIVE offers — a count the server made,
///   not the length of a page.
/// - This week is the orders placed in the last seven days, from Order Manager's own summary.
/// - Rating is the shop's, and "New" until anybody has rated it: no rating is not a bad rating.
/// A figure that could not be read is a dash on its own card, and the others still show.
///
/// The frame draws the customer app's tab bar with Account lit, as if the provider lived inside the
/// customer app. It does not: the provider works in the shop shell's services mode, which draws its own
/// navigation, so nothing here draws one.
class ServiceDashboardScreen extends StatefulWidget {
  const ServiceDashboardScreen({
    super.key,
    required this.orderApi,
    required this.catalogApi,
    required this.storeApi,
    this.zoneApi,
    this.storeId,
    this.pendingApproval = false,
    this.onViewOrders,
    this.onShowOffers,
    this.onNotifications,
    this.unreadNotifications,
  });

  final OrderApi orderApi;
  final CatalogApi catalogApi;
  final StoreApi storeApi;

  /// The shop's delivery areas, for the offer form's delivery rule. See [ServiceOffersScreen.zoneApi].
  final DeliveryZoneApi? zoneApi;

  /// The services shop the shell resolved; null reads the owner's services shop.
  final String? storeId;

  /// True while the application is still being decided: offers can be drafted, not published.
  final bool pendingApproval;

  /// Switches the shell to its Orders tab. Null draws no View orders button.
  final VoidCallback? onViewOrders;

  /// Switches the shell to its Offers tab, behind "See all". Null draws no such link.
  final VoidCallback? onShowOffers;

  /// Opens the account's notifications. Null draws no bell.
  final VoidCallback? onNotifications;

  /// What the bell's badge counts; null or zero draws none.
  final int? unreadNotifications;

  @override
  State<ServiceDashboardScreen> createState() => _ServiceDashboardScreenState();
}

class _ServiceDashboardScreenState extends State<ServiceDashboardScreen> {
  /// How many current offers the dashboard lists before "See all" takes over.
  static const int _listed = 5;

  Store? _shop;
  bool _noShop = false;
  int? _activeOffers;
  int? _thisWeek;
  List<Product> _offers = const <Product>[];
  bool _offersFailed = false;
  bool? _reach;
  bool _loading = true;
  bool _failed = false;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ServiceDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storeId != widget.storeId) _load();
  }

  static Future<T?> _orNull<T>(Future<T> read) async {
    try {
      return await read;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final Store? shop;
    try {
      shop = await svcFindShop(widget.storeApi, widget.storeId);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    if (shop == null) {
      if (!mounted) return;
      setState(() {
        _shop = null;
        _noShop = true;
        _loading = false;
      });
      return;
    }

    // Independent reads, so one that fails leaves only its own figure a dash.
    final Future<Paged<Product>?> active = _orNull(widget.catalogApi
        .myProducts(storeId: shop.id, status: ProductStatus.active, size: 1));
    final Future<MerchantSummary?> week = _orNull(widget.orderApi.merchantSummary(days: 7));
    final Future<Paged<Product>?> offers =
        _orNull(widget.catalogApi.myProducts(storeId: shop.id, size: 20));
    final Future<bool?> reach = svcDeliveryReach(shop, widget.zoneApi);

    final Paged<Product>? activePage = await active;
    final MerchantSummary? summary = await week;
    final Paged<Product>? offerPage = await offers;
    final bool? reaches = await reach;
    if (!mounted) return;
    setState(() {
      _shop = shop;
      _noShop = false;
      _activeOffers = activePage?.totalElements;
      _thisWeek = summary?.window.orders;
      _offers = offerPage == null
          ? const <Product>[]
          : offerPage.content
              .where((Product offer) => offer.status != ProductStatus.archived)
              .toList(growable: false);
      _offersFailed = offerPage == null;
      _reach = reaches;
      _loading = false;
      _failed = activePage == null && summary == null && offerPage == null;
    });
  }

  Future<void> _openForm([Product? existing]) async {
    final Store? shop = _shop;
    if (shop == null) return;
    await Navigator.of(context).push<Object?>(MaterialPageRoute<Object?>(
      builder: (_) => ServiceOfferFormScreen(
        api: widget.catalogApi,
        shop: shop,
        storeApi: widget.storeApi,
        deliveryReach: _reach,
        existing: existing,
        pendingApproval: widget.pendingApproval,
      ),
    ));
    if (mounted) await _load();
  }

  Future<void> _toggle(Product offer) async {
    setState(() => _busyId = offer.id);
    final Product? moved =
        await svcToggleOffer(context, widget.catalogApi, offer, deliveryReach: _reach);
    if (!mounted) return;
    setState(() {
      _busyId = null;
      if (moved != null) {
        _offers = <Product>[for (final Product p in _offers) p.id == moved.id ? moved : p];
        // A pause or a resume moves the live count by one; the next load says it exactly.
        final int? count = _activeOffers;
        if (count != null && moved.status != offer.status) {
          _activeOffers = moved.status == ProductStatus.active ? count + 1 : count - 1;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return ColoredBox(
      color: DeliveryColors.background,
      child: RefreshIndicator(
        onRefresh: _load,
        color: DeliveryColors.brand,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(DeliverySpacing.md),
          children: <Widget>[
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _content(t),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(DeliveryStrings t) {
    const SizedBox gap = SizedBox(height: DeliverySpacing.md);
    final Store? shop = _shop;

    if (_loading && shop == null && !_noShop) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.all(DeliverySpacing.xl),
          child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
        ),
      ];
    }
    if (_failed) {
      return <Widget>[
        YdEmptyState(
          icon: Icons.cloud_off_rounded,
          title: t.svcDashboardLoadFailed,
          message: t.thatDidNotGoThrough,
          action: YdPillButton.secondary(
            label: t.tryAgain,
            onPressed: _load,
            size: YdPillButtonSize.compact,
            expand: false,
          ),
        ),
      ];
    }

    return <Widget>[
      _header(t, shop),
      if (widget.pendingApproval) ...<Widget>[gap, SvcNotice(text: t.svcPublishAfterApproval)],
      if (_noShop || shop == null)
        YdEmptyState(
          icon: Icons.storefront_outlined,
          title: t.svcNoShopYet,
          message: t.svcNoShopYetBody,
        )
      else ...<Widget>[
        gap,
        _stats(t, shop),
        const SizedBox(height: DeliverySpacing.lg),
        _Caption(t.svcQuickActions),
        const SizedBox(height: DeliverySpacing.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: YdPillButton(
                label: t.svcAddOffer,
                icon: Icons.add_rounded,
                size: YdPillButtonSize.compact,
                onPressed: () => _openForm(),
              ),
            ),
            if (widget.onViewOrders != null) ...<Widget>[
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                child: YdPillButton.secondary(
                  label: t.svcViewOrders,
                  icon: Icons.assignment_outlined,
                  size: YdPillButtonSize.compact,
                  onPressed: widget.onViewOrders,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: DeliverySpacing.lg),
        _offersSection(t),
      ],
    ];
  }

  Widget _header(DeliveryStrings t, Store? shop) {
    final String? area = shop?.neighborhood ?? shop?.address;
    final VoidCallback? onBell = widget.onNotifications;
    return Row(
      children: <Widget>[
        if (shop != null) ...<Widget>[
          StoreAvatar(name: shop.name, logoUrl: shop.logoThumbUrl ?? shop.logoUrl, size: 40),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        shop.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.ink,
                        ),
                      ),
                    ),
                    // Only when the back office set it: a provider cannot award themselves this.
                    if (shop.verifiedLocal) ...<Widget>[
                      const SizedBox(width: DeliverySpacing.xs),
                      Icon(
                        Icons.verified_rounded,
                        size: 16,
                        color: DeliveryColors.brand,
                        semanticLabel: t.custVerifiedLocal,
                      ),
                    ],
                  ],
                ),
                if (area != null)
                  Text(
                    area,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
                  ),
              ],
            ),
          ),
        ] else
          const Spacer(),
        if (onBell != null) _Bell(count: widget.unreadNotifications, onTap: onBell),
      ],
    );
  }

  Widget _stats(DeliveryStrings t, Store shop) {
    final double? rating = shop.rating;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: _Stat(
              label: t.svcDashboardActiveOffers,
              value: _activeOffers?.toString() ?? '—',
              color: DeliveryColors.brand,
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: _Stat(
              label: t.svcDashboardThisWeek,
              value: _thisWeek?.toString() ?? '—',
              color: DeliveryColors.ink,
              caption: t.svcDashboardThisWeekCaption,
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: _Stat(
              label: t.svcDashboardRating,
              value: rating == null ? t.ratingNew : '★ ${rating.toStringAsFixed(1)}',
              color: DeliveryAccent.positive.onTint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _offersSection(DeliveryStrings t) {
    final List<Product> shown = _offers.take(_listed).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                t.svcCurrentOffers,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                ),
              ),
            ),
            if (widget.onShowOffers != null && _offers.length > _listed)
              TextButton(onPressed: widget.onShowOffers, child: Text(t.svcSeeAllOffers)),
          ],
        ),
        const SizedBox(height: DeliverySpacing.sm),
        if (_offersFailed)
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  t.svcOffersLoadFailed,
                  style: const TextStyle(fontSize: 13, color: DeliveryColors.muted),
                ),
              ),
              TextButton(onPressed: _load, child: Text(t.tryAgain)),
            ],
          )
        else if (_offers.isEmpty)
          YdEmptyState(
            icon: Icons.design_services_outlined,
            title: t.svcNoOffersYet,
            message: t.svcNoOffersYetBody,
            action: YdPillButton(
              label: t.svcAddOffer,
              icon: Icons.add_rounded,
              size: YdPillButtonSize.compact,
              expand: false,
              onPressed: () => _openForm(),
            ),
          )
        else
          for (int i = 0; i < shown.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: DeliverySpacing.sm),
            SvcOfferRow(
              offer: shown[i],
              busy: _busyId == shown[i].id,
              onTap: () => _openForm(shown[i]),
              onToggle: _busyId == null ? () => _toggle(shown[i]) : null,
            ),
          ],
      ],
    );
  }
}

/// One of the frame's three figures: a small label, a large value, and an optional caption.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color, this.caption});

  final String label;
  final String value;
  final Color color;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return YdCard.bordered(
      padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: DeliveryColors.muted,
              height: 1.25,
            ),
          ),
          const SizedBox(height: DeliverySpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color),
            ),
          ),
          if (caption != null)
            Text(
              caption!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: DeliveryColors.faint, height: 1.25),
            ),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: DeliveryColors.muted),
    );
  }
}

/// The frame's bell: a brand glyph in a soft circle, with the unread count when there is one.
class _Bell extends StatelessWidget {
  const _Bell({required this.onTap, this.count});

  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final int unread = count ?? 0;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Material(
          color: DeliveryColors.brandSoft,
          shape: const CircleBorder(),
          child: IconButton(
            onPressed: onTap,
            tooltip: t.notifications,
            icon: const Icon(Icons.notifications_none_rounded, color: DeliveryColors.brand, size: 22),
          ),
        ),
        if (unread > 0)
          PositionedDirectional(
            top: 2,
            end: 2,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: DeliveryColors.brand,
                  borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                  border: Border.all(color: DeliveryColors.white, width: 1.5),
                ),
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.white,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
