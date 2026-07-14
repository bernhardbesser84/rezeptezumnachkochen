import 'package:flutter/foundation.dart';

/// Setzt die Google-Client-ID für die Web-Anmeldung (Meta-Tag).
void applyGoogleSignInClientId(String clientId) {
  // Native / Tests: nichts nötig.
}

/// True, wenn wir auf dem Web laufen.
bool get isGoogleWebBackupSupported => kIsWeb;
