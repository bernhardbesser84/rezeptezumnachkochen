import 'package:flutter/foundation.dart';

/// Kleine Helfer, damit die Web-App auf dem iPhone klar erklärt wird.
class PlatformHints {
  static bool get isWeb => kIsWeb;

  /// Grober Check: iPhone/iPad im Browser (kein echtes Native-API).
  static bool get looksLikeAppleMobileWeb {
    if (!kIsWeb) return false;
    final agent = defaultTargetPlatform;
    // Auf Web ist defaultTargetPlatform oft iOS/Android je nach Gerät.
    return agent == TargetPlatform.iOS;
  }
}
