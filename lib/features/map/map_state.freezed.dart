// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'map_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$MapState {
  List<Poi> get pois => throw _privateConstructorUsedError;
  Poi? get selectedPoi => throw _privateConstructorUsedError;
  String? get selectedRoiId =>
      throw _privateConstructorUsedError; // null = 顯示全部
  String? get selectedDate => throw _privateConstructorUsedError;
  bool get isLoading => throw _privateConstructorUsedError;

  /// Create a copy of MapState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MapStateCopyWith<MapState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MapStateCopyWith<$Res> {
  factory $MapStateCopyWith(MapState value, $Res Function(MapState) then) =
      _$MapStateCopyWithImpl<$Res, MapState>;
  @useResult
  $Res call({
    List<Poi> pois,
    Poi? selectedPoi,
    String? selectedRoiId,
    String? selectedDate,
    bool isLoading,
  });
}

/// @nodoc
class _$MapStateCopyWithImpl<$Res, $Val extends MapState>
    implements $MapStateCopyWith<$Res> {
  _$MapStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MapState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? pois = null,
    Object? selectedPoi = freezed,
    Object? selectedRoiId = freezed,
    Object? selectedDate = freezed,
    Object? isLoading = null,
  }) {
    return _then(
      _value.copyWith(
            pois: null == pois
                ? _value.pois
                : pois // ignore: cast_nullable_to_non_nullable
                      as List<Poi>,
            selectedPoi: freezed == selectedPoi
                ? _value.selectedPoi
                : selectedPoi // ignore: cast_nullable_to_non_nullable
                      as Poi?,
            selectedRoiId: freezed == selectedRoiId
                ? _value.selectedRoiId
                : selectedRoiId // ignore: cast_nullable_to_non_nullable
                      as String?,
            selectedDate: freezed == selectedDate
                ? _value.selectedDate
                : selectedDate // ignore: cast_nullable_to_non_nullable
                      as String?,
            isLoading: null == isLoading
                ? _value.isLoading
                : isLoading // ignore: cast_nullable_to_non_nullable
                      as bool,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$MapStateImplCopyWith<$Res>
    implements $MapStateCopyWith<$Res> {
  factory _$$MapStateImplCopyWith(
    _$MapStateImpl value,
    $Res Function(_$MapStateImpl) then,
  ) = __$$MapStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    List<Poi> pois,
    Poi? selectedPoi,
    String? selectedRoiId,
    String? selectedDate,
    bool isLoading,
  });
}

/// @nodoc
class __$$MapStateImplCopyWithImpl<$Res>
    extends _$MapStateCopyWithImpl<$Res, _$MapStateImpl>
    implements _$$MapStateImplCopyWith<$Res> {
  __$$MapStateImplCopyWithImpl(
    _$MapStateImpl _value,
    $Res Function(_$MapStateImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MapState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? pois = null,
    Object? selectedPoi = freezed,
    Object? selectedRoiId = freezed,
    Object? selectedDate = freezed,
    Object? isLoading = null,
  }) {
    return _then(
      _$MapStateImpl(
        pois: null == pois
            ? _value._pois
            : pois // ignore: cast_nullable_to_non_nullable
                  as List<Poi>,
        selectedPoi: freezed == selectedPoi
            ? _value.selectedPoi
            : selectedPoi // ignore: cast_nullable_to_non_nullable
                  as Poi?,
        selectedRoiId: freezed == selectedRoiId
            ? _value.selectedRoiId
            : selectedRoiId // ignore: cast_nullable_to_non_nullable
                  as String?,
        selectedDate: freezed == selectedDate
            ? _value.selectedDate
            : selectedDate // ignore: cast_nullable_to_non_nullable
                  as String?,
        isLoading: null == isLoading
            ? _value.isLoading
            : isLoading // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc

class _$MapStateImpl implements _MapState {
  const _$MapStateImpl({
    final List<Poi> pois = const [],
    this.selectedPoi,
    this.selectedRoiId,
    this.selectedDate,
    this.isLoading = false,
  }) : _pois = pois;

  final List<Poi> _pois;
  @override
  @JsonKey()
  List<Poi> get pois {
    if (_pois is EqualUnmodifiableListView) return _pois;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_pois);
  }

  @override
  final Poi? selectedPoi;
  @override
  final String? selectedRoiId;
  // null = 顯示全部
  @override
  final String? selectedDate;
  @override
  @JsonKey()
  final bool isLoading;

  @override
  String toString() {
    return 'MapState(pois: $pois, selectedPoi: $selectedPoi, selectedRoiId: $selectedRoiId, selectedDate: $selectedDate, isLoading: $isLoading)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MapStateImpl &&
            const DeepCollectionEquality().equals(other._pois, _pois) &&
            const DeepCollectionEquality().equals(
              other.selectedPoi,
              selectedPoi,
            ) &&
            (identical(other.selectedRoiId, selectedRoiId) ||
                other.selectedRoiId == selectedRoiId) &&
            (identical(other.selectedDate, selectedDate) ||
                other.selectedDate == selectedDate) &&
            (identical(other.isLoading, isLoading) ||
                other.isLoading == isLoading));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    const DeepCollectionEquality().hash(_pois),
    const DeepCollectionEquality().hash(selectedPoi),
    selectedRoiId,
    selectedDate,
    isLoading,
  );

  /// Create a copy of MapState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MapStateImplCopyWith<_$MapStateImpl> get copyWith =>
      __$$MapStateImplCopyWithImpl<_$MapStateImpl>(this, _$identity);
}

abstract class _MapState implements MapState {
  const factory _MapState({
    final List<Poi> pois,
    final Poi? selectedPoi,
    final String? selectedRoiId,
    final String? selectedDate,
    final bool isLoading,
  }) = _$MapStateImpl;

  @override
  List<Poi> get pois;
  @override
  Poi? get selectedPoi;
  @override
  String? get selectedRoiId; // null = 顯示全部
  @override
  String? get selectedDate;
  @override
  bool get isLoading;

  /// Create a copy of MapState
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MapStateImplCopyWith<_$MapStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
