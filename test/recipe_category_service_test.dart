import 'package:flutter_test/flutter_test.dart';
import 'package:rezept_nachkochen/models/recipe.dart';
import 'package:rezept_nachkochen/services/recipe_category_service.dart';

void main() {
  test('normalisiert und sammelt Kategorien', () {
    final recipes = [
      Recipe(
        id: '1',
        title: 'Pasta',
        ingredients: const ['200 g Nudeln'],
        steps: const ['Kochen'],
        sourceUrl: '',
        createdAt: DateTime.now(),
        categories: const ['pasta', 'familie'],
      ),
      Recipe(
        id: '2',
        title: 'Reis',
        ingredients: const ['200 g Reis'],
        steps: const ['Kochen'],
        sourceUrl: '',
        createdAt: DateTime.now(),
        categories: const ['Familie', 'One Pot'],
      ),
    ];

    final categories = RecipeCategoryService.collectFromRecipes(recipes);
    expect(categories, containsAll(['Pasta', 'Familie', 'One Pot']));
    expect(categories.length, 3);
  });

  test('macht Vorschläge aus Titel und Zutaten', () {
    final recipe = Recipe(
      id: '3',
      title: 'Hähnchen One Pot Pasta',
      ingredients: const ['200 g Hähnchen', '250 g Pasta'],
      steps: const ['Kochen'],
      sourceUrl: '',
      createdAt: DateTime.now(),
    );
    final suggestions = RecipeCategoryService.suggestForRecipe(recipe);
    expect(suggestions, contains('One Pot'));
    expect(suggestions, contains('Pasta'));
    expect(suggestions, contains('Hähnchen'));
  });

  test('Kategorie umbenennen und entfernen auf Rezept', () {
    final recipe = Recipe(
      id: '4',
      title: 'Test',
      ingredients: const ['Salz'],
      steps: const ['Kochen'],
      sourceUrl: '',
      createdAt: DateTime.now(),
      categories: const ['Pasta', 'Familie'],
    );

    final renamed = RecipeCategoryService.renameCategoryOnRecipe(
      recipe: recipe,
      oldName: 'Pasta',
      newName: 'Nudeln',
    );
    expect(renamed.categories, containsAll(['Nudeln', 'Familie']));
    expect(renamed.categories, isNot(contains('Pasta')));

    final removed = RecipeCategoryService.removeCategoryFromRecipe(
      recipe: renamed,
      category: 'Familie',
    );
    expect(removed.categories, ['Nudeln']);
  });
}
