/// API-Schlüssel für den Gemini-429-Fallback (Groq → Mistral → OpenRouter).
///
/// Quellen (Reihenfolge): gespeicherter App-Wert, dann Compile-Zeit
/// (`--dart-define=GROQ_API_KEY=...` / `.env` über Build).
class FallbackApiKeys {
  const FallbackApiKeys({
    this.groq,
    this.mistral,
    this.openRouter,
  });

  final String? groq;
  final String? mistral;
  final String? openRouter;

  static const storageKeyGroq = 'groq_api_key';
  static const storageKeyMistral = 'mistral_api_key';
  static const storageKeyOpenRouter = 'openrouter_api_key';

  /// Aus `--dart-define` / Build-Umgebung (entspricht .env-Namen).
  factory FallbackApiKeys.fromEnvironment() {
    return const FallbackApiKeys(
      groq: String.fromEnvironment('GROQ_API_KEY'),
      mistral: String.fromEnvironment('MISTRAL_API_KEY'),
      openRouter: String.fromEnvironment('OPENROUTER_API_KEY'),
    );
  }

  /// Gespeicherte Keys überschreiben leere Env-Werte.
  FallbackApiKeys merge(FallbackApiKeys other) {
    return FallbackApiKeys(
      groq: _prefer(other.groq, groq),
      mistral: _prefer(other.mistral, mistral),
      openRouter: _prefer(other.openRouter, openRouter),
    );
  }

  static String? _prefer(String? primary, String? fallback) {
    final a = primary?.trim();
    if (a != null && a.isNotEmpty) return a;
    final b = fallback?.trim();
    if (b != null && b.isNotEmpty) return b;
    return null;
  }

  bool get hasAny =>
      (groq?.trim().isNotEmpty ?? false) ||
      (mistral?.trim().isNotEmpty ?? false) ||
      (openRouter?.trim().isNotEmpty ?? false);

  bool get hasGroq => groq?.trim().isNotEmpty ?? false;
  bool get hasMistral => mistral?.trim().isNotEmpty ?? false;
  bool get hasOpenRouter => openRouter?.trim().isNotEmpty ?? false;
}
