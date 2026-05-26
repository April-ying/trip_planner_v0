import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; //add for map
part 'database.g.dart';



@DriftDatabase(tables: [Rois, Pois, TimeChunks, MediaAssets, ReferenceImages])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(referenceImages);
          }
          if (from < 3) {
            await m.addColumn(mediaAssets, mediaAssets.referenceImageId);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // --- ROI Queries ---
  Future<List<Roi>> getAllRois() => select(rois).get();

  Stream<List<Roi>> watchAllRois() => select(rois).watch();

  Future<Roi> getRoiById(String id) =>
      (select(rois)..where((r) => r.id.equals(id))).getSingle();

  Stream<Roi> watchRoiById(String id) =>
      (select(rois)..where((r) => r.id.equals(id))).watchSingle();

  Future<int> insertRoi(RoisCompanion roi) => into(rois).insert(roi);

  Future<bool> updateRoi(RoisCompanion roi) => update(rois).replace(
        Roi(
          id: roi.id.value,
          name: roi.name.value,
          description: roi.description.value,
          isOfflineCached: roi.isOfflineCached.value,
          createdAt: roi.createdAt.value,
        ),
      );

  Future<int> deleteRoi(String id) =>
      (delete(rois)..where((r) => r.id.equals(id))).go();

  // --- POI Queries ---
  Future<List<Poi>> getPoisByRoi(String roiId) =>
      (select(pois)..where((p) => p.roiId.equals(roiId))).get();

  Stream<List<Poi>> watchPoisByRoi(String roiId) =>
      (select(pois)..where((p) => p.roiId.equals(roiId))).watch();

  Future<Poi> getPoiById(String id) =>
      (select(pois)..where((p) => p.id.equals(id))).getSingle();

  Stream<Poi> watchPoiById(String id) =>
      (select(pois)..where((p) => p.id.equals(id))).watchSingle();

  Stream<List<Poi>> watchAllPois() => select(pois).watch();

  Stream<List<Poi>> watchPoisByAnimeSeries(String name) =>
      (select(pois)..where((p) => p.animeSeriesRef.equals(name))).watch();

  Stream<List<Poi>> watchPoisByTag(String tag) {
    return select(pois).watch().map((rows) {
      return rows.where((p) {
        final tagStr = p.tags?.trim();
        if (tagStr == null || tagStr.isEmpty) return false;
        final tagList = tagStr.split(',').map((t) => t.trim());
        return tagList.contains(tag);
      }).toList();
    });
  }

  Future<int> insertPoi(PoisCompanion poi) => into(pois).insert(poi);

  Future<bool> updatePoi(PoisCompanion poi) => update(pois).replace(
        Poi(
          id: poi.id.value,
          roiId: poi.roiId.value,
          name: poi.name.value,
          description: poi.description.value,
          address: poi.address.value,
          lat: poi.lat.value,
          lng: poi.lng.value,
          businessHours: poi.businessHours.value,
          contactInfo: poi.contactInfo.value,
          coverImageUri: poi.coverImageUri.value,
          tags: poi.tags.value,
          animeSeriesRef: poi.animeSeriesRef.value,
        ),
      );

  Future<List<Poi>> getAllPois() => select(pois).get();

  Future<List<Poi>> getPoisByDate(String date) async {
    final chunks = await (select(timeChunks)
        ..where((t) => t.date.equals(date))).get();
    final poiIds = chunks.map((c) => c.poiId).toList();
    if (poiIds.isEmpty) return [];
    return (select(pois)
        ..where((p) => p.id.isIn(poiIds))).get();
  }

  Stream<List<String>> watchDistinctAnimeSeries() {
    return select(pois).watch().map((rows) {
      final series = <String>{};
      for (final p in rows) {
        final name = p.animeSeriesRef?.trim();
        if (name != null && name.isNotEmpty) {
          series.add(name);
        }
      }
      return series.toList()..sort();
    });
  }

  Stream<List<String>> watchDistinctTags() {
    return select(pois).watch().map((rows) {
      final tags = <String>{};
      for (final p in rows) {
        final tagStr = p.tags?.trim();
        if (tagStr == null || tagStr.isEmpty) continue;
        for (final t in tagStr.split(',')) {
          final trimmed = t.trim();
          if (trimmed.isNotEmpty) tags.add(trimmed);
        }
      }
      return tags.toList()..sort();
    });
  }

  Future<int> deletePoi(String id) =>
      (delete(pois)..where((p) => p.id.equals(id))).go();

  // --- TimeChunk Queries ---
  Future<List<TimeChunk>> getTimeChunksByPoi(String poiId) =>
      (select(timeChunks)..where((t) => t.poiId.equals(poiId))).get();

  Stream<List<TimeChunk>> watchTimeChunksByDate(String date) =>
      (select(timeChunks)..where((t) => t.date.equals(date))).watch();

  Stream<List<TimeChunk>> watchBacklogChunks() => (select(timeChunks)
        ..where((t) => t.status.equals('backlog')))
      .watch();

  Future<int> insertTimeChunk(TimeChunksCompanion chunk) =>
      into(timeChunks).insert(chunk);

  Future<bool> updateTimeChunk(TimeChunksCompanion chunk) =>
      update(timeChunks).replace(
        TimeChunk(
          id: chunk.id.value,
          poiId: chunk.poiId.value,
          date: chunk.date.value,
          startTime: chunk.startTime.value,
          endTime: chunk.endTime.value,
          status: chunk.status.value,
        ),
      );

  Stream<List<TimeChunk>> watchAllScheduledChunks() => (select(timeChunks)
        ..where((t) => t.status.equals('scheduled'))
        ..orderBy([(t) => OrderingTerm.asc(t.date)]))
      .watch();

  Future<int> deleteTimeChunk(String id) =>
      (delete(timeChunks)..where((t) => t.id.equals(id))).go();

  // --- MediaAsset Queries ---
  Future<List<MediaAsset>> getMediaAssetsByPoi(String poiId) =>
      (select(mediaAssets)..where((m) => m.poiId.equals(poiId))).get();

  Stream<List<MediaAsset>> watchMediaAssetsByPoi(String poiId) =>
      (select(mediaAssets)..where((m) => m.poiId.equals(poiId))).watch();

  Future<int> insertMediaAsset(MediaAssetsCompanion asset) =>
      into(mediaAssets).insert(asset);

  Future<int> updateMediaAssetLocalUri(String id, String localUri) =>
      (update(mediaAssets)..where((m) => m.id.equals(id))).write(
        MediaAssetsCompanion(localUri: Value(localUri)),
      );

  Future<int> deleteMediaAsset(String id) =>
      (delete(mediaAssets)..where((m) => m.id.equals(id))).go();

  // --- ReferenceImage Queries ---
  Future<List<ReferenceImage>> getReferenceImagesByPoi(String poiId) =>
      (select(referenceImages)..where((r) => r.poiId.equals(poiId))).get();

  Stream<List<ReferenceImage>> watchReferenceImagesByPoi(String poiId) =>
      (select(referenceImages)..where((r) => r.poiId.equals(poiId))).watch();

  Future<int> insertReferenceImage(ReferenceImagesCompanion image) =>
      into(referenceImages).insert(image);

  Future<int> updateReferenceImageLocalUri(String id, String localUri) =>
      (update(referenceImages)..where((r) => r.id.equals(id))).write(
        ReferenceImagesCompanion(localUri: Value(localUri)),
      );

  Future<int> deleteReferenceImage(String id) =>
      (delete(referenceImages)..where((r) => r.id.equals(id))).go();
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'trip_planner.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}



final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase()); // add for map