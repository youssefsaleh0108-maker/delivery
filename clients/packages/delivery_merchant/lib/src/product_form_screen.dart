import 'dart:typed_data';
import 'dart:ui' show PathMetric;

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
// material.dart already re-exports debugPrint and debugPrintStack. Importing foundation.dart for
// them drags in its Category annotation, which collides with delivery_core's Category model.
import 'package:flutter/material.dart';

import 'product_options_editor.dart';

/// Create or edit one product, and manage its images.
///
/// Drawn to the 2026-08 Figma frame `merchant-add-product` (3:1964): a dashed upload dropzone under
/// a SemiBold label, a stack of labelled white input boxes with Price and Category sharing a row,
/// a bordered "Variants & Options" card, and one full-width brand button at the bottom.
///
/// Photos can be picked while creating the product, not only after. The presign endpoint is scoped
/// to a product id, so on a NEW product the picked bytes are held in memory and uploaded the moment
/// the first save earns an id; on an existing product a pick uploads straight away. Either way the
/// ownership check on presign still holds, because the upload only ever happens against a product
/// this merchant just created or already owns.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({
    super.key,
    required this.api,
    this.storeApi,
    this.existing,
  });

  final CatalogApi api;

  /// Reads the product's option groups for the design's variants card.
  ///
  /// Optional because the option read model lives on [StoreApi] rather than [CatalogApi], and not
  /// every host has one to hand. Without it the card draws its empty state instead of pretending
  /// the product has no options.
  final StoreApi? storeApi;

  final Product? existing;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final TextEditingController _price =
      TextEditingController(text: widget.existing?.price.toStringAsFixed(2) ?? '');

  late String? _categoryId = widget.existing?.categoryId;
  late Product? _product = widget.existing;

  /// The category tree, which does not change while a form is open — but the fetch can fail, and a
  /// failure must not strand the form. It used to be a `late final` future read by a FutureBuilder
  /// whose only non-data branch was a spinner, so a category load that errored left a spinner that
  /// never resolved AND a merchant who could never reach the Save button past it. Held in state so
  /// it can be retried, and the field below renders a plain "Uncategorised" dropdown when it fails,
  /// because a product does not need a category to be created.
  late Future<List<Category>> _categories = widget.api.categories();

  void _reloadCategories() {
    setState(() => _categories = widget.api.categories());
  }

  /// The option groups this product already has, as the customer app reads them. Null when there
  /// is nothing to read them with — a new product, or a host that passed no [StoreApi].
  late Future<List<OptionGroup>>? _options = _loadOptions();

  bool _saving = false;
  bool _uploading = false;
  bool _dirty = false;

  /// Photos picked before the product exists, held until the first save can attach them.
  ///
  /// This is what lets a shopkeeper add pictures WHILE creating a product rather than having to
  /// save a blank item and come back for the photos. The create call returns an id, and these are
  /// uploaded against it immediately afterwards — see [_save]. On an existing product this list
  /// stays empty, because there a pick uploads straight away.
  final List<PickedImageBytes> _pendingImages = <PickedImageBytes>[];

  /// True while the option structure is being written. The whole structure goes in one PUT, so a
  /// second save landing mid-flight would race the first and one of them would lose silently.
  bool _savingOptions = false;

  Future<List<OptionGroup>>? _loadOptions() {
    final Product? product = _product;
    final StoreApi? store = widget.storeApi;
    if (product == null || store == null) {
      return null;
    }
    return store.productOptions(product.id);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _saving = true);

    final Product draft = Product(
      id: _product?.id ?? '',
      merchantId: '',
      name: _name.text.trim(),
      description: _description.text.trim(),
      price: double.parse(_price.text.trim()),
      categoryId: _categoryId,
      status: ProductStatus.draft,
    );

    try {
      final Product saved = _product == null
          ? await widget.api.create(draft)
          : await widget.api.update(_product!.id, draft);
      setState(() {
        _product = saved;
        _dirty = true;
        // The first save is what gives the product an id, and therefore what makes its options
        // readable at all.
        _options ??= _loadOptions();
      });

      // Now that the product has an id, attach any photos picked while it did not. This is the
      // other half of "add photos while creating": the pick buffered the bytes, the create earned
      // the id, and this is where the two meet. Kept inside the save spinner so the button stays
      // busy until the pictures are really up.
      final String? photoProblem = await _uploadPending(saved.id);

      Product finalProduct = saved;
      if (_pendingImages.isEmpty) {
        // Everything that was pending is now uploaded (or none was) — re-read so the tiles show the
        // real, server-hosted images rather than the local previews.
        try {
          finalProduct = await widget.api.read(saved.id);
        } catch (_) {
          // A failed re-read is cosmetic; the product and its images are saved. Keep what we have.
        }
      }

      if (!mounted) return;
      setState(() {
        _product = finalProduct;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(photoProblem ?? DeliveryStrings.of(context).saved)));
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(DeliveryStrings.of(context).couldNotSaveProduct)));
    }
  }

  /// Uploads the photos picked before the product existed, against its new id.
  ///
  /// Each one that lands is removed from [_pendingImages], so a retry after a partial failure only
  /// repeats what did not upload — and the product itself is already saved, so a photo that fails
  /// never costs the shopkeeper the item. Returns a sentence to show when something did not upload,
  /// or null when everything did.
  Future<String?> _uploadPending(String productId) async {
    if (_pendingImages.isEmpty) {
      return null;
    }
    for (final PickedImageBytes image
        in List<PickedImageBytes>.of(_pendingImages)) {
      try {
        await widget.api.uploadImage(
          productId: productId,
          bytes: image.bytes,
          contentType: image.contentType,
        );
        _pendingImages.remove(image);
      } catch (e, stack) {
        debugPrint('PENDING PRODUCT IMAGE UPLOAD FAILED: $e');
        debugPrintStack(stackTrace: stack, label: 'pending-product-image');
        if (!mounted) return null;
        // The product saved; only a picture did not. Say which way it failed and stop — the
        // remaining pending ones stay in the list for a retry from the now-existing product.
        return DeliveryStrings.of(context).uploadFailedBecause(_reasonFrom(e));
      }
    }
    return null;
  }

  /// Picks one photo, then either uploads it now or holds it for the first save.
  ///
  /// The dropzone is live whether the product exists yet or not — a shopkeeper adds pictures WHILE
  /// creating an item, not after. When the product already has an id the pick uploads immediately;
  /// when it does not, the bytes are held in [_pendingImages] and attached the moment [_save]
  /// creates the product.
  Future<void> _addImage() async {
    final PickedImageBytes? picked = await _pickImage();
    if (picked == null) {
      return;
    }

    final Product? product = _product;
    if (product == null) {
      // No id to presign against yet — hold it, show it as a pending thumbnail, and let Save do
      // the upload.
      setState(() {
        _pendingImages.add(picked);
        _dirty = true;
      });
      return;
    }

    setState(() => _uploading = true);
    try {
      await widget.api.uploadImage(
        productId: product.id,
        bytes: picked.bytes,
        contentType: picked.contentType,
      );
      final Product refreshed = await widget.api.read(product.id);
      setState(() {
        _product = refreshed;
        _dirty = true;
        _uploading = false;
      });
    } catch (e, stack) {
      debugPrint('PRODUCT IMAGE UPLOAD FAILED: $e');
      debugPrintStack(stackTrace: stack, label: 'product-image-upload');
      setState(() => _uploading = false);
      if (!mounted) return;
      // With the reason. "Upload failed" on its own cannot be acted on and cannot be reported:
      // a file too large, a refused type and a network that is not there all read identically.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(DeliveryStrings.of(context).uploadFailedBecause(_reasonFrom(e)))));
    }
  }

  /// Opens the picker and reads the bytes, or null on cancel. Failures are surfaced, never silent.
  Future<PickedImageBytes?> _pickImage() async {
    // The accepted types mirror the service's allow-list; it re-checks and returns 422 regardless,
    // so this only saves the user a pointless round trip.
    final XTypeGroup images = XTypeGroup(
      label: DeliveryStrings.of(context).images,
      extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: <String>['image/jpeg', 'image/png', 'image/webp'],
    );

    // INSIDE the guard, and that is the whole point of this block.
    //
    // openFile used to be called before the try, so anything it threw — a plugin missing on the
    // platform, a picker the OS refused to open — escaped this method as an unhandled async error.
    // The screen showed nothing at all: no snackbar, no spinner, no message. Tapping "add a photo"
    // simply did nothing, which is indistinguishable from a dead button and is exactly how it was
    // reported. Whatever goes wrong here now has to say so.
    final XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: <XTypeGroup>[images]);
    } catch (e, stack) {
      // The reason reaches the device log as well as the screen: a picker failure is a platform
      // fault, and the sentence a shopkeeper can read is rarely the sentence that diagnoses it.
      debugPrint('PRODUCT IMAGE PICKER FAILED: $e');
      debugPrintStack(stackTrace: stack, label: 'product-image-picker');
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(DeliveryStrings.of(context).couldNotOpenPicker(_reasonFrom(e)))));
      return null;
    }
    if (file == null) {
      // Cancelled. Not a failure, and must not be reported as one.
      return null;
    }
    return PickedImageBytes(await file.readAsBytes(), _contentTypeFor(file));
  }

  /// The shortest true sentence about a failure, for a snackbar.
  ///
  /// Dio wraps the useful part in a long toString that begins with the whole request; an
  /// ArgumentError carries only its message. Neither renders well raw, and a shopkeeper reading
  /// "DioException [bad response]: This exception was thrown because..." learns nothing.
  static String _reasonFrom(Object e) {
    if (e is DioException) {
      final int? code = e.response?.statusCode;
      if (code != null) return 'the server refused it ($code)';
      return e.message ?? 'the server could not be reached';
    }
    if (e is ArgumentError) return e.message?.toString() ?? e.toString();
    final String text = e.toString();
    return text.length > 140 ? '${text.substring(0, 140)}…' : text;
  }

  Future<void> _removeImage(String objectKey) async {
    final Product product = _product!;
    await widget.api.removeImage(productId: product.id, objectKey: objectKey);
    final Product refreshed = await widget.api.read(product.id);
    setState(() {
      _product = refreshed;
      _dirty = true;
    });
  }

  /// `XFile.mimeType` is null on several platforms, so fall back to the extension. The service
  /// rejects anything outside its allow-list either way.
  static String _contentTypeFor(XFile file) {
    final String? declared = file.mimeType;
    if (declared != null && declared.startsWith('image/')) {
      return declared;
    }
    final String name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool isNew = _product == null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          Navigator.of(context).pop(_dirty);
        }
      },
      child: Scaffold(
        backgroundColor: DeliveryColors.background,
        body: Column(
          children: <Widget>[
            YdScreenHeader(
              title: isNew ? t.merchbAddNewProduct : t.editProduct,
              onBack: () => Navigator.of(context).pop(_dirty),
              backSemanticLabel: t.back,
            ),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.topCenter,
                child: ConstrainedBox(
                  // The frame is a phone column. On a portal pane it stays a column rather than
                  // stretching a 12px-padded input box across a monitor.
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.all(DeliverySpacing.lg - DeliverySpacing.xs),
                      children: <Widget>[
                        _imageSection(t, isNew: isNew),
                        const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                        _inputs(t),
                        const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                        _variants(t),
                        const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                        _saveButton(t, isNew: isNew),
                        SizedBox(height: MediaQuery.paddingOf(context).bottom),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ image

  Widget _imageSection(DeliveryStrings t, {required bool isNew}) {
    final List<String> urls = _product?.imageUrls ?? const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SectionLabel(t.merchbProductImage),
        const SizedBox(height: DeliverySpacing.sm),
        _Dropzone(
          cta: t.merchbUploadImageCta,
          hint: t.merchbUploadHint,
          busy: _uploading,
          // Live whether the product exists yet or not. On a new product the pick is held and
          // uploaded on save; on an existing one it uploads straight away — see [_addImage].
          onTap: _uploading ? null : _addImage,
        ),
        if (isNew) ...<Widget>[
          // Below the box rather than inside it: the frame's inner hint line is one line of file
          // formats, and a two-line explanation there overflows the 130px the design gives the area.
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            _pendingImages.isEmpty ? t.merchbAddPhotosNow : t.merchbPhotosAddedOnSave,
            style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.35),
          ),
        ],
        // Photos picked before the product was saved, shown from their own bytes so the shopkeeper
        // sees exactly what will be attached.
        if (_pendingImages.isNotEmpty) ...<Widget>[
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          Wrap(
            spacing: DeliverySpacing.sm,
            runSpacing: DeliverySpacing.sm,
            children: <Widget>[
              for (int i = 0; i < _pendingImages.length; i++)
                _PendingImageTile(
                  bytes: _pendingImages[i].bytes,
                  onRemove: _saving
                      ? null
                      : () => setState(() => _pendingImages.removeAt(i)),
                ),
            ],
          ),
        ],
        if (urls.isNotEmpty) ...<Widget>[
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          Wrap(
            spacing: DeliverySpacing.sm,
            runSpacing: DeliverySpacing.sm,
            children: <Widget>[
              for (int i = 0; i < urls.length; i++)
                _ImageTile(
                  url: urls[i],
                  onRemove: i < _product!.imageRefs.length
                      ? () => _removeImage(_product!.imageRefs[i])
                      : null,
                ),
            ],
          ),
        ] else if (!isNew && _pendingImages.isEmpty) ...<Widget>[
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            t.needsAPhotoToPublish,
            style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.35),
          ),
        ],
      ],
    );
  }

  // ----------------------------------------------------------------- inputs

  Widget _inputs(DeliveryStrings t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Labelled(
          label: t.nameLabel,
          child: TextFormField(
            controller: _name,
            maxLength: 200,
            style: _valueStyle,
            cursorColor: DeliveryColors.brand,
            decoration: _boxDecoration(),
            validator: (String? value) =>
                (value == null || value.trim().isEmpty) ? t.nameRequired : null,
          ),
        ),
        const SizedBox(height: 14),
        _Labelled(
          label: t.descriptionLabel,
          child: TextFormField(
            controller: _description,
            maxLines: 3,
            maxLength: 4000,
            style: _valueStyle,
            cursorColor: DeliveryColors.brand,
            decoration: _boxDecoration(),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _Labelled(
                label: t.priceLabel,
                child: TextFormField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: _valueStyle,
                  cursorColor: DeliveryColors.brand,
                  decoration: _boxDecoration(),
                  validator: (String? value) {
                    final double? parsed = double.tryParse((value ?? '').trim());
                    if (parsed == null) return t.enterANumber;
                    // Mirrors the server's @DecimalMin("0.01").
                    if (parsed < 0.01) return t.priceMustBePositive;
                    return null;
                  },
                ),
              ),
            ),
            const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
            Expanded(child: _categoryField(t)),
          ],
        ),
      ],
    );
  }

  Widget _categoryField(DeliveryStrings t) {
    return _Labelled(
      label: t.categoryLabel,
      child: FutureBuilder<List<Category>>(
        future: _categories,
        builder: (BuildContext context, AsyncSnapshot<List<Category>> snapshot) {
          // Still loading: a spinner, but only while genuinely waiting.
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              height: 45,
              alignment: AlignmentDirectional.centerStart,
              padding: const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
              decoration: BoxDecoration(
                color: DeliveryColors.white,
                border: Border.all(color: DeliveryColors.border),
                borderRadius: BorderRadius.circular(DeliveryRadius.md),
              ),
              child: const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
              ),
            );
          }
          // Failed: a tappable "retry" rather than a spinner that never ends. Critically, the form
          // is still usable — Save creates the product uncategorised, so a category outage does not
          // block adding a product, which is exactly what it used to do.
          if (snapshot.hasError || snapshot.data == null) {
            return InkWell(
              onTap: _reloadCategories,
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              child: Container(
                height: 45,
                alignment: AlignmentDirectional.centerStart,
                padding:
                    const EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs),
                decoration: BoxDecoration(
                  color: DeliveryColors.white,
                  border: Border.all(color: DeliveryColors.border),
                  borderRadius: BorderRadius.circular(DeliveryRadius.md),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.refresh_rounded, size: 16, color: DeliveryColors.brand),
                    const SizedBox(width: DeliverySpacing.xs),
                    Flexible(
                      child: Text(
                        t.tryAgain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: DeliveryColors.brand),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final List<({Category category, int depth})> flat = Category.flatten(snapshot.data!);
          return DropdownButtonFormField<String>(
            initialValue: _categoryId,
            isExpanded: true,
            style: _valueStyle,
            icon: const Icon(Icons.expand_more, size: 16, color: DeliveryColors.ink),
            decoration: _boxDecoration(),
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(value: null, child: Text(t.uncategorised)),
              for (final ({Category category, int depth}) entry in flat)
                DropdownMenuItem<String>(
                  value: entry.category.id,
                  child: Text(
                    '${'    ' * entry.depth}${entry.category.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (String? value) => setState(() => _categoryId = value),
          );
        },
      ),
    );
  }

  // --------------------------------------------------------------- variants

  /// The frame's "Variants & Options" card — editable.
  ///
  /// It was read-only while `CatalogApi` wrapped only the read; the service has always had
  /// `PUT /api/products/{id}/options`, and now so does the client. A group can only be added once
  /// the product exists, because the endpoint is addressed by product id — so on a new product the
  /// action says to save first rather than opening an editor whose Save could not go anywhere.
  Widget _variants(DeliveryStrings t) {
    return YdCard.bordered(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  t.merchbVariantsOptions,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              // Brand-coloured and tappable once the product has an id. Before that it stays the
              // frame's text in the muted colour with the reason beneath the card, because an
              // enabled control whose save cannot be addressed is worse than a disabled one.
              InkWell(
                onTap: _product == null || _savingOptions ? null : () => _editOptions(t),
                borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: DeliverySpacing.xs, vertical: DeliverySpacing.xs),
                  child: Text(
                    t.merchbAddOption,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _product == null
                          ? DeliveryColors.faint
                          : DeliveryColors.brand,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _optionRows(t),
          // The only note left is the one that is still true: options are addressed by product id,
          // so a product that has never been saved has nowhere to put them.
          if (_product == null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              t.merchbOptionsNeedSave,
              style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  /// Opens the option editor, then writes the WHOLE structure back.
  ///
  /// The endpoint is a replace: what is sent becomes the product's options and anything left out is
  /// deleted. So the existing groups are read first and travel into the sheet — editing one group
  /// while silently dropping the others is exactly the mistake this shape invites.
  Future<void> _editOptions(DeliveryStrings t) async {
    final Product? product = _product;
    final StoreApi? store = widget.storeApi;
    if (product == null) return;

    List<OptionGroup> existing = const <OptionGroup>[];
    try {
      existing = store == null ? const <OptionGroup>[] : await store.productOptions(product.id);
    } catch (_) {
      // Editing from an unknown starting point would replace groups that are still there with
      // nothing. Refuse rather than risk deleting a menu.
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.merchbOptionsLoadFailed)));
      return;
    }
    if (!mounted) return;

    final List<OptionGroupDraft>? edited = await showModalBottomSheet<List<OptionGroupDraft>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => ProductOptionsEditor(
        groups: existing.map(OptionGroupDraft.from).toList(),
      ),
    );
    if (edited == null || !mounted) return;

    setState(() => _savingOptions = true);
    try {
      await widget.api.setProductOptions(product.id, edited);
      if (!mounted) return;
      setState(() {
        _savingOptions = false;
        _dirty = true;
        // Re-read rather than trusting the response into the same future the card renders from:
        // one source for what is on screen, which is the server's answer.
        _options = _loadOptions();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.saved)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingOptions = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.merchbOptionsSaveFailed)));
    }
  }

  Widget _optionRows(DeliveryStrings t) {
    final Future<List<OptionGroup>>? options = _options;
    if (options == null) {
      return _emptyOptions(t);
    }

    return FutureBuilder<List<OptionGroup>>(
      future: options,
      builder: (BuildContext context, AsyncSnapshot<List<OptionGroup>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 2,
            child: LinearProgressIndicator(
              minHeight: 2,
              color: DeliveryColors.brand,
              backgroundColor: DeliveryColors.borderFaint,
            ),
          );
        }
        // A failed load is NOT "no options" — showing the empty state there would tell a shopkeeper
        // their product lost its variants when the request merely errored. It gets a tappable retry
        // instead, the same treatment the category field got, so a load failure on an existing
        // product reads as something to fix rather than a silent blank (or, worse, a spinner that
        // never ends).
        if (snapshot.hasError) {
          return InkWell(
            onTap: () => setState(() => _options = _loadOptions()),
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.refresh_rounded, size: 16, color: DeliveryColors.brand),
                  const SizedBox(width: DeliverySpacing.xs),
                  Text(t.tryAgain,
                      style: const TextStyle(fontSize: 13, color: DeliveryColors.brand)),
                ],
              ),
            ),
          );
        }
        final List<OptionGroup> groups = snapshot.data ?? const <OptionGroup>[];
        if (groups.isEmpty) {
          return _emptyOptions(t);
        }
        return Column(
          children: <Widget>[
            for (int i = 0; i < groups.length; i++) ...<Widget>[
              if (i > 0) const Divider(height: 1, color: DeliveryColors.border),
              _OptionRow(group: groups[i], choicesLabel: t.merchbChoicesCount),
            ],
          ],
        );
      },
    );
  }

  Widget _emptyOptions(DeliveryStrings t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs),
        child: Text(
          t.merchbNoOptionsYet,
          style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.3),
        ),
      );

  // ------------------------------------------------------------------- save

  Widget _saveButton(DeliveryStrings t, {required bool isNew}) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _saving ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: DeliveryColors.brand,
          foregroundColor: DeliveryColors.white,
          disabledBackgroundColor: DeliveryColors.brandLine,
          disabledForegroundColor: DeliveryColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        child: _saving
            ? const SizedBox.square(
                dimension: 19,
                child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.white),
              )
            : Text(isNew ? t.merchbSaveMenuItem : t.saveChanges),
      ),
    );
  }
}

