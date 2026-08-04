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
