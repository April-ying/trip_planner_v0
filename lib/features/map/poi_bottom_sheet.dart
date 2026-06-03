import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database.dart';
import 'package:trip_planner/features/tag/providers/tag_provider.dart';

class PoiBottomSheet extends ConsumerWidget {
  final Poi poi;

  const PoiBottomSheet({super.key, required this.poi});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(tagsForPoiProvider(poi.id));
    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.25,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          // 拖曳把手
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (poi.coverImageUri != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(poi.coverImageUri!),
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  height: 180,
                  color: Colors.black12,
                  child: const Icon(Icons.broken_image, size: 48),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(poi.name,
              style: Theme.of(context).textTheme.titleLarge),
          if (poi.address != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.location_on, size: 16),
              const SizedBox(width: 4),
              Expanded(child: Text(poi.address!,
                  style: Theme.of(context).textTheme.bodySmall)),
            ]),
          ],
          if (poi.description != null) ...[
            const SizedBox(height: 8),
            Text(poi.description!),
          ],
          if (poi.businessHours != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.access_time, size: 16),
              const SizedBox(width: 4),
              Text(poi.businessHours!,
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ],
          ...tagsAsync.maybeWhen(
            data: (tags) => tags.isEmpty
                ? const []
                : [
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      children: tags
                          .map((tag) => Chip(label: Text(tag.name)))
                          .toList(),
                    ),
                  ],
            orElse: () => const [],
          ),
        ],
      ),
    );
  }
}