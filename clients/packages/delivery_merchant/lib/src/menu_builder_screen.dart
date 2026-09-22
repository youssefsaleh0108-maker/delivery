import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
// For CustomSemanticsAction: the drag is a long press, and a screen reader has none, so the order
// is reachable as two named actions on each row instead.
import 'package:flutter/semantics.dart';
import 'package:url_launcher/url_launcher.dart';

import 'order_detail_screen.dart';
import 'product_form_screen.dart';
import 'product_list_screen.dart';
import 'shop_share.dart';

/// The menu — Figma `merchant-menu-builder` (139:8).
///
/// The shop's own sections with the items inside them: a photo, a name, a description, a price and
/// a switch for "on the shelf right now". Adding an item, and a Preview that opens the page a
/// customer actually sees.
///
/// **This is the catalogue that already exists, arranged.** Not a second one. The sections are the
/// rows [MerchantCategoriesScreen] writes (`/api/stores/{id}/categories`), the items are the
/// products [ProductListScreen] writes (`/api/products`), the switch sends the publish and archive
/// this platform has always meant by availability, and the photo is the product's own first image.
/// Nothing here can be edited into existence: "Add Menu Item" opens [ProductFormScreen], the same
/// form the catalogue list opens, so a menu item and a product cannot drift into being two things.
///
/// Three things are worth saying about what it does and does not do:
///
/// * **The order is the feature.** A catalogue list is alphabetical because a merchant looks things
///   up in it; a menu is not, because a customer reads it top to bottom and the house special goes
///   first. Sections have had an order since V26; items got one in V41, and the drag here is what
///   writes it. It is optimistic and it reverts — a screen that silently kept an order the server
///   refused would be lying about what customers will see.
/// * **The drag is a long press on a row, inside one open section.** Not a handle: the design draws
///   none, and a 24px handle beside a 48px photo on a 320dp phone is a target a thumb misses. Not
///   across sections either — moving an item to another section is a change of section, which is
///   the form's field, not a gesture that has to be aimed while the list scrolls.
/// * **Preview opens the real page.** `/s/{slug}`, in a browser, with the app's language — not a
///   rendering of the menu drawn here. The point of a preview is to see what a customer sees, and
///   what a customer sees is a server-rendered page with its own rules about out of stock, prices
///   in lira, and which items are live at all.
///
/// One widget, two hosts, like every screen in this package: the phone hands it a thumb and 380dp,
/// the portal hands it the space beside its rail, where the column caps at [merchantMaxContentWidth].
class MenuBuilderScreen extends StatefulWidget {
  const MenuBuilderScreen({
    super.key,
    required this.api,
    required this.storeApi,
    this.storeId,
    this.origin = defaultShopPageOrigin,
    this.onBack,
  });

  /// The catalogue client. Sections, items, the availability switch and the reorder all come from
  /// here — there is no menu endpoint, because there is no second catalogue.
  final CatalogApi api;

  /// Passed through to [ProductFormScreen], which needs it to resolve the shop for a new item.
  final StoreApi storeApi;

  /// Which shop's menu this is. Null while a host is still resolving the merchant's store — the
  /// screen then draws its empty state rather than calling with a hole in the path.
  final String? storeId;

  /// The public origin Preview opens. See [defaultShopPageOrigin] for why it is a define.
  final String origin;

  /// Shows the header's back button when non-null. Hosts that mount this as a tab pass nothing.
  final VoidCallback? onBack;

  @override
  State<MenuBuilderScreen> createState() => _MenuBuilderScreenState();
}

/// One block of the menu: a section and the items filed under it, in the shop's own order.
///
/// The unsectioned block is one of these too, with a null [id] — the public page draws those items
/// last under a heading of its own, so the builder shows them in the same place rather than hiding
/// items the shop really does sell. It is the one block that cannot be dragged: there is no section
/// behind it to hold an order.
class _Block {
  _Block({required this.id, required this.name, required this.items});

  final String? id;
  final String name;
  final List<Product> items;

  bool get sortable => id != null && items.length > 1;
}

