import 'package:flutter/material.dart';

import '../services/recipe_category_service.dart';

Future<List<String>?> showRecipeCategoryPicker({
  required BuildContext context,
  required String title,
  required List<String> initialSelection,
  required List<String> suggestedCategories,
  required List<String> existingCategories,
}) async {
  final selected = {
    ...RecipeCategoryService.normalizeAll(initialSelection),
  };
  if (selected.isEmpty) {
    selected.addAll(RecipeCategoryService.normalizeAll(suggestedCategories));
  }
  final suggestions = RecipeCategoryService.normalizeAll(suggestedCategories);
  final known = RecipeCategoryService.normalizeAll([
    ...existingCategories,
    ...suggestions,
    ...selected,
  ]);
  final input = TextEditingController();

  final result = await showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          void addCustomCategory() {
            final normalized = RecipeCategoryService.normalizeOne(input.text);
            if (normalized == null) return;
            setModalState(() {
              if (!known.contains(normalized)) known.add(normalized);
              selected.add(normalized);
              input.clear();
            });
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                      'Du kannst mehrere Kategorien wählen und auch eigene anlegen.',
                    ),
                    const SizedBox(height: 14),
                    if (suggestions.isNotEmpty) ...[
                      const Text(
                        'Vorschläge',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final category in suggestions)
                            FilterChip(
                              label: Text(category),
                              selected: selected.contains(category),
                              onSelected: (isSelected) {
                                setModalState(() {
                                  if (isSelected) {
                                    selected.add(category);
                                  } else {
                                    selected.remove(category);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    const Text(
                      'Eigene Kategorien',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: input,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              hintText: 'Neue Kategorie eingeben',
                            ),
                            onSubmitted: (_) => addCustomCategory(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: addCustomCategory,
                          child: const Text('Hinzufügen'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Builder(
                      builder: (context) {
                        final ownCategories = known
                            .where((c) => !suggestions.contains(c))
                            .toList();
                        if (ownCategories.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final category in ownCategories)
                              FilterChip(
                                label: Text(category),
                                selected: selected.contains(category),
                                onSelected: (isSelected) {
                                  setModalState(() {
                                    if (isSelected) {
                                      selected.add(category);
                                    } else {
                                      selected.remove(category);
                                    }
                                  });
                                },
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(null),
                          child: const Text('Abbrechen'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            final output = selected.toList()
                              ..sort((a, b) =>
                                  a.toLowerCase().compareTo(b.toLowerCase()));
                            Navigator.of(context).pop(output);
                          },
                          child: const Text('Übernehmen'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  input.dispose();
  return result;
}
