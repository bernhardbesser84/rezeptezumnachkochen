import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rezept_nachkochen/models/family_config.dart';
import 'package:rezept_nachkochen/models/recipe.dart';
import 'package:rezept_nachkochen/services/app_repository.dart';
import 'package:rezept_nachkochen/services/family_sync_service.dart';
import 'package:rezept_nachkochen/services/recipe_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final recipe = Recipe(
    id: 'r-cover',
    title: 'Dönerteller',
    ingredients: const ['600 g Kartoffeln'],
    steps: const ['Backen'],
    sourceUrl: '',
    createdAt: DateTime(2026, 8, 14),
    imageUrl: 'https://example.com/doener.jpg',
  );

  final cloud = FamilyConfig(
    familyCode: 'KOCH-RRGP',
    deviceName: 'Test',
    supabaseUrl: 'https://example.supabase.co',
    supabaseAnonKey: 'test-key',
  );

  const missingImageUrlBody =
      '{"code":"PGRST204","details":null,"hint":null,"message":"Could not find the \'image_url\' column of \'recipes\' in the schema cache"}';

  test('Cloud-Speichern klappt ohne image_url-Spalte', () async {
    var calls = 0;
    final sync = FamilySyncService(
      client: MockClient((request) async {
        calls++;
        final decoded = jsonDecode(request.body);
        final row = decoded is List
            ? decoded.first as Map<String, dynamic>
            : decoded as Map<String, dynamic>;
        if (row.containsKey('image_url')) {
          return http.Response(missingImageUrlBody, 400);
        }
        return http.Response('{}', 201);
      }),
    );

    await sync.pushRecipe(cloud, recipe);
    expect(calls, 2);
  });

  test('Rezept bleibt lokal gespeichert, auch wenn Cloud image_url ablehnt',
      () async {
    final storage = RecipeStorage();
    await storage.saveFamilyConfig(cloud);
    final repo = AppRepository(
      storage: storage,
      sync: FamilySyncService(
        client: MockClient(
          (_) async => http.Response(missingImageUrlBody, 400),
        ),
      ),
    );

    await repo.saveRecipe(recipe);
    final saved = await storage.loadRecipes();
    expect(saved.single.imageUrl, 'https://example.com/doener.jpg');
  });
}
