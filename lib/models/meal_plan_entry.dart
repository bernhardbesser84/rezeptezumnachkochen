/// Ein Eintrag im Wochen-Essensplan: ein Rezept an einem bestimmten Tag.
class MealPlanEntry {
  MealPlanEntry({
    required this.id,
    required this.date,
    required this.recipeId,
    required this.recipeTitle,
    required this.updatedAt,
  });

  final String id;

  /// Kalendertag ohne Uhrzeit (nur Jahr-Monat-Tag).
  final DateTime date;
  final String recipeId;
  final String recipeTitle;
  final DateTime updatedAt;

  /// Stabiler Schlüssel nur für das Datum (YYYY-MM-DD).
  String get dateKey => keyFor(date);

  static String keyFor(DateTime d) {
    final local = DateTime(d.year, d.month, d.day);
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  MealPlanEntry copyWith({
    String? id,
    DateTime? date,
    String? recipeId,
    String? recipeTitle,
    DateTime? updatedAt,
  }) {
    return MealPlanEntry(
      id: id ?? this.id,
      date: date != null ? dateOnly(date) : this.date,
      recipeId: recipeId ?? this.recipeId,
      recipeTitle: recipeTitle ?? this.recipeTitle,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': dateKey,
        'recipeId': recipeId,
        'recipeTitle': recipeTitle,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory MealPlanEntry.fromJson(Map<String, dynamic> json) {
    final parsed = DateTime.tryParse(json['date'] as String? ?? '') ??
        DateTime.now();
    return MealPlanEntry(
      id: json['id'] as String,
      date: dateOnly(parsed),
      recipeId: json['recipeId'] as String? ?? '',
      recipeTitle: json['recipeTitle'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  factory MealPlanEntry.fromCloud(Map<String, dynamic> json) {
    final parsed = DateTime.tryParse(json['date'] as String? ?? '') ??
        DateTime.now();
    return MealPlanEntry(
      id: json['id'] as String,
      date: dateOnly(parsed),
      recipeId: json['recipe_id'] as String? ?? '',
      recipeTitle: json['recipe_title'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toCloud({required String familyCode}) => {
        'id': id,
        'family_code': familyCode,
        'date': dateKey,
        'recipe_id': recipeId,
        'recipe_title': recipeTitle,
        'updated_at': updatedAt.toIso8601String(),
      };
}
