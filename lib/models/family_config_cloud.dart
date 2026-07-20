import '../config/supabase_defaults.dart';
import 'family_config.dart';

/// Ergänzt gespeicherte Familien-Einstellungen um eingebaute Supabase-Defaults.
extension FamilyConfigCloud on FamilyConfig {
  String get effectiveSupabaseUrl {
    final stored = supabaseUrl?.trim() ?? '';
    if (stored.isNotEmpty) return stored;
    return SupabaseDefaults.url;
  }

  String get effectiveSupabaseAnonKey {
    final stored = supabaseAnonKey?.trim() ?? '';
    if (stored.isNotEmpty) return stored;
    return SupabaseDefaults.anonKey.trim();
  }

  bool get hasEffectiveCloud {
    return familyCode.trim().isNotEmpty &&
        effectiveSupabaseUrl.isNotEmpty &&
        effectiveSupabaseAnonKey.isNotEmpty;
  }

  /// Für Sync: immer URL + Key — auch wenn nur in der App eingebaut.
  FamilyConfig withEffectiveCloud() {
    return copyWith(
      supabaseUrl: effectiveSupabaseUrl,
      supabaseAnonKey: effectiveSupabaseAnonKey,
    );
  }
}
