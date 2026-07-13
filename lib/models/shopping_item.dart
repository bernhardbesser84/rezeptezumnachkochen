class ShoppingItem {
  ShoppingItem({
    required this.id,
    required this.name,
    required this.checked,
    required this.updatedAt,
    this.recipeId,
    this.recipeTitle,
  });

  final String id;
  final String name;
  final bool checked;
  final DateTime updatedAt;
  final String? recipeId;
  final String? recipeTitle;

  ShoppingItem copyWith({
    String? id,
    String? name,
    bool? checked,
    DateTime? updatedAt,
    String? recipeId,
    String? recipeTitle,
  }) {
    return ShoppingItem(
      id: id ?? this.id,
      name: name ?? this.name,
      checked: checked ?? this.checked,
      updatedAt: updatedAt ?? this.updatedAt,
      recipeId: recipeId ?? this.recipeId,
      recipeTitle: recipeTitle ?? this.recipeTitle,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'checked': checked,
        'updatedAt': updatedAt.toIso8601String(),
        'recipeId': recipeId,
        'recipeTitle': recipeTitle,
      };

  factory ShoppingItem.fromJson(Map<String, dynamic> json) {
    return ShoppingItem(
      id: json['id'] as String,
      name: json['name'] as String,
      checked: json['checked'] as bool? ?? false,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      recipeId: json['recipeId'] as String?,
      recipeTitle: json['recipeTitle'] as String?,
    );
  }

  /// Format aus der Cloud (Supabase: snake_case).
  factory ShoppingItem.fromCloud(Map<String, dynamic> json) {
    return ShoppingItem(
      id: json['id'] as String,
      name: json['name'] as String,
      checked: json['checked'] as bool? ?? false,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      recipeId: json['recipe_id'] as String?,
      recipeTitle: json['recipe_title'] as String?,
    );
  }

  Map<String, dynamic> toCloud({required String familyCode}) => {
        'id': id,
        'family_code': familyCode,
        'name': name,
        'checked': checked,
        'updated_at': updatedAt.toIso8601String(),
        'recipe_id': recipeId,
        'recipe_title': recipeTitle,
      };
}
