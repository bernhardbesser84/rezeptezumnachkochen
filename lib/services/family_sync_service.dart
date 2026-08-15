import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/family_config.dart';
import '../models/family_config_cloud.dart';
import '../models/meal_plan_entry.dart';
import '../models/recipe.dart';
import '../models/shopping_item.dart';

/// Ergebnis beim Hochladen eines Rezepts in die Familien-Cloud.
class CloudRecipePushResult {
  const CloudRecipePushResult({this.skippedImageUrl = false});

  /// True, wenn die Cloud-Spalte image_url noch fehlt.
  final bool skippedImageUrl;
}

/// Synchronisiert Rezepte und Einkaufsliste über Supabase (kostenlose Cloud).
/// Ohne Cloud-Daten in den Einstellungen bleibt alles nur lokal auf dem Gerät.
class FamilySyncService {
  FamilySyncService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Hinweis, wenn Vorschaubilder noch nicht in der Cloud landen können.
  static const imageUrlMigrationHint =
      'Vorschaubild ist lokal gespeichert, aber noch nicht in der Cloud. '
      'Bitte einmal in Supabase (SQL Editor) ausführen:\n'
      'alter table recipes add column if not exists image_url text;\n'
      'Danach Rezept erneut speichern oder „Verbinden & Sync“.';

  FamilyConfig _cfg(FamilyConfig config) => config.withEffectiveCloud();

