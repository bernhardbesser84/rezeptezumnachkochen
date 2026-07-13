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
      if (mounted) {
        setState(() {
          _items = items;
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

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final openCount = _items.where((e) => !e.checked).length;
    final checkedCount = _items.where((e) => e.checked).length;

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
                    ..._items.map(
                      (item) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: CheckboxListTile(
                          value: item.checked,
                          onChanged: (value) => _toggle(item, value),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            item.name,
                            style: TextStyle(
                              decoration: item.checked
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: item.checked
                                  ? Colors.black54
                                  : AppTheme.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: item.recipeTitle == null
                              ? null
                              : Text('aus: ${item.recipeTitle}'),
                          secondary: IconButton(
                            tooltip: 'Löschen',
                            onPressed: () async {
                              await widget.repository
                                  .deleteShoppingItem(item.id);
                              await _reload(silent: true);
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