/// The frame's input value text: Regular 14 in ink.
const TextStyle _valueStyle = TextStyle(
  fontSize: 14,
  color: DeliveryColors.ink,
  height: 1.3,
);

/// The frame's input box: white, 1px border, radius 12, 12px padding all round.
///
/// `counterText` is blanked because the frame draws no character counter; the `maxLength` limits
/// still apply, they are simply not narrated at a length no menu item comes near.
InputDecoration _boxDecoration() {
  const EdgeInsetsGeometry padding = EdgeInsetsDirectional.all(DeliverySpacing.md - DeliverySpacing.xs);
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: DeliveryColors.white,
    counterText: '',
    contentPadding: padding,
    border: border(DeliveryColors.border),
    enabledBorder: border(DeliveryColors.border),
    focusedBorder: border(DeliveryColors.brand, 1.5),
    errorBorder: border(DeliveryAccent.critical.color),
    focusedErrorBorder: border(DeliveryAccent.critical.color, 1.5),
    hintStyle: const TextStyle(fontSize: 14, color: DeliveryColors.faint),
    errorStyle: TextStyle(fontSize: 11, color: DeliveryAccent.critical.color),
  );
}

/// The SemiBold 14 ink label that heads a whole block on this frame.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: DeliveryColors.ink,
        height: 1.25,
      ),
    );
  }
}

