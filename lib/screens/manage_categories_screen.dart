import 'package:flutter/material.dart';

import '../services/app_repository.dart';
import '../services/recipe_category_service.dart';
import '../theme/app_theme.dart';

/// Zentrale Verwaltung: Kategorien anlegen, umbenennen und löschen.
class ManageCategoriesScreen extends StatefulWidget {
  const ManageCategoriesScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<ManageCategoriesScreen> createState() => _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState extends State<ManageCategoriesScreen> {
  final _newCategoryController = TextEditingController();
  List<String> _categories = [];
  Map<String, int> _counts = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _newCategoryController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final recipes =
          await widget.repository.loadRecipes(pullRemote: false);
      final categories =
          await widget.repository.loadCategories(pullRemote: false);
      final counts = <String, int>{
        for (final category in categories)
          category: RecipeCategoryService.countRecipesWithCategory(
            recipes,
            category,
          ),
      };
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _counts = counts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _createCategory() async {
    final name = _newCategoryController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte einen Namen eingeben.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await widget.repository.createCategory(name);
      _newCategoryController.clear();
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kategorie „$name“ angelegt.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renameCategory(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Kategorie umbenennen'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Neuer Name',
            ),
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Speichern'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || newName == oldName) return;

    setState(() => _busy = true);
    try {
      final changed = await widget.repository.renameCategory(
        oldName: oldName,
        newName: newName,
      );
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            changed == 0
                ? 'Kategorie umbenannt.'
                : 'Kategorie umbenannt ($changed Rezepte aktualisiert).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCategory(String name) async {
    final count = _counts[name] ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Kategorie löschen?'),
          content: Text(
            count == 0
                ? '„$name“ wird gelöscht. Rezepte bleiben erhalten.'
                : '„$name“ wird von $count Rezept'
                    '${count == 1 ? '' : 'en'} entfernt. '
                    'Die Rezepte selbst bleiben erhalten.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Löschen'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final changed = await widget.repository.deleteCategory(name);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            changed == 0
                ? 'Kategorie gelöscht.'
                : 'Kategorie gelöscht ($changed Rezepte aktualisiert).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kategorien verwalten'),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.seed,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    'Hier legst du Kategorien an, benennst sie um oder löschst sie. '
                    '„Alle Rezepte“ bleibt immer fest vorhanden.',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Neue Kategorie',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newCategoryController,
                        enabled: !_busy,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: 'z. B. One Pot',
                        ),
                        onSubmitted: (_) => _createCategory(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : _createCategory,
                      child: const Text('Anlegen'),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 22),
                Text(
                  'Deine Kategorien (${_categories.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                if (_categories.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Text(
                      'Noch keine Kategorien.\n'
                      'Lege oben die erste an oder speichere ein Rezept '
                      'mit Kategorie-Vorschlag.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (final category in _categories)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          category,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${_counts[category] ?? 0} Rezept'
                          '${(_counts[category] ?? 0) == 1 ? '' : 'e'}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Umbenennen',
                              onPressed:
                                  _busy ? null : () => _renameCategory(category),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Löschen',
                              onPressed:
                                  _busy ? null : () => _deleteCategory(category),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}
