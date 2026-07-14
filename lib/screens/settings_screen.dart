import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/ai_provider.dart';
import '../services/app_repository.dart';
import '../theme/app_theme.dart';
import '../utils/clipboard_paste.dart';
import 'family_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = true;
  bool _obscure = false; // Auf dem iPhone sonst oft kein „Einfügen“
  AiProvider _provider = AiProvider.openai;

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
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _switchProvider(AiProvider provider) async {
    if (provider == _provider) return;
    // Aktuellen Text erst zwischenspeichern, damit nichts verloren geht.
    await widget.repository.storage.setApiKeyFor(_provider, _controller.text);
    await widget.repository.storage.setAiProvider(provider);
    final key = await widget.repository.storage.getApiKeyFor(provider);
    setState(() {
      _provider = provider;
      _controller.text = key ?? '';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
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
    });
    _focusNode.requestFocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Schlüssel eingefügt.')),
    );
  }

  Future<void> _save() async {
    await widget.repository.storage.setAiProvider(_provider);
    await widget.repository.storage.setApiKeyFor(_provider, _controller.text);
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
                const Divider(height: 32),
                const Text(
                  'KI-Anbieter (optional)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Damit aus Videos eine richtige Schritt-für-Schritt-Anleitung '
                  'wird. Du kannst OpenAI, Gemini oder Claude nutzen. '
                  'Ohne Schlüssel funktioniert die App trotzdem, nur einfacher.',
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
                const SizedBox(height: 16),
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