  Uri _rest(
    FamilyConfig config,
    String table, {
    Map<String, String>? query,
  }) {
    final cloud = _cfg(config);
    final base = cloud.effectiveSupabaseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/rest/v1/$table').replace(
      queryParameters: query,
    );
  }

  Map<String, String> _headers(FamilyConfig config, {bool preferReturn = false}) {
    final key = _cfg(config).effectiveSupabaseAnonKey;
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

  Future<CloudRecipePushResult> pushRecipe(
    FamilyConfig config,
    Recipe recipe,
  ) async {
    if (!config.hasEffectiveCloud) {
      return const CloudRecipePushResult();
    }
    final omitted = <String>{};
    final response = await _upsertRecipes(
      config,
      recipe.toCloud(familyCode: config.familyCode),
      preferReturn: true,
      omitted: omitted,
    );
    _ensureOk(response, 'Rezept konnte nicht in die Cloud gespeichert werden.');
    return CloudRecipePushResult(
      skippedImageUrl: omitted.contains('image_url'),
    );
  }

  Future<void> deleteRecipe(FamilyConfig config, String recipeId) async {
    if (!config.hasEffectiveCloud) return;
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
    if (!config.hasEffectiveCloud) return [];
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
    if (!config.hasEffectiveCloud) return;
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
    if (!config.hasEffectiveCloud) return;
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
    if (!config.hasEffectiveCloud) return [];
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

  Future<CloudRecipePushResult> pushAllRecipes(
    FamilyConfig config,
    List<Recipe> recipes,
  ) async {
    if (!config.hasEffectiveCloud || recipes.isEmpty) {
      return const CloudRecipePushResult();
    }
    final payload =
        recipes.map((r) => r.toCloud(familyCode: config.familyCode)).toList();
    final omitted = <String>{};
    final response = await _upsertRecipes(
      config,
      payload,
      preferReturn: false,
      omitted: omitted,
    );
    _ensureOk(response, 'Rezepte konnten nicht synchronisiert werden.');
    return CloudRecipePushResult(
      skippedImageUrl: omitted.contains('image_url'),
    );
  }

  Future<void> pushAllShoppingItems(
    FamilyConfig config,
    List<ShoppingItem> items,
  ) async {
    if (!config.hasEffectiveCloud || items.isEmpty) return;
    final response = await _client.post(
      _rest(config, 'shopping_items', query: {'on_conflict': 'id'}),
      headers: _headers(config),
      body: jsonEncode(
        items.map((e) => e.toCloud(familyCode: config.familyCode)).toList(),
      ),
    );
    _ensureOk(response, 'Einkaufsliste konnte nicht synchronisiert werden.');
  }

  Future<void> pushMealPlanEntry(
    FamilyConfig config,
    MealPlanEntry entry,
  ) async {
    if (!config.hasEffectiveCloud) return;
    final response = await _client.post(
      _rest(config, 'meal_plan_entries', query: {'on_conflict': 'id'}),
      headers: _headers(config, preferReturn: true),
      body: jsonEncode(entry.toCloud(familyCode: config.familyCode)),
    );
    _ensureOk(
      response,
      'Wochenplan konnte nicht in die Cloud gespeichert werden.',
    );
  }

  Future<void> deleteMealPlanEntry(FamilyConfig config, String entryId) async {
    if (!config.hasEffectiveCloud) return;
    final uri = _rest(
      config,
      'meal_plan_entries',
      query: {
        'id': 'eq.$entryId',
        'family_code': 'eq.${config.familyCode}',
      },
    );
    final response = await _client.delete(uri, headers: _headers(config));
    _ensureOk(
      response,
      'Wochenplan-Eintrag konnte in der Cloud nicht gelöscht werden.',
    );
  }

  Future<List<MealPlanEntry>> pullMealPlanEntries(FamilyConfig config) async {
    if (!config.hasEffectiveCloud) return [];
    final uri = _rest(
      config,
      'meal_plan_entries',
      query: {
        'family_code': 'eq.${config.familyCode}',
        'order': 'date.asc',
      },
    );
    final response = await _client.get(uri, headers: _headers(config));
    _ensureOk(
      response,
      'Wochenplan konnte nicht aus der Cloud geladen werden.',
    );
    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => MealPlanEntry.fromCloud(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> pushAllMealPlanEntries(
    FamilyConfig config,
    List<MealPlanEntry> entries,
  ) async {
    if (!config.hasEffectiveCloud || entries.isEmpty) return;
    final response = await _client.post(
      _rest(config, 'meal_plan_entries', query: {'on_conflict': 'id'}),
      headers: _headers(config),
      body: jsonEncode(
        entries.map((e) => e.toCloud(familyCode: config.familyCode)).toList(),
      ),
    );
    _ensureOk(response, 'Wochenplan konnte nicht synchronisiert werden.');
  }

  Future<String?> testConnection(FamilyConfig config) async {
    if (!config.hasEffectiveCloud) {
      return 'Cloud-Adresse oder Schlüssel fehlen.';
    }
    try {
      // Bevorzugt den offiziellen Supabase-Client (nach Supabase.initialize).
      try {
        final client = Supabase.instance.client;
        await client
            .from('recipes')
            .select('id')
            .eq('family_code', _cfg(config).familyCode)
            .limit(1)
            .timeout(const Duration(seconds: 12));
        return await _checkImageUrlColumn(config);
      } catch (_) {
        // Fallback: direkte REST-Anfrage (z. B. in Tests ohne initialize).
      }

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
        final imageError = await _checkImageUrlColumn(config);
        return imageError;
      }
      final body = response.body.toLowerCase();
      if (response.statusCode == 404 &&
          (body.contains('pgrst205') || body.contains('could not find the table'))) {
        return 'Cloud ist erreichbar, aber die Tabellen fehlen noch. '
            'Bitte in Supabase einmalig die Datei supabase/schema.sql '
            'im SQL-Editor ausführen (Run).';
      }
      return 'Cloud antwortet mit Code ${response.statusCode}. '
          'Prüfe URL, Schlüssel und Tabellen (schema.sql).';
    } catch (e) {
      final text = e.toString().toLowerCase();
      if (text.contains('pgrst205') || text.contains('could not find the table')) {
        return 'Cloud ist erreichbar, aber die Tabellen fehlen noch. '
            'Bitte in Supabase einmalig die Datei supabase/schema.sql '
            'im SQL-Editor ausführen (Run).';
      }
      return 'Keine Verbindung zur Cloud: $e';
    }
  }

  /// Prüft, ob die Spalte für Vorschaubilder in der Cloud existiert.
  Future<String?> _checkImageUrlColumn(FamilyConfig config) async {
    final uri = _rest(
      config,
      'recipes',
      query: {
        'select': 'image_url',
        'limit': '1',
      },
    );
    final response = await _client
        .get(uri, headers: _headers(config))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return null;
    }
    if (_looksLikeMissingColumn(response.body)) {
      return 'Cloud ist verbunden, aber Vorschaubilder fehlen noch. '
          'Bitte einmal in Supabase (SQL Editor) ausführen:\n'
          'alter table recipes add column if not exists image_url text;';
    }
    return null;
  }

  void _ensureOk(http.Response response, String message) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = response.body.trim();
      final suffix = detail.isEmpty ? '' : ': $detail';
      throw Exception('$message (${response.statusCode})$suffix');
    }
  }

  /// Cloud-Fehler, die das lokale Speichern nicht blockieren sollen.
  /// Typisch: neue Spalte (Vorschaubild) fehlt noch in Supabase.
  static bool isIgnorableSchemaError(Object error) {
    return _looksLikeMissingColumn(error.toString());
  }

  Future<http.Response> _upsertRecipes(
    FamilyConfig config,
    Object payload, {
    required bool preferReturn,
    required Set<String> omitted,
  }) async {
    // Jeder Speichern-Versuch startet mit allen Spalten (auch image_url).
    // So landen Vorschaubilder automatisch in der Cloud, sobald die Spalte
    // einmal in Supabase angelegt wurde — ohne App-Neustart.
    Object current = _stripOmittedColumns(payload, omitted);
    var response = await _client.post(
      _rest(config, 'recipes', query: {'on_conflict': 'id'}),
      headers: _headers(config, preferReturn: preferReturn),
      body: jsonEncode(current),
    );

    for (var i = 0; i < 6; i++) {
      final missing = _missingRecipeColumn(response, omitted);
      if (missing == null || omitted.contains(missing)) {
        break;
      }
      omitted.add(missing);
      current = _stripOmittedColumns(payload, omitted);
      response = await _client.post(
        _rest(config, 'recipes', query: {'on_conflict': 'id'}),
        headers: _headers(config, preferReturn: preferReturn),
        body: jsonEncode(current),
      );
    }
    return response;
  }

  Object _stripOmittedColumns(Object payload, Set<String> omitted) {
    Map<String, dynamic> stripRow(Map<dynamic, dynamic> row) {
      final copy = Map<String, dynamic>.from(row);
      for (final column in omitted) {
        copy.remove(column);
      }
      return copy;
    }

    if (payload is List) {
      return payload
          .map((row) => stripRow(Map<dynamic, dynamic>.from(row as Map)))
          .toList();
    }
    return stripRow(Map<dynamic, dynamic>.from(payload as Map));
  }

  String? _missingRecipeColumn(http.Response response, Set<String> omitted) {
    if (response.statusCode < 400) return null;
    final body = response.body.toLowerCase();
    if (!_looksLikeMissingColumn(body)) return null;

    final quoted = RegExp(
      "could not find the ['\"]([a-z0-9_]+)['\"] column",
    ).firstMatch(body);
    if (quoted != null) return quoted.group(1);

    final pg = RegExp(r'column recipes\.([a-z0-9_]+)').firstMatch(body);
    if (pg != null) return pg.group(1);

    for (final column in const ['image_url', 'categories']) {
      if (body.contains(column) && !omitted.contains(column)) {
        return column;
      }
    }
    for (final column in const ['image_url', 'categories']) {
      if (!omitted.contains(column)) return column;
    }
    return null;
  }

  static bool _looksLikeMissingColumn(String text) {
    final body = text.toLowerCase();
    return body.contains('pgrst204') ||
        body.contains('42703') ||
        body.contains('schema cache') ||
        (body.contains('could not find') && body.contains('column')) ||
        (body.contains('does not exist') && body.contains('column'));
  }
}
