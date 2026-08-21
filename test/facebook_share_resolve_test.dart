import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rezept_nachkochen/services/facebook_share_resolve.dart';
import 'package:rezept_nachkochen/services/video_link_fetcher.dart';
import 'dart:typed_data';

void main() {
  test('extrahiert Reel-ID aus Plugin-Location', () {
    final reel = FacebookShareResolve.extractReelFromPluginHref(
      'https://m.facebook.com/plugins/video.php?'
      'href=https%3A%2F%2Fwww.facebook.com%2Freel%2F1072010665321936%2F'
      '&show_text=1&width=500',
    );
    expect(reel, 'https://www.facebook.com/reel/1072010665321936/');
  });

  test('Share-Story-Link wird über Plugin zur Reel-URL aufgelöst', () async {
    final client = MockClient((request) async {
      final path = request.url.path;
      final href = request.url.queryParameters['href'] ?? '';

      if (path.contains('/share/r/')) {
        return http.Response(
          '',
          302,
          headers: {
            'location':
                'https://www.facebook.com/story.php?story_fbid=122134117437353596&id=61590607882789',
          },
        );
      }
      if (path.contains('story.php')) {
        return http.Response(
          '',
          302,
          headers: {
            'location':
                'https://www.facebook.com/login/?next=https://www.facebook.com/story.php',
          },
        );
      }
      if (path.contains('/plugins/post.php') ||
          path.contains('/plugins/video.php')) {
        if (href.contains('story.php') || href.contains('/share/r/')) {
          return http.Response(
            '',
            301,
            headers: {
              'location':
                  'https://m.facebook.com/plugins/video.php?href=https%3A%2F%2Fwww.facebook.com%2Freel%2F1072010665321936%2F&show_text=1&width=500',
            },
          );
        }
        if (href.contains('/reel/1072010665321936')) {
          return http.Response('<html>ok</html>', 200);
        }
      }
      if (path.contains('/reel/1072010665321936')) {
        return http.Response('<html>reel</html>', 200);
      }
      return http.Response('missing', 404);
    });

    final resolver = FacebookShareResolve(client: client);
    final urls = await resolver.expandCandidateUrls(
      'https://www.facebook.com/share/r/1CYjkXzFgv/?mibextid=wwXlfr',
    );
    expect(
      urls.any((u) => u.contains('/reel/1072010665321936')),
      isTrue,
    );
  });

  test('lädt Video nach Story→Reel-Auflösung', () async {
    final fakeMp4 = Uint8List.fromList(List<int>.filled(2200, 7));
    final client = MockClient((request) async {
      final path = request.url.path;
      final href = request.url.queryParameters['href'] ?? '';

      if (request.url.host.contains('fbcdn.net')) {
        return http.Response.bytes(fakeMp4, 200, headers: {
          'content-type': 'video/mp4',
        });
      }
      if (path.contains('/share/r/')) {
        return http.Response(
          '',
          302,
          headers: {
            'location':
                'https://www.facebook.com/story.php?story_fbid=1&id=2',
          },
        );
      }
      if (path.contains('story.php')) {
        return http.Response(
          '',
          302,
          headers: {'location': 'https://www.facebook.com/login/?next=x'},
        );
      }
      if (path.contains('/plugins/')) {
        if (href.contains('story.php') || href.contains('/share/r/')) {
          return http.Response(
            '',
            301,
            headers: {
              'location':
                  'https://m.facebook.com/plugins/video.php?href=https%3A%2F%2Fwww.facebook.com%2Freel%2F999888777%2F',
            },
          );
        }
        return http.Response('ok', 200);
      }
      if (path.contains('/reel/999888777')) {
        return http.Response(
          '<html><head>'
          '<meta property="og:video" content="https://video.xx.fbcdn.net/v/t42/wrap.mp4?oh=1" />'
          '</head></html>',
          200,
        );
      }
      // m.facebook share/mobile variants
      return http.Response('missing', 404);
    });

    final fetcher = VideoLinkFetcher(client: client);
    final video = await fetcher.fetchFromUrl(
      'https://www.facebook.com/share/r/1CYjkXzFgv/',
    );
    expect(video.bytes.length, 2200);
    expect(video.fileName, 'facebook-reel.mp4');
  });
}
