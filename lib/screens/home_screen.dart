import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../models/recipe.dart';
import '../services/recipe_extractor.dart';
import '../services/recipe_storage.dart';
import '../theme/app_theme.dart';
import 'add_recipe_screen.dart';
import 'recipe_detail_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.storage,
    required this.extractor,
  });

  final RecipeStorage storage;
  final RecipeExtractor extractor;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Recipe> _recipes = [];
  bool _loading = true;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _listenForShares();
  }

  Future<void> _bootstrap() async {
    final recipes = await widget.storage.loadRecipes();
    if (recipes.isEmpty && !(await widget.storage.wasDemoSeeded())) {
      final demo = widget.extractor.buildDemoRecipe();
      await widget.storage.upsertRecipe(demo);
      await widget.storage.markDemoSeeded();
      _recipes = [demo];
    } else {
      _recipes = recipes;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _listenForShares() {
    // App war geschlossen und wurde über Teilen geöffnet
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      final text = _sharedTextFrom(files);
      if (text != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _openAddScreen(initialSharedText: text);
        });
        ReceiveSharingIntent.instance.reset();
      }
    }).catchError((_) {
      // z. B. in Tests / ohne nativen Plugin-Support
    });

    // App läuft bereits und bekommt etwas geteilt
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
    final recipes = await widget.storage.loadRecipes();
    if (mounted) setState(() => _recipes = recipes);
  }

  Future<void> _openAddScreen({String? initialSharedText}) async {
    final recipe = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute(
        builder: (_) => AddRecipeScreen(
          storage: widget.storage,
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
          onDelete: () async {
            await widget.storage.deleteRecipe(recipe.id);
            await _reload();
          },
        ),
      ),
    );
    await _reload();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(storage: widget.storage),
      ),
    );
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
                  const SizedBox(height: 20),
                  Text(
                    'Deine Rezepte',
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
            'Vom Video zur Einkaufsliste',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Teile Rezeptvideos aus Facebook & Co. – und bekomme '
            'Zutaten plus Schritt-für-Schritt-Anleitung.',
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
            '${recipe.steps.length} Schritte',
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
