import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'cart.dart';
import 'product_detail_screen.dart' show CustomerPhoto;
import 'store_page_screen.dart';
import 'store_power_chip.dart';
import 'store_state_mapping.dart';

/// The neighborhood browse (Figma `neighborhood-browse` + `shop-power-status`, merged): district
/// chips over the shops of that district, each row carrying its power chip, the verified-local
/// badge where Backoffice granted one, and a DARK shop dimmed rather than hidden.
///
/// One screen for both frames on purpose — they are the same list wearing two headings, and the
/// power column belongs on every hyperlocal row anyway. The search hint speaks arabizi because
/// that is how these shops are actually asked for.
class HyperlocalScreen extends StatefulWidget {
  const HyperlocalScreen({
    super.key,
    required this.storeApi,
    required this.orderApi,
    required this.cart,
  });

  final StoreApi storeApi;
  final OrderApi orderApi;
  final Cart cart;

  @override
  State<HyperlocalScreen> createState() => _HyperlocalScreenState();
}

class _HyperlocalScreenState extends State<HyperlocalScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  List<String> _districts = const <String>[];
  StoreFilters _filters = const StoreFilters();

  late final PagedList<StoreCard> _stores = PagedList<StoreCard>(
    pageSize: 20,
    fetch: (int page, int size) =>
        widget.storeApi.browseWith(_filters, page: page, size: size),
  );

  @override
  void initState() {
    super.initState();
    _stores.addListener(_changed);
    _stores.refresh();
    _loadDistricts();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDistricts() async {
    try {
      final List<String> districts = await widget.storeApi.neighborhoods();
      if (!mounted) return;
      setState(() => _districts = districts);
    } catch (_) {
      // The chips row stays empty; the list still lists.
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _stores.removeListener(_changed);
    _stores.dispose();
    super.dispose();
  }

  void _selectDistrict(String? district) {
    setState(() => _filters = district == null
        ? _filters.copyWith(clearNeighborhood: true)
        : _filters.copyWith(neighborhood: district));
    _stores.refresh();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _filters = _filters.copyWith(
            search: value.trim().isEmpty ? null : value.trim(),
            clearSearch: value.trim().isEmpty,
          ));
      _stores.refresh();
    });
  }

  void _open(StoreCard store) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StorePageScreen(
        storeApi: widget.storeApi,
        orderApi: widget.orderApi,
        cart: widget.cart,
        storeId: store.id,
        preview: store,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: t.custHyperlocalTitle,
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          if (notification.depth == 0 && shouldLoadMore(notification.metrics)) {
            _stores.loadMore();
          }
          return false;
        },
        child: RefreshIndicator(
          color: DeliveryColors.brand,
          onRefresh: _stores.refresh,
          child: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                      DeliverySpacing.md, DeliverySpacing.sm, DeliverySpacing.md, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        t.custHyperlocalSub,
                        style: const TextStyle(
                          fontSize: 13,
                          color: DeliveryColors.muted,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: DeliverySpacing.md),
                      YdSearchField(
                        controller: _search,
                        hintText: t.custSearchArabiziHint,
                        onChanged: _onSearch,
                        searchSemanticLabel: t.custSearchArabiziHint,
                      ),
                    ],
                  ),
                ),
              ),
              if (_districts.isNotEmpty) ...<Widget>[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        DeliverySpacing.md, DeliverySpacing.lg, DeliverySpacing.md, DeliverySpacing.sm),
                    child: Text(
                      t.custDistricts.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.faint,
                        letterSpacing: 0.6,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: _districtRow(t)),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                      DeliverySpacing.md, DeliverySpacing.md, DeliverySpacing.md, DeliverySpacing.sm),
                  child: Text(
                    t.custPowerDeclared,
                    style: const TextStyle(
                        fontSize: 11.5, color: DeliveryColors.faint, height: 1.3),
                  ),
                ),
              ),
              if (_stores.isLoadingFirstPage)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                      child: CircularProgressIndicator(color: DeliveryColors.brand)),
                )
              else if (_stores.isEmptyAfterLoad)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: YdEmptyState(
                    icon: Icons.storefront_outlined,
                    title: t.noShopsMatch,
                    message: t.tryClearingAFilter,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                      DeliverySpacing.md, 0, DeliverySpacing.md, 0),
                  sliver: SliverList.separated(
                    itemCount: _stores.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: DeliverySpacing.sm),
                    itemBuilder: (BuildContext context, int i) =>
                        _shopRow(t, _stores.items[i]),
                  ),
                ),
              const SliverToBoxAdapter(
                  child: SizedBox(height: DeliverySpacing.lg)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _districtRow(DeliveryStrings t) {
    return SizedBox(
      height: YdChip.minHeight + DeliverySpacing.sm,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: DeliverySpacing.md),
        children: <Widget>[
          YdChip(
            label: t.custAllDistricts,
            selected: _filters.neighborhood == null,
            onTap: () => _selectDistrict(null),
          ),
          for (final String district in _districts) ...<Widget>[
            const SizedBox(width: DeliverySpacing.sm),
            YdChip(
              label: district,
              selected: _filters.neighborhood == district,
              onTap: () => _selectDistrict(district),
            ),
          ],
        ],
      ),
    );
  }

  /// One dekkane row: photo, name against the power chip, the fact line, the district and
  /// verified badge. DARK dims the whole row — visible and honest, not hidden.
  Widget _shopRow(DeliveryStrings t, StoreCard store) {
    final Widget row = YdCard(
      onTap: () => _open(store),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
            child: SizedBox(
              width: 64,
              height: 64,
              child: CustomerPhoto(
                url: store.listCoverUrl,
                height: 64,
                icon: iconForVertical(store.vertical),
              ),
            ),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
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
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: DeliveryColors.ink,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (store.powerStatus != StorePowerStatus.unknown) ...<Widget>[
                      const SizedBox(width: DeliverySpacing.sm),
                      StorePowerChip(status: store.powerStatus, compact: true),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  store.powerNote?.isNotEmpty == true
                      ? store.powerNote!
                      : (store.tagline?.isNotEmpty == true
                          ? store.tagline!
                          : store.vertical.labelIn(t)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, color: DeliveryColors.muted, height: 1.3),
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    if (store.rating != null) ...<Widget>[
                      const Icon(Icons.star_rounded,
                          size: 13, color: DeliveryColors.brand),
                      const SizedBox(width: 2),
                      Text(
                        store.rating!.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.brand,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(width: DeliverySpacing.sm),
                    ],
                    Expanded(
                      child: Text(
                        store.etaLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: DeliveryAccent.positive.color,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (store.verifiedLocal) const VerifiedLocalBadge(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return store.powerStatus == StorePowerStatus.dark
        ? Opacity(opacity: 0.55, child: row)
        : row;
  }
}
