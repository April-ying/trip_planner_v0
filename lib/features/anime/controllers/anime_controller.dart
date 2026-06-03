import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';

part 'anime_controller.g.dart';

@riverpod
class AnimeController extends _$AnimeController {
  @override
  FutureOr<void> build() {}

  Future<bool> saveAnime({
    required bool isNew,
    String? id,
    required String name,
    required String description,
  }) async {
    state = const AsyncValue.loading();
    try {
      final db = ref.read(databaseProvider);
      String? nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

      if (isNew) {
        final newId = const Uuid().v4();
        await db.insertAnime(AnimesCompanion.insert(
          id: newId,
          name: name.trim(),
          description: Value(nullIfEmpty(description)),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
      } else {
        await db.updateAnime(AnimesCompanion(
          id: Value(id!),
          name: Value(name.trim()),
          description: Value(nullIfEmpty(description)),
        ));
      }

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}