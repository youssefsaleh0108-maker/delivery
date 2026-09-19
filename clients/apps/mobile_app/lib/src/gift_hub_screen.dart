import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'address_sheet.dart';
import 'cart.dart';
import 'delivery_address.dart';
import 'shops_listing_screen.dart';
import 'store_page_screen.dart';

/// Send a Gift (Figma 112:1684): where somebody abroad starts sending essentials to family in
/// Lebanon.
///
/// It replaces DiasporaScreen, which nothing could reach, and keeps its model: the recipient is a
/// saved address that names a person, and choosing one makes it the address the whole storefront
/// shops for. What moved out is the note, which is now written at the gift checkout beside the wrap
/// and the payment it goes with.
///
/// Four ways in, as the frame draws them — the how-it-works steps, gift categories, recent
/// recipients and featured care bundles. Starting any of them marks the basket as a gift
/// ([Cart.startGift]), which is what sends Proceed to Checkout to the gift checkout; the basket
/// says so and lets the customer undo it.
///
/// A gift is never cash, and the shell draws no way in here until Order Manager accepts a method
/// that can pay for one ([giftTerms]). Reached anyway while none can, the hub says so first, above
/// everything that would start a gift.
///
/// Where the frame promised more than the platform does, the copy is narrower: shops deliver where
/// they deliver, the shop receives the note rather than printing it, and "same day" is said only on
/// a bundle whose shop could still make it today.
///
/// Laid out at a phone's width rather than the frame's 560: the categories and recipients overflow
/// the frame, so both are horizontal scrollers, which also mirror in Arabic.
class GiftHubScreen extends StatefulWidget {
  const GiftHubScreen({
    super.key,
    required this.storeApi,
    required this.orderApi,
    required this.cart,
    required this.addresses,
    required this.zoneApi,
    required this.onOpenBasket,
    this.geocodingApi,
    this.onStartShopping,
    this.giftTerms,
  });

  final StoreApi storeApi;
  final OrderApi orderApi;
  final Cart cart;
  final DeliveryAddressStore addresses;

  /// Handed to the address sheet, so a recipient added here gets an area — the delivery fee is
  /// priced by it.
  final DeliveryZoneApi zoneApi;

  /// Handed to the address sheet for the place search. Optional: without it the sheet still takes a
  /// typed address.
  final GeocodingApi? geocodingApi;

  /// The shell's way to its Basket tab, for the basket bar of every shop opened from here.
  final VoidCallback onOpenBasket;

  /// Called after the hub closes itself for "Select Items & Start Order", so the shell can land the
  /// customer on Home to shop for the recipient. Null just closes the hub.
  final VoidCallback? onStartShopping;

  /// What a gift can be paid with, as the shell already asked; null and the hub asks for itself.
  ///
  /// Where it names no method the hub says a gift cannot be sent yet, at its top — rather than let
  /// the customer choose shops and type a recipient to meet a button that cannot work.
  final GiftTerms? giftTerms;

  @override
  State<GiftHubScreen> createState() => _GiftHubScreenState();
}

/// A gift category: a store vertical under the gift hub's name for it.
///
/// There is no gift taxonomy, so a category is drawn only where a vertical backs it — Care Package,
/// Groceries and Medicine & Health are verticals outright. The frame's Sweets & Pastries (no
/// vertical: a search of shop names, which misses every shop named in Arabic) and Baby & Kids (the
/// pharmacies again, under a second title) are left out until a vertical or a tag backs them.
class _GiftCategory {
  const _GiftCategory(this.label, this.icon, this.vertical);

  final String Function(DeliveryStrings t) label;
  final IconData icon;
  final StoreVertical vertical;
}

final List<_GiftCategory> _categories = <_GiftCategory>[
  _GiftCategory((DeliveryStrings t) => t.giftCatCarePackage, Icons.card_giftcard_rounded,
      StoreVertical.flowersGifts),
  _GiftCategory((DeliveryStrings t) => t.giftCatGroceries, Icons.local_grocery_store_outlined,
      StoreVertical.grocery),
  _GiftCategory((DeliveryStrings t) => t.giftCatMedicine, Icons.medical_services_outlined,
      StoreVertical.pharmacy),
];

