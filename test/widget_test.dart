import 'package:flutter_test/flutter_test.dart';
import 'package:rezept_nachkochen/main.dart';
import 'package:rezept_nachkochen/models/recipe.dart';
import 'package:rezept_nachkochen/services/app_repository.dart';
import 'package:rezept_nachkochen/services/family_sync_service.dart';
import 'package:rezept_nachkochen/services/recipe_extractor.dart';
import 'package:rezept_nachkochen/services/recipe_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App startet und zeigt Starttitel', (tester) async {
    await tester.pumpWidget(const RezeptNachkochenApp());
    await tester.pumpAndSettle();

    expect(find.text('Rezept Nachkochen'), findsWidgets);
    expect(find.textContaining('Einkauf'), findsWidgets);
  });

  test('Lokale Auswertung erkennt Zutaten und Schritte', () async {
    final extractor = RecipeExtractor();
    final recipe = await extractor.extractRecipe(
      sourceText: '''
Titel: Schnelle Rührei-Bowl
Zutaten:
- 3 Eier
- 1 Handvoll Spinat
- 1 EL Butter
Zubereitung:
1. Butter in der Pfanne erhitzen.
2. Eier verquirlen und braten.
3. Spinat unterheben und servieren.
''',
    );

    expect(recipe.title.toLowerCase(), contains('rührei'));
    expect(recipe.ingredients.length, greaterThanOrEqualTo(2));
    expect(recipe.steps.length, greaterThanOrEqualTo(2));
  });

  test('Einkaufsliste speichert Abhaken lokal', () async {
    final storage = RecipeStorage();
    final repo = AppRepository(storage: storage, sync: FamilySyncService());
    final recipe = Recipe(
      id: 'r1',
      title: 'Testpasta',
      ingredients: const ['500 g Nudeln', '1 Glas Pesto'],
      steps: const ['Kochen', 'Mischen'],
      sourceUrl: '',
      createdAt: DateTime.now(),
    );

    await repo.saveRecipe(recipe);
    final added = await repo.addRecipeToShopping(recipe);
    expect(added, 2);

    final items = await repo.loadShopping(pullRemote: false);
    expect(items.length, 2);
    await repo.setShoppingChecked(items.first, true);
    final updated = await repo.loadShopping(pullRemote: false);
    expect(updated.where((e) => e.checked).length, 1);
  });
}
