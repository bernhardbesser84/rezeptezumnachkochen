import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/recipe.dart';

class RecipeStorage {
  static const _recipesKey = 'saved_recipes';
  static const _apiKeyKey = 'openai_api_key';
  static const _seededKey = 'demo_seeded';

  Future<List<Recipe>> loadRecipes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recipesKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Recipe.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> saveRecipes(List<Recipe> recipes) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(recipes.map((r) => r.toJson()).toList());
    await prefs.setString(_recipesKey, encoded);
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

  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyKey);
  }

  Future<void> setApiKey(String? key) async {
    final prefs = await SharedPreferences.getInstance();
    if (key == null || key.trim().isEmpty) {
      await prefs.remove(_apiKeyKey);
    } else {
      await prefs.setString(_apiKeyKey, key.trim());
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
}
