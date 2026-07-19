/// Vorgefertigte Supabase-Cloud für „Rezept Nachkochen“.
///
/// Öffentlicher publishable/anon-Key (kein Service-Role-Geheimnis).
/// Per `--dart-define=SUPABASE_ANON_KEY=...` überschreibbar (z. B. Vercel).
class SupabaseDefaults {
  static const projectRef = 'ecnysosvuxusdnuvnrly';

  static const url = 'https://ecnysosvuxusdnuvnrly.supabase.co';

  static const _defaultAnonKey =
      'sb_publishable_1jIQXqud7qg5P5jG681iXw_K1njD8Zc';

  /// Öffentlicher anon/publishable Key.
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _defaultAnonKey,
  );

  static bool get hasBuiltInKey => anonKey.trim().isNotEmpty;

  static bool get hasBuiltInCloud => hasBuiltInKey;
}
