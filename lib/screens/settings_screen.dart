import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/recipe_storage.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.storage});

  final RecipeStorage storage;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await widget.storage.getApiKey();
    _controller.text = key ?? '';
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    await widget.storage.setApiKey(_controller.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Einstellungen gespeichert.')),
    );
    Navigator.pop(context);
  }

  Future<void> _openOpenAi() async {
    final uri = Uri.parse('https://platform.openai.com/api-keys');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'OpenAI API-Schlüssel (optional)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Wenn du einen Schlüssel hinterlegst, macht die App aus '
                  'Video-Links und Beschreibungen eine klarere Einkaufsliste '
                  'und Schritt-für-Schritt-Anleitung. Ohne Schlüssel funktioniert '
                  'die App trotzdem – dann mit einfacherer Auswertung.',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'API-Schlüssel',
                    hintText: 'sk-...',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _openOpenAi,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Schlüssel bei OpenAI holen'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Speichern'),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.seed.withValues(alpha: 0.12),
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Teilen von Facebook & Co.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'In der anderen App auf „Teilen“ tippen und dann '
                        '„Rezept Nachkochen“ auswählen. Der Link landet '
                        'automatisch in der App.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