/// A SemiBold 13 muted label six pixels above its field — the frame's `input-field` group.
class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: DeliveryColors.muted,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// The 130px dashed upload area.
class _Dropzone extends StatelessWidget {
  const _Dropzone({
    required this.cta,
    required this.hint,
    required this.busy,
    required this.onTap,
  });

  /// Already localised by the caller.
  final String cta;
  final String hint;

  final bool busy;

  /// Null draws the area at rest and refuses the tap — which is the state a product has before its
  /// first save.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;

    return Semantics(
      button: enabled,
      label: cta,
      child: Material(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DeliveryRadius.lg),
          child: CustomPaint(
            painter: const _DashedBorderPainter(
              radius: DeliveryRadius.lg,
              color: DeliveryColors.border,
            ),
            child: SizedBox(
              height: 130,
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.all(DeliverySpacing.lg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (busy)
                      const SizedBox.square(
                        dimension: 28,
                        child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
                      )
                    else
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 28,
                        color: enabled ? DeliveryColors.brand : DeliveryColors.faint,
                      ),
                    const SizedBox(height: 10),
                    Text(
                      cta,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: enabled ? DeliveryColors.brand : DeliveryColors.faint,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      hint,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: DeliveryColors.faint,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The frame's 2px dashed outline. Flutter has no dashed [BoxBorder], so the rounded rectangle is
/// walked with [PathMetrics] and drawn in segments.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.radius, required this.color});

  final double radius;
  final Color color;

  /// The frame's 2px stroke, walked in 6-on / 5-off segments.
  static const double _stroke = 2;
  static const double _dash = 6;
  static const double _gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius))
            .deflate(_stroke / 2),
      );
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;

    for (final PathMetric metric in path.computeMetrics()) {
      double start = 0;
      while (start < metric.length) {
        final double end = (start + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(start, end), paint);
        start = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

/// One option group on the variants card: its name and choices on one side, what it costs or how
/// many answers it has on the other — exactly the two lines the frame draws.
class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.group, required this.choicesLabel});

  final OptionGroup group;

  /// The localised "{count} choices" builder, passed in so this widget holds no strings.
  final String Function(int) choicesLabel;

  @override
  Widget build(BuildContext context) {
    final String names =
        group.options.map((ProductOptionChoice o) => o.name).join(', ');
    final String title = names.isEmpty ? group.name : '${group.name} ($names)';

    // A group with one priced answer is an add-on, and the frame labels those with the price
    // rather than the count — "+1.50" says more than "1 choice".
    final String meta = group.options.length == 1 && group.options.first.priceDelta != 0
        ? group.options.first.deltaLabel
        : choicesLabel(group.options.length);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.3),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Text(
            meta,
            maxLines: 1,
            style: const TextStyle(fontSize: 12, color: DeliveryColors.faint, height: 1.3),
          ),
        ],
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.url, this.onRemove});

  final String url;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            border: Border.all(color: DeliveryColors.border),
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image_outlined, color: DeliveryColors.muted),
          ),
        ),
        if (onRemove != null)
          PositionedDirectional(
            top: 2,
            end: 2,
            child: Material(
              color: DeliveryColors.white,
              shape: const CircleBorder(),
              child: IconButton(
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: const Icon(Icons.close, color: DeliveryColors.brand),
                tooltip: DeliveryStrings.of(context).remove,
              ),
            ),
          ),
      ],
    );
  }
}

