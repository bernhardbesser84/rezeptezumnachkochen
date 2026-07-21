import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/recipe.dart';
import '../services/app_repository.dart';
import '../services/recipe_extractor.dart';
import '../theme/app_theme.dart';
import 'cook_mode_screen.dart';
import 'edit_recipe_screen.dart';

class RecipeDetailScreen extends StatefulWidget {
  const RecipeDetailScreen({
    super.key,
    required this.recipe,
    required this.repository,
    required this.extractor,
    required this.onDelete,
  });

  final Recipe recipe;
  final AppRepository repository;
  final RecipeExtractor extractor;
  final Future<void> Function() onDelete;

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  late Recipe _recipe;

  @override
  void initState() {
    super.initState();
    _recipe = widget.recipe;
  }

  Future<void> _openSource() async {
    if (_recipe.sourceUrl.isEmpty) return;
    final uri = Uri.tryParse(_recipe.sourceUrl);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link konnte nicht geöffnet werden.')),
      );
    }
  }

  Future<void> _addToShopping() async {
    final count = await widget.repository.addRecipeToShopping(_recipe);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count == 0
              ? 'Zutaten waren schon auf der Einkaufsliste.'
              : '$count Zutaten zur Einkaufsliste hinzugefügt.',
        ),
      ),
    );
  }

  Future<void> _editRecipe({bool autoStartAiRetry = false}) async {
    final updated = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute(
        builder: (_) => EditRecipeScreen(
          recipe: _recipe,
          repository: widget.repository,
          extractor: widget.extractor,
          autoStartAiRetry: autoStartAiRetry,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _recipe = updated);
    }
  }

  Future<void> _confirmDelete() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rezept löschen?'),
        content: Text('„${_recipe.title}“ wirklich entfernen?'),
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
      ),
    );
    if (shouldDelete == true) {
      await widget.onDelete();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipe = _recipe;
    final needsAi = recipe.needsAiEnrichment;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Rezept'),
        actions: [
          IconButton(
            tooltip: 'Bearbeiten',
            onPressed: _editRecipe,
            icon: const Icon(Icons.edit_outlined),
          ),
          if (recipe.sourceUrl.isNotEmpty)
            IconButton(
              tooltip: 'Video anschauen',
              onPressed: _openSource,
              icon: const Icon(Icons.play_circle_outline),
            ),
          IconButton(
            tooltip: 'Löschen',
            onPressed: _confirmDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: AppTheme.pageBackdrop(),
        child: CustomPaint(
          painter: KitchenDotsPainter(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(
                recipe.title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (recipe.servings != null && recipe.servings!.isNotEmpty)
                    _MetaChip(
                      icon: Icons.restaurant,
                      label: recipe.servings!,
                    ),
                  if (recipe.prepTimeMinutes != null)
                    _MetaChip(
                      icon: Icons.timer_outlined,
                      label: '${recipe.prepTimeMinutes} Min.',
                    ),
                  _MetaChip(
                    icon: Icons.checklist_rtl,
                    label: '${recipe.ingredients.length} Zutaten',
                  ),
                ],
              ),
              if (needsAi) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.accentSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.28),
                    ),
                  ),
                  child: const Text(
                    'Zubereitung noch unvollständig (oft weil die KI '
                    'gerade kein Kontingent hatte). Du kannst die '
                    'Auswertung jetzt nachholen.',
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => _editRecipe(autoStartAiRetry: true),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('KI-Auswertung nachholen'),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: _editRecipe,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Alles bearbeiten'),
              ),
              const SizedBox(height: 8),
              if (recipe.sourceUrl.isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: _openSource,
                  icon: const Icon(Icons.ondemand_video),
                  label: const Text('Video zum Anschauen öffnen'),
                ),
              if (recipe.sourceUrl.isNotEmpty) const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CookModeScreen(recipe: recipe),
                    ),
                  );
                },
                icon: const Icon(Icons.soup_kitchen_outlined),
                label: const Text('Am Tablett nachkochen'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _addToShopping,
                icon: const Icon(Icons.shopping_cart_outlined),
                label: const Text('Zur Einkaufsliste'),
              ),
              if (recipe.notes != null && recipe.notes!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.accentSoft,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Text(recipe.notes!),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Einkaufsliste / Zutaten',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text('Das braucht ihr an Lebensmitteln:'),
              const SizedBox(height: 12),
              ...recipe.ingredients.asMap().entries.map(
                    (entry) => _IngredientTile(
                      index: entry.key + 1,
                      text: entry.value,
                    ),
                  ),
              const SizedBox(height: 28),
              Text(
                'So bereitet ihr es zu',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text('Schritt für Schritt:'),
              const SizedBox(height: 12),
              ...recipe.steps.asMap().entries.map(
                    (entry) => _StepTile(
                      number: entry.key + 1,
                      text: entry.value,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.mistDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.seed.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.seed),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _IngredientTile extends StatelessWidget {
  const _IngredientTile({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.seed.withValues(alpha: 0.12),
          foregroundColor: AppTheme.seed,
          child: Text('$index'),
        ),
        title: Text(text),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              child: Text('$number'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
