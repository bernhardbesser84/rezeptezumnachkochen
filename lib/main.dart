import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
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
    final extractor = RecipeExtractor();

    return MaterialApp(
      title: 'Rezept Nachkochen',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: HomeScreen(storage: storage, extractor: extractor),
    );
  }
}
