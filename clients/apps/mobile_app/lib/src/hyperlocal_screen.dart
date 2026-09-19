import 'dart:math' as math;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'address_sheet.dart';
import 'cart.dart';
import 'delivery_address.dart';
import 'neighbourhood_map_screen.dart';
import 'product_detail_screen.dart' show CustomerPhoto;
import 'store_page_screen.dart';
import 'store_power_chip.dart';
import 'store_state_mapping.dart';

/// The chips over the neighbourhood browse. Single-select, as the frame draws them.
///
/// Every one is a filter the server applies before the page is cut (see [StoreApi.nearby]), so
/// pages stay full and the list never quietly stops short. Two of the frame's five are not what it
/// drew, on purpose:
///
/// * "Has Generator" is [onGenerator], labelled "On generator now". The platform's data is what
///   the merchant says the lights are doing at this moment — mains, generator, dark — not whether
///   the shop owns a generator. A chip that said "has" would drop every shop that owns one and is
///   on mains right now, and present that as an answer.
/// * "Delivers" is not drawn at all. Every shop on YouDrop delivers, and whether the chip means "to
///   my door", "with its own rider" or something else is not decided; a chip whose meaning nobody
///   has settled cannot filter truthfully, and a control that cannot work is not drawn.
enum DekkaneFilter { all, openNow, onGenerator, joinedRecently }

/// "350 m away", "1.2 km away" — the distance line on a neighbourhood card, in the reader's
/// language and digits.
///
/// Tens of metres under a kilometre and one decimal above it. The distance is straight-line from
/// a pin somebody dropped by hand to another somebody dropped by hand, so a figure to the metre
/// would be claiming precision nobody has.
String dekkaneDistanceLabel(DeliveryStrings t, int metres) {
  final int tens = math.max(10, (metres / 10).round() * 10);
  if (tens < 1000) {
    return t.dekkaneDistanceMetres(tens);
  }
  return t.dekkaneDistanceKm((metres / 100).round() / 10);
}

/// The neighbourhood browse (Figma `customer-dekkane-browse`, 112:1941): the dekkanes around the
/// customer's delivery address, nearest first, each card carrying its distance, the Backoffice
/// trust badge where one was granted, and what the shop's lights are doing.
///
/// **Two sources, chosen by the address.** With an address pinned on the map the list comes from
/// `GET /api/stores/nearby` around that point — distance on every card, the chips, the map preview.
/// Without one there is no point to be near, so the list falls back to the storefront browse and
/// says plainly what pinning the address would add; the chips, the map and the distances are not
/// drawn, because each of them needs the point and would otherwise be a control that does nothing
/// or a number the platform does not have. Nor is the fallback called the neighbourhood: it is every
/// shop on the platform, best rated first, and its title, subtitle and heading say that instead.
///
/// **Pushed over the shell**, like every shop list. The frame draws a bottom bar with a "Shops"
/// tab the shipped customer bar does not have; that is the frame's, not a destination.
///
/// **A closed shop is dimmed, not hidden, and so is one currently declared dark.** Under "All" the
/// list holds shops that are shut right now. Each says so on its cover instead of letting a customer
/// open it to a shelf with nothing to add, and a list that silently dropped them would make the
/// neighbourhood look smaller than it is.
class HyperlocalScreen extends StatefulWidget {
  const HyperlocalScreen({
    super.key,
    required this.storeApi,
    required this.orderApi,
    required this.cart,
    required this.addresses,
    required this.onOpenBasket,
    this.zoneApi,
    this.shopChatAction,
  });

  final StoreApi storeApi;
  final OrderApi orderApi;
  final Cart cart;

  /// The shell's address book. The browse is measured from its selected address, reloads when that
  /// changes, and the location bar opens the same address sheet the home header does.
  final DeliveryAddressStore addresses;

  /// For the address sheet's area picker and the region in the header's subtitle. Optional: without
  /// it the sheet still takes a typed line and the subtitle keeps its generic wording.
  final DeliveryZoneApi? zoneApi;