class _MenuBuilderScreenState extends State<MenuBuilderScreen> {
  /// Below this the screen is on a phone. Measured against this widget's own constraints, never
  /// the window — the portal's rail can leave a desktop as narrow as a handset.
  static const double _phoneWidth = 600;

  /// The design's item card: a 48px photo and 12px of padding round it.
  static const double _thumb = 48;
  static const double _cardPadding = 12;

  /// Room under the last card so the floating "Add Menu Item" button sits over nothing rather than
  /// over the row somebody was about to drag.
  static const double _fabClearance = 88;

  /// One page of the shop's shelf. The public page draws at most 120 items, so a menu longer than
  /// this is longer than the thing it is a menu for; the screen says so rather than paging.
  static const int _shelfCap = 200;

  List<_Block>? _blocks;

  /// The last arrangement the server confirmed, by section id. A failed reorder reverts to exactly
  /// this, which is why it is kept apart from [_blocks] rather than re-derived from it.
  final Map<String, List<Product>> _confirmed = <String, List<Product>>{};

  /// Which sections are open. The first opens by default and the rest are collapsed, as the design
  /// draws it: a shop with nine sections should not open onto ninety rows.
  final Set<String> _open = <String>{};

  /// Set once, so re-expanding a section the merchant collapsed does not fight them on a reload.
  bool _openedFirst = false;

  Store? _store;
  bool _loading = true;
  Object? _error;

  /// Sections with a reorder in flight. Dragging is disabled meanwhile: a second move over an
  /// unsettled order would leave nothing sane to revert to.
  final Set<String> _savingOrder = <String>{};

