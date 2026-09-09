import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'order_detail_screen.dart';

/// The shop's own sections — Figma `merchant-categories` (94:351 phone / 94:3710 web).
///
/// Not the platform taxonomy. `/api/categories` is everybody's list and the Backoffice owns it;
/// these rows carry a `storeId`, are written by the merchant, and decide the order the customer
/// app draws the shop page in. The two are shown together on purpose — the sections a shop wrote
/// on top, the platform categories it can file them under underneath, read-only — because a
/// merchant who cannot see the difference will keep asking why "Drinks" cannot be renamed.
///
/// Three things here are load-bearing:
///
/// * **The drag is the feature.** `position` is the customer-facing display order, so the row a
///   merchant drags to the top is the section customers see first. The screen says so in as many
///   words ([DeliveryStrings.catDragToReorder]) rather than leaving the handle to explain itself.
/// * **The reorder is optimistic, and reverts.** The row moves the instant the finger lifts, then
///   `PUT …/categories/order` replaces the whole order. A failure puts the list back exactly as
///   the server last described it and says so — a screen that silently keeps a local order the
///   server rejected is lying about what customers will see.
/// * **Delete is refused, not attempted, while a section holds products.** The server answers 409
///   rather than orphaning listings; the count is already on the row, so the screen can explain
///   before the tap instead of translating an error afterwards.
///
/// The store-category endpoints ship with product-service release B. Until then every call here
/// resolves to the same calm "could not load" state and a retry — see [_load]. [storeId] is
/// nullable for the same reason: a host that has not resolved the shop yet gets an empty state,
/// never an exception.
///
/// One widget, two hosts. The Android shell hands it 380dp and a thumb; the portal hands it the
/// space beside its rail, where the column caps at [merchantMaxContentWidth] and centres rather
/// than stretching a 16px-padded row across a desk.
class MerchantCategoriesScreen extends StatefulWidget {
  const MerchantCategoriesScreen({
    super.key,
    required this.api,
    this.storeId,
    this.onBack,
  });

  /// The catalogue client. Store sections and the platform taxonomy both come from here.
  final CatalogApi api;

  /// Which shop's sections these are. Null while a host is still resolving the merchant's store —
  /// the screen then draws [_unavailable] instead of calling with a hole in the path.
  final String? storeId;

  /// Shows the header's back button when non-null. The hosts that mount this as a tab pass
  /// nothing; the ones that push it as a route pass a pop.
  final VoidCallback? onBack;

  @override
  State<MerchantCategoriesScreen> createState() => _MerchantCategoriesScreenState();
}

class _MerchantCategoriesScreenState extends State<MerchantCategoriesScreen> {
  /// Below this the page is on a phone: the header's refresh control gives way to the pull
  /// gesture. Measured against this widget's own constraints, never the window — the portal's rail
  /// can leave a desktop as narrow as a handset.
  static const double _phoneWidth = 600;

  /// The row thumbnail and the padding around it. Together they set the row's floor height.
  static const double _rowImage = 48;
  static const double _rowPadding = 10;

  /// Room under the last row so the floating "Add a section" button sits over nothing rather than
  /// over the row somebody was about to drag.
  static const double _fabClearance = 88;

  /// The shop's sections in display order. Null until the first answer.
  List<Category>? _sections;

  /// The last order the server confirmed. A failed reorder reverts to exactly this, which is why
  /// it is kept separately from [_sections] rather than re-derived from it.
  List<Category> _confirmed = const <Category>[];

  /// The platform taxonomy: the parent options in the editor, and the read-only block at the foot
  /// of the page. A failure here is not fatal — the editor simply offers "Top level" only.
  List<Category> _platform = const <Category>[];

  bool _loading = true;
  Object? _error;

  /// True from the moment a drag lands until the server has ruled on it. Dragging is disabled
  /// meanwhile: a second move over an unsettled order would leave nothing sane to revert to.
  bool _savingOrder = false;

