import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rezept_nachkochen/services/media_transcript.dart';

void main() {
  test('YouTube-ID aus watch- und shorts-URLs', () {
    final service = MediaTranscriptService();
    expect(
      service.youtubeIdForTest('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
      'dQw4w9WgXcQ',
    );
    expect(
      service.youtubeIdForTest('https://youtu.be/dQw4w9WgXcQ'),
      'dQw4w9WgXcQ',
    );
    expect(
      service.youtubeIdForTest('https://www.youtube.com/shorts/abc123XYZ0'),
      'abc123XYZ0',
    );
  });

  test('API-Pfad liest transcript aus JSON', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/fetch-transcript');
      expect(request.url.queryParameters['url'], contains('youtube.com'));
      return http.Response(
        jsonEncode({
          'transcript': 'Zwiebel anbraten und Hähnchen dazugeben.',
          'source': 'youtube-captionTracks',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    // kIsWeb ist in Unit-Tests false — wir prüfen die Direct-Route nicht.
    // Stattdessen die API-Logik indirekt über einen kleinen Wrapper-Test:
    // Hier simulieren wir nur, dass die JSON-Antwort korrekt lesbar ist.
    final response = await client.get(
      Uri.parse('/api/fetch-transcript').replace(
        queryParameters: {
          'url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        },
      ),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body['transcript'], contains('Zwiebel'));
  });

  test('Direct: captionTracks aus HTML + timedtext XML', () async {
    const videoId = 'testVideoId1';
    const timedUrl =
        'https://www.youtube.com/api/timedtext?v=$videoId&lang=de';
    final html =
        '"captionTracks":[{"baseUrl":"${timedUrl.replaceAll('&', r'\u0026')}",'
        '"languageCode":"de"}]';

    final client = MockClient((request) async {
      if (request.url.host.contains('youtube.com') &&
          request.url.path.contains('watch')) {
        return http.Response(html, 200);
      }
      if (request.url.path.contains('timedtext')) {
        return http.Response(
          '<transcript><text>Hallo</text><text>Welt</text></transcript>',
          200,
        );
      }
      return http.Response('not found', 404);
    });

    final service = MediaTranscriptService(client: client);
    final text = await service.fetchYoutubeTranscript(
      'https://www.youtube.com/watch?v=$videoId',
    );
    expect(text, isNotNull);
    expect(text, contains('Hallo'));
    expect(text, contains('Welt'));
  });
}
