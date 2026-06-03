import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';

final poisByRoiProvider =
    StreamProvider.family<List<Poi>, String>((ref, roiId) {
  final db = ref.watch(databaseProvider);
  return db.watchPoisByRoi(roiId);
});

final poisWithoutRoiProvider = StreamProvider<List<Poi>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchPoisWithoutRoi();
});

final poiByIdProvider = StreamProvider.family<Poi, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  return db.watchPoiById(id);
});

final mediaAssetsByPoiProvider =
    StreamProvider.family<List<MediaAsset>, String>((ref, poiId) {
  final db = ref.watch(databaseProvider);
  return db.watchMediaAssetsByPoi(poiId);
});

final referenceImagesByPoiProvider =
    StreamProvider.family<List<ReferenceImage>, String>((ref, poiId) {
  final db = ref.watch(databaseProvider);
  return db.watchReferenceImagesByPoi(poiId);
});

final timeChunksByPoiProvider =
    StreamProvider.family<List<TimeChunk>, String>((ref, poiId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.timeChunks)..where((t) => t.poiId.equals(poiId)))
      .watch();
});

final allPoisProvider = StreamProvider<Map<String, Poi>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllPois().map(
        (pois) => {for (final poi in pois) poi.id: poi},
      );
});
