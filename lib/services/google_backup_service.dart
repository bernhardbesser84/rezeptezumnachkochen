import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../models/ai_provider.dart';
import '../models/app_backup_payload.dart';
import '../utils/google_signin_web_stub.dart'
    if (dart.library.html) '../utils/google_signin_web.dart' as gweb;
import 'recipe_storage.dart';

/// Sichert Rezepte + Einstellungen in den privaten Google-Drive-App-Ordner.
///
/// Der Ordner ist nur für diese App sichtbar (nicht in „Meine Ablage“).
class GoogleBackupService {
  GoogleBackupService({
    required this.storage,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const backupFileName = 'rezept_nachkochen_backup_v1.json';
  static const driveScope =
      'https://www.googleapis.com/auth/drive.appdata';

  final RecipeStorage storage;
  final http.Client _client;

  GoogleSignIn? _signIn;
  GoogleSignInAccount? _account;

  bool get isSignedIn => _account != null;

  String? get email => _account?.email;

  Future<void> prepareClientId() async {
    final clientId = await storage.getGoogleWebClientId();
    if (clientId == null || clientId.isEmpty) return;
    gweb.applyGoogleSignInClientId(clientId);
  }

  GoogleSignIn _buildSignIn(String? webClientId) {
    return GoogleSignIn(
      scopes: const ['email', driveScope],
      // Web & iOS: Client-ID; Android: serverClientId (Web-Client).
      clientId: kIsWeb || defaultTargetPlatform == TargetPlatform.iOS
          ? webClientId
          : null,
      serverClientId: !kIsWeb && webClientId != null && webClientId.isNotEmpty
          ? webClientId
          : null,
    );
  }

  Future<GoogleSignIn> _ensureSignIn() async {
    await prepareClientId();
    final clientId = await storage.getGoogleWebClientId();
    if (clientId == null || clientId.trim().isEmpty) {
      throw Exception(
        'Bitte zuerst die Google-Client-ID (Web) in den Einstellungen '
        'eintragen. Ohne diese Nummer geht die Google-Anmeldung nicht.',
      );
    }
    _signIn ??= _buildSignIn(clientId.trim());
    return _signIn!;
  }

  Future<GoogleSignInAccount?> trySilentSignIn() async {
    try {
      final enabled = await storage.isGoogleBackupEnabled();
      if (!enabled) return null;
      final signIn = await _ensureSignIn();
      _account = await signIn.signInSilently();
      if (_account != null) {
        await storage.setGoogleBackupEmail(_account!.email);
      }
      return _account;
    } catch (_) {
      return null;
    }
  }

  Future<GoogleSignInAccount> signIn() async {
    final signIn = await _ensureSignIn();
    final account = await signIn.signIn();
    if (account == null) {
      throw Exception('Google-Anmeldung abgebrochen.');
    }
    _account = account;
    await storage.setGoogleBackupEnabled(true);
    await storage.setGoogleBackupEmail(account.email);
    return account;
  }

  Future<void> signOut() async {
    final signIn = _signIn ?? await _ensureSignIn();
    await signIn.signOut();
    _account = null;
    await storage.setGoogleBackupEnabled(false);
  }

  Future<String> _accessToken() async {
    final account = _account;
    if (account == null) {
      throw Exception('Nicht bei Google angemeldet.');
    }
    final auth = await account.authentication;
    final token = auth.accessToken;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Kein Google-Zugriffstoken. Bitte erneut anmelden und '
        'Drive-Zugriff erlauben.',
      );
    }
    return token;
  }

  Future<AppBackupPayload> buildPayload() async {
    final apiKeys = <String, String>{};
    for (final provider in AiProvider.values) {
      final key = await storage.getApiKeyFor(provider);
      if (key != null && key.trim().isNotEmpty) {
        apiKeys[provider.storageValue] = key.trim();
      }
    }

    return AppBackupPayload(
      savedAt: DateTime.now(),
      recipes: await storage.loadRecipes(),
      shoppingItems: await storage.loadShoppingItems(),
      familyConfig: await storage.loadFamilyConfig(),
      aiProvider: await storage.getAiProvider(),
      apiKeys: apiKeys,
      demoSeeded: await storage.wasDemoSeeded(),
    );
  }

