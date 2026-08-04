import '../models/family_config.dart';
import '../models/family_config_cloud.dart';
import '../models/meal_plan_entry.dart';
import '../models/recipe.dart';
import '../models/shopping_item.dart';
import 'family_sync_service.dart';
import 'google_backup_service.dart';
import 'recipe_category_service.dart';
import 'recipe_storage.dart';

/// Verbindet lokales Speichern und optionalen Cloud-Sync für die Familie.
class AppRepository {
  AppRepository({
    required this.storage,
    required this.sync,
    this.googleBackup,
  });

  final RecipeStorage storage;
  final FamilySyncService sync;
  final GoogleBackupService? googleBackup;

  Future<FamilyConfig?> family() async {
    final config = await storage.loadFamilyConfig();
    if (config == null) return null;
    return config.withEffectiveCloud();
  }

  FamilyConfig? _cloud(FamilyConfig? config) {
    if (config == null) return null;
    return config.withEffectiveCloud();
  }

  Future<List<Recipe>> loadRecipes({bool pullRemote = true}) async {
    final config = _cloud(await storage.loadFamilyConfig());
    if (pullRemote && config != null && config.hasEffectiveCloud) {
      try {
        final remote = await sync.pullRecipes(config);
        if (remote.isNotEmpty) {
          await storage.saveRecipes(remote);
          return remote;
        }
      } catch (_) {
        // Offline oder Cloud-Fehler: lokale Daten weiter nutzen
      }
    }
    return storage.loadRecipes();
  }

  Future<void> saveRecipe(Recipe recipe) async {
    await storage.upsertRecipe(recipe);
    final config = _cloud(await storage.loadFamilyConfig());
    if (config != null && config.hasEffectiveCloud) {
      await sync.pushRecipe(config, recipe);
    }
    await _backupQuietly();
  }

  Future<void> deleteRecipe(String id) async {
    await storage.deleteRecipe(id);
    final config = _cloud(await storage.loadFamilyConfig());
    if (config != null && config.hasEffectiveCloud) {
      await sync.deleteRecipe(config, id);
    }
    await _backupQuietly();
  }

  /// Alle bekannten Kategorien (gespeicherte + aus Rezepten).
  Future<List<String>> loadCategories({bool pullRemote = false}) async {
    final recipes = await loadRecipes(pullRemote: pullRemote);
    final known = await storage.loadKnownCategories();
    final merged = RecipeCategoryService.mergeCatalog(
      known: known,
      recipes: recipes,
    );
    // Katalog aktuell halten (neue Kategorien aus Rezepten übernehmen).
    await storage.saveKnownCategories(merged);
    return merged;
  }

