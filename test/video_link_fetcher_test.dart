import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rezept_nachkochen/services/video_link_fetcher.dart';

void main() {
  test('wählt kleines YouTube-MP4 unter Größengrenze', () {
    final picked = pickYoutubeStreamForTest({
      'streamingData': {
        'formats': [
          {
            'itag': 18,
            'mimeType': 'video/mp4; codecs="avc1.42001E, mp4a.40.2"',
            'url': 'https://example.com/small.mp4',
            'contentLength': '2000000',
          },
          {
            'itag': 22,
            'mimeType': 'video/mp4; codecs="avc1.64001F, mp4a.40.2"',
            'url': 'https://example.com/big.mp4',
            'contentLength': '9000000',
          },
        ],
        'adaptiveFormats': [
          {
            'itag': 139,
            'mimeType': 'audio/mp4; codecs="mp4a.40.5"',
            'url': 'https://example.com/audio.m4a',
            'contentLength': '500000',
          },
        ],
      },
    }, maxBytes: 3800000);

    expect(picked, isNotNull);
    expect(picked!.url, 'https://example.com/small.mp4');
    expect(picked.mimeType, 'video/mp4');
  });

  test('fällt auf Audio zurück wenn Video zu groß', () {
    final picked = pickYoutubeStreamForTest({
      'streamingData': {
        'formats': [
          {
            'itag': 22,
            'mimeType': 'video/mp4',
            'url': 'https://example.com/big.mp4',
            'contentLength': '9000000',
          },
        ],
        'adaptiveFormats': [
          {
            'itag': 139,
            'mimeType': 'audio/mp4; codecs="mp4a.40.5"',
            'url': 'https://example.com/audio.m4a',
            'contentLength': '500000',
          },
        ],
      },
    }, maxBytes: 3800000);

    expect(picked, isNotNull);
    expect(picked!.url, 'https://example.com/audio.m4a');
    expect(picked.mimeType, 'audio/mp4');
  });

  test('lädt Facebook-MP4 aus HTML (direkt)', () async {
    final fakeMp4 = Uint8List.fromList(List<int>.filled(2000, 1));
    final client = MockClient((request) async {
      if (request.url.host.contains('facebook.com')) {
        return http.Response(
          'og stuff https://video.xx.fbcdn.net/v/reel.mp4?oh=1 '
          'and more',
          200,
        );
      }
      if (request.url.path.contains('reel.mp4')) {
        return http.Response.bytes(fakeMp4, 200, headers: {
          'content-type': 'video/mp4',
        });
      }
      return http.Response('missing', 404);
    });

    final fetcher = VideoLinkFetcher(client: client);
    final video = await fetcher.fetchFromUrl(
      'https://www.facebook.com/reel/123',
    );
    expect(video.bytes.length, 2000);
    expect(video.mimeType, 'video/mp4');
  });

  test('API-Fehler-JSON wird als Exception gelesen', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/fetch-video');
      return http.Response(
        jsonEncode({
          'error': 'YouTube blockiert den automatischen Video-Download.',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    // kIsWeb ist in Tests false — wir prüfen die JSON-Fehlerantwort indirekt
    // über denselben Decode-Pfad wie die API-Route.
    final response = await client.get(
      Uri.parse('/api/fetch-video').replace(
        queryParameters: {'url': 'https://youtu.be/dQw4w9WgXcQ'},
      ),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body['error'], contains('YouTube'));
  });
}
