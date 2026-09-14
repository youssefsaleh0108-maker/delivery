import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'delivery_address.dart';
import 'service_provider_screen.dart';
import 'service_results_screen.dart';
import 'service_widgets.dart';
import 'services_kit.dart';

/// Where the providers under the category grid came from, which decides what their heading claims.
enum ServicesNearSource {
  /// Ranked by the orders nearby shops delivered: "Popular services near you".
  popular,

  /// Nearest first around the customer's pin: "Services near you".
  nearby,

  /// The listing, with no pin to measure from: "Service providers".
  listing,
}

/// The Services tab (Figma 126:285): the tab root the sixth destination opens.
///
/// * The greeting and the YOUDROP SERVICES pill; a search that opens its results page — providers by
///   name and offers by title.
/// * The category grid from the categories the server has **open**, and only those: a category the
///   platform has closed is never shown to a customer, so the frame's Cleaning, Beauty and Tutoring
///   tiles appear only if it opens them. Tailoring wears scissors, not the frame's circle-x. No "More"
///   tile: every open category already has its own.
/// * "Popular services near you" only when the customer's address has a pin and the server's ranking
///   has shops to show; otherwise the services nearest that pin, and without a pin the listing — each
///   under a heading that claims no more than it knows, and an honest empty state when there are none.
///
/// Built with every other tab and kept alive by the shell's stack, but it reads nothing until the
/// customer first opens it ([showing]).
class ServicesHomeScreen extends StatefulWidget {
  const ServicesHomeScreen({
    super.key,
    required this.kit,
    required this.session,
    this.showing = true,
  });

  final ServicesKit kit;
  final AuthSession session;

  /// Whether this tab is the one on screen.
  final bool showing;

  @override
  State<ServicesHomeScreen> createState() => _ServicesHomeScreenState();
}

class _ServicesHomeScreenState extends State<ServicesHomeScreen> {
  ServicesKit get _kit => widget.kit;

  bool _started = false;

  List<ServiceCategory>? _categories;
  bool _categoriesFailed = false;

  List<ServiceProviderEntry>? _providers;
  ServicesNearSource _source = ServicesNearSource.listing;
  bool _providersFailed = false;

