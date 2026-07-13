import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Anleitung: Web-App auf dem iPhone zum Home-Bildschirm hinzufügen.
class WebInstallScreen extends StatelessWidget {
  const WebInstallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aufs iPhone legen')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.seed,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text(
              'Keine 99 € nötig. Die App läuft als Website – fühlt sich aber '
              'wie eine normale App an.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const _Step(
            number: '1',
            title: 'In Safari öffnen',
            body:
                'Öffne den Link zur Web-App unbedingt in Safari '
                '(nicht in Chrome oder Facebook-Browser).',
          ),
          const _Step(
            number: '2',
            title: 'Teilen-Symbol tippen',
            body:
                'Unten (oder oben) das Teilen-Symbol tippen: '
                'Quadrat mit Pfeil nach oben.',
          ),
          const _Step(
            number: '3',
            title: 'Zum Home-Bildschirm',
            body:
                'Nach unten scrollen und „Zum Home-Bildschirm“ wählen. '
                'Dann „Hinzufügen“ tippen.',
          ),
          const _Step(
            number: '4',
            title: 'Rezept hinzufügen',
            body:
                'Bei einem Video den Link kopieren, die App öffnen und '
                '„Link einfügen“ tippen.',
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.seed.withValues(alpha: 0.12)),
            ),
            child: const Text(
              'Wichtig: Familie + Cloud einmal einrichten, damit iPhone, '
              'Galaxy und Tablett dieselbe Einkaufsliste sehen.',
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
            child: Text(number),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
