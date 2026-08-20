import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// Create or edit one product, and manage its images.
///
/// Images can only be attached to a product that already exists, because the presign endpoint is
/// scoped to a product id. On a new product the image section stays disabled until the first save —
/// which is also what makes the ownership check on presign meaningful.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, required this.api, this.existing});

  final CatalogApi api;
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

  /// Fetched once; the category tree does not change while a form is open.
  late final Future<List<Category>> _categories = widget.api.categories();

  bool _saving = false;
  bool _uploading = false;
  bool _dirty = false;

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
        _saving = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(DeliveryStrings.of(context).saved)));
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(DeliveryStrings.of(context).couldNotSaveProduct)));
    }
  }

  Future<void> _addImage() async {
    final Product? product = _product;
    if (product == null) {
      return;
    }

    // The accepted types mirror the service's allow-list; it re-checks and returns 422 regardless,
    // so this only saves the user a pointless round trip.
    final XTypeGroup images = XTypeGroup(
      label: DeliveryStrings.of(context).images,
      extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: <String>['image/jpeg', 'image/png', 'image/webp'],
    );

    final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[images]);
    if (file == null) {
      return;
    }

    setState(() => _uploading = true);
    try {
      await widget.api.uploadImage(
        productId: product.id,
        bytes: await file.readAsBytes(),
        contentType: _contentTypeFor(file),
      );
      final Product refreshed = await widget.api.read(product.id);
      setState(() {
        _product = refreshed;
        _dirty = true;
        _uploading = false;
      });
    } catch (e) {
      setState(() => _uploading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(DeliveryStrings.of(context).uploadFailed)));
    }
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
    final bool isNew = _product == null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          Navigator.of(context).pop(_dirty);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(isNew ? DeliveryStrings.of(context).newProduct : DeliveryStrings.of(context).editProduct)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints.tightFor(width: double.infinity),
            child: ListView(
              padding: const EdgeInsets.all(DeliverySpacing.lg),
              children: <Widget>[
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextFormField(
                        controller: _name,
                        decoration: InputDecoration(labelText: DeliveryStrings.of(context).nameLabel),
                        maxLength: 200,
                        validator: (String? value) =>
                            (value == null || value.trim().isEmpty) ? DeliveryStrings.of(context).nameRequired : null,
                      ),
                      const SizedBox(height: DeliverySpacing.md),
                      TextFormField(
                        controller: _description,
                        decoration: InputDecoration(labelText: DeliveryStrings.of(context).descriptionLabel),
                        maxLines: 3,
                        maxLength: 4000,
                      ),
                      const SizedBox(height: DeliverySpacing.md),
                      TextFormField(
                        controller: _price,
                        decoration: InputDecoration(labelText: DeliveryStrings.of(context).priceLabel),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (String? value) {
                          final double? parsed = double.tryParse((value ?? '').trim());
                          if (parsed == null) return DeliveryStrings.of(context).enterANumber;
                          // Mirrors the server's @DecimalMin("0.01").
                          if (parsed < 0.01) return DeliveryStrings.of(context).priceMustBePositive;
                          return null;
                        },
                      ),
                      const SizedBox(height: DeliverySpacing.md),
                      FutureBuilder<List<Category>>(
                        future: _categories,
                        builder: (BuildContext context,
                            AsyncSnapshot<List<Category>> snapshot) {
                          if (!snapshot.hasData) {
                            return const LinearProgressIndicator();
                          }
                          final List<({Category category, int depth})> flat =
                              Category.flatten(snapshot.data!);
                          return DropdownButtonFormField<String>(
                            initialValue: _categoryId,
                            decoration: InputDecoration(labelText: DeliveryStrings.of(context).categoryLabel),
                            items: <DropdownMenuItem<String>>[
                              DropdownMenuItem<String>(
                                  value: null, child: Text(DeliveryStrings.of(context).uncategorised)),
                              for (final ({Category category, int depth}) entry in flat)
                                DropdownMenuItem<String>(
                                  value: entry.category.id,
                                  child: Text(
                                      '${'    ' * entry.depth}${entry.category.name}'),
                                ),
                            ],
                            onChanged: (String? value) =>
                                setState(() => _categoryId = value),
                          );
                        },
                      ),
                      const SizedBox(height: DeliverySpacing.lg),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          child: Text(_saving ? DeliveryStrings.of(context).saving : DeliveryStrings.of(context).save),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: DeliverySpacing.xl),
                const Divider(),
                const SizedBox(height: DeliverySpacing.md),
                Text(DeliveryStrings.of(context).images, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: DeliverySpacing.xs),
                Text(
                  isNew
                      ? DeliveryStrings.of(context).saveProductFirst
                      : DeliveryStrings.of(context).needsAPhotoToPublish,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: DeliverySpacing.md),
                if (!isNew) _imageStrip(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _imageStrip() {
    final Product product = _product!;
    return Wrap(
      spacing: DeliverySpacing.sm,
      runSpacing: DeliverySpacing.sm,
      children: <Widget>[
        for (int i = 0; i < product.imageUrls.length; i++)
          _ImageTile(
            url: product.imageUrls[i],
            onRemove: i < product.imageRefs.length
                ? () => _removeImage(product.imageRefs[i])
                : null,
          ),
        InkWell(
          onTap: _uploading ? null : _addImage,
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          child: Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              color: DeliveryColors.brandSoft,
              border: Border.all(color: DeliveryColors.brandLine, width: 1.5),
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
            ),
            child: _uploading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(Icons.add_a_photo_outlined, color: DeliveryColors.brand),
                      SizedBox(height: DeliverySpacing.xs),
                      Text(DeliveryStrings.of(context).addPhoto,
                          style: TextStyle(color: DeliveryColors.brand, fontSize: 12)),
                    ],
                  ),
          ),
        ),
      ],
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
          Positioned(
            top: 2,
            right: 2,
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
