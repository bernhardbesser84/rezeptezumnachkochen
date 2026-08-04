import 'package:flutter/material.dart';

import '../models/meal_plan_entry.dart';
import '../models/recipe.dart';
import '../services/app_repository.dart';
import '../services/recipe_category_service.dart';
import '../theme/app_theme.dart';

/// Wochen-Essensplan: pro Tag ein Rezept auswählen.
class MealPlanScreen extends StatefulWidget {
  const MealPlanScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  static const _weekdayNames = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];

  late DateTime _weekStart;
  List<MealPlanEntry> _entries = [];
  List<Recipe> _recipes = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayOf(DateTime.now());
    _reload();
  }

  DateTime _mondayOf(DateTime day) {
    final only = MealPlanEntry.dateOnly(day);
    return only.subtract(Duration(days: only.weekday - DateTime.monday));
  }

  List<DateTime> get _weekDays =>
      List.generate(7, (i) => _weekStart.add(Duration(days: i)));

  MealPlanEntry? _entryFor(DateTime day) {
    final key = MealPlanEntry.keyFor(day);
    for (final entry in _entries) {
      if (entry.dateKey == key) return entry;
    }
    return null;
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final entries = await widget.repository.loadMealPlan(pullRemote: true);
    final recipes = await widget.repository.loadRecipes(pullRemote: false);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _recipes = recipes;
      _loading = false;
    });
  }

  Future<void> _pickRecipe(DateTime day) async {
    if (_recipes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Noch keine Rezepte gespeichert. Lege zuerst ein Rezept an.',
          ),
        ),
      );
      return;
    }

    final categories =
        await widget.repository.loadCategories(pullRemote: false);
    if (!mounted) return;

    final selected = await showModalBottomSheet<Recipe>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return _MealPlanRecipePicker(
          weekdayLabel: _weekdayNames[day.weekday - 1],
          recipes: _recipes,
          categories: categories,
        );
      },
    );

    if (selected == null) return;
    setState(() => _busy = true);
    await widget.repository.setMealPlanDay(date: day, recipe: selected);
    await _reload();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _clearDay(DateTime day) async {
    setState(() => _busy = true);
    await widget.repository.clearMealPlanDay(day);
    await _reload();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _addWeekToShopping() async {
    final weekEntries = [
      for (final day in _weekDays)
        if (_entryFor(day) != null) _entryFor(day)!,
    ];
    if (weekEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Diese Woche hat noch keine geplanten Rezepte.'),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final count =
        await widget.repository.addWeekRecipesToShopping(weekEntries);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count == 0
              ? 'Alle Zutaten dieser Woche waren schon auf der Liste.'
              : '$count Zutaten zur Einkaufsliste hinzugefügt '
                  '(gruppiert nach Rezept).',
        ),
      ),
    );
  }

  String _weekLabel() {
    final end = _weekStart.add(const Duration(days: 6));
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')}.';
    return '${fmt(_weekStart)} – ${fmt(end)}${end.year}';
  }

  @override
  Widget build(BuildContext context) {
    final plannedCount =
        _weekDays.where((d) => _entryFor(d) != null).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wochenplan'),
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.seed,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Essensplan für die Woche',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        plannedCount == 0
                            ? 'Tippe auf einen Tag, wähle eine Kategorie, dann ein Rezept.'
                            : '$plannedCount von 7 Tagen geplant',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Vorherige Woche',
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() {
                                _weekStart =
                                    _weekStart.subtract(const Duration(days: 7));
                              });
                            },
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        _weekLabel(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Nächste Woche',
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() {
                                _weekStart =
                                    _weekStart.add(const Duration(days: 7));
                              });
                            },
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() {
                            _weekStart = _mondayOf(DateTime.now());
                          });
                        },
                  child: const Text('Diese Woche'),
                ),
                const SizedBox(height: 8),
                for (final day in _weekDays) ...[
                  _DayTile(
                    weekdayLabel: _weekdayNames[day.weekday - 1],
                    dateLabel:
                        '${day.day.toString().padLeft(2, '0')}.'
                        '${day.month.toString().padLeft(2, '0')}.',
                    isToday: MealPlanEntry.keyFor(day) ==
                        MealPlanEntry.keyFor(DateTime.now()),
                    entry: _entryFor(day),
                    onPick: _busy ? null : () => _pickRecipe(day),
                    onClear: _busy || _entryFor(day) == null
                        ? null
                        : () => _clearDay(day),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _addWeekToShopping,
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: const Text('Wochen-Zutaten auf Einkaufsliste'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Die Einkaufsliste zeigt die Zutaten gruppiert nach Rezept.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.weekdayLabel,
    required this.dateLabel,
    required this.isToday,
    required this.entry,
    required this.onPick,
    required this.onClear,
  });

  final String weekdayLabel;
  final String dateLabel;
  final bool isToday;
  final MealPlanEntry? entry;
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isToday
                  ? AppTheme.seed.withValues(alpha: 0.45)
                  : AppTheme.seed.withValues(alpha: 0.12),
              width: isToday ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        weekdayLabel,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        dateLabel,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Text(
                    entry?.recipeTitle ?? 'Rezept wählen…',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: entry == null
                              ? AppTheme.inkMuted
                              : AppTheme.ink,
                          fontWeight:
                              entry == null ? FontWeight.w500 : FontWeight.w700,
                        ),
                  ),
                ),
                if (onClear != null)
                  IconButton(
                    tooltip: 'Tag leeren',
                    onPressed: onClear,
                    icon: const Icon(Icons.close),
                  )
                else
                  Icon(
                    Icons.add_rounded,
                    color: AppTheme.seed.withValues(alpha: 0.6),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Zuerst Kategorie wählen, danach das Rezept.
class _MealPlanRecipePicker extends StatefulWidget {
  const _MealPlanRecipePicker({
    required this.weekdayLabel,
    required this.recipes,
    required this.categories,
  });

  final String weekdayLabel;
  final List<Recipe> recipes;
  final List<String> categories;

  static const uncategorizedLabel = 'Ohne Kategorie';

  @override
  State<_MealPlanRecipePicker> createState() => _MealPlanRecipePickerState();
}

class _MealPlanRecipePickerState extends State<_MealPlanRecipePicker> {
  String? _selectedCategory;
  bool _allowCategoryBrowse = true;

  @override
  void initState() {
    super.initState();
    // Ohne angelegte Kategorien direkt die Rezeptliste zeigen.
    final hasCategories = widget.categories.isNotEmpty ||
        RecipeCategoryService.collectFromRecipes(widget.recipes).isNotEmpty;
    _allowCategoryBrowse = hasCategories;
    if (!hasCategories) {
      _selectedCategory = RecipeCategoryService.allRecipesLabel;
    }
  }

  List<String> get _categoryOptions {
    final fromRecipes =
        RecipeCategoryService.collectFromRecipes(widget.recipes);
    final merged = RecipeCategoryService.normalizeAll([
      ...widget.categories,
      ...fromRecipes,
    ]);
    merged.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final uncategorizedCount =
        widget.recipes.where((r) => r.categories.isEmpty).length;

    return [
      ...merged,
      if (uncategorizedCount > 0) _MealPlanRecipePicker.uncategorizedLabel,
      RecipeCategoryService.allRecipesLabel,
    ];
  }

  List<Recipe> get _visibleRecipes {
    final category = _selectedCategory;
    if (category == null ||
        category == RecipeCategoryService.allRecipesLabel) {
      return widget.recipes;
    }
    if (category == _MealPlanRecipePicker.uncategorizedLabel) {
      return widget.recipes.where((r) => r.categories.isEmpty).toList();
    }
    return widget.recipes
        .where(
          (r) => RecipeCategoryService.recipeHasCategory(r, category),
        )
        .toList();
  }

  int _countForCategory(String category) {
    if (category == RecipeCategoryService.allRecipesLabel) {
      return widget.recipes.length;
    }
    if (category == _MealPlanRecipePicker.uncategorizedLabel) {
      return widget.recipes.where((r) => r.categories.isEmpty).length;
    }
    return RecipeCategoryService.countRecipesWithCategory(
      widget.recipes,
      category,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showingRecipes = _selectedCategory != null;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 20, 8),
              child: Row(
                children: [
                  if (showingRecipes && _allowCategoryBrowse)
                    IconButton(
                      tooltip: 'Zurück zu Kategorien',
                      onPressed: () => setState(() => _selectedCategory = null),
                      icon: const Icon(Icons.arrow_back),
                    )
                  else
                    const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          showingRecipes
                              ? (_selectedCategory ==
                                      RecipeCategoryService.allRecipesLabel
                                  ? 'Rezept für ${widget.weekdayLabel}'
                                  : _selectedCategory!)
                              : 'Rezept für ${widget.weekdayLabel}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          showingRecipes
                              ? 'Rezept auswählen'
                              : 'Zuerst eine Kategorie wählen',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.inkMuted,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: showingRecipes
                  ? _buildRecipeList(context)
                  : _buildCategoryList(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryList(BuildContext context) {
    final options = _categoryOptions;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: options.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final category = options[index];
        final count = _countForCategory(category);
        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          leading: Icon(
            category == RecipeCategoryService.allRecipesLabel
                ? Icons.menu_book_outlined
                : category == _MealPlanRecipePicker.uncategorizedLabel
                    ? Icons.label_off_outlined
                    : Icons.folder_outlined,
            color: AppTheme.seed,
          ),
          title: Text(category),
          subtitle: Text(count == 1 ? '1 Rezept' : '$count Rezepte'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() => _selectedCategory = category),
        );
      },
    );
  }

  Widget _buildRecipeList(BuildContext context) {
    final recipes = _visibleRecipes;
    if (recipes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('In dieser Kategorie gibt es noch keine Rezepte.'),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: recipes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final recipe = recipes[index];
        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(recipe.title),
          subtitle: Text(
            recipe.categories.isEmpty
                ? '${recipe.ingredients.length} Zutaten'
                : '${recipe.categories.join(' · ')} · '
                    '${recipe.ingredients.length} Zutaten',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pop(recipe),
        );
      },
    );
  }
}
