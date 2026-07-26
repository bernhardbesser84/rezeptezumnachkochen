import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/gemini_defaults.dart';
import '../config/google_defaults.dart';
import '../models/ai_provider.dart';
import '../models/family_config.dart';
import '../models/meal_plan_entry.dart';
import '../models/recipe.dart';
import '../models/shopping_item.dart';

class RecipeStorage {
  static const _recipesKey = 'saved_recipes';
  static const _shoppingKey = 'shopping_items';
  static const _mealPlanKey = 'meal_plan_entries';
  static const _familyKey = 'family_config';
  static const _seededKey = 'demo_seeded';
  static const _aiProviderKey = 'ai_provider';
  static const _googleWebClientIdKey = 'google_web_client_id';
  static const _googleBackupEnabledKey = 'google_backup_enabled';
  static const _googleBackupEmailKey = 'google_backup_email';
  static const _googleBackupLastAtKey = 'google_backup_last_at';

  final _uuid = const Uuid();

  Future<List<Recipe>> loadRecipes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recipesKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Recipe.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> saveRecipes(List<Recipe> recipes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _recipesKey,
      jsonEncode(recipes.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> upsertRecipe(Recipe recipe) async {
    final recipes = await loadRecipes();
    final index = recipes.indexWhere((r) => r.id == recipe.id);
    if (index >= 0) {
      recipes[index] = recipe;
    } else {
      recipes.insert(0, recipe);
    }
    await saveRecipes(recipes);
  }

  Future<void> deleteRecipe(String id) async {
    final recipes = await loadRecipes();
    recipes.removeWhere((r) => r.id == id);
    await saveRecipes(recipes);
  }

  Future<List<ShoppingItem>> loadShoppingItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_shoppingKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => ShoppingItem.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) {
        if (a.checked != b.checked) return a.checked ? 1 : -1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  Future<void> saveShoppingItems(List<ShoppingItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _shoppingKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> upsertShoppingItem(ShoppingItem item) async {
    final items = await loadShoppingItems();
    final index = items.indexWhere((e) => e.id == item.id);
    if (index >= 0) {
      items[index] = item;
    } else {
      items.add(item);
    }
    await saveShoppingItems(items);
  }

  Future<void> deleteShoppingItem(String id) async {
    final items = await loadShoppingItems();
    items.removeWhere((e) => e.id == id);
    await saveShoppingItems(items);
  }

  Future<void> clearCheckedShoppingItems() async {
    final items = await loadShoppingItems();
    items.removeWhere((e) => e.checked);
    await saveShoppingItems(items);
  }

  Future<List<ShoppingItem>> addRecipeIngredientsToShopping(
    Recipe recipe,
  ) async {
    final items = await loadShoppingItems();
    // Gleiche Zutat darf bei verschiedenen Rezepten erscheinen –
    // so bleibt die Übersicht pro Rezept sauber.
    final existingKeys = items
        .map(
          (e) => '${e.recipeId ?? ''}|${e.name.toLowerCase().trim()}',
        )
        .toSet();
    final added = <ShoppingItem>[];

    for (final ingredient in recipe.ingredients) {
      final name = ingredient.trim();
      if (name.isEmpty) continue;
      final key = '${recipe.id}|${name.toLowerCase()}';
      if (existingKeys.contains(key)) continue;
      final item = ShoppingItem(
        id: _uuid.v4(),
        name: name,
        checked: false,
        updatedAt: DateTime.now(),
        recipeId: recipe.id,
        recipeTitle: recipe.title,
      );
      items.add(item);
      added.add(item);
      existingKeys.add(key);
    }

    await saveShoppingItems(items);
    return added;
  }

  Future<List<MealPlanEntry>> loadMealPlanEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_mealPlanKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => MealPlanEntry.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<void> saveMealPlanEntries(List<MealPlanEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _mealPlanKey,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> upsertMealPlanEntry(MealPlanEntry entry) async {
    final entries = await loadMealPlanEntries();
    final index = entries.indexWhere((e) => e.id == entry.id);
    if (index >= 0) {
      entries[index] = entry;
    } else {
      entries.add(entry);
    }
    await saveMealPlanEntries(entries);
  }

  Future<void> deleteMealPlanEntry(String id) async {
    final entries = await loadMealPlanEntries();
    entries.removeWhere((e) => e.id == id);
    await saveMealPlanEntries(entries);
  }

  /// Setzt (oder ersetzt) das Rezept für einen Tag.
  Future<MealPlanEntry> setMealPlanForDate({
    required DateTime date,
    required Recipe recipe,
  }) async {
    final day = MealPlanEntry.dateOnly(date);
    final key = MealPlanEntry.keyFor(day);
    final entries = await loadMealPlanEntries();
    final existingIndex = entries.indexWhere((e) => e.dateKey == key);

    final entry = MealPlanEntry(
      id: existingIndex >= 0 ? entries[existingIndex].id : _uuid.v4(),
      date: day,
      recipeId: recipe.id,
      recipeTitle: recipe.title,
      updatedAt: DateTime.now(),
    );

    if (existingIndex >= 0) {
      entries[existingIndex] = entry;
    } else {
      entries.add(entry);
    }
    await saveMealPlanEntries(entries);
    return entry;
  }

  Future<MealPlanEntry?> clearMealPlanForDate(DateTime date) async {
    final key = MealPlanEntry.keyFor(date);
    final entries = await loadMealPlanEntries();
    final index = entries.indexWhere((e) => e.dateKey == key);
    if (index < 0) return null;
    final removed = entries.removeAt(index);
    await saveMealPlanEntries(entries);
    return removed;
  }

  Future<FamilyConfig?> loadFamilyConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_familyKey);
    if (raw == null || raw.isEmpty) return null;
    return FamilyConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveFamilyConfig(FamilyConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_familyKey, jsonEncode(config.toJson()));
  }

  /// Erzeugt einen einfachen Familien-Code wie KOCH-4F2A
  String generateFamilyCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final part = List.generate(4, (_) => chars[random.nextInt(chars.length)])
        .join();
    return 'KOCH-$part';
  }

  Future<AiProvider> getAiProvider() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_aiProviderKey);
    // Noch nichts gewählt → Gemini, wenn der Schlüssel eingebaut ist.
    if (raw == null || raw.trim().isEmpty) {
      return GeminiDefaults.hasBuiltInKey
          ? AiProvider.gemini
          : AiProvider.openai;
    }
    return AiProvider.fromStorage(raw);
  }

  Future<void> setAiProvider(AiProvider provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aiProviderKey, provider.storageValue);
  }

  /// Aktiver Schlüssel für den gewählten Anbieter.
  Future<String?> getApiKey() async {
    final provider = await getAiProvider();
    return getApiKeyFor(provider);
  }

  Future<String?> getApiKeyFor(AiProvider provider) async {
    if (provider == AiProvider.openai) {
      final family = await loadFamilyConfig();
      if (family?.openaiApiKey != null &&
          family!.openaiApiKey!.trim().isNotEmpty) {
        return family.openaiApiKey;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(provider.storageKey)?.trim();
    if (stored != null && stored.isNotEmpty) return stored;

    // Gemini: eingebauter Schlüssel, falls lokal nichts eingetragen ist.
    if (provider == AiProvider.gemini && GeminiDefaults.hasBuiltInKey) {
      return GeminiDefaults.apiKey;
    }
    return null;
  }

  Future<void> setApiKey(String? key) async {
    final provider = await getAiProvider();
    await setApiKeyFor(provider, key);
  }

  Future<void> setApiKeyFor(AiProvider provider, String? key) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = key?.trim() ?? '';
    if (trimmed.isEmpty) {
      await prefs.remove(provider.storageKey);
    } else {
      await prefs.setString(provider.storageKey, trimmed);
    }

    // OpenAI-Schlüssel auch in der Familien-Config halten (wie bisher).
    if (provider == AiProvider.openai) {
      final family = await loadFamilyConfig() ??
          FamilyConfig(familyCode: generateFamilyCode(), deviceName: 'Gerät');
      await saveFamilyConfig(
        family.copyWith(
          openaiApiKey: trimmed.isEmpty ? null : trimmed,
          clearOpenaiApiKey: trimmed.isEmpty,
        ),
      );
    }
  }

  Future<bool> wasDemoSeeded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_seededKey) ?? false;
  }

  Future<void> markDemoSeeded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seededKey, true);
  }

  Future<String?> getGoogleWebClientId() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_googleWebClientIdKey)?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    if (GoogleDefaults.hasBuiltInClientId) {
      return GoogleDefaults.webClientId;
    }
    return null;
  }

  Future<void> setGoogleWebClientId(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = value?.trim() ?? '';
    // Eingebaute ID nicht unnötig lokal speichern.
    if (trimmed.isEmpty ||
        (GoogleDefaults.hasBuiltInClientId &&
            trimmed == GoogleDefaults.webClientId.trim())) {
      await prefs.remove(_googleWebClientIdKey);
      return;
    }
    await prefs.setString(_googleWebClientIdKey, trimmed);
  }

  Future<bool> isGoogleBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_googleBackupEnabledKey) ?? false;
  }

  Future<void> setGoogleBackupEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_googleBackupEnabledKey, value);
  }

  Future<String?> getGoogleBackupEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_googleBackupEmailKey);
  }

  Future<void> setGoogleBackupEmail(String? email) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = email?.trim() ?? '';
    if (trimmed.isEmpty) {
      await prefs.remove(_googleBackupEmailKey);
    } else {
      await prefs.setString(_googleBackupEmailKey, trimmed);
    }
  }

  Future<DateTime?> getGoogleBackupLastAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_googleBackupLastAtKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> setGoogleBackupLastAt(DateTime? when) async {
    final prefs = await SharedPreferences.getInstance();
    if (when == null) {
      await prefs.remove(_googleBackupLastAtKey);
    } else {
      await prefs.setString(_googleBackupLastAtKey, when.toIso8601String());
    }
  }
}
