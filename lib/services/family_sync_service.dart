import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/family_config.dart';
import '../models/recipe.dart';
import '../models/shopping_item.dart';

/// Synchronisiert Rezepte und Einkaufsliste über Supabase (kostenlose Cloud).
/// Ohne Cloud-Daten in den Einstellungen bleibt alles nur lokal auf dem Gerät.
class FamilySyncService {
  FamilySyncService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _rest(
    FamilyConfig config,
    String table, {
    Map<String, String>? query,
  }) {
    final base = config.supabaseUrl!.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/rest/v1/$table').replace(
      queryParameters: query,
    );
  }

  Map<String, String> _headers(FamilyConfig config, {bool preferReturn = false}) {
    final key = config.supabaseAnonKey!.trim();
    return {
      'apikey': key,
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
      if (preferReturn)
        'Prefer': 'resolution=merge-duplicates,return=representation'
      else
        'Prefer': 'resolution=merge-duplicates',
    };
  }

  Future<void> pushRecipe(FamilyConfig config, Recipe recipe) async {
    if (!config.hasCloud) return;
    final response = await _client.post(
      _rest(config, 'recipes', query: {'on_conflict': 'id'}),
      headers: _headers(config, preferReturn: true),
      body: jsonEncode(recipe.toCloud(familyCode: config.familyCode)),
    );
    _ensureOk(response, 'Rezept konnte nicht in die Cloud gespeichert werden.');
  }

  Future<void> deleteRecipe(FamilyConfig config, String recipeId) async {
    if (!config.hasCloud) return;
    final uri = _rest(
      config,
      'recipes',
      query: {
        'id': 'eq.$recipeId',
        'family_code': 'eq.${config.familyCode}',
      },
    );
    final response = await _client.delete(uri, headers: _headers(config));
    _ensureOk(response, 'Rezept konnte in der Cloud nicht gelöscht werden.');
  }

  Future<List<Recipe>> pullRecipes(FamilyConfig config) async {
    if (!config.hasCloud) return [];
    final uri = _rest(
      config,
      'recipes',
      query: {
        'family_code': 'eq.${config.familyCode}',
        'order': 'created_at.desc',
      },
    );
    final response = await _client.get(uri, headers: _headers(config));
    _ensureOk(response, 'Rezepte konnten nicht aus der Cloud geladen werden.');
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => Recipe.fromCloud(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> pushShoppingItem(
    FamilyConfig config,
    ShoppingItem item,
  ) async {
    if (!config.hasCloud) return;
    final response = await _client.post(
      _rest(config, 'shopping_items', query: {'on_conflict': 'id'}),
      headers: _headers(config, preferReturn: true),
      body: jsonEncode(item.toCloud(familyCode: config.familyCode)),
    );
    _ensureOk(
      response,
      'Einkaufspunkt konnte nicht in die Cloud gespeichert werden.',
    );
  }

  Future<void> deleteShoppingItem(FamilyConfig config, String itemId) async {
    if (!config.hasCloud) return;
    final uri = _rest(
      config,
      'shopping_items',
      query: {
        'id': 'eq.$itemId',
        'family_code': 'eq.${config.familyCode}',
      },
    );
    final response = await _client.delete(uri, headers: _headers(config));
    _ensureOk(
      response,
      'Einkaufspunkt konnte in der Cloud nicht gelöscht werden.',
    );
  }

  Future<List<ShoppingItem>> pullShoppingItems(FamilyConfig config) async {
    if (!config.hasCloud) return [];
    final uri = _rest(
      config,
      'shopping_items',
      query: {
        'family_code': 'eq.${config.familyCode}',
        'order': 'checked.asc,name.asc',
      },
    );
    final response = await _client.get(uri, headers: _headers(config));
    _ensureOk(
      response,
      'Einkaufsliste konnte nicht aus der Cloud geladen werden.',
    );
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => ShoppingItem.fromCloud(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> pushAllRecipes(
    FamilyConfig config,
    List<Recipe> recipes,
  ) async {
    if (!config.hasCloud || recipes.isEmpty) return;
    final response = await _client.post(
      _rest(config, 'recipes', query: {'on_conflict': 'id'}),
      headers: _headers(config),
      body: jsonEncode(
        recipes.map((r) => r.toCloud(familyCode: config.familyCode)).toList(),
      ),
    );
    _ensureOk(response, 'Rezepte konnten nicht synchronisiert werden.');
  }

  Future<void> pushAllShoppingItems(
    FamilyConfig config,
    List<ShoppingItem> items,
  ) async {
    if (!config.hasCloud || items.isEmpty) return;
    final response = await _client.post(
      _rest(config, 'shopping_items', query: {'on_conflict': 'id'}),
      headers: _headers(config),
      body: jsonEncode(
        items.map((e) => e.toCloud(familyCode: config.familyCode)).toList(),
      ),
    );
    _ensureOk(response, 'Einkaufsliste konnte nicht synchronisiert werden.');
  }

  Future<String?> testConnection(FamilyConfig config) async {
    if (!config.hasCloud) {
      return 'Cloud-Adresse oder Schlüssel fehlen.';
    }
    try {
      final uri = _rest(
        config,
        'recipes',
        query: {
          'family_code': 'eq.${config.familyCode}',
          'select': 'id',
          'limit': '1',
        },
      );
      final response = await _client
          .get(uri, headers: _headers(config))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return null;
      }
      return 'Cloud antwortet mit Code ${response.statusCode}. '
          'Prüfe URL, Schlüssel und Tabellen.';
    } catch (e) {
      return 'Keine Verbindung zur Cloud: $e';
    }
  }

  void _ensureOk(http.Response response, String message) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('$message (${response.statusCode})');
    }
  }
}
