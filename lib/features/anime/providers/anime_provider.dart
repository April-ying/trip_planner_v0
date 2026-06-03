import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';

final allAnimesProvider = StreamProvider<List<Anime>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllAnimes();
});

final animeByIdProvider = StreamProvider.family<Anime?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  return db.watchAnimeById(id);
});

final animesForPoiProvider =
    StreamProvider.family<List<Anime>, String>((ref, poiId) {
  final db = ref.watch(databaseProvider);
  return db.watchAnimesForPoi(poiId);
});

final poisByAnimeProvider =
    StreamProvider.family<List<Poi>, String>((ref, animeId) {
  final db = ref.watch(databaseProvider);
  return db.watchPoisByAnime(animeId);
});

final poiCountForAnimeProvider =
    StreamProvider.family<int, String>((ref, animeId) {
  final db = ref.watch(databaseProvider);
  return db.watchPoiCountForAnime(animeId);
});
