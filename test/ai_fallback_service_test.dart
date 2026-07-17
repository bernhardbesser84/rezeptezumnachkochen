import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rezept_nachkochen/models/ai_provider.dart';
import 'package:rezept_nachkochen/models/fallback_api_keys.dart';
import 'package:rezept_nachkochen/services/ai_fallback_service.dart';
import 'package:rezept_nachkochen/services/recipe_extractor.dart';

void main() {
  test('FallbackApiKeys merge bevorzugt gespeicherte Werte', () {
    const env = FallbackApiKeys(groq: 'env-groq', mistral: '');
    const stored = FallbackApiKeys(mistral: 'stored-mistral');
    final merged = env.merge(stored);
    expect(merged.groq, 'env-groq');
    expect(merged.mistral, 'stored-mistral');
  });

  test('Mistral-Chat liefert Rezept-JSON', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'api.mistral.ai');
      expect(request.url.path, '/v1/chat/completions');
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'title': 'Protein Bowl',
                  'servings': '2',
                  'prepTimeMinutes': 20,
                  'ingredients': ['Hähnchen', 'Reis'],
                  'steps': ['Anbraten', 'Servieren'],
                  'notes': null,
                }),
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = AiFallbackService(
      client: client,
      extractor: RecipeExtractor(client: client),
    );
    final recipe = await service.extractRecipeFromText(
      combinedText: 'Caption: Protein Bowl\n500 g Hähnchen',
      sourceUrl: 'https://example.com',
      keys: const FallbackApiKeys(mistral: 'test-key'),
    );
    expect(recipe.title, 'Protein Bowl');
    expect(recipe.ingredients, contains('Hähnchen'));
    expect(recipe.steps.length, 2);
  });

  test('Gemini 429 → Fallback mit Caption ohne Video', () async {
    var geminiCalls = 0;
    final client = MockClient((request) async {
      if (request.url.host.contains('googleapis.com')) {
        geminiCalls++;
        return http.Response(
          jsonEncode({
            'error': {
              'code': 429,
              'message': 'Resource exhausted',
              'status': 'RESOURCE_EXHAUSTED',
            },
          }),
          429,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.host.contains('mistral.ai')) {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'title': 'Knoblauch-Garnelen',
                    'servings': null,
                    'prepTimeMinutes': null,
                    'ingredients': ['200 g Garnelen', '2 Knoblauchzehen'],
                    'steps': ['Anbraten', 'Abschmecken'],
                    'notes': 'Fallback',
                  }),
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final extractor = RecipeExtractor(client: client);
    final recipe = await extractor.extractRecipe(
      sourceText: 'https://www.facebook.com/reel/1',
      captionText: 'Knoblauch-Garnelen\n200 g Garnelen\n2 Knoblauchzehen',
      apiKey: 'AIza-test',
      provider: AiProvider.gemini,
      useAi: true,
      skipPagePreview: true,
      fallbackKeys: const FallbackApiKeys(mistral: 'mistral-test'),
    );

    expect(geminiCalls, greaterThan(0));
    expect(recipe.title.toLowerCase(), contains('garnelen'));
    expect(recipe.ingredients.length, greaterThanOrEqualTo(2));
    expect(recipe.notes, contains('Fallback'));
  });
}
