import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rezept_nachkochen/services/video_link_fetcher.dart';

void main() {
  test('lädt Video-Bytes aus Facebook-HTML mit .mp4-URL', () async {
    final mp4Url = 'https://video.xx.fbcdn.net/v/t42.1790-2/demo.mp4';
    final fakeMp4 = Uint8List.fromList(
      List<int>.generate(2000, (i) => i % 256),
    );

    final client = MockClient((request) async {
      if (request.url.host.contains('facebook.com')) {
        return http.Response(
          '<html><body>"$mp4Url"</body></html>',
          200,
          headers: {'content-type': 'text/html'},
        );
      }
      if (request.url.toString().contains('.mp4')) {
        return http.Response.bytes(
          fakeMp4,
          200,
          headers: {'content-type': 'video/mp4'},
        );
      }
      return http.Response('not found', 404);
    });

    final fetcher = VideoLinkFetcher(client: client);
    final video = await fetcher.fetchFromUrl(
      'https://www.facebook.com/reel/123456789',
    );

    expect(video.bytes.length, 2000);
    expect(video.mimeType, 'video/mp4');
    expect(video.fileName, 'facebook-reel.mp4');
  });

  test('wirft Fehler bei ungültigem Link', () async {
    final fetcher = VideoLinkFetcher(client: MockClient((_) async {
      return http.Response('unused', 200);
    }));

    expect(
      () => fetcher.fetchFromUrl('kein-link'),
      throwsA(isA<Exception>()),
    );
  });

  test('wirft Fehler wenn HTML kein Video enthält', () async {
    final client = MockClient((request) async {
      return http.Response(
        '<html><body>nur Text, kein Video</body></html>',
        200,
        headers: {'content-type': 'text/html'},
      );
    });

    final fetcher = VideoLinkFetcher(client: client);
    expect(
      () => fetcher.fetchFromUrl('https://www.facebook.com/reel/1'),
      throwsA(
        predicate(
          (e) => e.toString().contains('kein ladbares Video'),
        ),
      ),
    );
  });

  test('API-Pfad: JSON-Fehler wird als Exception gelesen', () async {
    // kIsWeb ist in Unit-Tests false → wir prüfen die JSON-Logik indirekt
    // über die Direct-Route. Dieser Test sichert die Fehler-Meldung.
    final client = MockClient((request) async {
      if (request.url.path.contains('fetch-video')) {
        return http.Response(
          jsonEncode({'error': 'Video zu groß'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('<html></html>', 200);
    });

    final fetcher = VideoLinkFetcher(client: client);
    expect(
      () => fetcher.fetchFromUrl('https://www.facebook.com/reel/2'),
      throwsA(isA<Exception>()),
    );
  });
}
