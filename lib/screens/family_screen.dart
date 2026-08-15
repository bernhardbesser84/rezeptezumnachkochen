import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/supabase_defaults.dart';
import '../models/family_config.dart';
import '../models/family_config_cloud.dart';
import '../services/app_repository.dart';
import '../services/family_sync_service.dart';
import '../theme/app_theme.dart';
import '../utils/clipboard_paste.dart';

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
  bool _showAdvancedCloud = false;
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
      _urlController.text = (config.supabaseUrl?.trim().isNotEmpty ?? false)
          ? config.supabaseUrl!.trim()
          : SupabaseDefaults.url;
      _keyController.text = (config.supabaseAnonKey?.trim().isNotEmpty ?? false)
          ? config.supabaseAnonKey!.trim()
          : SupabaseDefaults.anonKey;
    } else {
      _deviceController.text = 'Mein Gerät';
      _urlController.text = SupabaseDefaults.url;
      _keyController.text = SupabaseDefaults.anonKey;
    }
    // Wenn die Cloud schon eingebaut ist, Advanced-Felder zu.
    _showAdvancedCloud = !SupabaseDefaults.hasBuiltInKey;
    if (mounted) setState(() => _loading = false);

    // Gespeicherte Familie ohne Cloud-Felder → Defaults dauerhaft eintragen.
    if (config != null &&
        SupabaseDefaults.hasBuiltInKey &&
        ((config.supabaseUrl?.trim().isEmpty ?? true) ||
            (config.supabaseAnonKey?.trim().isEmpty ?? true))) {
      await widget.repository.saveFamily(config.withEffectiveCloud());
    }
  }

  Future<void> _pasteInto(TextEditingController controller, String label) async {
    final result = await readClipboardText();
    if (!mounted) return;
    if (!result.isOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage!)),
      );
      return;
    }
    final text = result.text!;
    setState(() {
      controller.text = text;
      controller.selection = TextSelection.collapsed(offset: text.length);
    });
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
      // Leere Felder mit Defaults füllen (URL immer, Key falls eingebaut).
      final url = _urlController.text.trim().isEmpty
          ? SupabaseDefaults.url
          : _urlController.text.trim();
      final key = _keyController.text.trim().isEmpty
          ? SupabaseDefaults.anonKey.trim()
          : _keyController.text.trim();

      final config = FamilyConfig(
        familyCode: _familyCodeController.text.trim().toUpperCase(),
        deviceName: _deviceController.text.trim().isEmpty
            ? 'Gerät'
            : _deviceController.text.trim(),
        supabaseUrl: url.isEmpty ? null : url,
        supabaseAnonKey: key.isEmpty ? null : key,
        openaiApiKey: (await widget.repository.family())?.openaiApiKey,
      ).withEffectiveCloud();

      if (config.familyCode.isEmpty) {
        throw Exception('Bitte einen Familien-Code eingeben oder erstellen.');
      }

      if (testAndSync && !config.hasEffectiveCloud) {
        throw Exception(
          'Cloud-Schlüssel fehlt noch. '
          'Bitte den anon/public Key einmal eintragen '
          '(oder beim Web-Build als SUPABASE_ANON_KEY setzen).',
        );
      }

      await widget.repository.saveFamily(config);

      if (testAndSync && config.hasEffectiveCloud) {
        final error = await FamilySyncService().testConnection(config);
        if (error != null) throw Exception(error);
        await widget.repository.fullSync();
        _status =
            'Verbunden! Rezepte und Einkaufsliste sind synchronisiert.';
      } else if (config.hasEffectiveCloud) {
        _status = 'Gespeichert. Tippe auf „Verbinden & Sync“, um zu prüfen.';
      } else {
        _status =
            'Familien-Code gespeichert. Für Sync noch den Cloud-Schlüssel '
            'eintragen (siehe unten).';
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
    final cloudReady = SupabaseDefaults.hasBuiltInKey ||
        _keyController.text.trim().isNotEmpty;

    final builtInCloud = SupabaseDefaults.hasBuiltInKey;

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
                      'Dafür brauchen alle Geräte denselben Familien-Code.',
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
                  'Cloud-Sync',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                _InfoCard(
                  title: builtInCloud
                      ? 'Cloud ist fest in der App hinterlegt'
                      : 'Cloud-Projekt ist vorbereitet',
                  body: builtInCloud
                      ? 'Du musst URL und Schlüssel nicht mehr eintragen. '
                          'Gleicher Familien-Code auf allen Geräten — '
                          'dann „Verbinden & Sync“.'
                      : 'Die Projekt-URL ist schon eingetragen:\n'
                          '${SupabaseDefaults.url}\n\n'
                          'Es fehlt noch einmalig der öffentliche anon-Key.',
                ),
                if (builtInCloud) ...[
                  const SizedBox(height: 12),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.cloud_done, color: AppTheme.accent),
                            const SizedBox(width: 8),
                            const Text(
                              'Supabase verbunden (eingebaut)',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text('URL:\n${SupabaseDefaults.url}'),
                        const SizedBox(height: 8),
                        const Text(
                          'Schlüssel: ✓ in der App hinterlegt '
                          '(sb_publishable_…)',
                        ),
                      ],
                    ),
                  ),
                ],
                if (!builtInCloud) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _keyController,
                    obscureText: _obscureKey,
                    enableSuggestions: false,
                    autocorrect: false,
                    keyboardType: TextInputType.visiblePassword,
                    enableInteractiveSelection: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Supabase anon/public Key',
                      hintText: 'eyJhbGciOi...',
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                        icon: Icon(
                          _obscureKey
                              ? Icons.visibility
                              : Icons.visibility_off,
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
                    'Tipp fürs iPhone: Key zuerst kopieren, dann auf '
                    '„Schlüssel einfügen“ tippen.',
                  ),
                ],
                if (!builtInCloud) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(
                      () => _showAdvancedCloud = !_showAdvancedCloud,
                    ),
                    child: Text(
                      _showAdvancedCloud
                          ? 'Cloud-Details ausblenden'
                          : 'Cloud-Details anzeigen (für Profis)',
                    ),
                  ),
                  if (_showAdvancedCloud) ...[
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
                  ],
                ],
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
                  child: Text(
                    cloudReady
                        ? 'Verbinden & Sync'
                        : 'Verbinden & Sync (Key fehlt noch)',
                  ),
                ),
                const SizedBox(height: 20),
                const _InfoCard(
                  title: 'Vorschaubilder in der Cloud (einmalig)',
                  body:
                      'Damit Bilder beim Backup wiederhergestellt werden:\n\n'
                      '1. supabase.com → dein Projekt öffnen\n'
                      '2. Links SQL → New query\n'
                      '3. Diese Zeile einfügen und Run tippen:\n'
                      'alter table recipes add column if not exists image_url text;\n\n'
                      '4. Hier „Verbinden & Sync“ tippen\n'
                      '5. Rezepte mit Bild erneut speichern',
                ),
                const SizedBox(height: 12),
                const _InfoCard(
                  title: 'Einmalig in Supabase (Tabellen anlegen)',
                  body:
                      'URL und Schlüssel sind schon in der App. '
                      'Falls „Tabellen fehlen“ erscheint:\n\n'
                      '1. supabase.com → dein Projekt öffnen\n'
                      '2. Links SQL → New query\n'
                      '3. Inhalt aus supabase/schema.sql einfügen → Run\n'
                      '4. Hier zurück: Familien-Code erstellen → '
                      '„Verbinden & Sync“',
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
