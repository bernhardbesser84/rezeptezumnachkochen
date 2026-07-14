import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/family_config.dart';
import '../services/app_repository.dart';
import '../services/family_sync_service.dart';
import '../theme/app_theme.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final _familyCodeController = TextEditingController();
  final _deviceController = TextEditingController();
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _obscureKey = false; // Auf dem iPhone sonst oft kein „Einfügen“
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await widget.repository.family();
    if (config != null) {
      _familyCodeController.text = config.familyCode;
      _deviceController.text = config.deviceName;
      _urlController.text = config.supabaseUrl ?? '';
      _keyController.text = config.supabaseAnonKey ?? '';
    } else {
      _deviceController.text = 'Mein Gerät';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pasteInto(TextEditingController controller, String label) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Zwischenablage ist leer. Bitte zuerst kopieren.'),
        ),
      );
      return;
    }
    setState(() {
      controller.text = text;
      controller.selection = TextSelection.collapsed(offset: text.length);
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label eingefügt.')),
    );
  }

  Future<void> _createFamily() async {
    final code = widget.repository.storage.generateFamilyCode();
    _familyCodeController.text = code;
    setState(() => _status = 'Neuer Familien-Code erstellt. Jetzt speichern.');
  }

  Future<void> _save({bool testAndSync = false}) async {
    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      final config = FamilyConfig(
        familyCode: _familyCodeController.text.trim().toUpperCase(),
        deviceName: _deviceController.text.trim().isEmpty
            ? 'Gerät'
            : _deviceController.text.trim(),
        supabaseUrl: _urlController.text.trim().isEmpty
            ? null
            : _urlController.text.trim(),
        supabaseAnonKey: _keyController.text.trim().isEmpty
            ? null
            : _keyController.text.trim(),
        openaiApiKey: (await widget.repository.family())?.openaiApiKey,
      );

      if (config.familyCode.isEmpty) {
        throw Exception('Bitte einen Familien-Code eingeben oder erstellen.');
      }

      await widget.repository.saveFamily(config);

      if (testAndSync && config.hasCloud) {
        final error = await FamilySyncService().testConnection(config);
        if (error != null) throw Exception(error);
        await widget.repository.fullSync();
        _status =
            'Verbunden! Rezepte und Einkaufsliste sind synchronisiert.';
      } else if (config.hasCloud) {
        _status = 'Gespeichert. Tippe auf „Verbinden & Sync“, um zu prüfen.';
      } else {
        _status =
            'Familien-Code gespeichert. Für Handy + Tablett noch Cloud '
            'eintragen (kostenlos, siehe Anleitung unten).';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_status ?? 'Gespeichert')),
        );
      }
    } catch (e) {
      setState(() {
        _status = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _familyCodeController.dispose();
    _deviceController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Familie verbinden')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _InfoCard(
                  title: 'So nutzt ihr es zu dritt',
                  body:
                      '1. Bernhard teilt am iPhone ein Rezeptvideo in die App.\n'
                      '2. Am Samsung-Tablett öffnet ihr dasselbe Rezept zum Kochen.\n'
                      '3. Auf dem Galaxy-Handy sieht deine Frau die Einkaufsliste '
                      'und hakte ab, was schon im Korb ist.\n\n'
                      'Dafür brauchen alle Geräte denselben Familien-Code und '
                      'dieselbe Cloud-Verbindung.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _deviceController,
                  decoration: const InputDecoration(
                    labelText: 'Name dieses Geräts',
                    hintText: 'z. B. Bernhard iPhone, Tablett, Galaxy',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _familyCodeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Familien-Code',
                    hintText: 'KOCH-XXXX',
                    suffixIcon: IconButton(
                      tooltip: 'Code kopieren',
                      onPressed: () async {
                        final code = _familyCodeController.text.trim();
                        if (code.isEmpty) return;
                        await Clipboard.setData(ClipboardData(text: code));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code kopiert')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _createFamily,
                  icon: const Icon(Icons.vpn_key),
                  label: const Text('Neuen Familien-Code erstellen'),
                ),
                const SizedBox(height: 20),
                Text(
                  'Cloud (kostenlos, für Sync)',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Einmal bei Supabase (kostenlos) ein Projekt anlegen und die '
                  'zwei Werte hier eintragen. Anleitung steht in der README '
                  'und unten kurz zusammengefasst.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _urlController,
                  enableSuggestions: false,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  enableInteractiveSelection: true,
                  decoration: const InputDecoration(
                    labelText: 'Supabase Project URL',
                    hintText: 'https://xxxxx.supabase.co',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _pasteInto(_urlController, 'URL'),
                  icon: const Icon(Icons.content_paste),
                  label: const Text('URL einfügen'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _keyController,
                  obscureText: _obscureKey,
                  enableSuggestions: false,
                  autocorrect: false,
                  keyboardType: TextInputType.visiblePassword,
                  enableInteractiveSelection: true,
                  decoration: InputDecoration(
                    labelText: 'Supabase anon/public Key',
                    hintText: 'eyJhbGciOi...',
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                      icon: Icon(
                        _obscureKey ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _saving
                      ? null
                      : () => _pasteInto(_keyController, 'Schlüssel'),
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Schlüssel einfügen'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tipp fürs iPhone: Wert zuerst kopieren, dann auf '
                  '„… einfügen“ tippen.',
                ),
                const SizedBox(height: 14),
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_status!),
                  ),
                FilledButton(
                  onPressed: _saving ? null : () => _save(),
                  child: Text(_saving ? 'Speichern…' : 'Speichern'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _saving ? null : () => _save(testAndSync: true),
                  child: const Text('Verbinden & Sync'),
                ),
                const SizedBox(height: 20),
                const _InfoCard(
                  title: 'Kurz-Anleitung Cloud',
                  body:
                      '1. Auf supabase.com kostenloses Konto erstellen\n'
                      '2. Neues Projekt anlegen\n'
                      '3. SQL aus supabase/schema.sql ausführen\n'
                      '4. Unter Project Settings → API die URL und den '
                      'anon key kopieren\n'
                      '5. Hier einfügen und auf „Verbinden & Sync“ tippen\n'
                      '6. Denselben Code + dieselben Cloud-Daten auf '
                      'Tablett und Galaxy eintragen',
                ),
              ],
            ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.seed.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(body),
        ],
      ),
    );
  }
}
