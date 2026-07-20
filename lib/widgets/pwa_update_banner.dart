import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/pwa_update.dart';

/// Zeigt auf der Web-/PWA-Version einen Hinweis, wenn ein neues Deployment da ist.
class PwaUpdateBanner extends StatefulWidget {
  const PwaUpdateBanner({super.key});

  @override
  State<PwaUpdateBanner> createState() => _PwaUpdateBannerState();
}

class _PwaUpdateBannerState extends State<PwaUpdateBanner> {
  bool _updateAvailable = false;
  bool _checking = false;
  bool _applying = false;
  String? _remoteBuildId;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _checkForUpdate();
    }
  }

  Future<void> _checkForUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await requestServiceWorkerUpdate();
      final remote = await fetchRemoteBuildId();
      if (!mounted) return;
      final newer = isRemoteBuildNewer(
        localBuildId: kAppBuildId,
        remoteBuildId: remote,
      );
      setState(() {
        _remoteBuildId = remote;
        _updateAvailable = newer;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checking = false);
    }
  }

  Future<void> _applyUpdate() async {
    if (_applying) return;
    setState(() => _applying = true);
    await applyPwaUpdate();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !_updateAvailable) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Update verfügbar',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Die Home-Bildschirm-App hat noch eine ältere Version geladen. '
            'Bitte aktualisieren — sonst können Fehler wie „Schlüssel ungültig“ '
            'von der alten Version kommen.'
            '${_remoteBuildId != null ? '\n(Neu: $_remoteBuildId · Hier: $kAppBuildId)' : ''}',
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _applying ? null : _applyUpdate,
              icon: _applying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update),
              label: Text(_applying ? 'Aktualisiere…' : 'Jetzt aktualisieren'),
            ),
          ),
        ],
      ),
    );
  }
}
