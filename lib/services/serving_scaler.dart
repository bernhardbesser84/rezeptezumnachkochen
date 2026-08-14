/// Rechnet Zutatenmengen um, wenn die Portionszahl geändert wird.
class ServingScaler {
  static int parseCount(String? servings, {int fallback = 2}) {
    if (servings == null) return fallback;
    final match = RegExp(r'(\d+)').firstMatch(servings);
    if (match == null) return fallback;
    final n = int.tryParse(match.group(1)!);
    if (n == null || n < 1) return fallback;
    return n;
  }

  static String formatServings(int count) {
    if (count <= 1) return '1 Portion';
    return '$count Portionen';
  }

  static List<String> scaleAll(
    List<String> ingredients, {
    required int fromServings,
    required int toServings,
  }) {
    if (fromServings < 1 || toServings < 1 || fromServings == toServings) {
      return List<String>.from(ingredients);
    }
    final factor = toServings / fromServings;
    return [
      for (final line in ingredients) scaleLine(line, factor),
    ];
  }

  static String scaleLine(String line, double factor) {
    if (factor == 1) return line;
    final match = _leadingQuantity.firstMatch(line);
    if (match == null) return line;

    final prefix = match.group(1) ?? '';
    final first = _parseNumber(match.group(2)!);
    if (first == null) return line;
    final rangeEndRaw = match.group(3);
    final rest = line.substring(match.end);

    if (rangeEndRaw != null) {
      final last = _parseNumber(rangeEndRaw);
      if (last == null) return line;
      return '$prefix${_formatNumber(first * factor)}–'
          '${_formatNumber(last * factor)}$rest';
    }
    return '$prefix${_formatNumber(first * factor)}$rest';
  }

  static final _leadingQuantity = RegExp(
    r'^(\s*(?:ca\.|circa)\s*)?'
    r'((?:\d+\s+\d+/\d+)|\d+/\d+|\d+(?:[.,]\d+)?)'
    r'(?:\s*[-–—]\s*((?:\d+\s+\d+/\d+)|\d+/\d+|\d+(?:[.,]\d+)?))?',
    caseSensitive: false,
  );

  static double? _parseNumber(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    final mixed = RegExp(r'^(\d+)\s+(\d+)/(\d+)$').firstMatch(t);
    if (mixed != null) {
      final whole = double.tryParse(mixed.group(1)!);
      final num = double.tryParse(mixed.group(2)!);
      final den = double.tryParse(mixed.group(3)!);
      if (whole == null || num == null || den == null || den == 0) return null;
      return whole + (num / den);
    }
    final frac = RegExp(r'^(\d+)/(\d+)$').firstMatch(t);
    if (frac != null) {
      final num = double.tryParse(frac.group(1)!);
      final den = double.tryParse(frac.group(2)!);
      if (num == null || den == null || den == 0) return null;
      return num / den;
    }
    return double.tryParse(t);
  }

  static String _formatNumber(double value) {
    if (value <= 0) return '0';
    if ((value - value.round()).abs() < 0.05) {
      return '${value.round()}';
    }
    final halved = value * 2;
    if ((halved - halved.round()).abs() < 0.08) {
      final halves = halved.round();
      if (halves == 1) return '1/2';
      if (halves % 2 == 1) {
        return '${halves ~/ 2} 1/2';
      }
    }
    final asFixed = value >= 10
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return asFixed.replaceAll('.', ',').replaceFirst(RegExp(r',0$'), '');
  }
}
