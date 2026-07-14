import 'package:web/web.dart' as web;

/// Setzt die Google-Client-ID für die Web-Anmeldung (Meta-Tag im HTML-Kopf).
void applyGoogleSignInClientId(String clientId) {
  final trimmed = clientId.trim();
  if (trimmed.isEmpty) return;

  final head = web.document.head;
  if (head == null) return;

  final existing =
      web.document.querySelector('meta[name="google-signin-client_id"]');
  if (existing != null) {
    existing.setAttribute('content', trimmed);
    return;
  }

  final meta = web.document.createElement('meta');
  meta.setAttribute('name', 'google-signin-client_id');
  meta.setAttribute('content', trimmed);
  head.append(meta);
}

bool get isGoogleWebBackupSupported => true;
