import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await widget.repository.storage.getApiKey();
    _controller.text = key ?? '';
    if (mounted) setState(() => _loading = false);
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
    await widget.repository.storage.setApiKey(_controller.text);
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
                  'OpenAI API-Schlüssel (optional)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Damit aus Videos eine richtige Schritt-für-Schritt-Anleitung '
                  'wird. Ohne Schlüssel funktioniert die App trotzdem, nur '
                  'einfacher.',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  obscureText: _obscure,
                  enableSuggestions: false,
                  autocorrect: false,
                  keyboardType: TextInputType.visiblePassword,
                  enableInteractiveSelection: true,
                  decoration: InputDecoration(
                    labelText: 'API-Schlüssel',
                    hintText: 'sk-...',
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
                const Text(
                  'Tipp fürs iPhone: Schlüssel zuerst kopieren, dann hier auf '
                  '„Schlüssel einfügen“ tippen.\n'
                  'Wichtig: Bei OpenAI muss Billing/Guthaben aktiv sein. '
                  'Sonst kommt Fehler 429, auch wenn der Schlüssel stimmt.',
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
