import '../models/recipe.dart';

class RecipeCategoryService {
  static const allRecipesLabel = 'Alle Rezepte';

  static List<String> normalizeAll(Iterable<String> values) {
    final result = <String>[];
    for (final value in values) {
      final cleaned = normalizeOne(value);
      if (cleaned == null) continue;
      if (!result.contains(cleaned)) result.add(cleaned);
    }
    return result;
  }

  static String? normalizeOne(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.toLowerCase() == allRecipesLabel.toLowerCase()) return null;
    final parts = trimmed
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
        .toList();
    if (parts.isEmpty) return null;
    return parts.join(' ');
  }

  static List<String> collectFromRecipes(List<Recipe> recipes) {
    final all = <String>[];
    for (final recipe in recipes) {
      all.addAll(recipe.categories);
    }
    all.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return normalizeAll(all);
  }

  /// Bekannte Kategorien + Kategorien aus Rezepten zusammenführen.
  static List<String> mergeCatalog({
    required List<String> known,
    required List<Recipe> recipes,
  }) {
    final merged = normalizeAll([
      ...known,
      ...collectFromRecipes(recipes),
    ]);
    merged.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return merged;
  }

  static bool recipeHasCategory(Recipe recipe, String category) {
    final target = normalizeOne(category);
    if (target == null) return false;
    return recipe.categories.any((c) => normalizeOne(c) == target);
  }

  static int countRecipesWithCategory(List<Recipe> recipes, String category) {
    final target = normalizeOne(category);
    if (target == null) return 0;
    return recipes.where((r) => recipeHasCategory(r, target)).length;
  }

  /// Lokal und Cloud zusammenführen.
  /// Bei gleichem Erstelldatum gewinnt lokal (sonst gehen Bearbeitungen verloren).
  /// Kategorien werden immer zusammengeführt, damit nichts verloren geht.
  static Recipe mergeRecipes({
    required Recipe local,
    required Recipe remote,
  }) {
    final categories = normalizeAll([
      ...local.categories,
      ...remote.categories,
    ]);

    if (local.createdAt.isAfter(remote.createdAt)) {
      return local.copyWith(
        categories: categories,
        imageUrl: _preferImage(local.imageUrl, remote.imageUrl),
      );
    }
    if (remote.createdAt.isAfter(local.createdAt)) {
      return remote.copyWith(
        categories: categories,
        imageUrl: _preferImage(local.imageUrl, remote.imageUrl),
      );
    }
    return local.copyWith(
      categories: categories,
      imageUrl: _preferImage(local.imageUrl, remote.imageUrl),
    );
  }

  static String? _preferImage(String? a, String? b) {
    if (a != null && a.trim().isNotEmpty) return a;
    if (b != null && b.trim().isNotEmpty) return b;
    return a ?? b;
  }

  static Recipe renameCategoryOnRecipe({
    required Recipe recipe,
    required String oldName,
    required String newName,
  }) {
    final from = normalizeOne(oldName);
    final to = normalizeOne(newName);
    if (from == null || to == null) return recipe;
    if (!recipe.categories.contains(from)) return recipe;
    final updated = recipe.categories
        .map((c) => c == from ? to : c)
        .toList();
    return recipe.copyWith(categories: normalizeAll(updated));
  }

  static Recipe removeCategoryFromRecipe({
    required Recipe recipe,
    required String category,
  }) {
    final target = normalizeOne(category);
    if (target == null) return recipe;
    final updated =
        recipe.categories.where((c) => c != target).toList(growable: false);
    if (updated.length == recipe.categories.length) return recipe;
    return recipe.copyWith(categories: updated);
  }

  static List<String> suggestForRecipe(Recipe recipe) {
    final text = [
      recipe.title,
      recipe.ingredients.join(' '),
      recipe.notes ?? '',
      recipe.sourceUrl,
    ].join(' ').toLowerCase();

    final suggestions = <String>[];
    void addIf(bool condition, String category) {
      if (!condition) return;
      final normalized = normalizeOne(category);
      if (normalized != null && !suggestions.contains(normalized)) {
        suggestions.add(normalized);
      }
    }

    addIf(
      text.contains('one pot') || text.contains('onepot'),
      'One Pot',
    );
    addIf(
      text.contains('pasta') ||
          text.contains('penne') ||
          text.contains('spaghetti') ||
          text.contains('nudel'),
      'Pasta',
    );
    addIf(
      text.contains('reis') || text.contains('rice'),
      'Reis',
    );
    addIf(
      text.contains('hähnchen') || text.contains('huhn') || text.contains('chicken'),
      'Hähnchen',
    );
    addIf(
      text.contains('lachs') ||
          text.contains('salmon') ||
          text.contains('fisch') ||
          text.contains('shrimp') ||
          text.contains('garnelen'),
      'Fisch & Meer',
    );
    addIf(
      text.contains('salat'),
      'Salat',
    );
    addIf(
      text.contains('suppe') || text.contains('soup'),
      'Suppe',
    );
    addIf(
      text.contains('kuchen') ||
          text.contains('cake') ||
          text.contains('dessert') ||
          text.contains('keks'),
      'Dessert',
    );
    addIf(
      text.contains('vegetar') || text.contains('veggie'),
      'Vegetarisch',
    );

    if (suggestions.isEmpty) {
      suggestions.add('Ohne Kategorie');
    }
    return suggestions.take(4).toList();
  }
}
