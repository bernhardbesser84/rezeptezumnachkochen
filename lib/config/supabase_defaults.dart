/// Vorgefertigte Supabase-Cloud für „Rezept Nachkochen“.
///
/// URL kommt aus dem Projekt. Der öffentliche anon-Key kann per
/// `--dart-define=SUPABASE_ANON_KEY=...` (z. B. Vercel) gesetzt werden
/// oder später in der App eingetragen werden.
class SupabaseDefaults {
  static const projectRef = 'ecnysosvuxusdnuvnrly';

  static const url = 'https://ecnysosvuxusdnuvnrly.supabase.co';

  /// Öffentlicher anon/public Key (kein Geheimnis wie ein Service-Role-Key).
  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static bool get hasBuiltInKey => anonKey.trim().isNotEmpty;

  static bool get hasBuiltInCloud => hasBuiltInKey;
}
