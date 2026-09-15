import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// The platform-wide category taxonomy.
///
/// Only BACKOFFICE may add to it — merchants pick from it but cannot invent categories, otherwise
/// the catalog fragments into near-duplicates within a month. Product Service enforces that with
/// `@PreAuthorize("hasRole('BACKOFFICE')")`; this screen is just the UI for it.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key, required this.api});

  final CatalogApi api;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late Future<List<Category>> _categories = widget.api.categories();

  // Block body, not an arrow - see the note in settings_screen.dart: the arrow form returns the
  // future from the closure and trips setState's assertion in debug builds.
  void _reload() {
    setState(() {
      _categories = widget.api.categories();
    });
  }

  /// Posts one category, and answers the dialog with the reason when the service refuses.
  ///
  /// Returning the message rather than showing it keeps the dialog open, because both ways this
  /// fails are ones the operator fixes by editing what they already typed: the name collides
  /// with a sibling, or the write did not land. Popping first and reporting afterwards - which
  /// is what this screen used to do - threw the typing away and made them start over.
  Future<String?> _create(String name, String? parentId) async {
    try {
      await widget.api.createCategory(name: name, parentId: parentId);
      _reload();
      return null;
    } on DioException catch (e) {
      // 409 is the interesting one: the service has a uniqueness constraint on (name, parent).
      return e.response?.statusCode == 409
          ? 'A category with that name already exists here'
          : 'Could not create the category';
    }
  }

  Future<void> _add(List<Category> existing) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => _AddCategoryDialog(existing: existing, submit: _create),
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

        final List<Category> roots = snapshot.data!;
        final List<({Category category, int depth})> flat = Category.flatten(roots);

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _add(roots),
            backgroundColor: DeliveryColors.brand,
            foregroundColor: DeliveryColors.white,
            icon: const Icon(Icons.add),
            label: const Text('New category'),
          ),
          // Fills the width the rail shell gives it — see the note in dashboard_screen.dart.
          body: ListView(
                padding: const EdgeInsets.all(DeliverySpacing.lg),
                children: <Widget>[
                  Text('Categories', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: DeliverySpacing.xs),
                  Text(
                    '${flat.length} categories. Merchants choose from this list.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: DeliverySpacing.lg),
                  const SectionLabel('The taxonomy'),
                  SoftCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: <Widget>[
                        for (int i = 0; i < flat.length; i++) ...<Widget>[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            contentPadding: EdgeInsets.only(
                              left: DeliverySpacing.md + flat[i].depth * DeliverySpacing.lg,
                              right: DeliverySpacing.md,
                            ),
                            leading: Icon(
                              flat[i].depth == 0
                                  ? Icons.folder_outlined
                                  : Icons.subdirectory_arrow_right,
                              color: flat[i].depth == 0
                                  ? DeliveryColors.brand
                                  : DeliveryColors.muted,
                            ),
                            title: Text(flat[i].category.name),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
        );
      },
    );
  }
}

class _AddCategoryDialog extends StatefulWidget {
  const _AddCategoryDialog({required this.existing, required this.submit});

  final List<Category> existing;

  /// Writes the category. Returns null when it landed, or the message to show under the name.
  final Future<String?> Function(String name, String? parentId) submit;

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  final TextEditingController _name = TextEditingController();
  String? _parentId;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      // Without this the button is simply dead, which reads as a broken screen rather than as
      // an empty field.
      setState(() => _error = 'Give the category a name');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final String? failure = await widget.submit(name, _parentId);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _error = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<({Category category, int depth})> flat = Category.flatten(widget.existing);

    return AlertDialog(
      title: const Text('New category'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _name,
            autofocus: true,
            enabled: !_saving,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) {
              if (!_saving) _submit();
            },
            decoration: InputDecoration(labelText: 'Name', errorText: _error),
          ),
          const SizedBox(height: DeliverySpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _parentId,
            decoration: const InputDecoration(labelText: 'Parent'),
            items: <DropdownMenuItem<String>>[
              const DropdownMenuItem<String>(value: null, child: Text('Top level')),
              for (final ({Category category, int depth}) entry in flat)
                DropdownMenuItem<String>(
                  value: entry.category.id,
                  child: Text('${'    ' * entry.depth}${entry.category.name}'),
                ),
            ],
            onChanged: _saving ? null : (String? value) => setState(() => _parentId = value),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
