import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/database.dart';

class JsonSync {
  final AppDatabase db;

  JsonSync(this.db);

  Future<String> exportToJson() async {
    final rois = await db.getAllRois();
    final allPois = await db.getAllPois();

    final roiList = <Map<String, dynamic>>[];

    for (final roi in rois) {
      final roiPois = allPois.where((p) => p.roiId == roi.id).toList();
      final poisList = <Map<String, dynamic>>[];

      for (final poi in roiPois) {
        final chunks = await db.getTimeChunksByPoi(poi.id);
        final media = await db.getMediaAssetsByPoi(poi.id);

        poisList.add({
          'id': poi.id,
          'name': poi.name,
          'description': poi.description,
          'address': poi.address,
          'lat': poi.lat,
          'lng': poi.lng,
          'business_hours': poi.businessHours,
          'contact_info': poi.contactInfo,
          'cover_image_uri': poi.coverImageUri,
          'time_chunks': chunks
              .map((c) => {
                    'id': c.id,
                    'date': c.date,
                    'start_time': c.startTime,
                    'end_time': c.endTime,
                    'status': c.status,
                  })
              .toList(),
          'media_assets': media
              .map((m) => {
                    'id': m.id,
                    'type': m.type,
                    'local_uri': m.localUri,
                    'remote_url': m.remoteUrl,
                    'metadata': m.metadata,
                  })
              .toList(),
        });
      }

      roiList.add({
        'id': roi.id,
        'name': roi.name,
        'description': roi.description,
        'is_offline_cached': roi.isOfflineCached,
        'created_at': roi.createdAt,
        'pois': poisList,
      });
    }

    final payload = {
      'export_version': '1.0',
      'exported_at': DateTime.now().toIso8601String(),
      'rois': roiList,
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<void> importFromJson(String jsonString) async {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final rois = data['rois'] as List<dynamic>;

    for (final roiData in rois) {
      final roi = roiData as Map<String, dynamic>;

      await db.into(db.rois).insertOnConflictUpdate(RoisCompanion.insert(
        id: roi['id'] as String,
        name: roi['name'] as String,
        description: Value(roi['description'] as String?),
        isOfflineCached: Value(roi['is_offline_cached'] as int? ?? 0),
        createdAt: roi['created_at'] as int? ??
            DateTime.now().millisecondsSinceEpoch,
      ));

      final pois = roi['pois'] as List<dynamic>? ?? [];
      for (final poiData in pois) {
        final poi = poiData as Map<String, dynamic>;

        await db.into(db.pois).insertOnConflictUpdate(PoisCompanion.insert(
          id: poi['id'] as String,
          roiId: Value(roi['id'] as String),
          name: poi['name'] as String,
          description: Value(poi['description'] as String?),
          address: Value(poi['address'] as String?),
          lat: poi['lat'] as double,
          lng: poi['lng'] as double,
          businessHours: Value(poi['business_hours'] as String?),
          contactInfo: Value(poi['contact_info'] as String?),
          coverImageUri: Value(poi['cover_image_uri'] as String?),
        ));

        final chunks = poi['time_chunks'] as List<dynamic>? ?? [];
        for (final chunkData in chunks) {
          final chunk = chunkData as Map<String, dynamic>;
          await db
              .into(db.timeChunks)
              .insertOnConflictUpdate(TimeChunksCompanion.insert(
                id: chunk['id'] as String,
                poiId: poi['id'] as String,
                date: Value(chunk['date'] as String?),
                startTime: Value(chunk['start_time'] as String?),
                endTime: Value(chunk['end_time'] as String?),
                status: Value(chunk['status'] as String? ?? 'backlog'),
              ));
        }

        final media = poi['media_assets'] as List<dynamic>? ?? [];
        for (final mediaData in media) {
          final m = mediaData as Map<String, dynamic>;
          await db
              .into(db.mediaAssets)
              .insertOnConflictUpdate(MediaAssetsCompanion.insert(
                id: m['id'] as String,
                poiId: poi['id'] as String,
                type: m['type'] as String,
                localUri: m['local_uri'] as String,
                remoteUrl: Value(m['remote_url'] as String?),
                metadata: Value(m['metadata'] as String?),
              ));
        }
      }
    }
  }
}