  Future<void> applyPayload(AppBackupPayload payload) async {
    await storage.saveRecipes(payload.recipes);
    await storage.saveShoppingItems(payload.shoppingItems);
    if (payload.familyConfig != null) {
      await storage.saveFamilyConfig(payload.familyConfig!);
    }
    await storage.setAiProvider(payload.aiProvider);
    for (final provider in AiProvider.values) {
      final key = payload.apiKeys[provider.storageValue];
      await storage.setApiKeyFor(provider, key);
    }
    if (payload.demoSeeded) {
      await storage.markDemoSeeded();
    }
  }

  /// Sichert, wenn angemeldet — Fehler werden geschluckt (nicht den Ablauf stoppen).
  Future<bool> backupIfSignedIn() async {
    if (_account == null) {
      await trySilentSignIn();
    }
    if (_account == null) return false;
    await backupNow();
    return true;
  }

  Future<void> backupNow() async {
    final token = await _accessToken();
    final payload = await buildPayload();
    final body = payload.toJsonString();
    final existingId = await _findBackupFileId(token);

    if (existingId == null) {
      await _createBackupFile(token, body);
    } else {
      await _updateBackupFile(token, existingId, body);
    }

    await storage.setGoogleBackupLastAt(DateTime.now());
  }

  Future<AppBackupPayload?> downloadBackup() async {
    final token = await _accessToken();
    final fileId = await _findBackupFileId(token);
    if (fileId == null) return null;

    final response = await _client
        .get(
          Uri.parse(
            'https://www.googleapis.com/drive/v3/files/$fileId?alt=media',
          ),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Backup konnte nicht geladen werden (${response.statusCode}).',
      );
    }
    return AppBackupPayload.fromJsonString(response.body);
  }

  Future<AppBackupPayload> restoreNow() async {
    final payload = await downloadBackup();
    if (payload == null) {
      throw Exception(
        'Kein Backup in Google Drive gefunden. '
        'Zuerst einmal ein Rezept speichern oder „Jetzt sichern“ tippen.',
      );
    }
    await applyPayload(payload);
    return payload;
  }

  Future<String?> _findBackupFileId(String token) async {
    final uri = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files',
      {
        'spaces': 'appDataFolder',
        'fields': 'files(id,name)',
        'q': "name = '$backupFileName'",
      },
    );
    final response = await _client
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Google Drive nicht erreichbar (${response.statusCode}). '
        'Prüfe, ob die Drive API im Google-Cloud-Projekt aktiv ist.',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final files = body['files'] as List? ?? [];
    if (files.isEmpty) return null;
    return (files.first as Map)['id']?.toString();
  }

  Future<void> _createBackupFile(String token, String jsonBody) async {
    final boundary = 'rezept_backup_${DateTime.now().millisecondsSinceEpoch}';
    final metadata = jsonEncode({
      'name': backupFileName,
      'parents': ['appDataFolder'],
      'mimeType': 'application/json',
    });
    final body = '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$metadata\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json\r\n\r\n'
        '$jsonBody\r\n'
        '--$boundary--';

    final response = await _client
        .post(
          Uri.parse(
            'https://www.googleapis.com/upload/drive/v3/files'
            '?uploadType=multipart',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'multipart/related; boundary=$boundary',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Backup speichern fehlgeschlagen (${response.statusCode}).',
      );
    }
  }

  Future<void> _updateBackupFile(
    String token,
    String fileId,
    String jsonBody,
  ) async {
    final response = await _client
        .patch(
          Uri.parse(
            'https://www.googleapis.com/upload/drive/v3/files/$fileId'
            '?uploadType=media',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonBody,
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Backup aktualisieren fehlgeschlagen (${response.statusCode}).',
      );
    }
  }
}
