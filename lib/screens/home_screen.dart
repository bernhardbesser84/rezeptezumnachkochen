import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../models/recipe.dart';
import '../services/app_repository.dart';
import '../services/recipe_extractor.dart';
import '../theme/app_theme.dart';
import 'add_recipe_screen.dart';
import 'family_screen.dart';
import 'recipe_detail_screen.dart';
import 'settings_screen.dart';
import 'shopping_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.extractor,
  });

  final AppRepository repository;
  final RecipeExtractor extractor;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Recipe> _recipes = [];
  bool _loading = true;
  bool _cloudReady = false;
  String? _familyCode;
  int _openShoppingCount = 0;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _listenForShares();
  }

  Future<void> _bootstrap() async {
    final storage = widget.repository.storage;
    var recipes = await widget.repository.loadRecipes(pullRemote: true);
    if (recipes.isEmpty && !(await storage.wasDemoSeeded())) {
      final demo = widget.extractor.buildDemoRecipe();
      await widget.repository.saveRecipe(demo);
      await storage.markDemoSeeded();
      recipes = [demo];
    }
    final family = await widget.repository.family();
    final shopping = await widget.repository.loadShopping(pullRemote: true);
    if (mounted) {
      setState(() {
        _recipes = recipes;
        _cloudReady = family?.hasCloud ?? false;
        _familyCode = family?.familyCode;
        _openShoppingCount = shopping.where((e) => !e.checked).length;
        _loading = false;
      });
    }
  }

  void _listenForShares() {
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      final text = _sharedTextFrom(files);
      if (text != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _openAddScreen(initialSharedText: text);
        });
        ReceiveSharingIntent.instance.reset();
      }
    }).catchError((_) {});

    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) {
        final text = _sharedTextFrom(files);
        if (text != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _openAddScreen(initialSharedText: text);
          });
          ReceiveSharingIntent.instance.reset();
        }
      },
      onError: (_) {},
    );
  }

  String? _sharedTextFrom(List<SharedMediaFile> files) {
    if (files.isEmpty) return null;
    final parts = files
        .map((f) => f.path.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    return parts.join('\n');
  }

  Future<void> _reload() async {
    final recipes = await widget.repository.loadRecipes(pullRemote: true);
    final family = await widget.repository.family();
    final shopping = await widget.repository.loadShopping(pullRemote: true);
    if (mounted) {
      setState(() {
        _recipes = recipes;
        _cloudReady = family?.hasCloud ?? false;
        _familyCode = family?.familyCode;
        _openShoppingCount = shopping.where((e) => !e.checked).length;
      });
    }
  }

  Future<void> _openAddScreen({String? initialSharedText}) async {
    final recipe = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute(
        builder: (_) => AddRecipeScreen(
          repository: widget.repository,
          extractor: widget.extractor,
          initialSharedText: initialSharedText,
        ),
      ),
    );
    await _reload();
    if (recipe != null && mounted) {
      await _openDetail(recipe);
    }
  }

  Future<void> _openDetail(Recipe recipe) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen(
          recipe: recipe,
          repository: widget.repository,
          onDelete: () async {
            await widget.repository.deleteRecipe(recipe.id);
            await _reload();
          },
        ),
      ),
    );
    await _reload();
  }

  Future<void> _openShopping() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShoppingListScreen(repository: widget.repository),
      ),
    );
    await _reload();
  }

  Future<void> _openFamily() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FamilyScreen(repository: widget.repository),
      ),
    );
    await _reload();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(repository: widget.repository),
      ),
    );
    await _reload();
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rezept Nachkochen'),
        actions: [
          IconButton(
            tooltip: 'Familie',
            onPressed: _openFamily,
            icon: const Icon(Icons.home_outlined),
          ),
          IconButton(
            tooltip: 'Einstellungen',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddScreen(),
        icon: const Icon(Icons.add),
        label: const Text('Video teilen / Link'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                children: [
                  _HeroBanner(onAdd: () => _openAddScreen()),
                  const SizedBox(height: 12),
                  _FamilyStatusCard(
                    cloudReady: _cloudReady,
                    familyCode: _familyCode,
                    openShopping: _openShoppingCount,
                    onFamily: _openFamily,
                    onShopping: _openShopping,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Eure Rezepte',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  if (_recipes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Text(
                        'Noch keine Rezepte gespeichert.\n'
                        'Teile ein Video oder füge einen Link ein.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ..._recipes.map(
                      (recipe) => _RecipeCard(
                        recipe: recipe,
                        onTap: () => _openDetail(recipe),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2F6F4E), Color(0xFF4C8B68)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vom Video zum Familien-Rezept',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Am iPhone teilen, am Tablett nachkochen, am Galaxy '
            'die Einkaufsliste abhaken.',
            style: TextStyle(color: Colors.white, height: 1.35),
          ),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.seed,
            ),
            onPressed: onAdd,
            child: const Text('Jetzt Rezept hinzufügen'),
          ),
        ],
      ),
    );
  }
}

class _FamilyStatusCard extends StatelessWidget {
  const _FamilyStatusCard({
    required this.cloudReady,
    required this.familyCode,
    required this.openShopping,
    required this.onFamily,
    required this.onShopping,
  });

  final bool cloudReady;
  final String? familyCode;
  final int openShopping;
  final VoidCallback onFamily;
  final VoidCallback onShopping;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cloudReady
                  ? 'Familie verbunden${familyCode == null || familyCode!.isEmpty ? '' : ' · $familyCode'}'
                  : 'Familie noch nicht für alle Geräte verbunden',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              cloudReady
                  ? 'Rezepte und Einkaufsliste werden zwischen iPhone, '
                      'Tablett und Galaxy geteilt.'
                  : 'Tippe auf „Familie“, erstelle einen Code und trage die '
                      'Cloud-Daten ein – dann sehen alle dasselbe.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onFamily,
                    child: const Text('Familie'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: onShopping,
                    child: Text(
                      openShopping > 0
                          ? 'Einkauf ($openShopping)'
                          : 'Einkaufsliste',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe, required this.onTap});

  final Recipe recipe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          recipe.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${recipe.ingredients.length} Zutaten · '
            '${recipe.steps.length} Schritte'
            '${recipe.sourceUrl.isEmpty ? '' : ' · Video'}',
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
