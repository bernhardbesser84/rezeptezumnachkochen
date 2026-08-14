import 'dart:convert';

class Recipe {
  Recipe({
    required this.id,
    required this.title,
    required this.ingredients,
    required this.steps,
    required this.sourceUrl,
    required this.createdAt,
    this.servings,
    this.prepTimeMinutes,
    this.notes,
    this.categories = const [],
    this.imageUrl,
  });

  final String id;
  final String title;
  final List<String> ingredients;
  final List<String> steps;
  final String sourceUrl;
  final DateTime createdAt;
  final String? servings;
  final int? prepTimeMinutes;
  final String? notes;
  final List<String> categories;
  final String? imageUrl;

  /// Kategorien aus JSON/Cloud lesen (Liste oder JSON-Text).
  static List<String> parseCategories(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return const [];
      try {
        final decoded = jsonDecode(trimmed);
        return parseCategories(decoded);
      } catch (_) {
        return [trimmed];
      }
    }
    return const [];
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'ingredients': ingredients,
        'steps': steps,
        'sourceUrl': sourceUrl,
        'createdAt': createdAt.toIso8601String(),
        'servings': servings,
        'prepTimeMinutes': prepTimeMinutes,
        'notes': notes,
        'categories': categories,
        'imageUrl': imageUrl,
      };

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      id: json['id'] as String,
      title: json['title'] as String,
      ingredients: (json['ingredients'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      steps: (json['steps'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      sourceUrl: json['sourceUrl'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      servings: json['servings'] as String?,
      prepTimeMinutes: json['prepTimeMinutes'] as int?,
      notes: json['notes'] as String?,
      categories: parseCategories(json['categories']),
      imageUrl: _parseImageUrl(json['imageUrl'] ?? json['image_url']),
    );
  }

  factory Recipe.fromCloud(Map<String, dynamic> json) {
    return Recipe(
      id: json['id'] as String,
      title: json['title'] as String,
      ingredients: (json['ingredients'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      steps: (json['steps'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      sourceUrl: json['source_url'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      servings: json['servings'] as String?,
      prepTimeMinutes: json['prep_time_minutes'] as int?,
      notes: json['notes'] as String?,
      categories: parseCategories(json['categories']),
      imageUrl: _parseImageUrl(json['image_url'] ?? json['imageUrl']),
    );
  }

  Map<String, dynamic> toCloud({required String familyCode}) => {
        'id': id,
        'family_code': familyCode,
        'title': title,
        'ingredients': ingredients,
        'steps': steps,
        'source_url': sourceUrl,
        'created_at': createdAt.toIso8601String(),
        'servings': servings,
        'prep_time_minutes': prepTimeMinutes,
        'notes': notes,
        'categories': categories,
        'image_url': imageUrl,
      };

  Recipe copyWith({
    String? id,
    String? title,
    List<String>? ingredients,
    List<String>? steps,
    String? sourceUrl,
    DateTime? createdAt,
    String? servings,
    int? prepTimeMinutes,
    String? notes,
    List<String>? categories,
    String? imageUrl,
    bool clearNotes = false,
  }) {
    return Recipe(
      id: id ?? this.id,
      title: title ?? this.title,
      ingredients: ingredients ?? this.ingredients,
      steps: steps ?? this.steps,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      createdAt: createdAt ?? this.createdAt,
      servings: servings ?? this.servings,
      prepTimeMinutes: prepTimeMinutes ?? this.prepTimeMinutes,
      notes: clearNotes ? null : (notes ?? this.notes),
      categories: categories ?? this.categories,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  static String? _parseImageUrl(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  /// True, wenn die KI-Auswertung fehlgeschlagen/fehlt und nachgeholt werden kann.
  bool get needsAiEnrichment {
    final notesLower = (notes ?? '').toLowerCase();
    if (notesLower.contains('ki war gerade nicht nutzbar')) return true;
    if (notesLower.contains('erstellt ohne ki')) return true;
    if (notesLower.contains('einfache auswertung ohne ki')) return true;

    final stepText = steps.join(' ').toLowerCase();
    if (stepText.contains('öffne das originalvideo')) return true;
    if (stepText.contains('schritte manuell nach')) return true;
    if (stepText.contains('schritte noch ergänzen')) return true;
    if (stepText.contains('bitte video anhängen')) return true;
    if (stepText.contains('wie im video vorbereitet')) return true;
    return false;
  }
}
