import 'package:flutter_test/flutter_test.dart';
import 'package:rezept_nachkochen/services/youtube_caption.dart';

void main() {
  test('YouTube-IDs aus watch, shorts und youtu.be', () {
    expect(
      youtubeVideoId('https://www.youtube.com/watch?v=jNQXAC9IVRw'),
      'jNQXAC9IVRw',
    );
    expect(
      youtubeVideoId('https://www.youtube.com/shorts/jNQXAC9IVRw?si=abc'),
      'jNQXAC9IVRw',
    );
    expect(youtubeVideoId('https://youtu.be/jNQXAC9IVRw'), 'jNQXAC9IVRw');
    expect(youtubeVideoId('https://facebook.com/reel/1'), isNull);
  });

  test('YouTube-Platzhalter-Caption wird erkannt', () {
    expect(
      isYoutubeGarbageCaption(
        title: 'YouTube',
        caption: 'Teile deine Videos mit Freunden, Verwandten oder der ganzen Welt',
      ),
      isTrue,
    );
    expect(
      isYoutubeGarbageCaption(
        title: 'Big Mac Bowl',
        caption: '🛒 Zutaten (2 Portionen)\n* 400 g Drillinge',
      ),
      isFalse,
    );
  });

  test('Player-HTML liefert Beschreibung nur bei Status OK', () {
    const okHtml = '''
<script>
var ytInitialPlayerResponse = {"playabilityStatus":{"status":"OK"},"videoDetails":{"title":"High Protein Big Mac Bowl","shortDescription":"Zutaten\\n400 g Drillinge"}};
var x = 1;
</script>
''';
    final ok = youtubeDetailsFromPlayerHtml(okHtml);
    expect(ok, isNotNull);
    expect(ok!.title, 'High Protein Big Mac Bowl');
    expect(ok.caption, contains('400 g Drillinge'));

    const blockedHtml = '''
<script>
var ytInitialPlayerResponse = {"playabilityStatus":{"status":"LOGIN_REQUIRED"},"videoDetails":{"title":"YouTube","shortDescription":"Teile deine Videos mit Freunden"}};
</script>
''';
    expect(youtubeDetailsFromPlayerHtml(blockedHtml), isNull);

    const fakeHtml = '''
<script>
var ytInitialPlayerResponse = {"playabilityStatus":{"status":"UNPLAYABLE"},"videoDetails":{"title":"Me at the zoo","shortDescription":"Microplastics are accumulating"}};
</script>
''';
    expect(youtubeDetailsFromPlayerHtml(fakeHtml), isNull);
  });
}
