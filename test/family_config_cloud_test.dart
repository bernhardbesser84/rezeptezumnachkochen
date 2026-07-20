import 'package:flutter_test/flutter_test.dart';
import 'package:rezept_nachkochen/config/supabase_defaults.dart';
import 'package:rezept_nachkochen/models/family_config.dart';
import 'package:rezept_nachkochen/models/family_config_cloud.dart';

void main() {
  test('Eingebaute Supabase-Defaults gelten auch ohne gespeicherte URL/Key', () {
    final config = FamilyConfig(
      familyCode: 'KOCH-TEST',
      deviceName: 'iPhone',
    );
    expect(config.hasCloud, isFalse);
    expect(config.hasEffectiveCloud, isTrue);
    expect(config.effectiveSupabaseUrl, SupabaseDefaults.url);
    expect(config.effectiveSupabaseAnonKey, SupabaseDefaults.anonKey);
    expect(config.withEffectiveCloud().hasCloud, isTrue);
  });
}
