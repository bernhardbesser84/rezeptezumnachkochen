import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Zeigt das Vorschaubild eines Rezepts (Link-Bild oder eigenes Foto).
class RecipeCoverImage extends StatelessWidget {
  const RecipeCoverImage({
    super.key,
    required this.imageUrl,
    this.height = 200,
    this.width,
    this.borderRadius = 16,
  });

  final String? imageUrl;
  final double height;
  final double? width;
  final double borderRadius;

  bool get _hasImage => imageUrl != null && imageUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        width: width ?? double.infinity,
        child: _hasImage ? _image() : _placeholder(),
      ),
    );
  }

  Widget _image() {
    final url = imageUrl!.trim();
    Widget image;
    if (url.startsWith('data:image')) {
      final comma = url.indexOf(',');
      final raw = comma >= 0 ? url.substring(comma + 1) : url;
      try {
        image = Image.memory(
          base64Decode(raw),
          fit: BoxFit.cover,
          width: double.infinity,
          height: height,
          errorBuilder: (_, _, _) => _placeholder(),
        );
      } catch (_) {
        image = _placeholder();
      }
    } else {
      image = Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: height,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    return image;
  }

  Widget _placeholder() {
    return ColoredBox(
      color: AppTheme.mistDeep,
      child: Center(
        child: Icon(
          Icons.restaurant_menu,
          color: AppTheme.seed.withValues(alpha: 0.45),
          size: height < 80 ? 28 : 42,
        ),
      ),
    );
  }
}
