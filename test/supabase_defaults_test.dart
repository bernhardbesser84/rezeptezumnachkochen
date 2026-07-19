import 'package:flutter_test/flutter_test.dart';
import 'package:rezept_nachkochen/config/supabase_defaults.dart';

void main() {
  test('Supabase-Default-URL zeigt auf das Familien-Projekt', () {
    expect(SupabaseDefaults.projectRef, 'ecnysosvuxusdnuvnrly');
    expect(
      SupabaseDefaults.url,
      'https://ecnysosvuxusdnuvnrly.supabase.co',
    );
  });
}
