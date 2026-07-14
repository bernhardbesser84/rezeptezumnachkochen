import 'package:flutter/services.dart';

/// Ergebnis vom Lesen der Zwischenablage (Clipboard = kopierter Text).
class ClipboardPasteResult {
  const ClipboardPasteResult._({this.text, this.errorMessage});

  const ClipboardPasteResult.ok(String text) : this._(text: text);

  const ClipboardPasteResult.fail(String errorMessage)
      : this._(errorMessage: errorMessage);

  final String? text;
  final String? errorMessage;

  bool get isOk => text != null && text!.isNotEmpty;
}

/// Liest Text aus der Zwischenablage.
/// Auf dem iPhone (Safari) schlägt das oft fehl — dann kommt eine klare Meldung.
Future<ClipboardPasteResult> readClipboardText() async {
  try {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      return const ClipboardPasteResult.fail(
        'Zwischenablage ist leer. Bitte den Text zuerst kopieren, '
        'dann erneut auf „einfügen“ tippen.',
      );
    }
    return ClipboardPasteResult.ok(text);
  } catch (_) {
    return const ClipboardPasteResult.fail(
      'Einfügen nicht möglich. Tippe lange ins Textfeld und wähle „Einfügen“.',
    );
  }
}