class _GiftHubScreenState extends State<GiftHubScreen> {
  List<GiftBundle> _bundles = const <GiftBundle>[];
  bool _bundlesLoading = true;

  /// The gift terms: the shell's, or asked for here. Null while unknown, and then nothing is said —
  /// not knowing is not "cannot", and the gift checkout says for itself when it cannot load them.
  GiftTerms? _terms;

  @override
  void initState() {
    super.initState();
    widget.addresses.addListener(_repaint);
    widget.cart.addListener(_repaint);
    _loadBundles();
    _terms = widget.giftTerms;
    if (_terms == null) _loadTerms();
  }

  Future<void> _loadTerms() async {
    try {
      final GiftTerms terms = await widget.orderApi.giftTerms();
      if (mounted) setState(() => _terms = terms);
    } catch (_) {
      // Unknown stays unknown: nothing is said.
    }
  }

  @override
  void dispose() {
    widget.addresses.removeListener(_repaint);
    widget.cart.removeListener(_repaint);
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  Future<void> _loadBundles() async {
    try {
      final List<GiftBundle> bundles = await widget.storeApi.giftBundles();
      if (!mounted) return;
      setState(() {
        _bundles = bundles;
        _bundlesLoading = false;
      });
    } catch (_) {
      // Hidden rather than an error, like every rail in the app: the hub works without it.
      if (!mounted) return;
      setState(() {
        _bundles = const <GiftBundle>[];
        _bundlesLoading = false;
      });
    }
  }

  /// The saved addresses that name a person rather than a place, most recent first.
  List<DeliveryAddress> _recipients(DeliveryStrings t) => widget.addresses.recents
      .where((DeliveryAddress a) => a.personName(t) != null)
      .toList(growable: false);

  /// Whether [recipient] is who this gift is for right now.
  bool _isChosen(DeliveryAddress recipient) =>
      widget.cart.isGift && widget.addresses.selected == recipient;

  Future<void> _choose(DeliveryAddress recipient) async {
    widget.cart.startGift();
    await widget.addresses.select(recipient);
  }

  Future<void> _addRecipient() async {
    final DeliveryAddress? before = widget.addresses.selected;
    await showAddressSheet(context, widget.addresses,
        zoneApi: widget.zoneApi, geocodingApi: widget.geocodingApi);
    if (!mounted) return;
    // The sheet selects what it saved; saving one from here is choosing who the gift is for. A sheet
    // closed without saving leaves the basket as it was.
    final DeliveryAddress? after = widget.addresses.selected;
    if (after != null && (before == null || after.line != before.line)) {
      widget.cart.startGift();
    }
  }

  void _openCategory(_GiftCategory category) {
    widget.cart.startGift();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ShopsListingScreen(
        storeApi: widget.storeApi,
        orderApi: widget.orderApi,
        cart: widget.cart,
        addresses: widget.addresses,
        onOpenBasket: widget.onOpenBasket,
        initialVertical: category.vertical,
      ),
    ));
  }

  /// A bundle opens its shop, where it is added like any shelf item — through the shop page's own
  /// add flow, which already asks before replacing a basket that belongs to another shop.
  void _openBundle(GiftBundle bundle) {
    widget.cart.startGift();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StorePageScreen(
        storeApi: widget.storeApi,
        orderApi: widget.orderApi,
        cart: widget.cart,
        storeId: bundle.storeId,
        addresses: widget.addresses,
        onOpenBasket: widget.onOpenBasket,
      ),
    ));
  }

  void _startShopping() {
    Navigator.of(context).maybePop();
    widget.onStartShopping?.call();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<DeliveryAddress> recipients = _recipients(t);
    final bool chosen = recipients.any(_isChosen);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: t.giftHubTitle,
        subtitle: t.custDiasporaSub,
        onBack: () => Navigator.of(context).maybePop(),
        backSemanticLabel: t.back,
        trailing: const GiftBrandChip(),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: DeliverySpacing.md, bottom: DeliverySpacing.lg),
        children: <Widget>[
          // First, above everything that would mark the basket as a gift.
          if (_terms != null && !_terms!.canPay) _padded(_cannotSendYet(t)),
          _padded(_hero(t)),
          _sectionLabel(t.giftHowItWorks),
          _padded(_steps(t)),
          _sectionLabel(t.giftCategories),
          _categoryRail(t),
          _sectionLabel(t.giftRecentRecipients),
          _recipientRail(t, recipients),
          if (_bundlesLoading) ...<Widget>[
            _sectionLabel(t.giftFeaturedBundles),
            _padded(const _BundleSkeleton()),
          ] else if (_bundles.isNotEmpty) ...<Widget>[
            _sectionLabel(t.giftFeaturedBundles),
            for (final GiftBundle bundle in _bundles) _padded(_bundleRow(t, bundle)),
          ],
        ],
      ),
      // DiasporaScreen's way on, kept for a recipient already chosen: back to Home, shopping for
      // their address.
      bottomNavigationBar: chosen
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(DeliverySpacing.md),
                child: YdPillButton(label: t.custStartOrder, onPressed: _startShopping),
              ),
            )
          : null,
    );
  }

  static Widget _padded(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.md),
        child: child,
      );

  static Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(DeliverySpacing.md, DeliverySpacing.lg,
            DeliverySpacing.md, DeliverySpacing.md - DeliverySpacing.xs),
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

  /// No method this platform accepts can pay for a gift yet, so a basket started here could not be
  /// sent. Said before the customer spends any effort on one.
  static Widget _cannotSendYet(DeliveryStrings t) {
    return Container(
      margin: const EdgeInsets.only(bottom: DeliverySpacing.md),
      padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: DeliveryColors.brandSoft,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline_rounded, size: 16, color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Text(
              t.giftNoPaymentMethods,
              style: const TextStyle(fontSize: 12, color: DeliveryColors.ink, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  /// The frame's banner. A brand gradient where the frame has a photograph: the photo is a Figma
  /// asset the app does not ship, and a hero that fails to load is worse than none.
  Widget _hero(DeliveryStrings t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: <Color>[DeliveryColors.brandDark, DeliveryColors.brand],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            t.giftHubBannerTitle,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: DeliveryColors.white,
              height: 1.25,
            ),
          ),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            t.giftHubBannerBody,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: DeliveryColors.white,
              height: 18 / 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _steps(DeliveryStrings t) {
    return YdCard.bordered(
      child: Column(
        children: <Widget>[
          _step('1', t.giftStep1Title, t.giftStep1Body),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _step('2', t.giftStep2Title, t.giftStep2Body),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _step('3', t.giftStep3Title, t.giftStep3Body),
        ],
      ),
    );
  }

  static Widget _step(String number, String title, String body) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: DeliveryColors.brandSoft,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.brand,
            ),
          ),
        ),
        const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(fontSize: 11, color: DeliveryColors.muted, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _categoryRail(DeliveryStrings t) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.md),
        itemCount: _categories.length,
        separatorBuilder: (BuildContext _, int __) => const SizedBox(width: DeliverySpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final _GiftCategory category = _categories[index];
          return SizedBox(
            width: 100,
            child: YdCard.bordered(
              padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
              onTap: () => _openCategory(category),
              child: Column(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: DeliveryColors.brandSoft,
                      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                    ),
                    child: Icon(category.icon, size: 22, color: DeliveryColors.brand),
                  ),
                  const SizedBox(height: DeliverySpacing.sm),
                  Text(
                    category.label(t),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: DeliveryColors.ink,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _recipientRail(DeliveryStrings t, List<DeliveryAddress> recipients) {
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.md),
        children: <Widget>[
          for (final DeliveryAddress recipient in recipients) ...<Widget>[
            _recipientCard(t, recipient),
            const SizedBox(width: DeliverySpacing.sm),
          ],
          _addRecipientCard(t),
        ],
      ),
    );
  }

  Widget _recipientCard(DeliveryStrings t, DeliveryAddress recipient) {
    final bool chosen = _isChosen(recipient);
    final String name = recipient.personName(t)!;
    final String? area = recipient.zoneName;
    return Semantics(
      selected: chosen,
      button: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 132, maxWidth: 200),
        child: YdCard.bordered(
          radius: DeliveryRadius.md,
          padding: const EdgeInsets.symmetric(
              horizontal: DeliverySpacing.md - DeliverySpacing.xs, vertical: DeliverySpacing.sm),
          borderColor: chosen ? DeliveryColors.brand : DeliveryColors.border,
          onTap: () => _choose(recipient),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _Initials(name),
              const SizedBox(width: DeliverySpacing.sm + 2),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.25,
                      ),
                    ),
                    if (area != null && area.isNotEmpty)
                      Text(
                        area,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: DeliveryColors.muted, height: 1.3),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addRecipientCard(DeliveryStrings t) {
    return YdCard.bordered(
      radius: DeliveryRadius.md,
      padding: const EdgeInsets.symmetric(
          horizontal: DeliverySpacing.md - DeliverySpacing.xs, vertical: DeliverySpacing.sm),
      onTap: _addRecipient,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: DeliveryColors.brandSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_add_alt_1_outlined,
                size: 18, color: DeliveryColors.brand),
          ),
          const SizedBox(width: DeliverySpacing.sm + 2),
          Text(
            t.giftAddRecipient,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.brand,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bundleRow(DeliveryStrings t, GiftBundle bundle) {
    final String? description = bundle.description?.trim();
    final bool described = description != null && description.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.md - DeliverySpacing.xs),
      child: YdCard.bordered(
        padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
        onTap: () => _openBundle(bundle),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DeliveryProductImage(
              url: bundle.thumbUrl,
              width: 64,
              height: 64,
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
            ),
            const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          bundle.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: DeliveryColors.ink,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(width: DeliverySpacing.sm),
                      Text(
                        '\$${bundle.price.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.brand,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (described)
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: DeliveryColors.muted, height: 1.35),
                    ),
                  // The shop it comes from: a basket holds one shop, so the customer should know
                  // which one this is before it replaces anything.
                  Text(
                    bundle.storeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.35),
                  ),
                  if (bundle.sameDayDeliverable) ...<Widget>[
                    const SizedBox(height: DeliverySpacing.xs),
                    Row(
                      children: <Widget>[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: DeliveryAccent.positive.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: DeliverySpacing.xs),
                        Text(
                          t.giftSameDayDeliverable,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: DeliveryAccent.positive.color,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The frame's trailing YouDrop chip: a brand-soft pill with the brand dot and the wordmark. Shared
/// by the gift hub and the gift checkout, which draw the same header.
class GiftBrandChip extends StatelessWidget {
  const GiftBrandChip({super.key});

  @override
  Widget build(BuildContext context) {
    // The wordmark is a name, and reads left to right in either language.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: DeliveryColors.brandSoft,
          borderRadius: BorderRadius.circular(DeliveryRadius.pill),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 8,
              height: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(color: DeliveryColors.brand, shape: BoxShape.circle),
              ),
            ),
            SizedBox(width: 6),
            Text.rich(
              TextSpan(
                children: <TextSpan>[
                  TextSpan(text: 'You', style: TextStyle(color: DeliveryColors.ink)),
                  TextSpan(text: 'Drop', style: TextStyle(color: DeliveryColors.brand)),
                ],
              ),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

/// A person's initials in the brand-soft circle the frame draws for a recipient.
class _Initials extends StatelessWidget {
  const _Initials(this.name);

  final String name;

  /// "Mona (Mom)" → "MM", "Teta Layla" → "TL", "ماما" → "م". Letters only, so brackets and emoji
  /// in a label do not become an initial.
  static String of(String name) {
    final List<String> words = name
        .split(RegExp(r'\s+'))
        .map((String w) => w.replaceAll(RegExp(r'[^\p{L}]', unicode: true), ''))
        .where((String w) => w.isNotEmpty)
        .toList();
    return words.take(2).map((String w) => w.characters.first.toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: DeliveryColors.brandSoft, shape: BoxShape.circle),
      child: ExcludeSemantics(
        child: Text(
          of(name),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: DeliveryColors.brand,
          ),
        ),
      ),
    );
  }
}

/// What the bundles section shows while it loads: the shape of a row, no content.
class _BundleSkeleton extends StatelessWidget {
  const _BundleSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width) => Container(
          width: width,
          height: 10,
          decoration: BoxDecoration(
            color: DeliveryColors.border,
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          ),
        );
    return YdCard.bordered(
      padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
      child: Row(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: DeliveryColors.border,
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
            ),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                bar(140),
                const SizedBox(height: DeliverySpacing.sm),
                bar(96),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