  /// Handed to every shop opened from this list, for its basket bar. See
  /// [StorePageScreen.onOpenBasket].
  final VoidCallback onOpenBasket;

  /// Passed through to each dekkane shop page. Null today — see
  /// [StorePageScreen.shopChatAction] for what goes here and who wires it.
  final ShopChatActionBuilder? shopChatAction;

  /// How far "your neighbourhood" reaches: two kilometres, a walk of about twenty-five minutes.
  ///
  /// A neighbourhood, not a city. The home screen's nearby rail looks five kilometres out; a
  /// dekkane is the shop at the end of the street, and a list that reached across Beirut would
  /// bury it under every supermarket in range.
  static const int radiusMetres = 2000;

  /// What "New on YouDrop" means: first listed on the platform in the last thirty days.
  static const int joinedWithinDays = 30;

  /// The frame's map preview height.
  static const double mapPreviewHeight = 100;

  @override
  State<HyperlocalScreen> createState() => _HyperlocalScreenState();
}

/// One card's worth: the shop, and how far it is when there is a point to measure from.
typedef _Shop = ({StoreCard store, int? distanceMetres});

class _HyperlocalScreenState extends State<HyperlocalScreen> {
  /// How far below the location bar its tap reaches.
  ///
  /// The bar is drawn at the frame's height, about 34px, under the 44px a thumb needs. This band is
  /// the top padding of the row beneath it — the chips, or the pin prompt — moved up into the bar's
  /// tap area, so the target is 46px and nothing on the screen moves.
  static const double _locationBarSlop = DeliverySpacing.md - 4;

  DekkaneFilter _filter = DekkaneFilter.all;

  /// The point the nearby list was loaded around, or null while the browse fallback is showing.
  ///
  /// Held here rather than read off the address inside the fetch, so a next page requested after
  /// the address changed cannot be measured from the new point and appended to a list measured
  /// from the old one.
  LatLng? _point;

  /// The area the region subtitle was looked up for, so a late answer about the old one is dropped.
  String? _zoneId;
  String? _region;

  /// How many of the nearest shops the list covers when the search reached its ceiling, or null
  /// when it did not ([NearbyPage.truncated]). Only an answer to the question on screen may set it:
  /// [_question] moves on with every new address and chip, so a ceiling reached under one chip
  /// never labels the list of another.
  int? _searchedNearest;
  int _question = 0;

  late final PagedList<NearbyStore> _nearby = PagedList<NearbyStore>(
    pageSize: 20,
    fetch: (int page, int size) async {
      final LatLng point = _point!;
      final int question = _question;
      final NearbyPage answer = await widget.storeApi.nearby(
        point.latitude,
        point.longitude,
        radiusMetres: HyperlocalScreen.radiusMetres,
        openNow: _filter == DekkaneFilter.openNow,
        powerStatus: _filter == DekkaneFilter.onGenerator ? StorePowerStatus.generator : null,
        newSinceDays: _filter == DekkaneFilter.joinedRecently
            ? HyperlocalScreen.joinedWithinDays
            : null,
        page: page,
        size: size,
      );
      if (question == _question) {
        _searchedNearest = answer.truncated ? answer.candidateLimit : null;
      }
      return answer;
    },
  );

  late final PagedList<StoreCard> _browse = PagedList<StoreCard>(
    pageSize: 20,
    fetch: (int page, int size) =>
        widget.storeApi.browseWith(const StoreFilters(), page: page, size: size),
  );

  bool get _near => _point != null;

  PagedList<Object?> get _active => _near ? _nearby : _browse;

  List<_Shop> get _shops => _near
      ? <_Shop>[
          for (final NearbyStore n in _nearby.items)
            (store: n.store, distanceMetres: n.distanceMetres),
        ]
      : <_Shop>[
          for (final StoreCard s in _browse.items) (store: s, distanceMetres: null),
        ];

  @override
  void initState() {
    super.initState();
    _nearby.addListener(_changed);
    _browse.addListener(_changed);
    widget.addresses.addListener(_addressChanged);
    _reload();
  }