  Future<void> createCategory(String name) async {
    final normalized = RecipeCategoryService.normalizeOne(name);
    if (normalized == null) {
      throw Exception('Bitte einen gültigen Kategorienamen eingeben.');
    }
    if (normalized == RecipeCategoryService.allRecipesLabel) {
      throw Exception('„Alle Rezepte“ ist fest und kann nicht angelegt werden.');
    }
    final categories = await loadCategories(pullRemote: false);
    if (categories.any((c) => c.toLowerCase() == normalized.toLowerCase())) {
      throw Exception('Diese Kategorie gibt es schon.');
    }
    await storage.saveKnownCategories([...categories, normalized]..sort(
          (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
        ));
    await _backupQuietly();
  }

  Future<int> renameCategory({
    required String oldName,
    required String newName,
  }) async {
    final from = RecipeCategoryService.normalizeOne(oldName);
    final to = RecipeCategoryService.normalizeOne(newName);
    if (from == null || to == null) {
      throw Exception('Bitte einen gültigen Kategorienamen eingeben.');
    }
    if (from == to) return 0;

    final categories = await loadCategories(pullRemote: false);
    if (!categories.contains(from)) {
      throw Exception('Kategorie wurde nicht gefunden.');
    }
    if (categories.any((c) => c != from && c.toLowerCase() == to.toLowerCase())) {
      throw Exception('Der neue Name ist schon vergeben.');
    }

    final recipes = await storage.loadRecipes();
    var changed = 0;
    for (final recipe in recipes) {
      final updated = RecipeCategoryService.renameCategoryOnRecipe(
        recipe: recipe,
        oldName: from,
        newName: to,
      );
      if (updated.categories.join('|') != recipe.categories.join('|')) {
        await saveRecipe(updated);
        changed++;
      }
    }

    final next = categories.map((c) => c == from ? to : c).toList();
    await storage.saveKnownCategories(
      RecipeCategoryService.normalizeAll(next)
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
    );
    await _backupQuietly();
    return changed;
  }

  Future<int> deleteCategory(String name) async {
    final target = RecipeCategoryService.normalizeOne(name);
    if (target == null) {
      throw Exception('Bitte eine Kategorie auswählen.');
    }

    final recipes = await storage.loadRecipes();
    var changed = 0;
    for (final recipe in recipes) {
      final updated = RecipeCategoryService.removeCategoryFromRecipe(
        recipe: recipe,
        category: target,
      );
      if (updated.categories.length != recipe.categories.length) {
        await saveRecipe(updated);
        changed++;
      }
    }

    final categories = await loadCategories(pullRemote: false);
    await storage.saveKnownCategories(
      categories.where((c) => c != target).toList(),
    );
    await _backupQuietly();
    return changed;
  }

  Future<List<ShoppingItem>> loadShopping({bool pullRemote = true}) async {
    final config = _cloud(await storage.loadFamilyConfig());
    if (pullRemote && config != null && config.hasEffectiveCloud) {
      try {
        final remote = await sync.pullShoppingItems(config);
        await storage.saveShoppingItems(remote);
        return remote;
      } catch (_) {
        // lokale Liste behalten
      }
    }
    return storage.loadShoppingItems();
  }

  Future<void> setShoppingChecked(ShoppingItem item, bool checked) async {
    final updated = item.copyWith(
      checked: checked,
      updatedAt: DateTime.now(),
    );
    await storage.upsertShoppingItem(updated);
    final config = _cloud(await storage.loadFamilyConfig());
    if (config != null && config.hasEffectiveCloud) {
      await sync.pushShoppingItem(config, updated);
    }
    await _backupQuietly();
  }

  Future<void> deleteShoppingItem(String id) async {
    await storage.deleteShoppingItem(id);
    final config = _cloud(await storage.loadFamilyConfig());
    if (config != null && config.hasEffectiveCloud) {
      await sync.deleteShoppingItem(config, id);
    }
    await _backupQuietly();
  }

  Future<void> clearCheckedShopping() async {
    final items = await storage.loadShoppingItems();
    final checked = items.where((e) => e.checked).toList();
    await storage.clearCheckedShoppingItems();
    final config = _cloud(await storage.loadFamilyConfig());
    if (config != null && config.hasEffectiveCloud) {
      for (final item in checked) {
        await sync.deleteShoppingItem(config, item.id);
      }
    }
    await _backupQuietly();
  }

  Future<int> addRecipeToShopping(Recipe recipe) async {
    final added = await storage.addRecipeIngredientsToShopping(recipe);
    final config = _cloud(await storage.loadFamilyConfig());
    if (config != null && config.hasEffectiveCloud) {
      for (final item in added) {
        await sync.pushShoppingItem(config, item);
      }
    }
    await _backupQuietly();
    return added.length;
  }

  Future<List<MealPlanEntry>> loadMealPlan({bool pullRemote = true}) async {
    final config = _cloud(await storage.loadFamilyConfig());
    if (pullRemote && config != null && config.hasEffectiveCloud) {
      try {
        final remote = await sync.pullMealPlanEntries(config);
        await storage.saveMealPlanEntries(remote);
        return remote;
      } catch (_) {
        // lokale Liste behalten (z. B. wenn Tabelle noch fehlt)
      }
    }
    return storage.loadMealPlanEntries();
  }

  Future<MealPlanEntry> setMealPlanDay({
    required DateTime date,
    required Recipe recipe,
  }) async {
    final entry = await storage.setMealPlanForDate(date: date, recipe: recipe);
    final config = _cloud(await storage.loadFamilyConfig());
    if (config != null && config.hasEffectiveCloud) {
      try {
        await sync.pushMealPlanEntry(config, entry);
      } catch (_) {
        // Cloud optional – lokal bleibt gespeichert
      }
    }
    await _backupQuietly();
    return entry;
  }

  Future<void> clearMealPlanDay(DateTime date) async {
    final removed = await storage.clearMealPlanForDate(date);
    if (removed == null) return;
    final config = _cloud(await storage.loadFamilyConfig());
    if (config != null && config.hasEffectiveCloud) {
      try {
        await sync.deleteMealPlanEntry(config, removed.id);
      } catch (_) {}
    }
    await _backupQuietly();
  }

  /// Alle geplanten Rezepte einer Woche auf die Einkaufsliste setzen.
  Future<int> addWeekRecipesToShopping(List<MealPlanEntry> weekEntries) async {
    final recipes = await storage.loadRecipes();
    final byId = {for (final r in recipes) r.id: r};
    var total = 0;
    final seen = <String>{};
    for (final entry in weekEntries) {
      if (!seen.add(entry.recipeId)) continue;
      final recipe = byId[entry.recipeId];
      if (recipe == null) continue;
      total += await addRecipeToShopping(recipe);
    }
    return total;
  }

  Future<void> saveFamily(FamilyConfig config) async {
    await storage.saveFamilyConfig(config.withEffectiveCloud());
    await _backupQuietly();
  }

  Future<void> fullSync() async {
    final config = _cloud(await storage.loadFamilyConfig());
    if (config == null || !config.hasEffectiveCloud) return;

    final localRecipes = await storage.loadRecipes();
    final localShopping = await storage.loadShoppingItems();
    final localMealPlan = await storage.loadMealPlanEntries();

    final remoteRecipes = await sync.pullRecipes(config);
    final remoteShopping = await sync.pullShoppingItems(config);
    List<MealPlanEntry> remoteMealPlan = const [];
    try {
      remoteMealPlan = await sync.pullMealPlanEntries(config);
    } catch (_) {
      // Tabelle ggf. noch nicht angelegt
    }

    final mergedRecipes = _mergeRecipes(localRecipes, remoteRecipes);
    final mergedShopping = _mergeShopping(localShopping, remoteShopping);
    final mergedMealPlan = _mergeMealPlan(localMealPlan, remoteMealPlan);

    await storage.saveRecipes(mergedRecipes);
    await storage.saveShoppingItems(mergedShopping);
    await storage.saveMealPlanEntries(mergedMealPlan);

    await sync.pushAllRecipes(config, mergedRecipes);
    await sync.pushAllShoppingItems(config, mergedShopping);
    try {
      await sync.pushAllMealPlanEntries(config, mergedMealPlan);
    } catch (_) {}
    await _backupQuietly();
  }

  /// Nach Rezept-/Einstellungsänderungen still zu Google Drive sichern.
  Future<void> _backupQuietly() async {
    final backup = googleBackup;
    if (backup == null) return;
    try {
      await backup.backupIfSignedIn();
    } catch (_) {
      // Backup darf die App-Nutzung nicht blockieren.
    }
  }

  List<Recipe> _mergeRecipes(List<Recipe> local, List<Recipe> remote) {
    final map = <String, Recipe>{};
    for (final recipe in [...remote, ...local]) {
      final existing = map[recipe.id];
      if (existing == null || recipe.createdAt.isAfter(existing.createdAt)) {
        map[recipe.id] = recipe;
      }
    }
    return map.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<ShoppingItem> _mergeShopping(
    List<ShoppingItem> local,
    List<ShoppingItem> remote,
  ) {
    final map = <String, ShoppingItem>{};
    for (final item in [...remote, ...local]) {
      final existing = map[item.id];
      if (existing == null || item.updatedAt.isAfter(existing.updatedAt)) {
        map[item.id] = item;
      }
    }
    return map.values.toList()
      ..sort((a, b) {
        if (a.checked != b.checked) return a.checked ? 1 : -1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  List<MealPlanEntry> _mergeMealPlan(
    List<MealPlanEntry> local,
    List<MealPlanEntry> remote,
  ) {
    // Pro Tag gewinnt der neuere Eintrag.
    final byDate = <String, MealPlanEntry>{};
    for (final entry in [...remote, ...local]) {
      final existing = byDate[entry.dateKey];
      if (existing == null || entry.updatedAt.isAfter(existing.updatedAt)) {
        byDate[entry.dateKey] = entry;
      }
    }
    return byDate.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }
}
