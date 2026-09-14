import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'service_provider_screen.dart';
import 'service_widgets.dart';
import 'services_kit.dart';

/// One category's providers, opened from its tile on the Services tab: nearest first around the
/// customer's pin, or the listing without one.
class ServiceCategoryResultsScreen extends StatefulWidget {
  const ServiceCategoryResultsScreen({super.key, required this.kit, required this.category});

  final ServicesKit kit;
  final ServiceCategory category;

  @override
  State<ServiceCategoryResultsScreen> createState() => _ServiceCategoryResultsScreenState();
}

class _ServiceCategoryResultsScreenState extends State<ServiceCategoryResultsScreen> {
  List<ServiceProviderEntry>? _providers;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_failed) setState(() => _failed = false);
    try {
      final List<ServiceProviderEntry> providers =
          await loadServiceProviders(widget.kit, category: widget.category);
      if (mounted) setState(() => _providers = providers);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String label = widget.category.labelIn(t);
    final List<ServiceProviderEntry>? providers = _providers;
    final Widget body;
    if (_failed) {
      body = _failure(t, _load);
    } else if (providers == null) {
      body = const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    } else if (providers.isEmpty) {
      body = YdEmptyState(
          icon: serviceCategoryIcon(widget.category), title: t.svcCategoryEmpty(label));
    } else {
      body = ListView(
        padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
        children: _providerCards(context, widget.kit, providers),
      );
    }
    return _page(context, t, title: label, body: body);
  }
}

/// What a search on the Services tab found: providers whose name matches, and offers whose title
/// does — each section only when it has something, and one honest line when neither has.
class ServiceSearchResultsScreen extends StatefulWidget {
  const ServiceSearchResultsScreen({super.key, required this.kit, required this.query});

  final ServicesKit kit;
  final String query;

  @override
  State<ServiceSearchResultsScreen> createState() => _ServiceSearchResultsScreenState();
}

class _ServiceSearchResultsScreenState extends State<ServiceSearchResultsScreen> {
  List<ServiceProviderEntry>? _providers;
  List<Product> _offers = const <Product>[];
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_failed) setState(() => _failed = false);
    final CatalogApi? catalog = widget.kit.catalogApi;
    try {
      final (List<ServiceProviderEntry> providers, List<Product> offers) = await (
        loadServiceProviders(widget.kit, search: widget.query),
        catalog == null
            ? Future<List<Product>>.value(const <Product>[])
            : catalog
                .searchServices(search: widget.query)
                .then((Paged<Product> page) => page.content),
      ).wait;
      if (!mounted) return;
      setState(() {
        _providers = providers;
        _offers = offers;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _openOffer(Product offer) {
    final String? storeId = offer.storeId;
    if (storeId == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ServiceProviderScreen(kit: widget.kit, storeId: storeId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<ServiceProviderEntry>? providers = _providers;
    final Widget body;
    if (_failed) {
      body = _failure(t, _load);
    } else if (providers == null) {
      body = const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    } else if (providers.isEmpty && _offers.isEmpty) {
      body = YdEmptyState(icon: Icons.search_off_rounded, title: t.svcNoResults(widget.query));
    } else {
      body = ListView(
        padding: const EdgeInsetsDirectional.all(DeliverySpacing.md),
        children: <Widget>[
          if (providers.isNotEmpty) ...<Widget>[
            _heading(t.svcSearchProviders),
            ..._providerCards(context, widget.kit, providers),
            const SizedBox(height: DeliverySpacing.lg),
          ],
          if (_offers.isNotEmpty) ...<Widget>[
            _heading(t.svcOffers),
            for (final (int i, Product offer) in _offers.indexed) ...<Widget>[
              if (i > 0) const SizedBox(height: DeliverySpacing.md - 4),
              // The offer opens its provider's page, where it is ordered: that page knows whether the
              // shop is open and whether the offer can be ordered at all.
              ServiceOfferCard(
                offer: offer,
                onTap: offer.storeId == null ? null : () => _openOffer(offer),
              ),
            ],
          ],
        ],
      );
    }
    return _page(context, t, title: t.svcSearchTitle(widget.query), body: body);
  }

  static Widget _heading(String text) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: DeliverySpacing.sm + 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: DeliveryColors.ink)),
      );
}

Widget _page(BuildContext context, DeliveryStrings t, {required String title, required Widget body}) {
  return Scaffold(
    backgroundColor: DeliveryColors.background,
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SafeArea(
          bottom: false,
          child: YdScreenHeader(
            title: title,
            onBack: () => Navigator.of(context).maybePop(),
            backSemanticLabel: t.back,
          ),
        ),
        Expanded(child: body),
      ],
    ),
  );
}

Widget _failure(DeliveryStrings t, VoidCallback retry) => YdEmptyState(
      icon: Icons.cloud_off_rounded,
      title: t.svcCouldNotLoadServices,
      action: YdPillButton(
        label: t.tryAgain,
        expand: false,
        size: YdPillButtonSize.compact,
        onPressed: retry,
      ),
    );

List<Widget> _providerCards(
    BuildContext context, ServicesKit kit, List<ServiceProviderEntry> providers) {
  return <Widget>[
    for (final (int i, ServiceProviderEntry entry) in providers.indexed) ...<Widget>[
      if (i > 0) const SizedBox(height: DeliverySpacing.md - 4),
      ServiceProviderCard(
        entry: entry,
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) =>
              ServiceProviderScreen(kit: kit, storeId: entry.store.id, preview: entry.store),
        )),
      ),
    ],
  ];
}
