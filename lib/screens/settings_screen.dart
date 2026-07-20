import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/gemini_defaults.dart';
import '../models/ai_provider.dart';
import '../services/app_repository.dart';
import '../services/google_backup_service.dart';
import '../theme/app_theme.dart';
import '../utils/clipboard_paste.dart';
import '../utils/pwa_update.dart';
import 'family_screen.dart';
import 'google_backup_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    this.googleBackup,
  });

  final AppRepository repository;
  final GoogleBackupService? googleBackup;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = true;
  bool _obscure = false; // Auf dem iPhone sonst oft kein „Einfügen“
  bool _showGeminiOverride = false;
  AiProvider _provider =
      GeminiDefaults.hasBuiltInKey ? AiProvider.gemini : AiProvider.openai;

  bool get _geminiBuiltInActive =>
      _provider == AiProvider.gemini && GeminiDefaults.hasBuiltInKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = await widget.repository.storage.getAiProvider();
    final key = await widget.repository.storage.getApiKeyFor(provider);
    _provider = provider;
    _controller.text = key ?? '';
    // Eigenen Gemini-Schlüssel nur zeigen, wenn er vom eingebauten abweicht.
    _showGeminiOverride = provider == AiProvider.gemini &&
        GeminiDefaults.hasBuiltInKey &&
        (key?.trim().isNotEmpty ?? false) &&
        key!.trim() != GeminiDefaults.apiKey.trim();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _persistCurrentKey() async {
    if (_geminiBuiltInActive &&
        (_controller.text.trim().isEmpty ||
            _controller.text.trim() == GeminiDefaults.apiKey.trim())) {
      // Eingebauten Schlüssel nicht unnötig lokal speichern.
      await widget.repository.storage.setApiKeyFor(AiProvider.gemini, null);
      return;
    }
    await widget.repository.storage
        .setApiKeyFor(_provider, _controller.text);
  }

  Future<void> _switchProvider(AiProvider provider) async {
    if (provider == _provider) return;
    await _persistCurrentKey();
    await widget.repository.storage.setAiProvider(provider);
    final key = await widget.repository.storage.getApiKeyFor(provider);
    setState(() {
      _provider = provider;
      _controller.text = key ?? '';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      _showGeminiOverride = false;
    });
  }

  Future<void> _pasteKey() async {
    final result = await readClipboardText();
    if (!mounted) return;
    if (!result.isOk) {
      _focusNode.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage!)),
      );
      return;
    }
    final text = result.text!;
    setState(() {
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
      _showGeminiOverride = true;
    });
    _focusNode.requestFocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Schlüssel eingefügt.')),
    );
  }

  Future<void> _save() async {
    await widget.repository.storage.setAiProvider(_provider);
    await _persistCurrentKey();
    try {
      await widget.googleBackup?.backupIfSignedIn();
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_provider.label}-Einstellungen gespeichert.'),
      ),
    );
    Navigator.pop(context);
  }

  Future<void> _openKeyPage() async {
    final uri = Uri.parse(_provider.keyPageUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _refreshWebApp() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('App-Cache wird geleert…')),
    );
    await applyPwaUpdate();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('Familie & Cloud'),
                  subtitle: const Text(
                    'Code für iPhone, Tablett und Galaxy einrichten',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            FamilyScreen(repository: widget.repository),
                      ),
                    );
                  },
                ),
                if (widget.googleBackup != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('Google-Backup'),
                    subtitle: const Text(
                      'Anmelden und Rezepte + Einstellungen sichern',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GoogleBackupScreen(
                            repository: widget.repository,
                            backup: widget.googleBackup!,
                          ),
                        ),
                      );
                    },
                  ),
                const Divider(height: 32),
                const Text(
                  'KI-Anbieter',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  GeminiDefaults.hasBuiltInKey
                      ? 'Gemini ist fest in der App hinterlegt — '
                          'auf allen Geräten ohne Extra-Eingabe. '
                          'Optional kannst du OpenAI oder Claude wählen.'
                      : 'Damit aus Videos eine richtige Schritt-für-Schritt-'
                          'Anleitung wird. Du kannst OpenAI, Gemini oder '
                          'Claude nutzen. Ohne Schlüssel funktioniert die '
                          'App trotzdem, nur einfacher.',
                ),
                const SizedBox(height: 14),
                SegmentedButton<AiProvider>(
                  segments: [
                    for (final provider in AiProvider.values)
                      ButtonSegment(
                        value: provider,
                        label: Text(provider.label),
                      ),
                  ],
                  selected: {_provider},
                  onSelectionChanged: (values) {
                    if (values.isEmpty) return;
                    _switchProvider(values.first);
                  },
                ),
                if (_geminiBuiltInActive) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.accentSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.accent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_awesome, color: AppTheme.accent),
                            SizedBox(width: 8),
                            Text(
                              'Gemini verbunden (eingebaut)',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Schlüssel: ✓ in der App hinterlegt — '
                          'du musst nichts eintragen.',
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(
                      () => _showGeminiOverride = !_showGeminiOverride,
                    ),
                    child: Text(
                      _showGeminiOverride
                          ? 'Eigenen Schlüssel ausblenden'
                          : 'Anderen Gemini-Schlüssel eintragen',
                    ),
                  ),
                ],
                if (!_geminiBuiltInActive || _showGeminiOverride) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    obscureText: _obscure,
                    enableSuggestions: false,
                    autocorrect: false,
                    keyboardType: TextInputType.visiblePassword,
                    enableInteractiveSelection: true,
                    decoration: InputDecoration(
                      labelText: '${_provider.label} API-Schlüssel',
                      hintText: _provider.keyHint,
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Anzeigen' : 'Verbergen',
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: _pasteKey,
                    icon: const Icon(Icons.content_paste),
                    label: const Text('Schlüssel einfügen'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tipp fürs iPhone: ${_provider.label}-Schlüssel zuerst '
                    'kopieren, dann hier auf „Schlüssel einfügen“ tippen.\n'
                    'Jeder Anbieter speichert seinen eigenen Schlüssel. '
                    'Bei Limit-Fehler (429): Guthaben/Kontingent im '
                    '${_provider.label}-Konto prüfen.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openKeyPage,
                    icon: const Icon(Icons.open_in_new),
                    label: Text('Schlüssel bei ${_provider.label} holen'),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Speichern'),
                ),
                if (kIsWeb) ...[
                  const SizedBox(height: 28),
                  const Text(
                    'Home-Bildschirm-App (PWA)',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Wenn Fehler wie „Schlüssel ungültig“ nur in der '
                    'Home-Bildschirm-App erscheinen (nicht in Safari), '
                    'ist oft eine alte gecachte Version aktiv.\n'
                    'Aktuelle Build-ID: $kAppBuildId',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _refreshWebApp,
                    icon: const Icon(Icons.refresh),
                    label: const Text('App-Cache leeren & neu laden'),
                  ),
                ],
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
                        'Geräte-Ideen',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• iPhone: Videos finden und Link einfügen\n'
                        '• Samsung-Tablett: große Kochschritte + Video\n'
                        '• Galaxy-Handy: Einkaufsliste abhaken im Laden',
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
