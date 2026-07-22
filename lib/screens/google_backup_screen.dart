import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/google_defaults.dart';
import '../services/app_repository.dart';
import '../services/google_backup_service.dart';
import '../theme/app_theme.dart';
import '../utils/clipboard_paste.dart';

/// Google-Anmeldung + automatisches Backup / Wiederherstellen.
class GoogleBackupScreen extends StatefulWidget {
  const GoogleBackupScreen({
    super.key,
    required this.repository,
    required this.backup,
  });

  final AppRepository repository;
  final GoogleBackupService backup;

  @override
  State<GoogleBackupScreen> createState() => _GoogleBackupScreenState();
}

class _GoogleBackupScreenState extends State<GoogleBackupScreen> {
  final _clientIdController = TextEditingController();
  final _clientIdFocus = FocusNode();

  bool _loading = true;
  bool _busy = false;
  bool _showAdvancedClientId = false;
  String? _email;
  DateTime? _lastBackup;
  String? _info;
  String? _error;

  bool get _builtInClientId => GoogleDefaults.hasBuiltInClientId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storage = widget.repository.storage;
    final clientId = await storage.getGoogleWebClientId();
    final email = await storage.getGoogleBackupEmail();
    final last = await storage.getGoogleBackupLastAt();
    _clientIdController.text = clientId ?? '';
    // Ohne eingebaute ID: Felder zeigen. Mit eingebauter ID: nur wenn Override.
    final hasOverride = _builtInClientId &&
        (clientId?.trim().isNotEmpty ?? false) &&
        clientId!.trim() != GoogleDefaults.webClientId.trim();
    _showAdvancedClientId = !_builtInClientId || hasOverride;
    await widget.backup.prepareClientId();
    if (!mounted) return;
    setState(() {
      _email = widget.backup.email ?? email;
      _lastBackup = last;
      _loading = false;
    });
  }

  Future<void> _saveClientId() async {
    await widget.repository.storage.setGoogleWebClientId(
      _clientIdController.text,
    );
    await widget.backup.prepareClientId();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Google-Client-ID gespeichert.')),
    );
  }

  Future<void> _pasteClientId() async {
    final result = await readClipboardText();
    if (!mounted) return;
    if (!result.isOk) {
      _clientIdFocus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage!)),
      );
      return;
    }
    setState(() {
      _clientIdController.text = result.text!;
      _clientIdController.selection = TextSelection.collapsed(
        offset: result.text!.length,
      );
      _showAdvancedClientId = true;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    // Eingebaute ID sicher aktiv; sonst ggf. eingegebene ID speichern.
    if (_builtInClientId &&
        (_clientIdController.text.trim().isEmpty ||
            _clientIdController.text.trim() ==
                GoogleDefaults.webClientId.trim())) {
      await widget.repository.storage.setGoogleWebClientId(null);
    } else {
      await _saveClientId();
    }
    await widget.backup.prepareClientId();

    await _run(() async {
      final account = await widget.backup.signIn();
      setState(() => _email = account.email);
      // Nach Anmeldung einmal sichern.
      await widget.backup.backupNow();
      final last = await widget.repository.storage.getGoogleBackupLastAt();
      if (mounted) {
        setState(() {
          _lastBackup = last;
          _info =
              'Angemeldet als ${account.email}. Backup ist aktiv — '
              'nach jedem neuen Rezept wird automatisch gesichert.';
        });
      }

      // Nach Neuinstallation: leere App → Wiederherstellen anbieten.
      final recipes = await widget.repository.storage.loadRecipes();
      if (recipes.isEmpty && mounted) {
        final restore = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Backup wiederherstellen?'),
            content: const Text(
              'Auf diesem Gerät sind noch keine Rezepte. '
              'Soll das Google-Backup jetzt geladen werden?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Später'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Wiederherstellen'),
              ),
            ],
          ),
        );
        if (restore == true) {
          await _restore();
        }
      }
    });
  }

  Future<void> _signOut() async {
    await _run(() async {
      await widget.backup.signOut();
      if (mounted) {
        setState(() {
          _email = null;
          _info = 'Von Google abgemeldet. Automatisches Backup ist aus.';
        });
      }
    });
  }

  Future<void> _backupNow() async {
    await _run(() async {
      if (!widget.backup.isSignedIn) {
        await widget.backup.signIn();
      }
      await widget.backup.backupNow();
      final last = await widget.repository.storage.getGoogleBackupLastAt();
      if (mounted) {
        setState(() {
          _email = widget.backup.email;
          _lastBackup = last;
          _info = 'Backup gespeichert.';
        });
      }
    });
  }

  Future<void> _restore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup laden?'),
        content: const Text(
          'Rezepte, Einkaufsliste und Einstellungen (inkl. KI-Schlüssel) '
          'werden durch das Google-Backup ersetzt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Wiederherstellen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await _run(() async {
      if (!widget.backup.isSignedIn) {
        await widget.backup.signIn();
      }
      final payload = await widget.backup.restoreNow();
      if (mounted) {
        setState(() {
          _email = widget.backup.email;
          _info =
              'Wiederhergestellt: ${payload.recipes.length} Rezepte '
              '(Stand ${_formatDate(payload.savedAt)}).';
        });
      }
    });
  }

  Future<void> _openCloudConsole() async {
    final uri = Uri.parse('https://console.cloud.google.com/apis/credentials');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openDriveApi() async {
    final uri = Uri.parse(
      'https://console.cloud.google.com/apis/library/drive.googleapis.com',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final d =
        '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year}';
    final t =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$d, $t';
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientIdFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Google-Backup')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF4FAF6), Color(0xFFFFF7F3)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppTheme.seed.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Text(
                    _builtInClientId
                        ? 'Melde dich mit Google an. Die App-Anmeldung ist '
                            'schon eingerichtet — du musst keine Client-ID '
                            'mehr eintragen. Nach dem Login sichert die App '
                            'Rezepte, Einkaufsliste und Einstellungen.'
                        : 'Melde dich mit Google an. Dann sichert die App '
                            'nach jedem neuen Rezept automatisch Rezepte, '
                            'Einkaufsliste und Einstellungen (auch KI-Schlüssel). '
                            'Wenn du die App löschst, kannst du alles '
                            'wiederherstellen.',
                  ),
                ),
                if (_builtInClientId) ...[
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
                            Icon(Icons.verified_user_outlined,
                                color: AppTheme.accent),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Google-Anmeldung vorbereitet (eingebaut)',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Client-ID: ✓ in der App hinterlegt. '
                          'Nur noch „Mit Google anmelden“ tippen.',
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(
                      () => _showAdvancedClientId = !_showAdvancedClientId,
                    ),
                    child: Text(
                      _showAdvancedClientId
                          ? 'Technische Details ausblenden'
                          : 'Technische Details (für Profis)',
                    ),
                  ),
                ],
                if (!_builtInClientId || _showAdvancedClientId) ...[
                  const SizedBox(height: 8),
                  Text(
                    _builtInClientId
                        ? 'Eigene Client-ID (optional)'
                        : '1. Einmalig: Google-Client-ID',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _builtInClientId
                        ? 'Nur nötig, wenn du eine andere Google-Cloud-'
                            'App nutzen willst. Sonst leer lassen.'
                        : 'In der Google Cloud Console ein „OAuth-Client-ID“ '
                            'vom Typ „Webanwendung“ anlegen. Als JavaScript-'
                            'Ursprung deine App-Adresse eintragen '
                            '(z. B. https://…vercel.app). Außerdem die '
                            'Google Drive API aktivieren.',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _openCloudConsole,
                        icon: const Icon(Icons.key_outlined),
                        label: const Text('Client-ID holen'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _openDriveApi,
                        icon: const Icon(Icons.cloud_outlined),
                        label: const Text('Drive API'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _clientIdController,
                    focusNode: _clientIdFocus,
                    enabled: !_busy,
                    keyboardType: TextInputType.visiblePassword,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Google-Client-ID (Web)',
                      hintText: '….apps.googleusercontent.com',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _busy ? null : _pasteClientId,
                          icon: const Icon(Icons.content_paste),
                          label: const Text('Einfügen'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _saveClientId,
                          child: const Text('ID speichern'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 28),
                Text(
                  _builtInClientId
                      ? 'Anmelden & sichern'
                      : '2. Anmelden & sichern',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_email != null) ...[
                  Text('Angemeldet: $_email'),
                  const SizedBox(height: 6),
                ],
                Text(
                  _lastBackup == null
                      ? 'Noch kein Backup gespeichert.'
                      : 'Letztes Backup: ${_formatDate(_lastBackup!)}',
                ),
                const SizedBox(height: 12),
                if (_email == null)
                  FilledButton.icon(
                    onPressed: _busy ? null : _signIn,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: const Text('Mit Google anmelden'),
                  )
                else ...[
                  FilledButton.icon(
                    onPressed: _busy ? null : _backupNow,
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Jetzt sichern'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _restore,
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Backup wiederherstellen'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Abmelden'),
                  ),
                ],
                if (_info != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _info!,
                    style: TextStyle(color: AppTheme.seed),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
    );
  }
}
