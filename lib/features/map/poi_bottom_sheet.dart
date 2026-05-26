import 'package:flutter/material.dart';
import '../../../core/database/tables.dart';
import '../../../core/database/database.dart';

class PoiBottomSheet extends StatelessWidget {
  final Poi poi;

  const PoiBottomSheet({super.key, required this.poi});

  @override
  Widget build(BuildContext context) {
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
              child: Image.network(
                poi.coverImageUri!,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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
          if (poi.tags != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: (poi.tags ?? '').split(',')
                  .where((t) => t.trim().isNotEmpty)
                  .map((tag) => Chip(label: Text(tag.trim())))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}