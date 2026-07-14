import '../models/family_config.dart';
import '../models/recipe.dart';
import '../models/shopping_item.dart';
import 'family_sync_service.dart';
import 'google_backup_service.dart';
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

  Future<FamilyConfig?> family() => storage.loadFamilyConfig();

  Future<List<Recipe>> loadRecipes({bool pullRemote = true}) async {
    final config = await storage.loadFamilyConfig();
    if (pullRemote && config != null && config.hasCloud) {
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
    final config = await storage.loadFamilyConfig();
    if (config != null && config.hasCloud) {
      await sync.pushRecipe(config, recipe);
    }
    await _backupQuietly();
  }

  Future<void> deleteRecipe(String id) async {
    await storage.deleteRecipe(id);
    final config = await storage.loadFamilyConfig();
    if (config != null && config.hasCloud) {
      await sync.deleteRecipe(config, id);
    }
    await _backupQuietly();
  }

  Future<List<ShoppingItem>> loadShopping({bool pullRemote = true}) async {
    final config = await storage.loadFamilyConfig();
    if (pullRemote && config != null && config.hasCloud) {
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
    final config = await storage.loadFamilyConfig();
    if (config != null && config.hasCloud) {
      await sync.pushShoppingItem(config, updated);
    }
    await _backupQuietly();
  }

  Future<void> deleteShoppingItem(String id) async {
    await storage.deleteShoppingItem(id);
    final config = await storage.loadFamilyConfig();
    if (config != null && config.hasCloud) {
      await sync.deleteShoppingItem(config, id);
    }
    await _backupQuietly();
  }

  Future<void> clearCheckedShopping() async {
    final items = await storage.loadShoppingItems();
    final checked = items.where((e) => e.checked).toList();
    await storage.clearCheckedShoppingItems();
    final config = await storage.loadFamilyConfig();
    if (config != null && config.hasCloud) {
      for (final item in checked) {
        await sync.deleteShoppingItem(config, item.id);
      }
    }
    await _backupQuietly();
  }

  Future<int> addRecipeToShopping(Recipe recipe) async {
    final added = await storage.addRecipeIngredientsToShopping(recipe);
    final config = await storage.loadFamilyConfig();
    if (config != null && config.hasCloud) {
      for (final item in added) {
        await sync.pushShoppingItem(config, item);
      }
    }
    await _backupQuietly();
    return added.length;
  }

  Future<void> saveFamily(FamilyConfig config) async {
    await storage.saveFamilyConfig(config);
    await _backupQuietly();
  }

  Future<void> fullSync() async {
    final config = await storage.loadFamilyConfig();
    if (config == null || !config.hasCloud) return;

    final localRecipes = await storage.loadRecipes();
    final localShopping = await storage.loadShoppingItems();

    final remoteRecipes = await sync.pullRecipes(config);
    final remoteShopping = await sync.pullShoppingItems(config);

    final mergedRecipes = _mergeRecipes(localRecipes, remoteRecipes);
    final mergedShopping = _mergeShopping(localShopping, remoteShopping);

    await storage.saveRecipes(mergedRecipes);
    await storage.saveShoppingItems(mergedShopping);

    await sync.pushAllRecipes(config, mergedRecipes);
    await sync.pushAllShoppingItems(config, mergedShopping);
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
}