/// A photo the shopkeeper picked, in memory, waiting to be uploaded.
///
/// Held while a new product has no id to attach it to. Carries the bytes and a content type the
/// server's allow-list accepts; the upload path shrinks it to fit before it goes.
class PickedImageBytes {
  const PickedImageBytes(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;
}

/// One picked-but-not-yet-uploaded photo, drawn from its own bytes.
///
/// Distinct from [_ImageTile], which loads an already-hosted image over the network. This one has
/// no URL — the point of the feature is that it is shown before it has been sent anywhere.
class _PendingImageTile extends StatelessWidget {
  const _PendingImageTile({required this.bytes, this.onRemove});

  final Uint8List bytes;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            border: Border.all(color: DeliveryColors.border),
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image_outlined, color: DeliveryColors.muted),
          ),
        ),
        // A small badge so it reads as "queued", not "saved".
        PositionedDirectional(
          bottom: 0,
          start: 0,
          end: 0,
          child: Container(
            color: DeliveryColors.ink.withValues(alpha: 0.55),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              DeliveryStrings.of(context).merchbPending,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: DeliveryColors.white, height: 1.2),
            ),
          ),
        ),
        if (onRemove != null)
          PositionedDirectional(
            top: 2,
            end: 2,
            child: Material(
              color: DeliveryColors.white,
              shape: const CircleBorder(),
              child: IconButton(
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: const Icon(Icons.close, color: DeliveryColors.brand),
                tooltip: DeliveryStrings.of(context).remove,
              ),
            ),
          ),
      ],
    );
  }
}
