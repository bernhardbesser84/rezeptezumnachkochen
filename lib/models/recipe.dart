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
      };
}
