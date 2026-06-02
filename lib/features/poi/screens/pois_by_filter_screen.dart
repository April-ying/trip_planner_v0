import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../providers/poi_provider.dart';
import '../../../core/widgets/add_speed_dial.dart';
import '../../roi/providers/roi_provider.dart';
import '../../anime/providers/anime_provider.dart';
import '../../tag/providers/tag_provider.dart';
import 'poi_browse_screen.dart';

class PoisByAnimeScreen extends ConsumerWidget {
  final String animeId;

  const PoisByAnimeScreen({super.key, required this.animeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animeAsync = ref.watch(animeByIdProvider(animeId));
    final poisAsync = ref.watch(poisByAnimeProvider(animeId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/pois?tab=anime'),
        ),
        title: animeAsync.maybeWhen(
          data: (anime) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Anime', style: TextStyle(fontSize: 12)),
              Text(anime?.name ?? 'Unknown',
                  style:
                      const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
          orElse: () => const Text('Anime'),
        ),
        actions: [
          animeAsync.maybeWhen(
            data: (anime) => anime == null
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Edit anime',
                    onPressed: () => context.push('/animes/${anime.id}/edit'),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: _PoiListView(
        poisAsync: poisAsync,
        emptyText: 'No POIs for this anime yet',
      ),
      floatingActionButton: AddSpeedDial(
        actions: buildDefaultAddActions(context),
      ),
    );
  }
}

class PoisByTagScreen extends ConsumerWidget {
  final String tagId;

  const PoisByTagScreen({super.key, required this.tagId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagAsync = ref.watch(tagByIdProvider(tagId));
    final poisAsync = ref.watch(poisByTagProvider(tagId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/pois?tab=tag'),
        ),
        title: tagAsync.maybeWhen(
          data: (tag) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tag', style: TextStyle(fontSize: 12)),
              Text(tag?.name ?? 'Unknown',
                  style:
                      const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
          orElse: () => const Text('Tag'),
        ),
        actions: [
          tagAsync.maybeWhen(
            data: (tag) => tag == null
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Edit tag',
                    onPressed: () => context.push('/tags/${tag.id}/edit'),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body:
          _PoiListView(poisAsync: poisAsync, emptyText: 'No POIs for this tag'),
      floatingActionButton: AddSpeedDial(
        actions: buildDefaultAddActions(context),
      ),
    );
  }
}

/// Small leading thumbnail used on POI list tiles. Prefers a user-set
/// cover, otherwise falls back to the first Anitabi-imported reference
/// image. When neither exists (or the file is gone) renders the generic
/// location icon.
class _PoiThumbnail extends ConsumerWidget {
  final Poi poi;
  const _PoiThumbnail({required this.poi});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refsAsync = ref.watch(referenceImagesByPoiProvider(poi.id));
    String? uri = poi.coverImageUri;
    uri ??= refsAsync.maybeWhen(
      data: (refs) => refs.isEmpty ? null : refs.first.localUri,
      orElse: () => null,
    );
    if (uri == null) return const Icon(Icons.location_on);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Image.file(
          File(uri),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const ColoredBox(
              color: Colors.black12, child: Icon(Icons.location_on)),
        ),
      ),
    );
  }
}

class _PoiListView extends ConsumerWidget {
  final AsyncValue poisAsync;
  final String emptyText;

  const _PoiListView({required this.poisAsync, required this.emptyText});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roisAsync = ref.watch(allRoisProvider);
    final roiMap = roisAsync.maybeWhen(
      data: (rois) => {for (final r in rois) r.id: r},
      orElse: () => <String, Roi>{},
    );

    return poisAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
      data: (pois) {
        if (pois.isEmpty) {
          return Center(child: Text(emptyText));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: pois.length,
          itemBuilder: (context, index) {
            final poi = pois[index];
            final roiName = poi.roiId == null ? null : roiMap[poi.roiId]?.name;
            return Card(
              child: ListTile(
                leading: _PoiThumbnail(poi: poi),
                title: Text(poi.name),
                subtitle: roiName != null ? Text(roiName) : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/pois/${poi.id}'),
              ),
            );
          },
        );
      },
    );
  }
}