  /// Items with a write in flight, so a double tap cannot fire two publishes.
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MenuBuilderScreen old) {
    super.didUpdateWidget(old);
    if (old.storeId != widget.storeId) {
      _load();
    }
  }

  // ---------------------------------------------------------------- reading the menu

  Future<void> _load() async {
    final String? storeId = widget.storeId;
    if (storeId == null) {
      setState(() {
        _loading = false;
        _error = null;
        _blocks = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Three reads, in parallel, because none of them needs the others: the shop (for Preview's
      // address and the header), the sections, and the shelf.
      final List<Object?> answers = await Future.wait(<Future<Object?>>[
        widget.api.storeCategories(storeId),
        widget.api.myProducts(storeId: storeId, size: _shelfCap),
        _readStore(storeId),
      ]);
      if (!mounted) return;
      final List<Category> sections = answers[0]! as List<Category>;
      final Paged<Product> shelf = answers[1]! as Paged<Product>;
      setState(() {
        _store = answers[2] as Store?;
        _blocks = _arrange(sections, shelf.content);
        _confirmed
          ..clear()
          ..addEntries(_blocks!
              .where((_Block b) => b.id != null)
              .map((_Block b) => MapEntry<String, List<Product>>(b.id!, List<Product>.of(b.items))));
        if (!_openedFirst && _blocks!.isNotEmpty) {
          _open.add(_blocks!.first.id ?? '');
          _openedFirst = true;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// The shop, for its name and its slug. A failure is not fatal — the menu still draws, and only
  /// Preview is unavailable, which the button says for itself.
  Future<Store?> _readStore(String storeId) async {
    try {
      return await widget.storeApi.read(storeId);
    } catch (_) {
      return null;
    }
  }

  /// The shelf grouped into the blocks the public page draws, in the page's own order.
  ///
  /// The shop's own sections first, in the merchant's order, then everything with no section of
  /// this shop's — which is what the page puts last. Inside a block, the order the shop wrote
  /// (`position`), with the name breaking ties so a block nobody has ever dragged comes out exactly
  /// as it always did.
  static List<_Block> _arrange(List<Category> sections, List<Product> shelf) {
    final Map<String, List<Product>> bySection = <String, List<Product>>{
      for (final Category section in sections) section.id: <Product>[],
    };
    final List<Product> loose = <Product>[];
    for (final Product item in shelf) {
      final String? section = item.categoryId;
      if (section != null && bySection.containsKey(section)) {
        bySection[section]!.add(item);
      } else {
        // Either no section at all, or filed under a platform category, which is not a block this
        // shop arranges. Both are drawn by the page in its last, unnamed block.
        loose.add(item);
      }
    }

    int byMenuOrder(Product a, Product b) {
      final int order = a.position.compareTo(b.position);
      return order != 0 ? order : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }

    final List<_Block> blocks = <_Block>[
      for (final Category section in sections)
        _Block(
          id: section.id,
          name: section.name,
          items: bySection[section.id]!..sort(byMenuOrder),
        ),
    ];
    if (loose.isNotEmpty) {
      blocks.add(_Block(id: null, name: '', items: loose..sort(byMenuOrder)));
    }
    return blocks;
  }

  // ---------------------------------------------------------------- the switch

  /// "On the shelf right now", in both directions — [MerchantAvailabilitySwitch]'s own meaning.
  ///
  /// On is `publish`, which the service refuses with 422 for an item with no photo; that reason is
  /// worth showing, because the fix is not otherwise obvious. Off is `archive`, the only "not on
  /// the shelf" this platform has for goods and reversible by publishing again. Deliberately *not*
  /// `inStock`, which is inventory-service's projection and nothing a merchant may write: a switch
  /// that wrote it would be this screen claiming a stock level nobody counted.
  Future<void> _setAvailable(Product item, bool available) async {
    if (_busy.contains(item.id)) return;
    final DeliveryStrings t = DeliveryStrings.of(context);

    if (!available) {
      // Taking an item off the menu is not destructive, but it does stop customers finding it, and
      // a mis-tapped switch beside a scrolling list should not do that silently.
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(t.menuTakeOffTitle),
          content: Text(t.menuTakeOffConfirm(item.name)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.cancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.menuTakeOff),
            ),
          ],
        ),
      );
      if (!(confirmed ?? false) || !mounted) return;
    }

    setState(() => _busy.add(item.id));
    try {
      final Product saved = available
          ? await widget.api.publish(item.id)
          : await widget.api.archive(item.id);
      if (!mounted) return;
      // Replace the one row rather than reloading the screen: a reload would collapse the sections
      // the merchant opened and scroll them back to the top, for a change to one switch.
      setState(() => _replace(saved));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageFor(e, fallback: t.couldNotPublishProduct))),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  void _replace(Product saved) {
    for (final _Block block in _blocks ?? const <_Block>[]) {
      final int at = block.items.indexWhere((Product p) => p.id == saved.id);
      if (at >= 0) {
        block.items[at] = saved;
        final List<Product>? confirmed = block.id == null ? null : _confirmed[block.id];
        if (confirmed != null) {
          final int was = confirmed.indexWhere((Product p) => p.id == saved.id);
          if (was >= 0) confirmed[was] = saved;
        }
        return;
      }
    }
  }

  // ---------------------------------------------------------------- the drag

  /// Applies a drag inside one section: the row moves now, the server rules on it after.
  ///
  /// [to] is the index the row ends up at, already adjusted for its own removal — which is what
  /// `onReorderItem` hands over, and is why nothing here subtracts one.
  Future<void> _move(_Block block, int from, int to) async {
    final String sectionId = block.id!;
    if (_savingOrder.contains(sectionId) || to == from) return;
    final DeliveryStrings t = DeliveryStrings.of(context);

    setState(() {
      block.items.insert(to, block.items.removeAt(from));
      _savingOrder.add(sectionId);
    });

    try {
      final List<String> order = await widget.api.reorderSectionProducts(
        widget.storeId!,
        sectionId,
        block.items.map((Product p) => p.id).toList(),
      );
      if (!mounted) return;
      setState(() {
        // Settle on the server's answer rather than on what was sent: another device may have been
        // arranging the same section, and the order that reaches customers is the one the server
        // holds.
        final Map<String, Product> byId = <String, Product>{
          for (final Product item in block.items) item.id: item,
        };
        final List<Product> settled = <Product>[
          for (final String id in order)
            if (byId[id] != null) byId[id]!,
        ];
        if (settled.length == block.items.length) {
          block.items
            ..clear()
            ..addAll(settled);
        }
        _confirmed[sectionId] = List<Product>.of(block.items);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final List<Product>? was = _confirmed[sectionId];
        if (was != null) {
          block.items
            ..clear()
            ..addAll(was);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageFor(e, fallback: t.menuCouldNotReorder))),
      );
    } finally {
      if (mounted) setState(() => _savingOrder.remove(sectionId));
    }
  }

  // ---------------------------------------------------------------- the two buttons

  Future<void> _addItem() async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => ProductFormScreen(
          api: widget.api,
          storeApi: widget.storeApi,
          storeId: widget.storeId,
        ),
      ),
    );
    if ((saved ?? false) && mounted) {
      _load();
    }
  }

  Future<void> _editItem(Product item) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => ProductFormScreen(
          api: widget.api,
          storeApi: widget.storeApi,
          existing: item,
          storeId: widget.storeId,
        ),
      ),
    );
    if ((saved ?? false) && mounted) {
      _load();
    }
  }

  /// Opens `/s/{slug}` — the page a customer opens, not a drawing of it.
  ///
  /// A browser tab for the same reason the poster is one: it is a server-rendered document, and the
  /// only honest preview of it is the document. It carries this app's language so the merchant
  /// previews the rendering they are reading.
  Future<void> _preview() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final Store? store = _store;
    if (store == null) return;
    final String origin = widget.origin.endsWith('/')
        ? widget.origin.substring(0, widget.origin.length - 1)
        : widget.origin;
    final String lang = Localizations.localeOf(context).languageCode;
    bool opened = false;
    try {
      opened = await launchUrl(
        Uri.parse('$origin/s/${store.slug}?lang=$lang'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.menuCouldNotPreview),
        backgroundColor: DeliveryColors.brandDark,
      ),
    );
  }

  /// Whether the shop has a page for Preview to open. The same two conditions the share card
  /// checks, and for the same reason: a preview that opened a 404 would teach a merchant that their
  /// menu is broken when it is their pin that is missing.
  bool get _previewable {
    final Store? store = _store;
    return store != null && store.hasPin && store.status.isListed;
  }

  // ---------------------------------------------------------------- drawing

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < _phoneWidth;
        return Scaffold(
          backgroundColor: DeliveryColors.background,
          body: Column(
            children: <Widget>[
              YdScreenHeader(
                title: t.menuBuilderTitle,
                subtitle: _store?.name,
                onBack: widget.onBack,
                backSemanticLabel: t.back,
                trailing: _previewButton(t),
              ),
              Expanded(child: _body(t, narrow)),
            ],
          ),
          floatingActionButton: (_blocks == null || _loading)
              ? null
              : _AddMenuItemButton(label: t.menuAddItem, onPressed: _addItem),
        );
      },
    );
  }

  /// The design's soft-brand "Preview" pill in the header's end slot.
  Widget _previewButton(DeliveryStrings t) {
    final bool enabled = _previewable;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: DeliveryColors.brandSoft,
          borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? _preview : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DeliverySpacing.md - DeliverySpacing.xs,
                vertical: DeliverySpacing.sm - 2,
              ),
              child: Text(
                t.menuPreview,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.brand,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(DeliveryStrings t, bool narrow) {
    if (widget.storeId == null) {
      return YdEmptyState(
        icon: Icons.storefront_outlined,
        title: t.noShopYet,
        message: t.shopCreatedAutomatically,
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
    }
    if (_error != null) {
      return YdEmptyState(
        icon: Icons.cloud_off_rounded,
        title: t.menuCouldNotLoad,
        message: _messageFor(_error!, fallback: '$_error'),
        action: YdPillButton.secondary(
          label: t.tryAgain,
          onPressed: _load,
          size: YdPillButtonSize.compact,
          expand: false,
        ),
      );
    }
    final List<_Block> blocks = _blocks ?? const <_Block>[];
    if (blocks.isEmpty || blocks.every((_Block b) => b.items.isEmpty)) {
      return YdEmptyState(
        icon: Icons.restaurant_menu_outlined,
        title: t.menuEmptyTitle,
        message: t.menuEmptyMessage,
        action: YdPillButton(
          label: t.menuAddItem,
          icon: Icons.add,
          onPressed: _addItem,
          size: YdPillButtonSize.compact,
          expand: false,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: DeliveryColors.brand,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          DeliverySpacing.md,
          DeliverySpacing.md,
          DeliverySpacing.md,
          _fabClearance + MediaQuery.paddingOf(context).bottom,
        ),
        children: <Widget>[
          Align(
            alignment: AlignmentDirectional.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final _Block block in blocks) ...<Widget>[
                    _sectionHeader(t, block),
                    if (_isOpen(block)) _itemsOf(t, block),
                    const SizedBox(height: DeliverySpacing.md),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isOpen(_Block block) => _open.contains(block.id ?? '');

  /// The design's section row: the name, an item count pill, and a chevron that says which way the
  /// block opens. A rule under a closed block, none under an open one — the items are the rule.
  Widget _sectionHeader(DeliveryStrings t, _Block block) {
    final bool open = _isOpen(block);
    final String name = block.id == null ? t.menuOtherItems : block.name;
    return Semantics(
      button: true,
      expanded: open,
      header: true,
      child: InkWell(
        onTap: () => setState(() {
          final String key = block.id ?? '';
          if (!_open.remove(key)) _open.add(key);
        }),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
          decoration: open
              ? null
              : const BoxDecoration(
                  border: Border(bottom: BorderSide(color: DeliveryColors.border)),
                ),
          child: Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DeliverySpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: DeliveryColors.border,
                  borderRadius: BorderRadius.circular(DeliveryRadius.pill),
                ),
                child: Text(
                  t.menuItemCount(block.items.length),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.muted,
                  ),
                ),
              ),
              const Spacer(),
              if (_savingOrder.contains(block.id))
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
                )
              else
                Icon(
                  // Down when open, and the way the reader reads when closed.
                  open ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                  color: DeliveryColors.faint,
                  semanticLabel: open ? t.menuCollapseSection : t.menuExpandSection,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemsOf(DeliveryStrings t, _Block block) {
    if (block.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
        child: Text(
          t.menuSectionEmpty,
          style: const TextStyle(fontSize: 13, color: DeliveryColors.muted),
        ),
      );
    }

    final List<Widget> cards = <Widget>[
      for (final Product item in block.items)
        Padding(
          key: ValueKey<String>(item.id),
          padding: const EdgeInsets.only(top: DeliverySpacing.sm + 2),
          child: _ItemCard(
            item: item,
            busy: _busy.contains(item.id),
            onEdit: () => _editItem(item),
            onAvailability: (bool on) => _setAvailable(item, on),
          ),
        ),
    ];

    if (!block.sortable) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: cards);
    }

    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      // The drag is a long press on the whole card. The design draws no handle, and a handle that
      // fits beside a 48px photo on a 320dp phone is a target a thumb misses — whereas the card is
      // the largest thing on the row.
      // `onReorderItem`, not the deprecated `onReorder`: this one hands over an index already
      // adjusted for the removal, so nothing here subtracts one.
      onReorderItem: _savingOrder.contains(block.id)
          ? (int from, int to) {}
          : (int from, int to) => _move(block, from, to),
      // Flutter needs the proxy to be lifted off the list; the default is a Material elevation that
      // paints a grey rectangle behind a bordered white card.
      proxyDecorator: (Widget child, int index, Animation<double> animation) => Material(
        color: Colors.transparent,
        child: child,
      ),
      children: <Widget>[
        for (int i = 0; i < cards.length; i++)
          ReorderableDelayedDragStartListener(
            key: cards[i].key!,
            index: i,
            child: Semantics(
              // Assistive tech has no long press. The custom actions are what make the order
              // reachable without one, in the same words the row would be dragged by.
              customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
                if (i > 0)
                  CustomSemanticsAction(label: t.menuMoveUp): () => _move(block, i, i - 1),
                if (i < cards.length - 1)
                  CustomSemanticsAction(label: t.menuMoveDown): () => _move(block, i, i + 1),
              },
              child: cards[i],
            ),
          ),
      ],
    );
  }
}

/// One item, as the design draws it: a 48px photo, the name and the price on one line, the
/// description and the availability switch under them.
class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.busy,
    required this.onEdit,
    required this.onAvailability,
  });

  final Product item;
  final bool busy;
  final VoidCallback onEdit;
  final ValueChanged<bool> onAvailability;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool available = item.status == ProductStatus.active;

    return YdCard.bordered(
      padding: const EdgeInsets.all(_MenuBuilderScreenState._cardPadding),
      // The design's 12px corner, not the 16px every other card keeps: on a row this short the
      // difference reads as a different kind of surface.
      radius: DeliveryRadius.md,
      onTap: onEdit,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _photo(t),
          const SizedBox(width: _MenuBuilderScreenState._cardPadding),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: DeliverySpacing.sm),
                    Text(
                      // The package's own money helper, so a price here is the number the order
                      // detail and the statement print. Left-to-right in both languages: a price
                      // read right-to-left is a price read wrong.
                      '\$${merchantMoney(item.price)}',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: DeliverySpacing.xs),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        (item.description ?? '').trim().isEmpty
                            ? t.menuNoDescription
                            : item.description!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
                      ),
                    ),
                    const SizedBox(width: DeliverySpacing.sm),
                    MerchantAvailabilitySwitch(
                      value: available,
                      busy: busy,
                      semanticLabel: t.menuAvailableSwitch(item.name),
                      onChanged: onAvailability,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photo(DeliveryStrings t) {
    const double side = _MenuBuilderScreenState._thumb;
    if (item.listImageUrl == null) {
      // A menu item with no photo is the commonest row in a shop's first week. The glyph is what
      // the catalogue list draws at this size too, with the same sentence attached, because the
      // words "No photo" do not fit under a 48px square.
      return Tooltip(
        message: t.noPhoto,
        child: Container(
          width: side,
          height: side,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DeliveryColors.background,
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
          ),
          child: Icon(
            Icons.image_outlined,
            size: 22,
            color: DeliveryColors.faint,
            semanticLabel: t.noPhoto,
          ),
        ),
      );
    }
    return SizedBox.square(
      dimension: side,
      child: DeliveryProductImage(
        url: item.listImageUrl,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        unavailableLabel: t.imageUnavailable,
        openLabel: t.openFullSizePhoto,
        onTap: null,
      ),
    );
  }
}

