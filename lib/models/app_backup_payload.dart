import 'dart:convert';

import '../models/ai_provider.dart';
import '../models/family_config.dart';
import '../models/meal_plan_entry.dart';
import '../models/recipe.dart';
import '../models/shopping_item.dart';

/// Komplettes App-Backup (Rezepte + Einkauf + Wochenplan + Einstellungen).
class AppBackupPayload {
  AppBackupPayload({
    required this.savedAt,
    required this.recipes,
    required this.shoppingItems,
    required this.aiProvider,
    required this.apiKeys,
    required this.demoSeeded,
    this.mealPlanEntries = const [],
    this.categories = const [],
    this.familyConfig,
    this.version = 3,
  });

  final int version;
  final DateTime savedAt;
  final List<Recipe> recipes;
  final List<ShoppingItem> shoppingItems;
  final List<MealPlanEntry> mealPlanEntries;
  final List<String> categories;
  final FamilyConfig? familyConfig;
  final AiProvider aiProvider;
  final Map<String, String> apiKeys;
  final bool demoSeeded;

  Map<String, dynamic> toJson() => {
        'version': version,
        'savedAt': savedAt.toIso8601String(),
        'recipes': recipes.map((r) => r.toJson()).toList(),
        'shoppingItems': shoppingItems.map((e) => e.toJson()).toList(),
        'mealPlanEntries': mealPlanEntries.map((e) => e.toJson()).toList(),
        'categories': categories,
        'familyConfig': familyConfig?.toJson(),
        'aiProvider': aiProvider.storageValue,
        'apiKeys': apiKeys,
        'demoSeeded': demoSeeded,
      };

  String toJsonString() => jsonEncode(toJson());

  factory AppBackupPayload.fromJson(Map<String, dynamic> json) {
    final keysRaw = json['apiKeys'];
    final keys = <String, String>{};
    if (keysRaw is Map) {
      for (final entry in keysRaw.entries) {
        final value = entry.value?.toString() ?? '';
        if (value.isNotEmpty) keys[entry.key.toString()] = value;
      }
    }

    return AppBackupPayload(
      version: json['version'] as int? ?? 1,
      savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ??
          DateTime.now(),
      recipes: (json['recipes'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Recipe.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      shoppingItems: (json['shoppingItems'] as List? ?? [])
          .whereType<Map>()
          .map((e) => ShoppingItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      mealPlanEntries: (json['mealPlanEntries'] as List? ?? [])
          .whereType<Map>()
          .map((e) => MealPlanEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      categories: (json['categories'] as List? ?? [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      familyConfig: json['familyConfig'] is Map
          ? FamilyConfig.fromJson(
              Map<String, dynamic>.from(json['familyConfig'] as Map),
            )
          : null,
      aiProvider: AiProvider.fromStorage(json['aiProvider'] as String?),
      apiKeys: keys,
      demoSeeded: json['demoSeeded'] as bool? ?? false,
    );
  }

  factory AppBackupPayload.fromJsonString(String raw) {
    return AppBackupPayload.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
