import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/app_repository.dart';
import 'services/family_sync_service.dart';
import 'services/google_backup_service.dart';
import 'services/recipe_extractor.dart';
import 'services/recipe_storage.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RezeptNachkochenApp());
}

class RezeptNachkochenApp extends StatelessWidget {
  const RezeptNachkochenApp({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = RecipeStorage();
    final sync = FamilySyncService();
    final googleBackup = GoogleBackupService(storage: storage);
    final repository = AppRepository(
      storage: storage,
      sync: sync,
      googleBackup: googleBackup,
    );
    final extractor = RecipeExtractor();

    // Client-ID (falls schon gespeichert) für Web-Login vorbereiten.
    googleBackup.prepareClientId();
    googleBackup.trySilentSignIn();

    return MaterialApp(
      title: 'Rezept Nachkochen',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: HomeScreen(
        repository: repository,
        extractor: extractor,
        googleBackup: googleBackup,
      ),
    );
  }
}
