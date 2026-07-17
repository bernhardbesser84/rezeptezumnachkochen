import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rezept_nachkochen/services/link_content_fetcher.dart';

void main() {
  test('Facebook kombiniert: Caption + Video aus einem HTML-Abruf', () async {
    final mp4Url = 'https://video.xx.fbcdn.net/v/t42.1790-2/demo.mp4';
    final fakeMp4 = List<int>.generate(2000, (i) => i % 256);
    final html =
        '<html><head>'
        '<meta property="og:title" content="High Protein Döner Wrap" />'
        '<meta property="og:description" content="Zutaten: Hähnchen, Salat" />'
        '"$mp4Url"'
        '</head></html>';

    final client = MockClient((request) async {
      if (request.url.host.contains('facebook.com')) {
        return http.Response(html, 200, headers: {'content-type': 'text/html'});
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

    final fetcher = LinkContentFetcher(client: client);
    final result = await fetcher.fetchFromUrl(
      'https://www.facebook.com/reel/123456789',
    );

    expect(result.hasCaption, isTrue);
    expect(result.caption, contains('Zutaten'));
    expect(result.hasVideo, isTrue);
    expect(result.videoBytes!.length, 2000);
  });
}
