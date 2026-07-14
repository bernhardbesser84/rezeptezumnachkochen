import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../models/recipe.dart';
import '../services/app_repository.dart';
import '../services/recipe_extractor.dart';
import '../theme/app_theme.dart';
import '../utils/platform_hints.dart';
import 'add_recipe_screen.dart';
import 'family_screen.dart';
import 'recipe_detail_screen.dart';
import 'settings_screen.dart';
import 'shopping_list_screen.dart';
import 'web_install_screen.dart';

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
  StreamSubscription<Uri>? _linkSub;
  final _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _listenForShares();
    _listenForAppLinks();
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
      _handleSharedFiles(files);
      ReceiveSharingIntent.instance.reset();
    }).catchError((_) {});

    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) {
        _handleSharedFiles(files);
        ReceiveSharingIntent.instance.reset();
      },
      onError: (_) {},
    );
  }

  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;

    String? text;
    Uint8List? videoBytes;
    String? videoMime;
    String? videoName;

    final textParts = <String>[];
    for (final file in files) {
      final path = file.path.trim();
      if (path.isEmpty) continue;

      final isVideo = file.type == SharedMediaType.video ||
          path.toLowerCase().endsWith('.mp4') ||
          path.toLowerCase().endsWith('.mov') ||
          path.toLowerCase().endsWith('.m4v') ||
          path.toLowerCase().endsWith('.webm');

      if (isVideo && !kIsWeb) {
        try {
          final data = await XFile(path).readAsBytes();
          if (data.isNotEmpty && data.length < 18 * 1024 * 1024) {
            videoBytes = data;
            videoMime = path.toLowerCase().endsWith('.webm')
                ? 'video/webm'
                : path.toLowerCase().endsWith('.mov')
                    ? 'video/quicktime'
                    : 'video/mp4';
            videoName = path.split('/').last;
          }
        } catch (_) {}
      } else if (file.type == SharedMediaType.text ||
          path.startsWith('http') ||
          !isVideo) {
        textParts.add(path);
      }
    }

    if (textParts.isNotEmpty) {
      text = textParts.join('\n');
    }

    if (text == null && videoBytes == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openAddScreen(
        initialSharedText: text,
        initialVideoBytes: videoBytes,
        initialVideoMimeType: videoMime,
        initialVideoName: videoName,
      );
    });
  }

  /// Für iPhone-Kurzbefehle: rezeptnachkochen://add?text=...
  void _listenForAppLinks() {
    _appLinks.getInitialLink().then((uri) {
      _handleAppLink(uri);
    }).catchError((_) {});

    _linkSub = _appLinks.uriLinkStream.listen(
      _handleAppLink,
      onError: (_) {},
    );
  }

  void _handleAppLink(Uri? uri) {
    if (uri == null) return;
    if (uri.scheme != 'rezeptnachkochen') return;

    final text = uri.queryParameters['text'] ??
        uri.queryParameters['url'] ??
        uri.queryParameters['link'] ??
        '';
    if (text.trim().isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openAddScreen(initialSharedText: text.trim());
    });
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

  Future<void> _openAddScreen({
    String? initialSharedText,
    Uint8List? initialVideoBytes,
    String? initialVideoMimeType,
    String? initialVideoName,
  }) async {
    final recipe = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute(
        builder: (_) => AddRecipeScreen(
          repository: widget.repository,
          extractor: widget.extractor,
          initialSharedText: initialSharedText,
          initialVideoBytes: initialVideoBytes,
          initialVideoMimeType: initialVideoMimeType,
          initialVideoName: initialVideoName,
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
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.accentSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                color: AppTheme.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Rezept Nachkochen'),
          ],
        ),
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
        icon: const Icon(Icons.add_rounded),
        label: Text(
          PlatformHints.isWeb ? 'Link einfügen' : 'Video teilen / Link',
        ),
      ),
      body: DecoratedBox(
        decoration: AppTheme.pageBackdrop(),
        child: CustomPaint(
          painter: KitchenDotsPainter(),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  color: AppTheme.seed,
                  onRefresh: _reload,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                    children: [
                      if (PlatformHints.isWeb) ...[
                        _WebInstallBanner(
                          onOpenHelp: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const WebInstallScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                      ],
                      _HeroBanner(onAdd: () => _openAddScreen()),
                      const SizedBox(height: 16),
                      _FamilyStatusCard(
                        cloudReady: _cloudReady,
                        familyCode: _familyCode,
                        openShopping: _openShoppingCount,
                        onFamily: _openFamily,
                        onShopping: _openShopping,
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Text(
                            'Eure Rezepte',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Spacer(),
                          Text(
                            '${_recipes.length}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: AppTheme.seed,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_recipes.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: AppTheme.seed.withValues(alpha: 0.12),
                            ),
                          ),
                          child: const Column(
                            children: [
                              Icon(
                                Icons.restaurant_menu_rounded,
                                size: 40,
                                color: AppTheme.seedSoft,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Noch keine Rezepte gespeichert.\n'
                                'Teile ein Video oder füge einen Link ein.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      else
                        ..._recipes.asMap().entries.map(
                              (entry) => _RecipeCard(
                                recipe: entry.value,
                                tintIndex: entry.key,
                                onTap: () => _openDetail(entry.value),
                              ),
                            ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _WebInstallBanner extends StatelessWidget {
  const _WebInstallBanner({required this.onOpenHelp});

  final VoidCallback onOpenHelp;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'iPhone ohne App Store',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Du kannst diese Web-App dauerhaft auf den Home-Bildschirm legen – '
            'kostenlos, ohne Apple-Abo.',
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onOpenHelp,
            child: const Text('So füge ich sie hinzu'),
          ),
        ],
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - value)),
              child: child,
            ),
          );
        },
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF1B5E40),
                    Color(0xFF2F8B5C),
                    Color(0xFF4FA37A),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rezept Nachkochen',
                    style: GoogleFonts.sora(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      height: 1.12,
                      letterSpacing: -0.7,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Vom Video zum Familien-Rezept — teilen, nachkochen, einkaufen.',
                    style: GoogleFonts.nunitoSans(
                      color: Colors.white.withValues(alpha: 0.92),
                      height: 1.4,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.seed,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
                    onPressed: onAdd,
                    child: const Text('Jetzt Rezept hinzufügen'),
                  ),
                ],
              ),
            ),
            Positioned(
              right: -30,
              top: -20,
              child: IgnorePointer(
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 40,
              bottom: -40,
              child: IgnorePointer(
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.accent.withValues(alpha: 0.18),
                  ),
                ),
              ),
            ),
          ],
        ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.seed.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cloudReady
                      ? AppTheme.seed.withValues(alpha: 0.12)
                      : AppTheme.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  cloudReady ? Icons.check_circle_outline : Icons.groups_2_outlined,
                  color: cloudReady ? AppTheme.seed : AppTheme.accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  cloudReady
                      ? 'Familie verbunden${familyCode == null || familyCode!.isEmpty ? '' : ' · $familyCode'}'
                      : 'Familie noch nicht für alle Geräte verbunden',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            cloudReady
                ? 'Rezepte und Einkaufsliste werden zwischen iPhone, '
                    'Tablett und Galaxy geteilt.'
                : 'Tippe auf „Familie“, erstelle einen Code und trage die '
                    'Cloud-Daten ein – dann sehen alle dasselbe.',
          ),
          const SizedBox(height: 14),
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
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({
    required this.recipe,
    required this.onTap,
    required this.tintIndex,
  });

  final Recipe recipe;
  final VoidCallback onTap;
  final int tintIndex;

  static const _tints = [
    Color(0xFFFFFFFF),
    Color(0xFFF4FAF6),
    Color(0xFFFFF7F3),
  ];

  @override
  Widget build(BuildContext context) {
    final tint = _tints[tintIndex % _tints.length];
    final barColor =
        tintIndex.isEven ? AppTheme.seed : AppTheme.accent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: tint,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.seed.withValues(alpha: 0.1)),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 7,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(20),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  recipe.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${recipe.ingredients.length} Zutaten · '
                                  '${recipe.steps.length} Schritte'
                                  '${recipe.sourceUrl.isEmpty ? '' : ' · Video'}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: AppTheme.seed.withValues(alpha: 0.55),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