  @override
  void dispose() {
    widget.addresses.removeListener(_addressChanged);
    _nearby
      ..removeListener(_changed)
      ..dispose();
    _browse
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  static LatLng? _pointOf(DeliveryAddress? address) => address != null && address.hasPoint
      ? LatLng(address.latitude!, address.longitude!)
      : null;

  void _reload() {
    final DeliveryAddress? address = widget.addresses.selected;
    _point = _pointOf(address);
    if (_near) {
      _askNearby();
    } else {
      _browse.refresh();
    }
    _loadRegion(address?.zoneId);
  }

  /// Puts a new question to the nearby search. The ceiling note belonged to the last answer, so it
  /// goes with it rather than labelling a list it was never about.
  void _askNearby() {
    _question++;
    _searchedNearest = null;
    _nearby.refresh();
  }

  /// A new address is a new neighbourhood. The same one re-selected — or the store merely
  /// finishing its load with what was already there — is not a reason to throw the list away.
  void _addressChanged() {
    final DeliveryAddress? address = widget.addresses.selected;
    if (_pointOf(address) == _point && address?.zoneId == _zoneId) {
      _changed();
      return;
    }
    _reload();
    _changed();
  }

  /// The region the address's area belongs to — "Beirut" — for the header's "Local Beirut
  /// dekkanes". Quiet on failure: the subtitle keeps its generic line rather than naming a city
  /// nobody confirmed.
  Future<void> _loadRegion(String? zoneId) async {
    _zoneId = zoneId;
    _region = null;
    final DeliveryZoneApi? api = widget.zoneApi;
    if (zoneId == null || api == null) return;
    try {
      final List<DeliveryZone> zones = await api.picker();
      if (!mounted || zoneId != _zoneId) return;
      String? region;
      for (final DeliveryZone zone in zones) {
        if (zone.id == zoneId) region = zone.region?.trim();
      }
      setState(() => _region = (region == null || region.isEmpty) ? null : region);
    } catch (_) {
      // The generic subtitle stays.
    }
  }

  void _select(DekkaneFilter filter) {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    _askNearby();
  }

  void _open(StoreCard store) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StorePageScreen(
        storeApi: widget.storeApi,
        orderApi: widget.orderApi,
        cart: widget.cart,
        storeId: store.id,
        preview: store,
        addresses: widget.addresses,
        onOpenBasket: widget.onOpenBasket,
        layout: StorePageLayout.dekkane,
        shopChatAction: widget.shopChatAction,
      ),
    ));
  }

  void _openMap() {
    final LatLng? home = _point;
    if (home == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NeighbourhoodMapScreen(
        home: home,
        shops: _nearby.items,
        onOpenShop: _open,
      ),
    ));
  }

  void _pickAddress() =>
      showAddressSheet(context, widget.addresses, zoneApi: widget.zoneApi);

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final PagedList<Object?> list = _active;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        // Without a point the list is the whole storefront, and it is named as that.
        title: _near ? t.dekkaneBrowseTitle : t.dekkaneBrowseTitleAll,
        subtitle: !_near
            ? t.dekkaneBrowseSubAll
            : _region == null
                ? t.custHyperlocalSub
                : t.dekkaneBrowseSubRegion(_region!),
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
        trailing: YouDropPill(semanticLabel: t.appTitle),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          // depth 0: the chip strip scrolls sideways and would otherwise report its own metrics.
          if (notification.depth == 0 && shouldLoadMore(notification.metrics)) {
            list.loadMore();
          }
          return false;
        },
        child: RefreshIndicator(
          color: DeliveryColors.brand,
          onRefresh: list.refresh,
          child: CustomScrollView(
            // A short list still pulls to refresh.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(child: _locationBar(t)),
              SliverToBoxAdapter(child: _near ? _filterRow(t) : _pinPrompt(t)),
              if (_near && _nearby.items.isNotEmpty) SliverToBoxAdapter(child: _mapPreview(t)),
              SliverToBoxAdapter(
                child: _sectionLabel(_near ? t.dekkaneNearbyShops : t.dekkaneAllShops),
              ),
              ..._listSlivers(t, list),
              const SliverToBoxAdapter(child: SizedBox(height: DeliverySpacing.xl)),
            ],
          ),
        ),
      ),
    );
  }

  /// The frame's `location-bar`: the area the list is measured from, and the way to change it.
  Widget _locationBar(DeliveryStrings t) {
    final DeliveryAddress? address = widget.addresses.selected;
    final String? area = address?.zoneName?.trim();
    final String label = address == null
        ? t.setDeliveryAddress
        : (area == null || area.isEmpty)
            ? address.line
            : (_region == null ? area : t.dekkaneAreaInRegion(area, _region!));

    // The band under the bar answers its tap as well ([_locationBarSlop]). Left out of semantics:
    // the bar itself is the button a screen reader is offered.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: _pickAddress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Material(
            color: DeliveryColors.white,
            child: InkWell(
              onTap: _pickAddress,
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm),
                child: Semantics(
                  button: true,
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.location_on_outlined, size: 16, color: DeliveryColors.brand),
                      const SizedBox(width: DeliverySpacing.sm),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: DeliveryColors.ink,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: _locationBarSlop),
        ],
      ),
    );
  }

  Widget _filterRow(DeliveryStrings t) {
    Widget chip(DekkaneFilter filter, String label, {IconData? icon}) => YdChip(
          label: label,
          icon: icon,
          selected: _filter == filter,
          onTap: () => _select(filter),
        );

    return SizedBox(
      // Its top padding is the location bar's tap band now; see [_locationBarSlop].
      height: YdChip.minHeight + DeliverySpacing.lg - _locationBarSlop,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.fromSTEB(
            DeliverySpacing.md, 0, DeliverySpacing.md, DeliverySpacing.md - 4),
        children: <Widget>[
          chip(DekkaneFilter.all, t.all),
          const SizedBox(width: DeliverySpacing.sm),
          chip(DekkaneFilter.openNow, t.dekkaneFilterOpenNow),
          const SizedBox(width: DeliverySpacing.sm),
          chip(DekkaneFilter.onGenerator, t.dekkaneFilterOnGenerator, icon: Icons.bolt_rounded),
          const SizedBox(width: DeliverySpacing.sm),
          chip(DekkaneFilter.joinedRecently, t.dekkaneFilterNew),
        ],
      ),
    );
  }

  /// Without a pinned address: what pinning it would add, as the way to do it.
  Widget _pinPrompt(DeliveryStrings t) {
    return Padding(
      // No top padding: that is the location bar's tap band; see [_locationBarSlop].
      padding: const EdgeInsetsDirectional.fromSTEB(
          DeliverySpacing.md, 0, DeliverySpacing.md, DeliverySpacing.md),
      child: YdCard.bordered(
        onTap: _pickAddress,
        padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - 4),
        child: Row(
          children: <Widget>[
            const Icon(Icons.push_pin_outlined, size: 18, color: DeliveryColors.brand),
            const SizedBox(width: DeliverySpacing.md - 4),
            Expanded(
              child: Text(
                t.dekkanePinAddressPrompt,
                style: const TextStyle(fontSize: 12.5, color: DeliveryColors.muted, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The frame's 100px `map-preview`: a real map of the address and the loaded shops, still, with
  /// the one control that opens it full screen. When the tiles cannot be fetched the preview says
  /// so and drops the control — the full map would be the same dead surface, larger.
  Widget _mapPreview(DeliveryStrings t) {
    final LatLng home = _point!;
    final List<NearbyStore> shops = _nearby.items;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          DeliverySpacing.md, 0, DeliverySpacing.md, DeliverySpacing.md),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        child: SizedBox(
          height: HyperlocalScreen.mapPreviewHeight,
          child: OsmBasemap(
            options: MapOptions(
              initialCameraFit: CameraFit.coordinates(
                coordinates: <LatLng>[
                  home,
                  for (final NearbyStore shop in shops) LatLng(shop.latitude, shop.longitude),
                ],
                padding: const EdgeInsets.all(20),
                maxZoom: 16,
              ),
              // A preview, not a map to use: it must not swallow the page's own scroll.
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
            ),
            layers: <Widget>[
              ExcludeSemantics(
                child: MarkerLayer(
                  markers: <Marker>[
                    Marker(
                      point: home,
                      width: 20,
                      height: 20,
                      child: const Icon(Icons.place, size: 20, color: DeliveryColors.ink),
                    ),
                    for (final NearbyStore shop in shops)
                      Marker(
                        point: LatLng(shop.latitude, shop.longitude),
                        width: 12,
                        height: 12,
                        child: Container(
                          decoration: BoxDecoration(
                            color: DeliveryColors.brand,
                            shape: BoxShape.circle,
                            border: Border.all(color: DeliveryColors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            fallback: const NeighbourhoodMapUnavailable(compact: true),
            overlay: (bool tilesLive) => tilesLive
                ? Center(
                    child: NeighbourhoodMapExpandButton(
                      label: t.dekkaneExpandMap,
                      onPressed: _openMap,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          DeliverySpacing.md, 0, DeliverySpacing.md, DeliverySpacing.md),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: DeliveryColors.ink,
          height: 1.2,
        ),
      ),
    );
  }

  List<Widget> _listSlivers(DeliveryStrings t, PagedList<Object?> list) {
    if (list.isLoadingFirstPage) {
      return const <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
        ),
      ];
    }
    // A first page that failed. Without this the screen showed the empty state — "no shops
    // match" — over a request that never answered, which is a different and untrue sentence.
    if (list.error != null && list.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: YdEmptyState(
            icon: Icons.cloud_off,
            title: t.dekkaneCouldNotLoadShops,
            action: YdPillButton(
              label: t.tryAgain,
              onPressed: list.refresh,
              size: YdPillButtonSize.compact,
              expand: false,
            ),
          ),
        ),
      ];
    }
    if (list.isEmptyAfterLoad) {
      final bool filtered = _near && _filter != DekkaneFilter.all;
      final int? nearest = _near ? _searchedNearest : null;
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: YdEmptyState(
            icon: Icons.storefront_outlined,
            title: filtered || !_near ? t.noShopsMatch : t.dekkaneNoShopsNearby,
            // Past the search's ceiling, "none match" is only known of the nearest shops, so the
            // message says which shops were looked at.
            message: nearest != null
                ? t.dekkaneSearchedNearest(nearest)
                : (filtered ? t.tryClearingAFilter : null),
          ),
        ),
      ];
    }

    final List<_Shop> shops = _shops;
    return <Widget>[
      SliverPadding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: DeliverySpacing.md),
        sliver: SliverList.separated(
          itemCount: shops.length,
          separatorBuilder: (_, __) => const SizedBox(height: DeliverySpacing.md),
          itemBuilder: (BuildContext context, int i) => DekkaneShopCard(
            store: shops[i].store,
            distanceMetres: shops[i].distanceMetres,
            onTap: () => _open(shops[i].store),
          ),
        ),
      ),
      SliverToBoxAdapter(child: _footer(t, list)),
    ];
  }

  Widget _footer(DeliveryStrings t, PagedList<Object?> list) {
    if (list.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(DeliverySpacing.lg),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: DeliveryColors.brand),
          ),
        ),
      );
    }
    if (list.error != null && list.items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(DeliverySpacing.md),
        child: Center(
          child: TextButton.icon(
            onPressed: list.loadMore,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(t.couldNotLoadMore),
            style: TextButton.styleFrom(foregroundColor: DeliveryColors.brand),
          ),
        ),
      );
    }
    // Past the search's ceiling the list is the nearest shops only. Said at its end, so the last
    // card is not taken for the edge of the neighbourhood.
    final int? nearest = _near ? _searchedNearest : null;
    if (nearest != null && !list.hasMore) {
      return Padding(
        padding: const EdgeInsets.all(DeliverySpacing.md),
        child: Text(
          t.dekkaneSearchedNearest(nearest),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.35),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// One dekkane on the browse (the frame's shop card): a 120px cover, the name against the trust
/// badge, one line about the shop, and the rating, the distance and the power badge underneath.
///
/// The fact line is the shop's own tagline, then the merchant's power note, then the kind of shop —
/// whichever exists first, so the line is never empty and never invented. The distance appears
/// only when there was a point to measure from.
///
/// A shop that is not simply open says so on its cover — closing soon, busy, closed — in the pill
/// the dekkane shop page's hero uses, and a closed one is dimmed like a dark one
/// ([dekkaneDimmed]). The frame's list is headed "active nearby shops"; a shut shop that looked like
/// the rest was opened only to show a shelf with nothing to add.
class DekkaneShopCard extends StatelessWidget {
  const DekkaneShopCard({
    super.key,
    required this.store,
    required this.onTap,
    this.distanceMetres,
  });

  final StoreCard store;
  final int? distanceMetres;
  final VoidCallback onTap;

  static const double coverHeight = 120;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String? tagline = store.tagline?.trim();
    final String? note = store.powerNote?.trim();
    final String fact = (tagline != null && tagline.isNotEmpty)
        ? tagline
        : (note != null && note.isNotEmpty)
            ? note
            : store.vertical.labelIn(t);

    final Widget card = YdCard.bordered(
      padding: EdgeInsets.zero,
      clipContent: true,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: coverHeight,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                CustomerPhoto(
                  // A list surface: the derivative, falling back to the full-size cover by itself.
                  url: store.listCoverUrl,
                  width: double.infinity,
                  height: coverHeight,
                  icon: iconForVertical(store.vertical),
                ),
                if (store.availability != StoreAvailability.open)
                  PositionedDirectional(
                    top: DeliverySpacing.sm,
                    start: DeliverySpacing.sm,
                    child: DekkaneStatePill(availability: store.availability),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        store.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.ink,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (store.verifiedLocal) ...<Widget>[
                      const SizedBox(width: DeliverySpacing.sm),
                      const TrustedLocalBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: DeliverySpacing.sm),
                Text(
                  fact,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.3),
                ),
                const SizedBox(height: DeliverySpacing.sm),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints row) => Row(
                    children: <Widget>[
                      _rating(t),
                      if (distanceMetres != null) ...<Widget>[
                        const Padding(
                          padding:
                              EdgeInsetsDirectional.symmetric(horizontal: DeliverySpacing.sm),
                          child: Text('•',
                              style: TextStyle(fontSize: 12, color: DeliveryColors.faint)),
                        ),
                        // Expanded, with no Spacer beside it. A Flexible and a Spacer split what the
                        // rating and the badge left evenly, so on a 360px phone "350 m away" lost
                        // its last word while an empty stretch as wide sat next to it.
                        Expanded(
                          child: Text(
                            dekkaneDistanceLabel(t, distanceMetres!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: DeliveryColors.muted, height: 1.2),
                          ),
                        ),
                      ] else
                        const Spacer(),
                      const SizedBox(width: DeliverySpacing.sm),
                      // At most half the row. The badge is far narrower than that in practice;
                      // past it — a long translation, a large system text size — its words
                      // shorten rather than pushing the row off the card.
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: row.maxWidth / 2),
                        child: DekkanePowerPill(store: store),
                      ),
                    ],
                  ),
                ),
                // How long ago the merchant said so, under the badge and on a line of its own, so
                // the words never take room from the distance however long they run.
                if (DekkanePowerPill.shows(store) && store.powerUpdatedAt != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: DekkanePowerAge(store: store),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return dekkaneDimmed(store) ? Opacity(opacity: 0.55, child: card) : card;
  }

  /// The frame's amber "★ 4.6". The star is the amber glyph; the number is the same hue's darker
  /// stop, because the bright amber measures under 3:1 as 12px text on white — the token system's
  /// own rule for accents on bare white. "New" is muted for the same reason: faint is for
  /// decoration, and this is a word someone reads.
  Widget _rating(DeliveryStrings t) {
    final double? rating = store.rating;
    if (rating == null) {
      return Text(
        t.ratingNew,
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: DeliveryColors.muted, height: 1.2),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.star_rounded, size: 14, color: DeliveryAccent.caution.color),
        const SizedBox(width: 2),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: DeliveryAccent.caution.onTint,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}