/// The design's extended FAB: a brand pill with a plus, lifted by a brand-tinted shadow.
///
/// Not a [FloatingActionButton.extended], which is 56 tall — the frame's is 44, and beside a 48px
/// photo the difference is the difference between a button and a landmark.
class _AddMenuItemButton extends StatelessWidget {
  const _AddMenuItemButton({required this.label, required this.onPressed});

  /// Already localised by the caller.
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.pill);
    return Semantics(
      button: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: corners,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: DeliveryColors.brand.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: DeliveryColors.brand,
          borderRadius: corners,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: DeliverySpacing.md,
                vertical: DeliverySpacing.md - DeliverySpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.add, size: 18, color: DeliveryColors.white),
                  const SizedBox(width: DeliverySpacing.sm),
                  // Constrained rather than free: "أضف صنفًا إلى القائمة" beside a 16px plus on a
                  // 320dp phone is wider than the screen, and a FAB that runs off the edge takes
                  // the tap target with it.
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.white,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pulls the human-readable half out of an RFC 9457 problem response.
///
/// The service always includes a `correlationId`; showing it lets a merchant quote one value that
/// finds their exact request across every service it touched.
String _messageFor(Object error, {required String fallback}) {
  if (error is DioException) {
    final Object? body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final String? detail = body['detail'] as String?;
      final String? correlationId = body['correlationId'] as String?;
      if (detail != null) {
        return correlationId == null ? detail : '$detail (ref: $correlationId)';
      }
    }
  }
  return fallback;
}
