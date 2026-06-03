import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';

final allTagsProvider = StreamProvider<List<Tag>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllTags();
});

final tagByIdProvider = StreamProvider.family<Tag?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  return db.watchTagById(id);
});

final tagsForPoiProvider =
    StreamProvider.family<List<Tag>, String>((ref, poiId) {
  final db = ref.watch(databaseProvider);
  return db.watchTagsForPoi(poiId);
});

final poisByTagProvider =
    StreamProvider.family<List<Poi>, String>((ref, tagId) {
  final db = ref.watch(databaseProvider);
  return db.watchPoisByTag(tagId);
});

final poiCountForTagProvider =
    StreamProvider.family<int, String>((ref, tagId) {
  final db = ref.watch(databaseProvider);
  return db.watchPoiCountForTag(tagId);
});
