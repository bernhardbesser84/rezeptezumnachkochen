import 'package:flutter_test/flutter_test.dart';
import 'package:rezept_nachkochen/config/gemini_defaults.dart';
import 'package:rezept_nachkochen/models/ai_provider.dart';
import 'package:rezept_nachkochen/services/recipe_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Gemini-Schlüssel ist fest hinterlegt und Standard-Anbieter', () async {
    expect(GeminiDefaults.hasBuiltInKey, isTrue);
    expect(GeminiDefaults.apiKey.trim(), isNotEmpty);

    final storage = RecipeStorage();
    expect(await storage.getAiProvider(), AiProvider.gemini);
    expect(await storage.getApiKey(), GeminiDefaults.apiKey);
    expect(
      await storage.getApiKeyFor(AiProvider.gemini),
      GeminiDefaults.apiKey,
    );
  });

  test('Eigener Gemini-Schlüssel überschreibt den eingebauten', () async {
    final storage = RecipeStorage();
    await storage.setApiKeyFor(AiProvider.gemini, 'AIza-eigen');
    expect(await storage.getApiKeyFor(AiProvider.gemini), 'AIza-eigen');

    await storage.setApiKeyFor(AiProvider.gemini, null);
    expect(
      await storage.getApiKeyFor(AiProvider.gemini),
      GeminiDefaults.apiKey,
    );
  });
}
