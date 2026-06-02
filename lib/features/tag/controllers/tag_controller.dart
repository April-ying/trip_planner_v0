import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';

part 'tag_controller.g.dart';

@riverpod
class TagController extends _$TagController {
  @override
  FutureOr<void> build() {}

  Future<bool> saveTag({
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
        await db.insertTag(TagsCompanion.insert(
          id: newId,
          name: name.trim(),
          description: Value(nullIfEmpty(description)),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
      } else {
        await db.updateTag(TagsCompanion(
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