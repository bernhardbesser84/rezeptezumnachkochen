/// Vorgefertigte Google-OAuth-Client-ID (Web) für „Rezept Nachkochen“.
///
/// Für Anmeldung + Drive-Backup auf rezeptezumnachkochen.vercel.app.
/// Per `--dart-define=GOOGLE_WEB_CLIENT_ID=...` überschreibbar.
class GoogleDefaults {
  static const _defaultWebClientId =
      '301933139322-37dugr0a64psof2gr8qjrban93hq36oq.apps.googleusercontent.com';

  /// OAuth-Client-ID vom Typ „Webanwendung“.
  static const webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: _defaultWebClientId,
  );

  static bool get hasBuiltInClientId => webClientId.trim().isNotEmpty;
}
