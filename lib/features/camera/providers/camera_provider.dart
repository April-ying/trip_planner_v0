import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class CameraState {
  final bool isInitialized;
  final File? referenceImage;
  final String? referenceImageId;
  // Whether the reference overlay should currently be painted on top
  // of the live preview. The reference itself stays in state when
  // toggled off so the user can flick it back on without re-picking.
  final bool overlayVisible;
  final String? poiId;
  final String? error;
  final Offset overlayOffset;
  final double overlayScale;
  final double overlayOpacity;

  const CameraState({
    this.isInitialized = false,
    this.referenceImage,
    this.referenceImageId,
    this.overlayVisible = true,
    this.poiId,
    this.error,
    this.overlayOffset = Offset.zero,
    this.overlayScale = 1,
    this.overlayOpacity = 0.55,
  });

  CameraState copyWith({
    bool? isInitialized,
    File? referenceImage,
    String? referenceImageId,
    bool? overlayVisible,
    String? poiId,
    String? error,
    Offset? overlayOffset,
    double? overlayScale,
    double? overlayOpacity,
    bool clearReferenceImage = false,
    bool clearReferenceImageId = false,
    bool clearError = false,
  }) {
    return CameraState(
      isInitialized: isInitialized ?? this.isInitialized,
      referenceImage:
          clearReferenceImage ? null : (referenceImage ?? this.referenceImage),
      referenceImageId: (clearReferenceImage || clearReferenceImageId)
          ? null
          : (referenceImageId ?? this.referenceImageId),
      overlayVisible: overlayVisible ?? this.overlayVisible,
      poiId: poiId ?? this.poiId,
      error: clearError ? null : (error ?? this.error),
      overlayOffset: overlayOffset ?? this.overlayOffset,
      overlayScale: overlayScale ?? this.overlayScale,
      overlayOpacity: overlayOpacity ?? this.overlayOpacity,
    );
  }
}

class CameraNotifier extends StateNotifier<CameraState> {
  CameraNotifier() : super(const CameraState());

  void initialize(String? poiId) {
    state = state.copyWith(poiId: poiId, isInitialized: true, clearError: true);
  }

  void setCameraError(String message) {
    state = state.copyWith(error: message);
  }

  void setReferenceImage(File file, {String? referenceImageId}) {
    state = state.copyWith(
      referenceImage: file,
      referenceImageId: referenceImageId,
      clearReferenceImageId: referenceImageId == null,
      overlayVisible: true,
      overlayOffset: Offset.zero,
      overlayScale: 1,
      overlayOpacity: 0.55,
    );
  }

  void clearReferenceImage() {
    state = state.copyWith(clearReferenceImage: true);
  }

  /// Flip the overlay's visibility without throwing away the reference
  /// itself — the eye-icon toggle uses this so the user can hide the
  /// overlay temporarily and bring it back without re-picking from
  /// the library.
  void toggleOverlayVisibility() {
    state = state.copyWith(overlayVisible: !state.overlayVisible);
  }

  void updateOverlayTransform({
    required Offset offset,
    required double scale,
  }) {
    state = state.copyWith(
      overlayOffset: offset,
      overlayScale: scale.clamp(0.35, 4).toDouble(),
    );
  }

  void setOverlayOpacity(double opacity) {
    state = state.copyWith(overlayOpacity: opacity.clamp(0.1, 1).toDouble());
  }

  void resetOverlay() {
    state = state.copyWith(
      overlayOffset: Offset.zero,
      overlayScale: 1,
      overlayOpacity: 0.55,
    );
  }

  void setPoiId(String id) {
    state = state.copyWith(poiId: id);
  }
}

final cameraProvider =
    StateNotifierProvider.autoDispose<CameraNotifier, CameraState>(
  (ref) => CameraNotifier(),
);
