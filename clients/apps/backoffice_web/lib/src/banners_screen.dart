import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// Home-screen editorial: the banner rail and the artwork on the category strip.
///
/// Two tabs because they are two jobs that happen to share a screen — banners are campaigns with
/// a lifecycle, category pictures are a one-off setup you revisit rarely. Both are BACKOFFICE-only
/// server-side; this screen is only the UI for it.
class BannersScreen extends StatelessWidget {
  const BannersScreen({super.key, required this.api, required this.catalogApi});

  final BannerApi api;
  final CatalogApi catalogApi;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: <Widget>[
          const TabBar(
            labelColor: DeliveryColors.brand,
            indicatorColor: DeliveryColors.brand,
            tabs: <Widget>[
              Tab(text: 'Banners'),
              Tab(text: 'Category pictures'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _BannerList(api: api),
                _CategoryImages(api: api, catalogApi: catalogApi),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------- banners

class _BannerList extends StatefulWidget {
  const _BannerList({required this.api});

  final BannerApi api;

  @override
  State<_BannerList> createState() => _BannerListState();
}

class _BannerListState extends State<_BannerList> {
  static const int _pageSize = 20;

  late Future<Paged<HomeBanner>> _page = widget.api.all(size: _pageSize);
  int _pageIndex = 0;
  bool _busy = false;

  void _load(int page) {
    setState(() {
      _pageIndex = page;
      _page = widget.api.all(page: page, size: _pageSize);
    });
  }

  /// Runs a write and reloads, turning whatever went wrong into one sentence.
  ///
  /// Catches everything, not just [DioException]: a failure that is not an HTTP failure — a
  /// missing platform plugin, a bad decode — would otherwise leave the button looking like it
  /// simply does nothing, which is the worst thing a button can do.
  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      _load(_pageIndex);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The service validates that a STORE or CATEGORY destination actually exists, so a 422 here
  /// almost always means a bad link rather than a bad title.
  static String _message(Object error) {
    if (error is! DioException) {
      // Not an HTTP failure. Say what actually happened rather than a generic apology — the one
      // that bites here is a platform plugin the build did not register.
      return 'Something went wrong: $error';
    }
    final int? status = error.response?.statusCode;
    if (status == 422 || status == 400) {
      final dynamic body = error.response?.data;
      if (body is Map && body['message'] is String) return body['message'] as String;
      if (body is Map && body['detail'] is String) return body['detail'] as String;
      return 'That destination does not exist';
    }
    if (status == 403) return 'Your account cannot edit banners';
    return 'Could not save the banner';
  }

  Future<void> _edit({HomeBanner? existing}) async {
    final _BannerDraft? draft = await showDialog<_BannerDraft>(
      context: context,
      builder: (BuildContext context) => _BannerDialog(existing: existing),
    );
    if (draft == null) return;

    await _run(
      () async {
        if (existing == null) {
          await widget.api.create(
            title: draft.title,
            subtitle: draft.subtitle,
            linkKind: draft.linkKind,
            linkTarget: draft.linkTarget,
            position: draft.position,
            active: draft.active,
          );
        } else {
          await widget.api.update(
            existing.id,
            title: draft.title,
            subtitle: draft.subtitle,
            linkKind: draft.linkKind,
            linkTarget: draft.linkTarget,
            position: draft.position,
            active: draft.active,
          );
        }
      },
      existing == null ? 'Banner created' : 'Banner saved',
    );
  }

  Future<void> _upload(HomeBanner banner) async {
    final _PickedImage? picked = await _pickImage(context);
    if (picked == null) return;
    await _run(
      () => widget.api
          .uploadBannerImage(
              bannerId: banner.id, bytes: picked.bytes, contentType: picked.contentType)
          .then((_) {}),
      'Artwork uploaded',
    );
  }

  Future<void> _setActive(HomeBanner banner, bool active) {
    // Withdraw is its own endpoint; putting a banner back is an ordinary edit.
    return _run(
      () => active
          ? widget.api
              .update(banner.id,
                  title: banner.title,
                  subtitle: banner.subtitle,
                  linkKind: banner.linkKind,
                  linkTarget: banner.linkTarget,
                  position: banner.position,
                  active: true)
              .then((_) {})
          : widget.api.withdraw(banner.id),
      active ? 'Banner is live' : 'Banner withdrawn',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _edit(),
        backgroundColor: DeliveryColors.brand,
        foregroundColor: DeliveryColors.white,
        icon: const Icon(Icons.add),
        label: const Text('New banner'),
      ),
      body: FutureBuilder<Paged<HomeBanner>>(
        future: _page,
        builder: (BuildContext context, AsyncSnapshot<Paged<HomeBanner>> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load banners: ${snapshot.error}'));
          }

          final Paged<HomeBanner> page = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(DeliverySpacing.lg),
            children: <Widget>[
              Text('Banners', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: DeliverySpacing.xs),
              Text(
                '${page.totalElements} banners. They appear on the customer home screen in '
                'position order, lowest first.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: DeliverySpacing.lg),
              const SectionLabel('Campaigns'),
              if (page.content.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(DeliverySpacing.lg),
                    child: Text('No banners yet. The home rail is hidden until there is one.'),
                  ),
                )
              else
                for (final HomeBanner banner in page.content)
                  _bannerCard(context, banner),
              const SizedBox(height: DeliverySpacing.md),
              _pager(page),
              // Clears the FAB, which would otherwise sit on the last row.
              const SizedBox(height: DeliverySpacing.xl * 2),
            ],
          );
        },
      ),
    );
  }

  Widget _bannerCard(BuildContext context, HomeBanner banner) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.md),
      child: SoftCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _thumbnail(banner),
            const SizedBox(width: DeliverySpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(banner.title,
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      _statusChip(banner),
                    ],
                  ),
                  if (banner.subtitle != null && banner.subtitle!.isNotEmpty) ...<Widget>[
                    const SizedBox(height: DeliverySpacing.xs),
                    Text(banner.subtitle!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: DeliverySpacing.xs),
                  Text(_destination(banner),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: DeliveryColors.muted)),
                  const SizedBox(height: DeliverySpacing.sm),
                  Wrap(
                    spacing: DeliverySpacing.xs,
                    children: <Widget>[
                      TextButton.icon(
                        onPressed: _busy ? null : () => _edit(existing: banner),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit'),
                      ),
                      TextButton.icon(
                        onPressed: _busy ? null : () => _upload(banner),
                        icon: const Icon(Icons.image_outlined, size: 18),
                        label: Text(banner.imageUrl == null ? 'Add artwork' : 'Replace artwork'),
                      ),
                      TextButton.icon(
                        onPressed: _busy ? null : () => _setActive(banner, !banner.active),
                        icon: Icon(
                            banner.active
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 18),
                        label: Text(banner.active ? 'Withdraw' : 'Put back'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail(HomeBanner banner) {
    const double width = 132;
    const double height = 74; // 16:9, the ratio the customer rail renders at.
    if (banner.imageUrl == null) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: DeliveryColors.brandSoft,
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
        ),
        child: const Icon(Icons.image_outlined, color: DeliveryColors.brand),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(DeliveryRadius.md),
      child: Image.network(
        banner.imageUrl!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        // A presigned URL can expire while the page is open; a broken-image box explains that
        // better than an exception in the console.
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) => Container(
          width: width,
          height: height,
          color: DeliveryColors.background,
          child: const Icon(Icons.broken_image_outlined, color: DeliveryColors.muted),
        ),
      ),
    );
  }

  Widget _statusChip(HomeBanner banner) {
    final bool live = banner.active;
    // Borrows the storefront's open/closed pair rather than introducing a fourth green: "live"
    // and "open" mean the same thing to a reader — this is showing, that is trading.
    final Color colour =
        live ? DeliveryStoreState.open.color : DeliveryStoreState.closed.color;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: DeliverySpacing.sm, vertical: DeliverySpacing.xs),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
      ),
      child: Text(
        live ? 'Live' : 'Withdrawn',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colour),
      ),
    );
  }

  static String _destination(HomeBanner banner) {
    final String position = 'Position ${banner.position}';
    return switch (banner.linkKind) {
      BannerLinkKind.none => '$position  ·  Informational, not tappable',
      BannerLinkKind.store => '$position  ·  Opens store ${banner.linkTarget}',
      BannerLinkKind.category => '$position  ·  Opens category ${banner.linkTarget}',
      BannerLinkKind.url => '$position  ·  Opens ${banner.linkTarget}',
    };
  }

  Widget _pager(Paged<HomeBanner> page) {
    if (page.totalPages <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        TextButton.icon(
          onPressed: _pageIndex > 0 ? () => _load(_pageIndex - 1) : null,
          icon: const Icon(Icons.chevron_left),
          label: const Text('Previous'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.md),
          child: Text('Page ${_pageIndex + 1} of ${page.totalPages}'),
        ),
        TextButton.icon(
          onPressed: _pageIndex + 1 < page.totalPages ? () => _load(_pageIndex + 1) : null,
          icon: const Icon(Icons.chevron_right),
          label: const Text('Next'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------- banner dialog

class _BannerDraft {
  const _BannerDraft({
    required this.title,
    required this.subtitle,
    required this.linkKind,
    required this.linkTarget,
    required this.position,
    required this.active,
  });

  final String title;
  final String? subtitle;
  final BannerLinkKind linkKind;
  final String? linkTarget;
  final int position;
  final bool active;
}

class _BannerDialog extends StatefulWidget {
  const _BannerDialog({this.existing});

  final HomeBanner? existing;

  @override
  State<_BannerDialog> createState() => _BannerDialogState();
}

class _BannerDialogState extends State<_BannerDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _subtitle =
      TextEditingController(text: widget.existing?.subtitle ?? '');
  late final TextEditingController _target =
      TextEditingController(text: widget.existing?.linkTarget ?? '');
  late final TextEditingController _position =
      TextEditingController(text: '${widget.existing?.position ?? 0}');

  late BannerLinkKind _kind = widget.existing?.linkKind ?? BannerLinkKind.none;
  late bool _active = widget.existing?.active ?? true;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _target.dispose();
    _position.dispose();
    super.dispose();
  }

  void _submit() {
    final String title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'A banner needs a title');
      return;
    }
    final String target = _target.text.trim();
    if (_kind != BannerLinkKind.none && target.isEmpty) {
      setState(() => _error = 'A ${_kindLabel(_kind).toLowerCase()} banner needs a destination');
      return;
    }
    final int? position = int.tryParse(_position.text.trim());
    if (position == null || position < 0 || position > 999) {
      setState(() => _error = 'Position must be a number from 0 to 999');
      return;
    }

    Navigator.of(context).pop(_BannerDraft(
      title: title,
      subtitle: _subtitle.text.trim().isEmpty ? null : _subtitle.text.trim(),
      linkKind: _kind,
      linkTarget: _kind == BannerLinkKind.none ? null : target,
      position: position,
      active: _active,
    ));
  }

  static String _kindLabel(BannerLinkKind kind) => switch (kind) {
        BannerLinkKind.none => 'No destination',
        BannerLinkKind.store => 'Store',
        BannerLinkKind.category => 'Category',
        BannerLinkKind.url => 'Web link',
      };

  static String _targetLabel(BannerLinkKind kind) => switch (kind) {
        BannerLinkKind.none => '',
        BannerLinkKind.store => 'Store id or slug',
        BannerLinkKind.category => 'Category id',
        BannerLinkKind.url => 'https://…',
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New banner' : 'Edit banner'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _title,
                autofocus: true,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: _subtitle,
                maxLength: 240,
                decoration: const InputDecoration(
                  labelText: 'Subtitle',
                  helperText: 'Optional — the smaller line under the title',
                ),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              DropdownButtonFormField<BannerLinkKind>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Tapping it opens'),
                items: <DropdownMenuItem<BannerLinkKind>>[
                  for (final BannerLinkKind kind in BannerLinkKind.values)
                    DropdownMenuItem<BannerLinkKind>(
                        value: kind, child: Text(_kindLabel(kind))),
                ],
                onChanged: (BannerLinkKind? value) =>
                    setState(() => _kind = value ?? BannerLinkKind.none),
              ),
              if (_kind != BannerLinkKind.none) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                TextField(
                  controller: _target,
                  decoration: InputDecoration(
                    labelText: _targetLabel(_kind),
                    helperText: _kind == BannerLinkKind.url
                        ? null
                        : 'Checked when you save — a destination that does not exist is refused',
                  ),
                ),
              ],
              const SizedBox(height: DeliverySpacing.sm),
              TextField(
                controller: _position,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Position',
                  helperText: 'Lowest first on the home rail',
                ),
              ),
              SwitchListTile(
                value: _active,
                onChanged: (bool value) => setState(() => _active = value),
                contentPadding: EdgeInsets.zero,
                activeThumbColor: DeliveryColors.brand,
                title: const Text('Live'),
                subtitle: const Text('Off keeps it here but off the customer home screen'),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: DeliverySpacing.xs),
                Text(_error!, style: const TextStyle(color: DeliveryColors.brand)),
              ],
              if (widget.existing != null) ...<Widget>[
                const SizedBox(height: DeliverySpacing.xs),
                Text(
                  'Artwork is uploaded from the list, not here — it needs the banner to exist first.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: DeliveryColors.muted),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(widget.existing == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------- category pictures

class _CategoryImages extends StatefulWidget {
  const _CategoryImages({required this.api, required this.catalogApi});

  final BannerApi api;
  final CatalogApi catalogApi;

  @override
  State<_CategoryImages> createState() => _CategoryImagesState();
}

class _CategoryImagesState extends State<_CategoryImages> {
  late Future<List<Category>> _categories = widget.catalogApi.categories();
  bool _busy = false;

  void _reload() {
    setState(() {
      _categories = widget.catalogApi.categories();
    });
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      _reload();
    } on DioException catch (e) {
      if (!mounted) return;
      // 409: the vertical is uniquely indexed, so only one category can stand for each.
      final String message = e.response?.statusCode == 409
          ? 'Another category already stands for that vertical'
          : 'Could not save the category';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload(Category category) async {
    final _PickedImage? picked = await _pickImage(context);
    if (picked == null) return;
    await _run(
      () => widget.api
          .uploadCategoryImage(
              categoryId: category.id, bytes: picked.bytes, contentType: picked.contentType)
          .then((_) {}),
      'Picture uploaded',
    );
  }

  Future<void> _setVertical(Category category, StoreVertical? vertical) {
    return _run(
      () => widget.api.setVertical(category.id, vertical).then((_) {}),
      vertical == null ? 'Removed from the home strip' : 'Added to the home strip',
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Category>>(
      future: _categories,
      builder: (BuildContext context, AsyncSnapshot<List<Category>> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Could not load categories: ${snapshot.error}'));
        }

        // Top level only. The home strip shows roots; a picture on a leaf category would never
        // be rendered anywhere, so offering to upload one would be a lie.
        final List<Category> roots = snapshot.data!;
        final int tagged = roots.where((Category c) => c.vertical != null).length;

        return ListView(
          padding: const EdgeInsets.all(DeliverySpacing.lg),
          children: <Widget>[
            Text('Category pictures', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: DeliverySpacing.xs),
            Text(
              '$tagged of ${roots.length} top-level categories appear in the customer home strip. '
              'A category shows there once it stands for a vertical; the picture is what it shows.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: DeliverySpacing.lg),
            const SectionLabel('Top-level categories'),
            SoftCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < roots.length; i++) ...<Widget>[
                    if (i > 0) const Divider(height: 1),
                    _row(context, roots[i], roots),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, Category category, List<Category> all) {
    // Verticals already spoken for by another category cannot be picked twice — the database has
    // a unique index on it, so showing them would only produce a 409.
    final Set<StoreVertical> taken = all
        .where((Category c) => c.id != category.id && c.vertical != null)
        .map((Category c) => c.vertical!)
        .toSet();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
          horizontal: DeliverySpacing.md, vertical: DeliverySpacing.xs),
      leading: _avatar(category),
      title: Text(category.name),
      subtitle: Text(
        category.vertical == null
            ? 'Not in the home strip'
            : 'Filters the storefront by ${category.vertical!.label}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<StoreVertical?>(
              // Keyed on the value the server last confirmed, so a rejected change (the vertical
              // was already taken) snaps back instead of leaving the dropdown showing a state
              // that was refused.
              key: ValueKey<String>('${category.id}:${category.vertical?.wireValue}'),
              initialValue: category.vertical,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Vertical',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<StoreVertical?>>[
                const DropdownMenuItem<StoreVertical?>(value: null, child: Text('None')),
                for (final StoreVertical vertical in StoreVertical.values)
                  if (!taken.contains(vertical))
                    DropdownMenuItem<StoreVertical?>(
                        value: vertical, child: Text(vertical.label)),
              ],
              onChanged: _busy
                  ? null
                  : (StoreVertical? value) => _setVertical(category, value),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          TextButton.icon(
            onPressed: _busy ? null : () => _upload(category),
            icon: const Icon(Icons.image_outlined, size: 18),
            label: Text(category.imageUrl == null ? 'Add picture' : 'Replace'),
          ),
        ],
      ),
    );
  }

  Widget _avatar(Category category) {
    if (category.imageUrl == null) {
      return const CircleAvatar(
        backgroundColor: DeliveryColors.brandSoft,
        child: Icon(Icons.category_outlined, color: DeliveryColors.brand),
      );
    }
    return CircleAvatar(
      backgroundColor: DeliveryColors.background,
      // ClipOval over Image.network rather than backgroundImage: it gives somewhere to put an
      // error fallback, which a NetworkImage on an avatar does not.
      child: ClipOval(
        child: Image.network(
          category.imageUrl!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
              const Icon(Icons.broken_image_outlined, color: DeliveryColors.muted),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------- picking

class _PickedImage {
  const _PickedImage(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;
}

/// Opens the file picker and reads the bytes.
///
/// `file_selector` rather than `image_picker`, matching the merchant portal — it is the one that
/// works cleanly on Flutter Web, which is the only place this app runs.
///
/// Deliberately called straight from the button handler rather than from inside a guarded
/// helper: on the web the file dialog may only open while the browser still considers the click
/// to be in progress, and putting work in front of it forfeits that. It reports its own failures
/// instead, because a picker that throws silently leaves a button that appears to do nothing.
Future<_PickedImage?> _pickImage(BuildContext context) async {
  // Mirrors the service's allow-list. It re-checks and returns 422 regardless, so this only saves
  // a pointless round trip.
  const XTypeGroup images = XTypeGroup(
    label: 'Images',
    extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
    mimeTypes: <String>['image/jpeg', 'image/png', 'image/webp'],
  );

  try {
    final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[images]);
    if (file == null) return null;
    return _PickedImage(await file.readAsBytes(), _contentTypeFor(file));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open the file picker: $e')));
    }
    return null;
  }
}

/// `XFile.mimeType` is null on several platforms, so fall back to the extension.
String _contentTypeFor(XFile file) {
  final String? declared = file.mimeType;
  if (declared != null && declared.startsWith('image/')) return declared;
  final String name = file.name.toLowerCase();
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}
