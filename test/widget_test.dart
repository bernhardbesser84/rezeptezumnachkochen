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

  test('Ohne API entsteht trotzdem ein Rezept aus Link-Text', () async {
    final extractor = RecipeExtractor();
    final recipe = await extractor.extractRecipe(
      sourceText: 'https://example.com/mein-kuchen',
      useAi: false,
    );
    expect(recipe.title.isNotEmpty, isTrue);
    expect(recipe.title.toLowerCase(), isNot(contains('facebook')));
    expect(recipe.ingredients, isNotEmpty);
    expect(recipe.steps, isNotEmpty);
  });

  test('Facebook-Link ohne Caption ergibt keinen Plattform-Titel', () async {
    final extractor = RecipeExtractor();
    final recipe = await extractor.extractRecipe(
      sourceText: 'https://www.facebook.com/watch/?v=123',
      useAi: false,
    );
    expect(recipe.title.toLowerCase(), isNot(contains('facebook')));
    expect(recipe.title.toLowerCase(), isNot(contains('rezept von')));
  });

  test('Caption liefert den Gerichtsnamen', () async {
    final extractor = RecipeExtractor();
    final recipe = await extractor.extractRecipe(
      sourceText: 'https://www.facebook.com/reel/1',
      captionText: 'Knoblauch-Garnelen\n200 g Garnelen\n2 Knoblauchzehen',
      useAi: false,
    );
    expect(recipe.title.toLowerCase(), contains('garnelen'));
  });

  test('KI-JSON mit Codeblock und Extra-Text wird gelesen', () {
    final extractor = RecipeExtractor();
    final recipe = extractor.parseAiRecipeJson('''
Hier ist das Rezept:
```json
{
  "title": "Tomatensuppe",
  "servings": "2 Portionen",
  "prepTimeMinutes": 20,
  "ingredients": ["Tomaten", "Zwiebel"],
  "steps": ["Anbraten", "Köcheln"],
  "notes": "Geschätzt"
}
```
Viel Erfolg!
''');
    expect(recipe.title, 'Tomatensuppe');
    expect(recipe.ingredients, ['Tomaten', 'Zwiebel']);
    expect(recipe.steps, ['Anbraten', 'Köcheln']);
    expect(recipe.prepTimeMinutes, 20);
  });

  test('Gemini-Denktext wird vom Antwort-JSON getrennt', () {
    final extractor = RecipeExtractor();
    final text = extractor.readGeminiAnswerText({
      'candidates': [
        {
          'finishReason': 'STOP',
          'content': {
            'parts': [
              {
                'text': 'Ich überlege: zuerst Zwiebeln...',
                'thought': true,
              },
              {
                'text':
                    '{"title":"Ofenkartoffeln","servings":null,'
                    '"prepTimeMinutes":35,"ingredients":["Kartoffeln"],'
                    '"steps":["Waschen","Backen"],"notes":null}',
              },
            ],
          },
        },
      ],
    });
    final recipe = extractor.parseAiRecipeJson(text);
    expect(recipe.title, 'Ofenkartoffeln');
    expect(recipe.ingredients, ['Kartoffeln']);
    expect(text.contains('überlege'), isFalse);
  });

  test('Manuelles Rezept speichert Zutaten und Schritte', () {
    final extractor = RecipeExtractor();
    final recipe = extractor.buildManualRecipe(
      title: 'Omas Kuchen',
      ingredients: const ['Mehl', 'Zucker'],
      steps: const ['Mischen', 'Backen'],
    );
    expect(recipe.title, 'Omas Kuchen');
    expect(recipe.ingredients, ['Mehl', 'Zucker']);
    expect(recipe.steps, ['Mischen', 'Backen']);
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
