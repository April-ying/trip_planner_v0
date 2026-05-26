import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database.dart';
import 'map_state.dart';
import '../../core/database/tables.dart';

final mapNotifierProvider =
    StateNotifierProvider<MapNotifier, MapState>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return MapNotifier(db);
});

class MapNotifier extends StateNotifier<MapState> {
  final AppDatabase _db;

  MapNotifier(this._db) : super(const MapState()) {
    loadPois();
  }

  Future<void> loadPois({String? roiId}) async {
    state = state.copyWith(isLoading: true);
    final pois = roiId != null
        ? await _db.getPoisByRoi(roiId)
        : await _db.getAllPois();
    state = state.copyWith(pois: pois, isLoading: false, selectedRoiId: roiId);
  }

  

  Future<void> loadPoisByDate(String? date) async {
    state = state.copyWith(isLoading: true);
    final pois = date != null
        ? await _db.getPoisByDate(date)
        : await _db.getAllPois();
    state = state.copyWith(
      pois: pois,
      isLoading: false,
      selectedDate: date,
      selectedRoiId: null,
    );
  }

  void selectPoi(Poi? poi) => state = state.copyWith(selectedPoi: poi);

  void clearSelection() => state = state.copyWith(selectedPoi: null);
}