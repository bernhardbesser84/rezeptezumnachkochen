/// Vorgefertigter Gemini-API-Schlüssel für „Rezept Nachkochen“.
///
/// Für den privaten Familiengebrauch in der App hinterlegt.
/// Per `--dart-define=GEMINI_API_KEY=...` überschreibbar (z. B. Vercel).
class GeminiDefaults {
  static const _defaultApiKey =
      'AQ.Ab8RN6JuYmAIpTv1uY0wlOwJ-uE6ZrXgRXOgG4n4ACbLPkTA1A';

  /// Gemini-API-Schlüssel (Google AI Studio / Gemini API).
  static const apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: _defaultApiKey,
  );

  static bool get hasBuiltInKey => apiKey.trim().isNotEmpty;
}