  /// Sections with a write in flight, so a double tap cannot fire two deletes.
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads both lists. The sections decide whether the page has anything to show; the taxonomy is
  /// a nicety, so its failure is swallowed rather than blanking a page that loaded fine.
  Future<void> _load() async {
    final String? storeId = widget.storeId;
    if (storeId == null) {
      setState(() {
        _loading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    List<Category> platform = const <Category>[];
    try {
      platform = await widget.api.categories();
    } catch (_) {
      // The parent picker degrades to "Top level" and the reference block does not draw.
    }

    try {
      final List<Category> sections = await widget.api.storeCategories(storeId);
      if (!mounted) return;
      setState(() {
        _sections = sections;
        _confirmed = sections;
        _platform = platform;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _platform = platform;
        _error = e;
        _loading = false;
      });
    }
  }

  /// The same load, finishing only when the request does — [RefreshIndicator] keeps spinning until
  /// its future completes.
  Future<void> _refresh() => _load();

  // ------------------------------------------------------------------ reorder

  void _onReorder(int oldIndex, int newIndex) {
    final List<Category>? current = _sections;
    if (current == null || _savingOrder) {
      return;
    }
    // `onReorderItem`, not the deprecated `onReorder`: this one hands over an index that has
    // already been adjusted for the removal, so the list must NOT subtract one itself.
    if (newIndex == oldIndex) {
      return;
    }

    final List<Category> moved = List<Category>.of(current);
    moved.insert(newIndex, moved.removeAt(oldIndex));
    setState(() {
      _sections = moved;
      _savingOrder = true;
    });
    _persistOrder(moved);
  }

  /// Sends the complete order and reconciles with whatever the server says it wrote.
  ///
  /// The endpoint is a whole-list REPLACE — it rewrites `position` 0..n-1 in one transaction and
  /// refuses a list that is not exactly this shop's sections — so the ids go up in full, and the
  /// response, not the local guess, becomes the new truth.
  Future<void> _persistOrder(List<Category> order) async {
    final String? storeId = widget.storeId;
    if (storeId == null) {
      return;
    }
    final DeliveryStrings t = DeliveryStrings.of(context);
    try {
      final List<Category> saved = await widget.api.reorderStoreCategories(
        storeId,
        order.map((Category c) => c.id).toList(),
      );
      if (!mounted) return;
      // A server that answers 204-with-no-body leaves the local order standing, which is the order
      // it just accepted anyway.
      final List<Category> settled = saved.isEmpty ? order : saved;
      setState(() {
        _sections = settled;
        _confirmed = settled;
        _savingOrder = false;
      });
      _say(t.catOrderSaved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sections = List<Category>.of(_confirmed);
        _savingOrder = false;
      });
      _say(_messageFor(e, fallback: t.catOrderFailed));
    }
  }

  // ------------------------------------------------------------- create / edit

  Future<void> _openEditor([Category? existing]) async {
    final String? storeId = widget.storeId;
    if (storeId == null) {
      return;
    }
    final DeliveryStrings t = DeliveryStrings.of(context);

    final _SectionDraft? draft = await showDialog<_SectionDraft>(
      context: context,
      builder: (BuildContext context) => _SectionEditorDialog(
        existing: existing,
        platform: _platform,
      ),
    );
    if (draft == null || !mounted) {
      return;
    }

    setState(() {
      if (existing != null) _busy.add(existing.id);
    });
    try {
      if (existing == null) {
        await widget.api.createStoreCategory(
          storeId,
          name: draft.name,
          parentId: draft.parentId,
        );
      } else {
        await widget.api.updateStoreCategory(
          storeId,
          existing.id,
          name: draft.name,
          parentId: draft.parentId,
        );
      }
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      _say(_messageFor(e, fallback: t.somethingWentWrong));
    } finally {
      if (mounted && existing != null) {
        setState(() => _busy.remove(existing.id));
      }
    }
  }

  // ------------------------------------------------------------------- delete

  Future<void> _delete(Category section) async {
    final String? storeId = widget.storeId;
    if (storeId == null || _busy.contains(section.id)) {
      return;
    }
    final DeliveryStrings t = DeliveryStrings.of(context);

    // The row already carries the count, so the refusal can be explained before the request rather
    // than translated out of a 409 afterwards.
    if (section.productCount > 0) {
      _say(t.catCannotDeleteNonEmpty(section.productCount));
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(t.catDelete),
        content: Text(t.catDeleteConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t.catDelete),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted) {
      return;
    }

    setState(() => _busy.add(section.id));
    try {
      await widget.api.deleteStoreCategory(storeId, section.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      // The server is the authority on whether the section is empty; its count can be newer than
      // the one on the row this screen loaded.
      final String fallback = _isConflict(e)
          ? t.catCannotDeleteNonEmpty(section.productCount)
          : t.somethingWentWrong;
      _say(_messageFor(e, fallback: fallback));
    } finally {
      if (mounted) {
        setState(() => _busy.remove(section.id));
      }
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool narrow = constraints.maxWidth < _phoneWidth;

        return Scaffold(
          backgroundColor: DeliveryColors.background,
          // No AppBar: the framing belongs to whichever app is hosting this screen.
          floatingActionButton: widget.storeId == null
              ? null
              : YdPillButton(
                  label: t.catAdd,
                  icon: Icons.add,
                  expand: false,
                  size: YdPillButtonSize.compact,
                  onPressed: () => _openEditor(),
                ),
          body: Column(
            children: <Widget>[
              MerchantScreenHeader(
                title: t.catTitle,
                subtitle: t.catSubtitle,
                onBack: widget.onBack,
                // The refresh button only exists where there is no pull gesture to replace it.
                trailing: narrow
                    ? null
                    : IconButton(
                        onPressed: _loading ? null : _load,
                        icon: const Icon(Icons.refresh, size: 20),
                        color: DeliveryColors.ink,
                        tooltip: t.refresh,
                      ),
              ),
              Expanded(child: _body(t, narrow: narrow)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(DeliveryStrings t, {required bool narrow}) {
    final Widget scroller = Align(
      // Top, not centre: the column caps its width on a desktop but still starts at the header.
      alignment: AlignmentDirectional.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
        child: _scroller(t, narrow: narrow),
      ),
    );

    if (!narrow || widget.storeId == null) {
      return scroller;
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      color: DeliveryColors.brand,
      child: scroller,
    );
  }

  Widget _scroller(DeliveryStrings t, {required bool narrow}) {
    final Widget? placeholder = _placeholder(t);
    final List<Category> sections = placeholder != null ? const <Category>[] : _sections!;

    return CustomScrollView(
      // Always scrollable, or the pull-to-refresh is dead on the two states where a merchant most
      // wants to retry: nothing loaded, and nothing to show.
      physics: narrow ? const AlwaysScrollableScrollPhysics() : null,
      slivers: <Widget>[
        if (placeholder != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(DeliverySpacing.lg),
              child: placeholder,
            ),
          )
        else ...<Widget>[
          if (sections.length > 1)
            SliverToBoxAdapter(child: _reorderHint(t)),
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              DeliverySpacing.lg,
              DeliverySpacing.lg,
              DeliverySpacing.lg,
              DeliverySpacing.sm,
            ),
            sliver: SliverToBoxAdapter(
              child: YdSectionHeader(
                title: t.catYourSections,
                trailing: _savingOrder
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: DeliveryColors.brand,
                        ),
                      )
                    : null,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.lg),
            // A sliver rather than a ReorderableListView, so the hint above it and the taxonomy
            // block below it scroll with the rows instead of pinning a list between two bands.
            sliver: SliverReorderableList(
              itemCount: sections.length,
              onReorderItem: _onReorder,
              proxyDecorator: _liftedRow,
              itemBuilder: (BuildContext context, int index) {
                final Category section = sections[index];
                return Padding(
                  // Keyed on the section, not the index: the key is what lets the framework carry
                  // a row's state across the move.
                  key: ValueKey<String>(section.id),
                  padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
                  child: _SectionRow(
                    section: section,
                    index: index,
                    busy: _busy.contains(section.id),
                    draggable: !_savingOrder && sections.length > 1,
                    dragHint: t.catDragToReorder,
                    onEdit: () => _openEditor(section),
                    onDelete: () => _delete(section),
                  ),
                );
              },
            ),
          ),
          if (_platform.isNotEmpty)
            SliverToBoxAdapter(child: _platformBlock(t)),
          SliverToBoxAdapter(
            child: SizedBox(
              // Clears the floating button, then the gesture bar under it. `paddingOf`, not
              // `viewPaddingOf`: a host that already wrapped this in a SafeArea spent the inset.
              height: _fabClearance + MediaQuery.paddingOf(context).bottom,
            ),
          ),
        ],
      ],
    );
  }

  /// The design's own sentence about what dragging does. It is the only place the customer-facing
  /// consequence of `position` is written down, so it is not decoration.
  Widget _reorderHint(DeliveryStrings t) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        DeliverySpacing.lg,
        DeliverySpacing.md,
        DeliverySpacing.lg,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
        decoration: BoxDecoration(
          color: DeliveryColors.brandSoft,
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.drag_indicator, size: 18, color: DeliveryColors.brand),
            const SizedBox(width: DeliverySpacing.sm),
            Expanded(
              child: Text(
                t.catDragToReorder,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: DeliveryColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The platform taxonomy, read-only: what a section can be filed under, and the thing a merchant
  /// keeps trying to rename. Chips without a tap, because there is nothing here to do.
  Widget _platformBlock(DeliveryStrings t) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        DeliverySpacing.lg,
        DeliverySpacing.lg,
        DeliverySpacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          YdSectionHeader(title: t.catPlatformCategories, fontSize: 14),
          const SizedBox(height: DeliverySpacing.sm),
          Wrap(
            spacing: DeliverySpacing.sm,
            runSpacing: DeliverySpacing.sm,
            children: <Widget>[
              for (final Category category in _platform) YdChip(label: category.name),
            ],
          ),
        ],
      ),
    );
  }

  /// What goes where the list would be when there is no list to draw. Null means draw the rows.
  Widget? _placeholder(DeliveryStrings t) {
    if (widget.storeId == null) {
      return YdEmptyState(
        icon: Icons.storefront_outlined,
        title: t.catCouldNotLoad,
        // Closest existing string; see the note on this screen about `catNoShopYet`.
        message: t.staffNoShopYet,
      );
    }
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(DeliverySpacing.xl),
          child: CircularProgressIndicator(color: DeliveryColors.brand),
        ),
      );
    }
    if (_error != null) {
      return YdEmptyState(
        icon: Icons.cloud_off_rounded,
        title: t.catCouldNotLoad,
        message: _messageFor(_error!, fallback: t.somethingWentWrong),
        action: YdPillButton.secondary(
          label: t.tryAgain,
          onPressed: _load,
          size: YdPillButtonSize.compact,
          expand: false,
        ),
      );
    }
    if ((_sections ?? const <Category>[]).isEmpty) {
      return YdEmptyState(
        icon: Icons.category_outlined,
        title: t.catEmpty,
        message: t.catEmptyHint,
        action: YdPillButton(
          label: t.catAdd,
          icon: Icons.add,
          onPressed: () => _openEditor(),
          size: YdPillButtonSize.compact,
          expand: false,
        ),
      );
    }
    return null;
  }

  /// The row under the finger while it is being dragged: the same row, lifted.
  ///
  /// The default proxy inherits a Material elevation that paints a grey rectangle behind a card
  /// with rounded corners. This keeps the card's own shape and just raises it.
  Widget _liftedRow(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? built) {
        final double lift = Curves.easeInOut.transform(animation.value);
        return Material(
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DeliveryRadius.lg),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: DeliveryColors.ink.withValues(alpha: 0.12 * lift),
                  blurRadius: 16 * lift,
                  offset: Offset(0, 4 * lift),
                ),
              ],
            ),
            child: built,
          ),
        );
      },
      child: child,
    );
  }
}

