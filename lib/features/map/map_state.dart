import 'package:freezed_annotation/freezed_annotation.dart';
import '../../core/database/tables.dart';
import '../../core/database/database.dart';

part 'map_state.freezed.dart';

@freezed
class MapState with _$MapState {
  const factory MapState({
    @Default([]) List<Poi> pois,
    Poi? selectedPoi,
    String? selectedRoiId,   // null = 顯示全部
    String? selectedDate,
    @Default(false) bool isLoading,
  }) = _MapState;
}

