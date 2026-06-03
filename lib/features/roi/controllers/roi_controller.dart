import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:drift/drift.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';

part 'roi_controller.g.dart';

@riverpod
class RoiController extends _$RoiController {
  @override
  FutureOr<void> build() {}

  Future<bool> updateRoi({
    required String id,
    required String name,
    required String description,
    int? existingIsOfflineCached,
    int? existingCreatedAt,
  }) async {
    state = const AsyncValue.loading();
    try {
      final db = ref.read(databaseProvider);
      String? nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

      await db.updateRoi(RoisCompanion(
        id: Value(id),
        name: Value(name.trim()),
        description: Value(nullIfEmpty(description)),
        isOfflineCached: Value(existingIsOfflineCached ?? 0),
        createdAt: Value(existingCreatedAt ?? DateTime.now().millisecondsSinceEpoch),
      ));

      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}