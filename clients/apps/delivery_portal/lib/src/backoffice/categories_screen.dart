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

  Future<void> _add(List<Category> existing) async {
    final _NewCategory? result = await showDialog<_NewCategory>(
      context: context,
      builder: (BuildContext context) => _AddCategoryDialog(existing: existing),
    );
    if (result == null) return;

    try {
      await widget.api.createCategory(name: result.name, parentId: result.parentId);
      _reload();
    } on DioException catch (e) {
      if (!mounted) return;
      // 409 is the interesting one: the service has a uniqueness constraint on (name, parent).
      final String message = e.response?.statusCode == 409
          ? 'A category with that name already exists here'
          : 'Could not create the category';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
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

class _NewCategory {
  const _NewCategory(this.name, this.parentId);

  final String name;
  final String? parentId;
}

class _AddCategoryDialog extends StatefulWidget {
  const _AddCategoryDialog({required this.existing});

  final List<Category> existing;

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  final TextEditingController _name = TextEditingController();
  String? _parentId;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
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
            decoration: const InputDecoration(labelText: 'Name'),
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
            onChanged: (String? value) => setState(() => _parentId = value),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final String name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop(_NewCategory(name, _parentId));
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
