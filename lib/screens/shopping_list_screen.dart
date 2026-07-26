import 'dart:async';

import 'package:flutter/material.dart';

import '../models/shopping_item.dart';
import '../services/app_repository.dart';
import '../theme/app_theme.dart';

class ShoppingListScreen extends StatefulWidget {
  const ShoppingListScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  List<ShoppingItem> _items = [];
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  /// Einstellung: Rezepte einklappbar (aus Einstellungen).
  bool _collapseEnabled = false;

  /// Welche Rezept-Gruppen gerade geöffnet sind (nur wenn Einklappen an).
  final Set<String> _expandedKeys = {};

  @override
  void initState() {
    super.initState();
    _reload();
    // Alle paar Sekunden Cloud abfragen – damit das Abhaken live ankommt
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _reload(silent: true);
    });
  }

  Future<void> _reload({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await widget.repository.loadShopping(pullRemote: true);
      final collapse =
          await widget.repository.storage.isShoppingCollapseEnabled();
      if (mounted) {
        setState(() {
          _items = items;
          _collapseEnabled = collapse;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggle(ShoppingItem item, bool? value) async {
    if (value == null) return;
    setState(() {
      _items = [
        for (final entry in _items)
          if (entry.id == item.id)
            entry.copyWith(checked: value, updatedAt: DateTime.now())
          else
            entry,
      ];
    });
    try {
      await widget.repository.setShoppingChecked(item, value);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
      await _reload(silent: true);
    }
  }

  Future<void> _clearChecked() async {
    await widget.repository.clearCheckedShopping();
    await _reload();
  }

  void _toggleGroup(String key) {
    setState(() {
      if (_expandedKeys.contains(key)) {
        _expandedKeys.remove(key);
      } else {
        _expandedKeys.add(key);
      }
    });
  }

  /// Zutaten nach Rezept gruppieren – Reihenfolge wie hinzugefügt.
  List<_ShoppingGroup> _groupsFor(List<ShoppingItem> items) {
    final buckets = <String, List<ShoppingItem>>{};
    final titles = <String, String>{};
    final order = <String>[];

    for (final item in items) {
      final title = item.recipeTitle?.trim() ?? '';
      final key = (item.recipeId != null && item.recipeId!.isNotEmpty)
          ? 'id:${item.recipeId}'
          : title.isNotEmpty
              ? 'title:$title'
              : '_none';
      if (!buckets.containsKey(key)) {
        buckets[key] = [];
        order.add(key);
      }
      buckets[key]!.add(item);
      titles[key] = title.isNotEmpty ? title : 'Ohne Rezept';
    }

    // „Ohne Rezept“ ans Ende, sonst Reihenfolge beibehalten.
    order.sort((a, b) {
      if (a == '_none') return 1;
      if (b == '_none') return -1;
      return 0;
    });

    return [
      for (var i = 0; i < order.length; i++)
        _ShoppingGroup(
          key: order[i],
          number: i + 1,
          title: titles[order[i]]!,
          items: (buckets[order[i]]!
                ..sort((a, b) {
                  if (a.checked != b.checked) return a.checked ? 1 : -1;
                  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                }))
              .toList(),
        ),
    ];
  }

  Widget _ingredientTile(ShoppingItem item) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: CheckboxListTile(
        value: item.checked,
        onChanged: (value) => _toggle(item, value),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.only(right: 0),
        dense: true,
        title: Text(
          item.name,
          style: TextStyle(
            decoration: item.checked ? TextDecoration.lineThrough : null,
            color: item.checked ? Colors.black54 : AppTheme.ink,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        secondary: IconButton(
          tooltip: 'Löschen',
          onPressed: () async {
            await widget.repository.deleteShoppingItem(item.id);
            await _reload(silent: true);
          },
          icon: const Icon(Icons.close, size: 20),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final openCount = _items.where((e) => !e.checked).length;
    final checkedCount = _items.where((e) => e.checked).length;
    final groups = _groupsFor(_items);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einkaufsliste'),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            onPressed: _reload,
            icon: const Icon(Icons.sync),
          ),
          if (checkedCount > 0)
            IconButton(
              tooltip: 'Erledigte entfernen',
              onPressed: _clearChecked,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.seed,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      openCount == 0
                          ? 'Alles im Korb – nichts fehlt mehr.'
                          : '$openCount noch offen · $checkedCount schon im Korb',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (_collapseEnabled) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Tipp: Tippe auf einen Rezeptnamen, um die Zutaten '
                      'ein- oder auszuklappen.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Text(
                        'Noch nichts auf der Liste.\n'
                        'Öffne ein Rezept und tippe auf '
                        '„Zur Einkaufsliste“.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    for (final group in groups) ...[
                      Builder(
                        builder: (context) {
                          final openInGroup =
                              group.items.where((e) => !e.checked).length;
                          final expanded = !_collapseEnabled ||
                              _expandedKeys.contains(group.key);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(
                                  top: group.number == 1 ? 4 : 16,
                                  bottom: 4,
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _collapseEnabled
                                        ? () => _toggleGroup(group.key)
                                        : null,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                        horizontal: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${group.number}. ${group.title}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                    color: AppTheme.ink,
                                                    fontWeight: FontWeight.w800,
                                                    height: 1.25,
                                                  ),
                                            ),
                                          ),
                                          if (_collapseEnabled) ...[
                                            Text(
                                              '$openInGroup offen',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    color: AppTheme.inkMuted,
                                                  ),
                                            ),
                                            const SizedBox(width: 4),
                                            Icon(
                                              expanded
                                                  ? Icons.expand_less
                                                  : Icons.expand_more,
                                              color: AppTheme.seed,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (expanded)
                                for (final item in group.items)
                                  _ingredientTile(item),
                            ],
                          );
                        },
                      ),
                    ],
                ],
              ),
            ),
    );
  }
}

class _ShoppingGroup {
  const _ShoppingGroup({
    required this.key,
    required this.number,
    required this.title,
    required this.items,
  });

  final String key;
  final int number;
  final String title;
  final List<ShoppingItem> items;
}
