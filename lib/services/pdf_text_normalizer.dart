/// Bereinigt aus PDFs extrahierten Text, damit Mengen und Zutaten
/// nicht über viele Zeilen verteilt sind (häufig bei Web-Rezept-PDFs).
class PdfTextNormalizer {
  static const _unicodeFractions = {
    '½': '1/2',
    '¾': '3/4',
    '¼': '1/4',
    '⅓': '1/3',
    '⅔': '2/3',
    '⅛': '1/8',
    '⅜': '3/8',
    '⅝': '5/8',
    '⅞': '7/8',
  };

  static const _units = {
    'tablespoon',
    'tablespoons',
    'teaspoon',
    'teaspoons',
    'cup',
    'cups',
    'oz',
    'lbs',
    'lb',
    'g',
    'mg',
    'kg',
    'ml',
    'l',
    'kcal',
    'mins',
    'min',
  };

  /// Macht aus zerstückeltem PDF-Text lesbare Zeilen.
  static String normalize(String raw) {
    var text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    for (final entry in _unicodeFractions.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }

    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where(_keepLine)
        .toList();

    final merged = _mergeFragmentedLines(lines);
    return merged.join('\n').trim();
  }

  /// Nur erkannte Zutatenzeilen (mit Menge + Einheit) für die KI.
  static String? extractIngredientsSection(String normalized) {
    final lines = extractIngredientLines(normalized);
    if (lines.length < 3) return null;
    return 'Ingredients\n${lines.join('\n')}';
  }

  static List<String> extractIngredientLines(String normalized) {
    final found = <String>[];
    final seen = <String>{};

    for (final line in normalized.split('\n')) {
      final trimmed = line.trim();
      if (!_looksLikeIngredientLine(trimmed)) continue;
      final key = trimmed.toLowerCase();
      if (seen.add(key)) found.add(trimmed);
    }
    return found;
  }

  static bool _looksLikeIngredientLine(String line) {
    if (line.length < 4) return false;
    if (!RegExp(r'^(\d+\.\d+|\d+/\d+|\d+)\s').hasMatch(line)) return false;
    final lower = line.toLowerCase();
    var hasUnit = false;
    for (final unit in _units) {
      if (RegExp('\\b$unit\\b').hasMatch(lower)) hasUnit = true;
    }
    if (!hasUnit && !RegExp(r'\d+\s*(g|mg|ml|l|kg)\b').hasMatch(lower)) {
      return false;
    }

    // Nur „1.5 lbs“ oder „3 tablespoon“ ohne Lebensmittelname = noch unvollständig.
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length == 2 && _isUnitWord(parts[1])) return false;
    if (parts.length == 3 && _isUnitWord(parts[1])) return false;

    return true;
  }

  static bool _keepLine(String line) {
    final lower = line.toLowerCase();
    if (lower.startsWith('http')) return false;
    if (lower.contains('print.grow.me')) return false;
    if (RegExp(r'^seite \d+ von \d+$', caseSensitive: false).hasMatch(line)) {
      return false;
    }
    if (RegExp(r'^\d{2}\.\d{2}\.\d{2}').hasMatch(line)) return false;
    if (lower == 'from' || lower == 'votes') return false;
    return true;
  }

  static List<String> _mergeFragmentedLines(List<String> lines) {
    final out = <String>[];
    var buffer = '';

    for (final line in lines) {
      if (_isSectionHeader(line)) {
        if (buffer.isNotEmpty) {
          out.add(buffer.trim());
          buffer = '';
        }
        out.add(line);
        continue;
      }

      if (buffer.isEmpty) {
        buffer = line;
        continue;
      }

      if (_shouldJoin(buffer, line)) {
        buffer = '$buffer $line';
      } else {
        out.add(buffer.trim());
        buffer = line;
      }
    }

    if (buffer.isNotEmpty) out.add(buffer.trim());
    return out;
  }

  static bool _isSectionHeader(String line) {
    final lower = line.toLowerCase();
    const headers = {
      'ingredients',
      'instructions',
      'equipment',
      'notes',
      'storage',
      'tips',
      'nutrition',
      'salmon',
      'sauce',
      'prep time',
      'cook time',
      'total time',
    };
    return headers.contains(lower) ||
        RegExp(r'^(course|cuisine|keyword|servings|calories|author):',
                caseSensitive: false)
            .hasMatch(line);
  }

  static bool _shouldJoin(String buffer, String next) {
    // Neue Zutat beginnt mit Zahl — nicht an „Large pot“ o. Ä. anhängen.
    if (_isNumericFragment(next) && !_startsWithQuantity(buffer)) {
      return false;
    }
    if (_looksLikeIngredientLine(buffer)) return false;
    if (_isNumericFragment(next)) return true;
    if (_isUnitWord(next)) return true;
    if (RegExp(r'(\d+/\d+|\d+\.?\d*)$').hasMatch(buffer.trim())) return true;
    if (_isUnitWord(buffer.split(' ').last) &&
        !next.startsWith(RegExp(r'^\d'))) {
      return true;
    }
    return false;
  }

  static bool _startsWithQuantity(String line) {
    return RegExp(r'^(\d+\.\d+|\d+/\d+|\d+)\b').hasMatch(line.trim());
  }

  static bool _isNumericFragment(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    return RegExp(r'^\d+\.?\d*$').hasMatch(v) ||
        RegExp(r'^\d+/\d+$').hasMatch(v);
  }

  static bool _isUnitWord(String value) {
    return _units.contains(value.trim().toLowerCase());
  }
}

/// Korrigiert häufige Fehler in Zutatenzeilen nach der KI-Auswertung.
class IngredientQuantityNormalizer {
  static const _unicodeFractions = PdfTextNormalizer._unicodeFractions;

  static String normalize(String line) {
    var s = line.trim();
    if (s.isEmpty) return s;

    for (final entry in _unicodeFractions.entries) {
      s = s.replaceAll(entry.key, entry.value);
    }

    // KI schreibt manchmal nur "/2 EL" statt "1/2 EL".
    s = s.replaceFirstMapped(RegExp(r'^/(\d+)\b'), (m) => '1/${m[1]}');

    // Leerzeichen zwischen Menge und Einheit.
    s = s.replaceAllMapped(
      RegExp(
        r'^(\d+(?:\.\d+)?|\d+/\d+)\s*(EL|TL|g|kg|ml|l|Cup|Prise|Stück)\b',
        caseSensitive: false,
      ),
      (m) => '${m[1]} ${m[2]}',
    );

    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<String> normalizeAll(List<String> lines) {
    return lines.map(normalize).toList();
  }
}
