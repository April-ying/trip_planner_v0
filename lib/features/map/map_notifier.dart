import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_provider.dart';
import 'map_state.dart';
import '../../core/database/tables.dart';

final mapNotifierProvider =
    StateNotifierProvider<MapNotifier, MapState>((ref) {
  final db = ref.watch(databaseProvider);
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

  /// 清除日期篩選，並重新載入不限日期的 POI 資料
  Future<void> clearDateFilter() async {
    state = state.copyWith(isLoading: true);
    
    // 重新撈取全部或原本區域的 POI
    final pois = await _db.getAllPois(); 
    
    state = state.copyWith(
      pois: pois,
      isLoading: false,
      selectedDate: null, // ✨ 明確地在這裡把狀態清空
    );
  }
}