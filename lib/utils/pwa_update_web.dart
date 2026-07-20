import 'dart:convert';
import 'dart:js_interop';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

@JS('RezeptPwa')
external RezeptPwaJs? get _rezeptPwa;

/// JS-Bridge zu web/pwa_boot.js
extension type RezeptPwaJs._(JSObject _) implements JSObject {
  external void clearAndReload();
  external JSPromise checkServiceWorkerUpdate();
}

/// Liest /version.json ohne Cache — für den Update-Hinweis.
Future<String?> fetchRemoteBuildId() async {
  try {
    final uri = Uri.parse('version.json').replace(
      queryParameters: {'_': DateTime.now().millisecondsSinceEpoch.toString()},
    );
    final response = await http
        .get(
          uri,
          headers: const {
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map) return null;
    final id = body['buildId']?.toString().trim();
    if (id == null || id.isEmpty) return null;
    return id;
  } catch (_) {
    return null;
  }
}

/// Cache leeren, Service Worker abmelden, Seite hart neu laden.
Future<void> applyPwaUpdate() async {
  final bridge = _rezeptPwa;
  if (bridge != null) {
    bridge.clearAndReload();
    return;
  }
  web.window.location.reload();
}

Future<void> requestServiceWorkerUpdate() async {
  final bridge = _rezeptPwa;
  if (bridge == null) return;
  try {
    await bridge.checkServiceWorkerUpdate().toDart;
  } catch (_) {
    // best-effort
  }
}