/// One section, as the frame draws it: drag handle, picture, name over a product count, then the
/// edit pencil and the delete affordance.
class _SectionRow extends StatelessWidget {
  const _SectionRow({
    required this.section,
    required this.index,
    required this.busy,
    required this.draggable,
    required this.dragHint,
    required this.onEdit,
    required this.onDelete,
  });

  final Category section;

  /// The row's place in the reorderable list — [ReorderableDragStartListener] needs it to know
  /// which row the drag started on.
  final int index;

  final bool busy;

  /// False while an order is being saved, and for a one-row list where there is nothing to
  /// reorder. The handle is still drawn, greyed, so the row's shape does not jump.
  final bool draggable;

  /// Already localised by the caller.
  final String dragHint;

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    final Widget handle = Tooltip(
      message: dragHint,
      child: Semantics(
        label: dragHint,
        child: SizedBox.square(
          dimension: 32,
          child: Icon(
            Icons.drag_indicator,
            size: 20,
            color: draggable ? DeliveryColors.faint : DeliveryColors.border,
          ),
        ),
      ),
    );

    return YdCard.bordered(
      padding: const EdgeInsetsDirectional.fromSTEB(
        DeliverySpacing.sm,
        _MerchantCategoriesScreenState._rowPadding,
        _MerchantCategoriesScreenState._rowPadding,
        _MerchantCategoriesScreenState._rowPadding,
      ),
      child: Row(
        children: <Widget>[
          // An explicit listener rather than the list's default handles: the default is a delayed
          // long-press on touch and nothing at all under a mouse, and this screen is mounted in a
          // browser as often as on a phone.
          if (draggable)
            ReorderableDragStartListener(index: index, child: handle)
          else
            handle,
          const SizedBox(width: DeliverySpacing.xs),
          _SectionThumbnail(
            section: section,
            label: t.catImage,
            unavailableLabel: t.imageUnavailable,
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  section.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t.catProductsCount(section.productCount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DeliveryColors.muted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: DeliverySpacing.md),
              child: SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DeliveryColors.brand,
                ),
              ),
            )
          else ...<Widget>[
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: DeliveryColors.muted,
              tooltip: t.catRename,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
              color: DeliveryColors.muted,
              tooltip: t.catDelete,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}

/// The section's picture, or the glyph that stands in for one.
///
/// [DeliveryProductImage]'s own empty state is an icon over the words "No photo", which wants more
/// height than this 48px slot has — so an artwork-less section falls back to the glyph alone, with
/// the sentence on the semantic label instead.
class _SectionThumbnail extends StatelessWidget {
  const _SectionThumbnail({
    required this.section,
    required this.label,
    required this.unavailableLabel,
  });

  final Category section;

  /// Already localised by the caller.
  final String label;

  /// What artwork whose presigned link has expired says instead. Also already localised.
  final String unavailableLabel;

  @override
  Widget build(BuildContext context) {
    const double size = _MerchantCategoriesScreenState._rowImage;
    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.md);
    final String? url = section.imageUrl;

    if (url == null || url.isEmpty) {
      return Semantics(
        label: label,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: DeliveryColors.background,
            borderRadius: corners,
          ),
          child: const Icon(
            Icons.category_outlined,
            size: 20,
            color: DeliveryColors.faint,
          ),
        ),
      );
    }

