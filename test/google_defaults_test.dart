import 'package:flutter_test/flutter_test.dart';
import 'package:rezept_nachkochen/config/google_defaults.dart';
import 'package:rezept_nachkochen/services/recipe_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Google-Client-ID ist fest hinterlegt', () async {
    expect(GoogleDefaults.hasBuiltInClientId, isTrue);
    expect(
      GoogleDefaults.webClientId,
      contains('.apps.googleusercontent.com'),
    );

    final storage = RecipeStorage();
    expect(await storage.getGoogleWebClientId(), GoogleDefaults.webClientId);
  });

  test('Eigene Client-ID überschreibt die eingebaute', () async {
    final storage = RecipeStorage();
    await storage.setGoogleWebClientId('eigene-id.apps.googleusercontent.com');
    expect(
      await storage.getGoogleWebClientId(),
      'eigene-id.apps.googleusercontent.com',
    );

    await storage.setGoogleWebClientId(GoogleDefaults.webClientId);
    expect(await storage.getGoogleWebClientId(), GoogleDefaults.webClientId);
  });
}
