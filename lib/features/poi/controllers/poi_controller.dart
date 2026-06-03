import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';

part 'poi_controller.g.dart';

@riverpod
class PoiController extends _$PoiController {
  @override
  FutureOr<void> build() {}

  /// Handles business logic and database operations for saving a POI.
  ///
  /// Returns the POI id on success (the existing id when editing, or a
  /// freshly generated one when creating) so callers can attach related
  /// records such as a captured photo. Returns null on failure.
  Future<String?> savePoi({
    required String? id,
    required String? roiId,
    required String name,
    required String description,
    required String address,
    required String latStr,
    required String lngStr,
    required String businessHours,
    required String contactInfo,
    required List<String> animeIds,
    required List<String> tagIds,
    String? coverImageUri,
  }) async {
    // Set state to loading to prevent multiple submissions
    state = const AsyncValue.loading();
    
    try {
      final db = ref.read(databaseProvider);
      final poiId = id ?? const Uuid().v4();

      // Business logic: clean up empty strings to store null in DB
      String? nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

      final companion = PoisCompanion(
        id: Value(poiId),
        roiId: Value(roiId),
        name: Value(name.trim()),
        description: Value(nullIfEmpty(description)),
        address: Value(nullIfEmpty(address)),
        lat: Value(double.parse(latStr.trim())),
        lng: Value(double.parse(lngStr.trim())),
        businessHours: Value(nullIfEmpty(businessHours)),
        contactInfo: Value(nullIfEmpty(contactInfo)),
        // Preserve the existing cover on edit. updatePoi does a full-row
        // replace, so passing null here would wipe an Anitabi-imported or
        // user-set cover; callers thread the loaded value back through.
        coverImageUri: Value(coverImageUri),
      );

      // Execute database operations 
      await db.transaction(() async {
        if (id != null) {
          await db.updatePoi(companion);
        } else {
          await db.insertPoi(companion);
        }
        await db.setAnimesForPoi(poiId, animeIds);
        await db.setTagsForPoi(poiId, tagIds);
      });

      // Success: return to normal data state
      state = const AsyncValue.data(null);
      return poiId;
    } catch (e, st) {
      // Error occurred: propagate the error state
      state = AsyncValue.error(e, st);
      return null;
    }
  }
}