    return SizedBox.square(
      dimension: size,
      child: DeliveryProductImage(
        url: url,
        borderRadius: corners,
        unavailableLabel: unavailableLabel,
      ),
    );
  }
}

/// What the editor dialog hands back: a name, and the platform category it sits under.
///
/// A record would do, except that `null` is a meaningful `parentId` (top level) and a nullable
/// record makes "cancelled" and "moved to top level" the same value at the call site.
class _SectionDraft {
  const _SectionDraft({required this.name, this.parentId});

  final String name;
  final String? parentId;
}

/// Add and rename in one dialog — the fields are identical and the only difference is the title.
class _SectionEditorDialog extends StatefulWidget {
  const _SectionEditorDialog({required this.existing, required this.platform});

  /// Null for a new section.
  final Category? existing;

  /// The platform taxonomy, flattened into the parent picker. A store section may hang under a
  /// platform row, never under another section, so this list is deliberately not the store's own.
  final List<Category> platform;

  @override
  State<_SectionEditorDialog> createState() => _SectionEditorDialogState();
}

class _SectionEditorDialogState extends State<_SectionEditorDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');

  String? _parentId;

  /// The flattened taxonomy, computed once — the tree does not change while a dialog is open.
  late final List<({Category category, int depth})> _parents =
      Category.flatten(widget.platform);

  @override
  void initState() {
    super.initState();
    // Only keep the incoming parent if it is still an offerable option; a section whose parent was
    // retired from the taxonomy would otherwise hand the dropdown a value it has no item for,
    // which asserts.
    final String? incoming = widget.existing?.parentId;
    if (incoming != null &&
        _parents.any((({Category category, int depth}) p) => p.category.id == incoming)) {
      _parentId = incoming;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      return;
    }
    Navigator.of(context).pop(_SectionDraft(name: name, parentId: _parentId));
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return AlertDialog(
      title: Text(widget.existing == null ? t.catAdd : t.catRename),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: t.catName,
              hintText: t.catNameHint,
            ),
          ),
          if (_parents.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.md),
            DropdownButtonFormField<String?>(
              initialValue: _parentId,
              isExpanded: true,
              decoration: InputDecoration(labelText: t.catParent),
              items: <DropdownMenuItem<String?>>[
                DropdownMenuItem<String?>(value: null, child: Text(t.catNoParent)),
                for (final ({Category category, int depth}) parent in _parents)
                  DropdownMenuItem<String?>(
                    value: parent.category.id,
                    child: Text(
                      // Indented rather than nested, because a dropdown item is one flat line.
                      '${'    ' * parent.depth}${parent.category.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (String? value) => setState(() => _parentId = value),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(t.save),
        ),
      ],
    );
  }
}

/// True when the server refused because the thing is still in use — here, a section that still
/// holds products.
bool _isConflict(Object error) =>
    error is DioException && error.response?.statusCode == 409;

/// Pulls the human-readable half out of an RFC 9457 problem response.
///
/// The service always includes a `correlationId`; showing it lets a merchant quote one value that
/// finds their exact request across every service it touched. The fallback is required rather than
/// defaulted: a default would have to be a compile-time constant, which a translated string is not.
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