  /// The pin the providers were read around ('' for none), so a changed address reads them again and
  /// an answer for the old one is dropped.
  String? _readFor;

  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _kit.addresses.addListener(_onAddress);
    if (widget.showing) _start();
  }

  @override
  void didUpdateWidget(ServicesHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showing && !_started) _start();
  }

  @override
  void dispose() {
    _kit.addresses.removeListener(_onAddress);
    _search.dispose();
    super.dispose();
  }

  void _start() {
    _started = true;
    unawaited(_loadCategories());
    unawaited(_loadProviders());
  }

  String get _pin {
    final DeliveryAddress? at = _kit.addresses.selected;
    return at != null && at.hasPoint ? '${at.latitude},${at.longitude}' : '';
  }

  void _onAddress() {
    if (!_started || !mounted || _pin == _readFor) return;
    setState(() {
      _providers = null;
      _providersFailed = false;
    });
    unawaited(_loadProviders());
  }

  Future<void> _loadCategories() async {
    try {
      final List<ServiceCategory> categories = await _kit.storeApi.serviceCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _categoriesFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _categoriesFailed = true);
    }
  }

  Future<void> _loadProviders() async {
    final String pin = _pin;
    _readFor = pin;
    final DeliveryAddress? at = _kit.addresses.selected;
    try {
      if (at != null && at.hasPoint) {
        List<NearbyStore> popular = const <NearbyStore>[];
        try {
          popular = await _kit.storeApi.popularServices(at.latitude!, at.longitude!);
        } catch (_) {
          // No ranking to show is not a failure of the tab: the nearest services stand in.
        }
        if (popular.isNotEmpty) {
          if (!mounted || pin != _readFor) return;
          setState(() {
            _providers = <ServiceProviderEntry>[
              for (final NearbyStore near in popular)
                ServiceProviderEntry(near.store, distanceMetres: near.distanceMetres),
            ];
            _source = ServicesNearSource.popular;
            _providersFailed = false;
          });
          return;
        }
      }
      final List<ServiceProviderEntry> entries = await loadServiceProviders(_kit);
      if (!mounted || pin != _readFor) return;
      setState(() {
        _providers = entries;
        _source = pin.isEmpty ? ServicesNearSource.listing : ServicesNearSource.nearby;
        _providersFailed = false;
      });
    } catch (_) {
      if (!mounted || pin != _readFor) return;
      setState(() => _providersFailed = true);
    }
  }

  Future<void> _refresh() async {
    await Future.wait(<Future<void>>[_loadCategories(), _loadProviders()]);
  }

  void _retry() {
    setState(() {
      if (_categoriesFailed) _categoriesFailed = false;
      if (_providersFailed) {
        _providersFailed = false;
        _providers = null;
      }
    });
    if (_categories == null) unawaited(_loadCategories());
    if (_providers == null) unawaited(_loadProviders());
  }

  void _openSearch(String query) {
    final String words = query.trim();
    if (words.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ServiceSearchResultsScreen(kit: _kit, query: words),
    ));
  }

  void _openCategory(ServiceCategory category) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ServiceCategoryResultsScreen(kit: _kit, category: category),
    ));
  }

  void _openProvider(ServiceProviderEntry entry) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          ServiceProviderScreen(kit: _kit, storeId: entry.store.id, preview: entry.store),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Container(
      color: DeliveryColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _header(t),
          Expanded(child: _body(t)),
        ],
      ),
    );
  }

  Widget _header(DeliveryStrings t) {
    final String firstName = widget.session.displayName.split(' ').first;
    final bool hasDrawer = Scaffold.maybeOf(context)?.hasDrawer ?? false;
    Widget avatar = StoreMonogram(name: widget.session.displayName, size: 32, radius: 16);
    if (hasDrawer) {
      // The profile menu, as Home's avatar opens it.
      avatar = Semantics(
        button: true,
        label: t.custAccountSettings,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Scaffold.of(context).openDrawer(),
          child: avatar,
        ),
      );
    }
    return Container(
      color: DeliveryColors.white,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              DeliverySpacing.md, DeliverySpacing.md - 4, DeliverySpacing.md, DeliverySpacing.md - 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  avatar,
                  const SizedBox(width: DeliverySpacing.sm + 2),
                  Expanded(
                    child: Text(
                      t.custHiName(firstName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: DeliveryColors.ink),
                    ),
                  ),
                  const SizedBox(width: DeliverySpacing.sm),
                  Container(
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: DeliveryColors.brandSoft,
                      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                    ),
                    child: Text(t.svcBrandPill,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600, color: DeliveryColors.brand)),
                  ),
                ],
              ),
              const SizedBox(height: DeliverySpacing.md - 4),
              YdSearchField(
                controller: _search,
                hintText: t.svcSearchHint,
                onSubmitted: _openSearch,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(DeliveryStrings t) {
    // Nothing at all until first shown — not even a spinner. The shell keeps every tab alive and
    // animating behind the one on screen, and a spinner nobody can see is a frame drawn every tick
    // for as long as the customer stays on another tab.
    if (!_started) return const SizedBox.shrink();
    final List<ServiceCategory>? categories = _categories;
    if (_categoriesFailed && _providersFailed) {
      return YdEmptyState(
        icon: Icons.cloud_off_rounded,
        title: t.svcCouldNotLoadServices,
        action: YdPillButton(
          label: t.tryAgain,
          expand: false,
          size: YdPillButtonSize.compact,
          onPressed: _retry,
        ),
      );
    }
    if (categories == null && !_categoriesFailed) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    // No category open means no provider can be listed either: say that, not "nothing near you".
    if (categories != null && categories.isEmpty) {
      return YdEmptyState(icon: Icons.work_outline_rounded, title: t.svcServicesNotOffered);
    }

    return RefreshIndicator(
      color: DeliveryColors.brand,
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
        children: <Widget>[
          _sectionTitle(t.svcCategoriesTitle),
          const SizedBox(height: DeliverySpacing.sm + 4),
          if (categories != null) _grid(categories, t) else _retryCard(t),
          const SizedBox(height: DeliverySpacing.lg),
          _sectionTitle(switch (_source) {
            ServicesNearSource.popular => t.svcPopularNearYou,
            ServicesNearSource.nearby => t.svcNearYou,
            ServicesNearSource.listing => t.svcAllProviders,
          }),
          const SizedBox(height: DeliverySpacing.sm + 4),
          ..._providerList(t),
        ],
      ),
    );
  }

  List<Widget> _providerList(DeliveryStrings t) {
    final List<ServiceProviderEntry>? providers = _providers;
    if (_providersFailed) return <Widget>[_retryCard(t)];
    if (providers == null) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.all(DeliverySpacing.lg),
          child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
        ),
      ];
    }
    if (providers.isEmpty) {
      return <Widget>[
        YdEmptyState(
          icon: Icons.storefront_outlined,
          title: t.svcNoServicesNearby,
          message: t.svcNoServicesNearbyHint,
        ),
      ];
    }
    return <Widget>[
      for (final (int i, ServiceProviderEntry entry) in providers.indexed) ...<Widget>[
        if (i > 0) const SizedBox(height: DeliverySpacing.md - 4),
        ServiceProviderCard(entry: entry, onTap: () => _openProvider(entry)),
      ],
    ];
  }

  Widget _retryCard(DeliveryStrings t) => YdCard.bordered(
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(t.svcCouldNotLoadServices,
                  style: const TextStyle(fontSize: 13, color: DeliveryColors.muted)),
            ),
            TextButton(
              onPressed: _retry,
              style: TextButton.styleFrom(foregroundColor: DeliveryColors.brand),
              child: Text(t.tryAgain),
            ),
          ],
        ),
      );

  /// Four tiles to a row, as the frame lays them out; a short last row keeps its tiles' width.
  Widget _grid(List<ServiceCategory> categories, DeliveryStrings t) {
    const int perRow = 4;
    return Column(
      children: <Widget>[
        for (int start = 0; start < categories.length; start += perRow) ...<Widget>[
          if (start > 0) const SizedBox(height: DeliverySpacing.sm + 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = start; i < start + perRow; i++) ...<Widget>[
                if (i > start) const SizedBox(width: DeliverySpacing.sm + 2),
                Expanded(
                  child: i < categories.length
                      ? _CategoryTile(
                          category: categories[i],
                          onTap: () => _openCategory(categories[i]),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  static Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DeliveryColors.ink),
      );
}

/// One category tile: the frame's 36px tinted box with its glyph, over a label that wraps to two lines
/// before it ellipsises.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final ServiceCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Semantics(
      button: true,
      child: Material(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          child: Container(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 4, vertical: DeliverySpacing.md - 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              border: Border.all(color: DeliveryColors.border),
            ),
            child: Column(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: DeliveryColors.brandSoft,
                    borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                  ),
                  child: Icon(serviceCategoryIcon(category), size: 18, color: DeliveryColors.brand),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 28,
                  child: Text(
                    category.labelIn(t),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600, color: DeliveryColors.ink, height: 1.2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
