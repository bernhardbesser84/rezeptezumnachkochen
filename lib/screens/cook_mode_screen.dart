import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/recipe.dart';
import '../theme/app_theme.dart';

/// Große Ansicht zum Nachkochen am Tablett: Video + große Schritte.
class CookModeScreen extends StatefulWidget {
  const CookModeScreen({super.key, required this.recipe});

  final Recipe recipe;

  @override
  State<CookModeScreen> createState() => _CookModeScreenState();
}

class _CookModeScreenState extends State<CookModeScreen> {
  int _stepIndex = 0;

  Future<void> _openVideo() async {
    if (widget.recipe.sourceUrl.isEmpty) return;
    final uri = Uri.tryParse(widget.recipe.sourceUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.recipe.steps;
    final safeIndex = steps.isEmpty ? 0 : _stepIndex.clamp(0, steps.length - 1);
    final current = steps.isEmpty ? 'Keine Schritte vorhanden.' : steps[safeIndex];

    return Scaffold(
      backgroundColor: AppTheme.cream,
      appBar: AppBar(
        title: Text(widget.recipe.title),
        actions: [
          if (widget.recipe.sourceUrl.isNotEmpty)
            IconButton(
              tooltip: 'Video anschauen',
              onPressed: _openVideo,
              icon: const Icon(Icons.play_circle_outline),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.recipe.sourceUrl.isNotEmpty)
              FilledButton.icon(
                onPressed: _openVideo,
                icon: const Icon(Icons.ondemand_video),
                label: const Text('Rezeptvideo öffnen'),
              ),
            const SizedBox(height: 16),
            Text(
              steps.isEmpty
                  ? 'Schritt'
                  : 'Schritt ${safeIndex + 1} von ${steps.length}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: AppTheme.seed.withValues(alpha: 0.12),
                  ),
                ),
                child: Center(
                  child: SingleChildScrollView(
                    child: Text(
                      current,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: safeIndex > 0
                        ? () => setState(() => _stepIndex = safeIndex - 1)
                        : null,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Zurück'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: safeIndex < steps.length - 1
                        ? () => setState(() => _stepIndex = safeIndex + 1)
                        : null,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Nächster Schritt'),
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
