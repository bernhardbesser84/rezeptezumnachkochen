import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rezept_nachkochen/main.dart';
import 'package:rezept_nachkochen/models/ai_provider.dart';
import 'package:rezept_nachkochen/models/app_backup_payload.dart';
import 'package:rezept_nachkochen/models/recipe.dart';
import 'package:rezept_nachkochen/services/app_repository.dart';
import 'package:rezept_nachkochen/services/family_sync_service.dart';
import 'package:rezept_nachkochen/services/google_backup_service.dart';
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

  test('Facebook-Titel behält den Gerichtsnamen hinter |', () {
    final extractor = RecipeExtractor();
    final title = extractor.cleanDishTitleForTest(
      '58.263 Aufrufe · 7.530 Reaktionen | High Protein Döner Wrap 🌯🔥 (74g Protein)',
    );
    expect(title.toLowerCase(), contains('döner wrap'));
    expect(title.toLowerCase(), isNot(contains('aufrufe')));
  });

  test('HTML-Entities in Facebook-Titeln werden dekodiert', () {
    final extractor = RecipeExtractor();
    final decoded = extractor.decodeHtmlForTest(
      'High Protein D&#xf6;ner Wrap',
    );
    expect(decoded, 'High Protein Döner Wrap');
  });

  test('Facebook-Meta liefert Döner-Wrap aus Share-Link', () async {
    final client = MockClient((request) async {
      expect(request.headers['User-Agent'], contains('facebookexternalhit'));
      return http.Response(
        '''
<html><head>
<meta property="og:title" content="58.263 Aufrufe · 7.530 Reaktionen | High Protein D&#xf6;ner Wrap &#x1f32f;

Dieser High Protein D&#xf6;ner Wrap mit Sauce und Wrap. Kommentiere DÖNER. #highprotein #rezepte" />
<meta property="og:description" content="High Protein D&#xf6;ner Wrap mit Sauce..."/>
<meta property="og:image:alt" content="58.263 Aufrufe | High Protein D&#xf6;ner Wrap

Dieser High Protein D&#xf6;ner Wrap mit selbstgemachten Dönerfleisch ist die perfekte Alternative.

Willst du das Rezept als PDF? Kommentiere DÖNER. #highprotein #rezepte KevinElstner" />
<meta property="og:url" content="https://www.facebook.com/reel/3276267172553159/" />
</head><body></body></html>
''',
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });

    final extractor = RecipeExtractor(client: client);
    final preview = await extractor.fetchPagePreview(
      'https://www.facebook.com/share/r/1N5VosFAK7/',
    );

    expect(
      extractor.cleanDishTitleForTest(preview.title).toLowerCase(),
      contains('döner wrap'),
    );
    expect(preview.description.toLowerCase(), contains('döner wrap'));
    expect(preview.description.contains('...'), isFalse);
    expect(preview.description.length, greaterThan(120));
    expect(preview.url, contains('/reel/'));
  });

  test('Abgeschnittene Facebook-Description wird zugunsten Titel verworfen', () {
    final extractor = RecipeExtractor();
    final html = '''
<meta property="og:description" content="High Protein Döner Wrap als..." />
<meta property="og:title" content="10 Aufrufe | High Protein Döner Wrap

Lange Caption ohne Abschneidung mit Zutatenhinweis und Hashtags." />
''';
    final caption = extractor.bestFacebookCaptionForTest(html);
    expect(caption.contains('Lange Caption'), isTrue);
    expect(caption.endsWith('...'), isFalse);
  });

  test('Fehlende Umlaute in KI-Text werden korrigiert', () {
    final extractor = RecipeExtractor();
    final fixed = extractor.fixGermanSpellingForTest(
      'Hhnchen Reis One Pot. 150ml Gemsebrhe, Hirtenkse. '
      'In einer groen Pfanne wrzen und fr 15 Min. kcheln. '
      'Zubereitung wurde geschtzt.',
    );
    expect(fixed, contains('Hähnchen'));
    expect(fixed, contains('Gemüsebrühe'));
    expect(fixed, contains('Hirtenkäse'));
    expect(fixed, contains('großen'));
    expect(fixed, contains('würzen'));
    expect(fixed, contains('für'));
    expect(fixed, contains('köcheln'));
    expect(fixed, contains('geschätzt'));
    expect(fixed.contains('Hhnchen'), isFalse);
  });

  test('KI-JSON mit fehlenden Umlauten wird beim Parsen repariert', () {
    final extractor = RecipeExtractor();
    final recipe = extractor.parseAiRecipeJson('''
{
  "title": "Hhnchen Reis One Pot",
  "servings": "4",
  "prepTimeMinutes": 30,
  "ingredients": ["500g Hhnchenbrustfilet", "150ml Gemsebrhe"],
  "steps": ["Hhnchenfleisch in groen Pfanne wrzen."],
  "notes": "Zeiten wurden geschtzt."
}
''');
    expect(recipe.title, contains('Hähnchen'));
    expect(recipe.ingredients.first, contains('Hähnchenbrustfilet'));
    expect(recipe.ingredients.last, contains('Gemüsebrühe'));
    expect(recipe.steps.first, contains('würzen'));
    expect(recipe.notes, contains('geschätzt'));
  });

  test('Caption mit nur Zutaten wird erkannt', () {
    final extractor = RecipeExtractor();
    expect(
      extractor.captionLooksLikeIngredientsOnly('''
High Protein Bowl
500 g Hähnchenbrust
200 g Reis
150 ml Gemüsebrühe
1 Zwiebel
'''),
      isTrue,
    );
    expect(
      extractor.captionLooksLikeIngredientsOnly('''
Zubereitung:
1. Zwiebel anbraten.
2. Hähnchen scharf anbraten.
3. Reis dazugeben und köcheln.
'''),
      isFalse,
    );
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

  test('Backup-Payload enthält Rezepte und Einstellungen', () async {
    final storage = RecipeStorage();
    await storage.setAiProvider(AiProvider.gemini);
    await storage.setApiKeyFor(AiProvider.gemini, 'AIza-test');
    await storage.upsertRecipe(
      Recipe(
        id: 'b1',
        title: 'Backup-Salat',
        ingredients: const ['Salat'],
        steps: const ['Waschen'],
        sourceUrl: '',
        createdAt: DateTime.now(),
      ),
    );

    final backup = GoogleBackupService(storage: storage);
    final payload = await backup.buildPayload();
    expect(payload.recipes.any((r) => r.title == 'Backup-Salat'), isTrue);
    expect(payload.aiProvider, AiProvider.gemini);
    expect(payload.apiKeys['gemini'], 'AIza-test');

    final roundtrip = AppBackupPayload.fromJsonString(payload.toJsonString());
    expect(roundtrip.recipes.first.title, 'Backup-Salat');
    expect(roundtrip.apiKeys['gemini'], 'AIza-test');

    await storage.deleteRecipe('b1');
    await storage.setApiKeyFor(AiProvider.gemini, null);
    await backup.applyPayload(roundtrip);
    final recipes = await storage.loadRecipes();
    expect(recipes.any((r) => r.title == 'Backup-Salat'), isTrue);
    expect(await storage.getApiKeyFor(AiProvider.gemini), 'AIza-test');
  });
}
