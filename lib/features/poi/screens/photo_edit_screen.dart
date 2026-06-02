import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../../camera/services/reinhard_match_service.dart';
import '../providers/poi_provider.dart';
import '../services/brightness_service.dart';
import '../services/edit_preview_service.dart';
import '../services/media_asset_service.dart';
import '../services/sharpness_service.dart';
import 'collage_page.dart';

/// One step in the edit history.
///
/// Filters chain: every step's [toolBaseBytes] is the previous step's
/// committed [bytes] (or the editor's downscaled `_editingBaseBytes`
/// for the very first step), so a sequence like Match Color → Brightness
/// → Sharpness stacks effects on top of each other instead of throwing
/// the previous one away.
///
/// `bytes == null` means the step has been created but not yet committed
/// (the user is still dialling in the slider); on Confirm we compute the
/// byte-buffer result against [toolBaseBytes] and populate [bytes].
///
/// Tool-specific fields (`matchedBaseBytes` + `strength` for Match
/// Color, `brightness`, `sharpness`) ride along so a slider drag can
/// mutate the current step rather than spam undo with one history entry
/// per slider tick.
@immutable
class _EditState {
  final Uint8List? bytes;
  final String? tool;
  final Uint8List? toolBaseBytes;
  final Uint8List? matchedBaseBytes;
  final double strength;
  final double brightness;
  final double sharpness;

  const _EditState({
    this.bytes,
    this.tool,
    this.toolBaseBytes,
    this.matchedBaseBytes,
    this.strength = 1.0,
    this.brightness = 0,
    this.sharpness = 0,
  });

  _EditState copyWith({
    Uint8List? bytes,
    String? tool,
    Uint8List? toolBaseBytes,
    Uint8List? matchedBaseBytes,
    double? strength,
    double? brightness,
    double? sharpness,
  }) {
    return _EditState(
      bytes: bytes ?? this.bytes,
      tool: tool ?? this.tool,
      toolBaseBytes: toolBaseBytes ?? this.toolBaseBytes,
      matchedBaseBytes: matchedBaseBytes ?? this.matchedBaseBytes,
      strength: strength ?? this.strength,
      brightness: brightness ?? this.brightness,
      sharpness: sharpness ?? this.sharpness,
    );
  }
}

/// Standalone photo editor — reads everything it needs from its
/// constructor args and saves directly via [persistMediaAsset], so the
/// same screen serves both the live camera flow ("just shot this") and
/// the POI-detail flow ("picked this from gallery") without either
/// path needing to seed any global state. Lives under `poi/screens`
/// because the result is a POI's media asset; reuses the colour-match
/// service that still ships from the camera feature.
class PhotoEditScreen extends ConsumerStatefulWidget {
  /// POI whose media assets list the saved photo joins.
  final String poiId;

  /// File on disk that this screen edits in place — the editor writes
  /// the edited bytes back onto this path before [persistMediaAsset]
  /// copies it into permanent app storage. Callers should hand over a
  /// temp copy (for gallery picks) or the camera's own capture file
  /// (which already lives in cache), not a path it can't safely mutate.
  final String sourcePath;

  /// Optional anime-scene reference: when set, the editor allows the
  /// reference-overlay toggle, the swipe-to-reference page, and the
  /// Match Color chip. When null, all three are disabled.
  final String? referencePath;

  /// If a reference image is provided, the matching `ReferenceImages`
  /// row id is passed through to the saved `MediaAsset` so the
  /// before/after pair survives in the database.
  final String? referenceImageId;

  /// `true` when [sourcePath] is a gallery-picked image rather than a
  /// fresh camera capture, picked up by [persistMediaAsset] so the
  /// resulting row's `type` column is `uploaded_image` and the POI
  /// detail list renders the upload icon.
  final bool wasUpload;

  const PhotoEditScreen({
    super.key,
    required this.poiId,
    required this.sourcePath,
    this.referencePath,
    this.referenceImageId,
    this.wasUpload = false,
  });

  @override
  ConsumerState<PhotoEditScreen> createState() => _PhotoEditScreenState();
}

class _PhotoEditScreenState extends ConsumerState<PhotoEditScreen> {
  // History always starts with the original (bytes: null, tool: null).
  // _historyIndex points at the currently-visible step; tapping a tool
  // truncates anything past it and appends the new step.
  List<_EditState> _history = const [_EditState()];
  int _historyIndex = 0;

  // Reference image is mutable — the AppBar's photo_library button lets
  // the user swap it (or add one when there isn't one yet) without
  // leaving the editor. When the swap happens we drop any pending
  // Match Color result because the matched bytes were computed against
  // the old reference and would mislead the user.
  String? _referencePath;
  String? _referenceImageId;

  // Reference overlay starts visible (when a reference image is in
  // play) to match the live camera — the floating bar provides the eye
  // toggle to hide / re-show it without leaving the canvas.
  bool _showOverlay = true;
  // Overlay pan / pinch / opacity, matched to the live camera's
  // reference overlay so behaviour transfers across screens.
  Offset _overlayOffset = Offset.zero;
  // Starts at 0.8 (not 1) so that when the user first toggles the
  // overlay on, the reference image is clearly inset from the canvas
  // edges — otherwise a full-size overlay can blanket the underlying
  // photo so completely that the user can't tell anything changed.
  double _overlayScale = 0.8;
  double _overlayOpacity = 0.4;
  Offset _gestureStartOffset = Offset.zero;
  Offset _gestureStartFocalPoint = Offset.zero;
  double _gestureStartScale = 1;

  bool _processing = false;
  bool _saving = false;

  // Downscaled (1024 px long edge) copy of the source built once on
  // editor mount. Every preview compute — Match Color's Reinhard,
  // Sharpness prepare, the canvas Image.memory — runs against this
  // instead of the full-res source, so each tool's first interactive
  // result lands in well under a second on a 12 MP shot. Save still
  // re-runs each tool's effect on the full-res source so disk quality
  // isn't downscaled.
  Uint8List? _editingBaseBytes;
  bool _preparingEditingBase = false;

  // Cached downscaled source + blur for the Sharpness preview path.
  // Built once when the user enters Sharpness mode (faster now that
  // the input is already the 1024 px editing base), reused across
  // every slider release after that.
  PreparedSharpness? _sharpnessCache;
  bool _preparingSharpness = false;

  // When true the editor shows the Compose (collage) page instead of the
  // Adjust page. Kept alive in an IndexedStack so going Back to Adjust
  // doesn't lose placed cutout / overlay layers. Only reachable when a
  // reference image is in play (the cutout source).
  bool _collagePage = false;

  // True while the user is actively dialling in a tool's parameters.
  // In this submode the AppBar swaps to Cancel + tool name + Confirm,
  // the bottom tool row hides, and the active slider becomes the only
  // interactive control — committing or backing out is the only way
  // to switch tools.
  bool _inEditMode = false;

  // After each Confirm, a background `compute()` is scheduled to run
  // the same filter chain on the **full-resolution source** (and to
  // chain on top of the previous step's full-res checkpoint). The
  // Future is stored here keyed by `_historyIndex`, so when the user
  // hits Save the editor just awaits this Future — if the background
  // job already finished, Save returns instantly; if not, Save waits
  // for whatever remains instead of doubling the compute cost.
  //
  // Cleared from the map whenever the step's params change (new push,
  // re-Confirm with different slider value) so the next replay rebuilds
  // against the new state.
  final Map<int, Future<Uint8List?>> _fullResCheckpoints = {};

  _EditState get _current => _history[_historyIndex];
  bool get _canUndo => _historyIndex > 0;
  bool get _canRedo => _historyIndex < _history.length - 1;

  /// Tools with a committed step in the active chain (≤ `_historyIndex`). Their
  /// tool button shows an "applied" (blue) state; because it's derived from the
  /// history index, undo/redo automatically re-colours the icons as the stack
  /// is walked.
  Set<String> get _appliedTools {
    final applied = <String>{};
    for (var i = 1; i <= _historyIndex && i < _history.length; i++) {
      final step = _history[i];
      if (step.tool != null && step.bytes != null) applied.add(step.tool!);
    }
    return applied;
  }

  /// Bytes that a freshly-tapped tool chip should chain on top of —
  /// the most recent committed bytes in history, or the downscaled
  /// editing base when nothing has been confirmed yet.
  Uint8List? get _chainBase {
    for (var i = _historyIndex; i >= 0; i--) {
      final b = _history[i].bytes;
      if (b != null) return b;
    }
    return _editingBaseBytes;
  }

  File get _sourceFile => File(widget.sourcePath);
  File? get _referenceFile =>
      _referencePath != null ? File(_referencePath!) : null;
  bool get _hasReference => _referencePath != null;

  @override
  void initState() {
    super.initState();
    _referencePath = widget.referencePath;
    _referenceImageId = widget.referenceImageId;
    unawaited(_prepareEditingBase());
  }

  /// Decode the source + downscale to 1024 px long edge once, cache
  /// the resulting JPEG bytes. Every preview compute reads from this
  /// instead of decoding the source repeatedly, so a 12 MP JPEG only
  /// pays its ~300-500 ms decode cost a single time per editing
  /// session.
  Future<void> _prepareEditingBase() async {
    setState(() => _preparingEditingBase = true);
    try {
      final sourceBytes = await _sourceFile.readAsBytes();
      final downscaled = await compute(downscaleForEditing, sourceBytes);
      if (!mounted) return;
      setState(() => _editingBaseBytes = downscaled);
    } finally {
      if (mounted) setState(() => _preparingEditingBase = false);
    }
  }

  void _pushHistory(_EditState state) {
    // Drop any redo branch when a new edit is applied past an undo.
    final oldIndex = _historyIndex;
    final base = _historyIndex < _history.length - 1
        ? _history.sublist(0, _historyIndex + 1)
        : List<_EditState>.from(_history);
    base.add(state);
    _history = base;
    _historyIndex = _history.length - 1;
    // Background full-res checkpoints for the truncated redo branch
    // are stale now — drop them so a future Save doesn't reuse the
    // wrong filter chain. Running futures complete in the background
    // and their results just get dropped.
    _fullResCheckpoints.removeWhere((k, _) => k > oldIndex);
  }

  void _undo() {
    if (!_canUndo) return;
    setState(() => _historyIndex--);
  }

  void _redo() {
    if (!_canRedo) return;
    setState(() => _historyIndex++);
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Runs the given compute-safe match algorithm against the current
  /// source + reference bytes and pushes the result onto the edit
  /// history. Filters are applied against the **original** source
  /// image (not the previous filter's output), so tapping a different
  /// chip swaps filter rather than stacking it — undo lets the user
  /// step back through previously-applied filters.
  Future<void> _runMatch(
    String activeTool,
    Future<Uint8List> Function(MatchArgs) algorithm, {
    bool storeMatchedBase = false,
  }) async {
    final ref = _referenceFile;
    if (ref == null) return;
    if (_processing) return;
    // Re-tapping the same chip while already on this tool's step just
    // re-enters edit submode without recomputing the (still-cached)
    // matched bytes — useful after Confirm when the user wants to
    // fine-tune the slider again.
    if (_current.tool == activeTool && _current.matchedBaseBytes != null) {
      setState(() => _inEditMode = true);
      return;
    }
    final existing = _stepIndexForTool(activeTool);
    if (existing != -1 && _history[existing].matchedBaseBytes != null) {
      _revisitStep(existing); // revisit the single Match instance
      return;
    }
    // Chain on top of whatever filters have already been confirmed —
    // Reinhard runs against the previous step's bytes (or the editing
    // base when nothing has landed yet), not against the raw source.
    final base = _chainBase;
    if (base == null) return;

    setState(() => _processing = true);
    try {
      final referenceBytes = await ref.readAsBytes();
      final result = await compute(
        algorithm,
        MatchArgs(
          capturedBytes: base,
          referenceBytes: referenceBytes,
        ),
      );
      if (!mounted) return;
      setState(() {
        _pushHistory(_EditState(
          // bytes left null until the user Confirms — slider drag
          // previews via Stack opacity on top of `toolBaseBytes`, so
          // there's no need to commit a byte buffer until then.
          tool: activeTool,
          toolBaseBytes: base,
          matchedBaseBytes: storeMatchedBase ? result : null,
          strength: 1.0,
        ));
        _inEditMode = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Match failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// Replace the current history step with [update] applied to it.
  /// Slider drags shouldn't push a new history step every frame, so
  /// instead the current entry's tool params get mutated in place —
  /// undo still goes back to before the tool was tapped.
  void _mutateCurrent(_EditState Function(_EditState) update) {
    setState(() {
      final newHistory = List<_EditState>.from(_history);
      newHistory[_historyIndex] = update(_current);
      _history = newHistory;
    });
  }

  void _setStrength(double value) {
    if (_current.tool != 'match' || _current.matchedBaseBytes == null) return;
    _mutateCurrent((s) => s.copyWith(strength: value));
  }

  /// Brightness drag mutates the live state — the canvas re-renders
  /// the source image through a `ColorFilter.matrix` matrix in real
  /// time, so the user gets immediate visual feedback without any
  /// per-frame compute. The byte-buffer adjust isn't needed until the
  /// user actually saves: `_resolveBytesForSave` runs it once against
  /// the source so the JPEG that lands on disk matches the canvas.
  void _setBrightness(double value) {
    if (_current.tool != 'brightness') return;
    _mutateCurrent((s) => s.copyWith(brightness: value));
  }

  void _setSharpness(double value) {
    if (_current.tool != 'sharpness') return;
    _mutateCurrent((s) => s.copyWith(sharpness: value));
  }

  /// Pre-compute the Sharpness preview cache (downscaled source +
  /// blurred buffer). Idempotent — early-returns if it's already
  /// built or in-flight.
  Future<void> _prepareSharpnessCache() async {
    if (_sharpnessCache != null || _preparingSharpness) return;
    // Cache is per-chain-step — the bytes the user is about to
    // sharpen are this step's `toolBaseBytes` (= the previous
    // filter's committed result), not the raw editing base.
    final baseBytes = _current.toolBaseBytes ?? _editingBaseBytes;
    if (baseBytes == null) return;
    setState(() => _preparingSharpness = true);
    try {
      final prepared = await compute(prepareSharpness, baseBytes);
      if (!mounted) return;
      setState(() => _sharpnessCache = prepared);
    } finally {
      if (mounted) setState(() => _preparingSharpness = false);
    }
  }

  Future<void> _commitSharpness(double value) async {
    if (_current.tool != 'sharpness') return;
    if (_processing) return;
    final cache = _sharpnessCache;
    final base = _current.toolBaseBytes ?? _editingBaseBytes;
    if (base == null) return;
    setState(() => _processing = true);
    try {
      final Uint8List result;
      if (cache != null) {
        // Fast path — combine on the cached prepare (downscaled +
        // pre-blurred copy of `toolBaseBytes`), encode a small JPEG.
        result = await compute(
          applySharpnessQuick,
          QuickSharpnessArgs(prepared: cache, amount: value),
        );
      } else {
        // Cache wasn't ready yet — run the full path on this step's
        // base bytes. Slower but the next release will be fast.
        result = await compute(
          applySharpness,
          SharpnessArgs(sourceBytes: base, amount: value),
        );
      }
      if (!mounted) return;
      _mutateCurrent((s) => s.copyWith(bytes: result, sharpness: value));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// Brightness / Sharpness chip taps push a fresh history step with
  /// the relevant tool selected — slider starts at the no-op value
  /// (0) so the displayed image equals the source until the user
  /// drags. Tapping the chip again with the same tool already active
  /// is a no-op so it doesn't reset slider state mid-edit.
  void _runBrightness() {
    if (_current.tool == 'brightness') {
      setState(() => _inEditMode = true);
      return;
    }
    final existing = _stepIndexForTool('brightness');
    if (existing != -1) {
      _revisitStep(existing); // one instance per tool — revisit, don't stack
      return;
    }
    final base = _chainBase;
    if (base == null) return;
    setState(() {
      _pushHistory(_EditState(tool: 'brightness', toolBaseBytes: base));
      _inEditMode = true;
    });
  }

  void _runSharpness() {
    if (_current.tool == 'sharpness') {
      setState(() => _inEditMode = true);
      return;
    }
    final existing = _stepIndexForTool('sharpness');
    if (existing != -1) {
      _revisitStep(existing);
      _sharpnessCache = null;
      unawaited(_prepareSharpnessCache());
      return;
    }
    final base = _chainBase;
    if (base == null) return;
    setState(() {
      _pushHistory(_EditState(tool: 'sharpness', toolBaseBytes: base));
      _inEditMode = true;
    });
    // Sharpness cache is tied to a specific `toolBaseBytes`, so a new
    // chain step always needs a fresh prepare.
    _sharpnessCache = null;
    unawaited(_prepareSharpnessCache());
  }

  /// Jump back to an already-applied tool's step to re-dial its value (showing
  /// its current params). Editing discards any redo branch; tools applied after
  /// it stay in the chain and are replayed on Confirm.
  void _revisitStep(int index) {
    setState(() {
      if (_historyIndex < _history.length - 1) {
        _history = _history.sublist(0, _historyIndex + 1);
      }
      _historyIndex = index;
      _inEditMode = true;
    });
  }

  /// Commit the current tool's dialled-in result into the history
  /// step's `bytes` field, then exit edit submode. The next tool the
  /// user picks chains on top of these bytes — that's how stacking
  /// filters works.
  ///
  /// Sharpness already commits on each slider release, so it only
  /// needs a no-op confirm. Brightness's preview lives entirely in
  /// the `ColorFilter` widget, so Confirm runs the byte-buffer
  /// adjust here. Match Color lerps the cached match against the
  /// step's `toolBaseBytes` according to the current strength.
  Future<void> _confirmEdit() async {
    if (_processing) return;
    final state = _current;
    final base = state.toolBaseBytes ?? _editingBaseBytes;
    if (base == null) {
      setState(() => _inEditMode = false);
      return;
    }

    setState(() => _processing = true);
    try {
      Uint8List? newBytes;
      switch (state.tool) {
        case 'match':
          if (state.matchedBaseBytes != null) {
            final t = state.strength.clamp(0.0, 1.0);
            if (t >= 0.999) {
              newBytes = state.matchedBaseBytes;
            } else if (t <= 0.001) {
              newBytes = base;
            } else {
              newBytes = await compute(
                lerpJpegs,
                LerpArgs(
                  jpegA: base,
                  jpegB: state.matchedBaseBytes!,
                  strength: t,
                ),
              );
            }
          }
          break;
        case 'brightness':
          if (state.brightness != 0) {
            newBytes = await compute(
              applyBrightness,
              BrightnessArgs(
                sourceBytes: base,
                brightness: state.brightness,
              ),
            );
          } else {
            newBytes = base;
          }
          break;
        case 'sharpness':
          if (state.bytes != null) {
            newBytes = state.bytes;
          } else if (state.sharpness != 0) {
            // No release happened yet (user confirmed without
            // touching the slider). Quick-path against the cache
            // when ready, otherwise full-path on `base`.
            final cache = _sharpnessCache;
            if (cache != null) {
              newBytes = await compute(
                applySharpnessQuick,
                QuickSharpnessArgs(prepared: cache, amount: state.sharpness),
              );
            } else {
              newBytes = await compute(
                applySharpness,
                SharpnessArgs(sourceBytes: base, amount: state.sharpness),
              );
            }
          } else {
            newBytes = base;
          }
          break;
      }
      if (!mounted) return;
      if (newBytes != null) {
        _mutateCurrent((s) => s.copyWith(bytes: newBytes));
      }
      final editedIndex = _historyIndex;
      // Replay any later tools on top of this step's new result, so revisiting
      // an earlier adjustment keeps the later ones instead of dropping them.
      await _replayDownstream(editedIndex);
      if (!mounted) return;
      setState(() {
        _historyIndex = _history.length - 1; // show the full composed result
        _inEditMode = false;
      });
      // The edited step + everything downstream changed — drop their stale
      // full-res checkpoints and reschedule for the chain end.
      _fullResCheckpoints.removeWhere((k, _) => k >= editedIndex);
      _scheduleFullResCheckpoint(_historyIndex);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  /// Schedule a background `compute()` for the full-res result of the
  /// filter at [idx]. Idempotent — early-returns if the checkpoint is
  /// already in the map (running or completed). The actual work runs
  /// in a worker isolate; Save just awaits the Future stored here.
  void _scheduleFullResCheckpoint(int idx) {
    if (idx <= 0) return;
    if (_fullResCheckpoints.containsKey(idx)) return;
    // Capture the step + reference at scheduling time so a later
    // re-Confirm (which will reschedule with new params) can't make
    // this Future see mutated state mid-run.
    final step = _history[idx];
    final referenceFile = _referenceFile;
    _fullResCheckpoints[idx] =
        _computeFullResForStep(idx, step, referenceFile);
  }

  Future<Uint8List?> _computeFullResForStep(
    int idx,
    _EditState step,
    File? referenceFile,
  ) async {
    if (idx <= 0) return null;

    // Resolve the base: either the source (for the very first filter)
    // or recursively the previous step's full-res checkpoint.
    Uint8List baseBytes;
    if (idx == 1) {
      baseBytes = await _sourceFile.readAsBytes();
    } else {
      if (!_fullResCheckpoints.containsKey(idx - 1)) {
        _scheduleFullResCheckpoint(idx - 1);
      }
      final prevFuture = _fullResCheckpoints[idx - 1];
      if (prevFuture == null) return null;
      final prev = await prevFuture;
      if (prev == null) return null;
      baseBytes = prev;
    }

    switch (step.tool) {
      case 'match':
        if (referenceFile == null) return baseBytes;
        final t = step.strength.clamp(0.0, 1.0);
        if (t <= 0.001) return baseBytes;
        final referenceBytes = await referenceFile.readAsBytes();
        final matched = await compute(
          reinhardMatch,
          MatchArgs(
            capturedBytes: baseBytes,
            referenceBytes: referenceBytes,
          ),
        );
        if (t >= 0.999) return matched;
        return compute(
          lerpJpegs,
          LerpArgs(jpegA: baseBytes, jpegB: matched, strength: t),
        );
      case 'brightness':
        if (step.brightness == 0) return baseBytes;
        return compute(
          applyBrightness,
          BrightnessArgs(
            sourceBytes: baseBytes,
            brightness: step.brightness,
          ),
        );
      case 'sharpness':
        if (step.sharpness == 0) return baseBytes;
        return compute(
          applySharpness,
          SharpnessArgs(
            sourceBytes: baseBytes,
            amount: step.sharpness,
          ),
        );
      default:
        return baseBytes;
    }
  }

  /// Index of the committed step for [tool] in the active chain
  /// (1.._historyIndex), or -1 — so re-tapping a tool revisits its single
  /// instance instead of stacking a duplicate.
  int _stepIndexForTool(String tool) {
    for (var i = 1; i <= _historyIndex && i < _history.length; i++) {
      if (_history[i].tool == tool && _history[i].bytes != null) return i;
    }
    return -1;
  }

  /// Re-apply [step]'s tool to [base] (preview resolution) — used to replay the
  /// later tools after an earlier one is revisited.
  Future<Uint8List?> _recomputePreview(_EditState step, Uint8List base) async {
    switch (step.tool) {
      case 'brightness':
        if (step.brightness == 0) return base;
        return compute(applyBrightness,
            BrightnessArgs(sourceBytes: base, brightness: step.brightness));
      case 'sharpness':
        if (step.sharpness == 0) return base;
        return compute(applySharpness,
            SharpnessArgs(sourceBytes: base, amount: step.sharpness));
      case 'match':
        final ref = _referenceFile;
        if (ref == null || step.matchedBaseBytes == null) return base;
        final t = step.strength.clamp(0.0, 1.0);
        if (t <= 0.001) return base;
        if (t >= 0.999) return step.matchedBaseBytes;
        return compute(
            lerpJpegs,
            LerpArgs(
                jpegA: base, jpegB: step.matchedBaseBytes!, strength: t));
      default:
        return base;
    }
  }

  /// After the step at [from] changes, replay every later tool on top of it so
  /// revisiting an earlier adjustment keeps the later ones. Re-matches Match
  /// against the new upstream so its colour transfer stays correct.
  Future<void> _replayDownstream(int from) async {
    final ref = _referenceFile;
    for (var j = from + 1; j < _history.length; j++) {
      final prev = _history[j - 1].bytes;
      if (prev == null) continue;
      var step = _history[j];
      if (step.tool == 'match' && ref != null) {
        final refBytes = await ref.readAsBytes();
        final matched = await compute(
            reinhardMatch, MatchArgs(capturedBytes: prev, referenceBytes: refBytes));
        step = step.copyWith(matchedBaseBytes: matched);
      }
      final recomputed = await _recomputePreview(step, prev);
      _history[j] = step.copyWith(toolBaseBytes: prev, bytes: recomputed);
    }
  }

  /// Discard the tool's history step and exit edit submode — same
  /// effect as undo + closing the slider strip, used by the AppBar's
  /// Cancel button while a tool is being edited.
  void _cancelEdit() {
    setState(() {
      if (_historyIndex > 0) _historyIndex--;
      _inEditMode = false;
    });
  }

  String _editModeTitle() {
    switch (_current.tool) {
      case 'match':
        return 'Match Color';
      case 'brightness':
        return 'Brightness';
      case 'sharpness':
        return 'Sharpness';
      default:
        return '';
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final db = ref.read(databaseProvider);

    setState(() => _saving = true);
    try {
      // Single-shot save: write the edited bytes over the source so
      // persistMediaAsset's copy-into-storage step picks them up, then
      // record the matching MediaAsset row.
      final bytesToWrite = await _resolveBytesForSave();
      if (bytesToWrite != null) {
        await _sourceFile.writeAsBytes(bytesToWrite, flush: true);
      }
      final ok = await persistMediaAsset(
        db: db,
        source: _sourceFile,
        poiId: widget.poiId,
        type: widget.wasUpload ? 'uploaded_image' : 'user_photo',
        referenceImageId: _referenceImageId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Photo saved.' : 'Save failed.')),
      );
      if (ok) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _back() {
    Navigator.of(context).pop();
  }

  /// Replace the reference image by picking from this POI's
  /// `ReferenceImages` rows — keeping the foreign-key link so the
  /// saved MediaAsset records which reference frame it was matched
  /// against. When the user is editing through a Match Color result,
  /// push a fresh original step on top of the history — the existing
  /// matched bytes were computed against the previous reference and
  /// would be misleading to keep displayed.
  Future<void> _changeReference() async {
    if (_processing) return;
    final images = await ref
        .read(referenceImagesByPoiProvider(widget.poiId).future);
    if (!mounted) return;
    if (images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('No reference images on this POI. Add some on its page.'),
        ),
      );
      return;
    }

    final picked = await showModalBottomSheet<ReferenceImage>(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (ctx) => ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: images.length,
        itemBuilder: (ctx, index) {
          final image = images[index];
          final file = File(image.localUri);
          return ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 52,
                height: 52,
                child: Image.file(
                  file,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Colors.black26,
                    child: Icon(Icons.broken_image, color: Colors.white54),
                  ),
                ),
              ),
            ),
            title: Text(
              p.basenameWithoutExtension(image.localUri),
              style: const TextStyle(color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => Navigator.pop(ctx, image),
          );
        },
      ),
    );
    if (picked == null) return;
    if (!mounted) return;
    final file = File(picked.localUri);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image file not found: ${picked.localUri}')),
      );
      return;
    }
    setState(() {
      _referencePath = picked.localUri;
      _referenceImageId = picked.id;
      _overlayOffset = Offset.zero;
      _overlayScale = 0.8;
      _overlayOpacity = 0.4;
      if (_current.tool == 'match') {
        _pushHistory(const _EditState());
      }
      // Changing the reference invalidates any in-progress edit; drop
      // back to main mode so the user can re-enter a tool against the
      // new reference.
      _inEditMode = false;
    });
  }

  void _resetOverlay() {
    setState(() {
      _overlayOffset = Offset.zero;
      _overlayScale = 0.8;
      _overlayOpacity = 0.4;
    });
  }

  /// Save reads the cached background full-res result for the current
  /// history step instead of replaying filters inline. The Future is
  /// scheduled at Confirm time, so by the time the user reaches Save
  /// it is either already done (instant) or just finishing (waits the
  /// remaining ms). If nothing has been Confirmed yet, returns null
  /// so persistMediaAsset records the original untouched source.
  Future<Uint8List?> _resolveBytesForSave() async {
    if (_historyIndex <= 0) return null;
    if (!_fullResCheckpoints.containsKey(_historyIndex)) {
      _scheduleFullResCheckpoint(_historyIndex);
    }
    final future = _fullResCheckpoints[_historyIndex];
    if (future == null) return null;
    try {
      return await future;
    } catch (_) {
      return null;
    }
  }

  /// Bottom strip — centered slider for the active tool's continuous
  /// param above, horizontal row of icon-above-label tool buttons +
  /// Save below. Modelled on Google Photos: each tool reads as a
  /// little icon with its label underneath, the slider lives on its
  /// own centered row above the tool icons so it doesn't have to
  /// share width with the buttons.
  Widget _buildBottomStrip(
    ThemeData theme,
    bool hasReference,
    String? activeTool,
  ) {
    final slider = _activeSliderForTool(activeTool, theme);
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (slider != null) ...[
            slider,
            if (!_inEditMode) const SizedBox(height: 4),
          ],
          // Tool row hides while a tool is being dialled in — the
          // AppBar's Cancel / Confirm pair is the only legal way to
          // switch tools while editing, so the row would just be a
          // distracting accidental-tap target if it stayed visible.
          if (!_inEditMode)
            SizedBox(
              // 72 px (not 64) gives the two-line "Match\nColor" label
              // enough vertical room without truncating; single-line
              // labels stay vertically centered.
              height: 72,
              child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // 4 buttons × ~72 px easily fits the narrowest phone
                // width, so Center keeps them as a balanced row in the
                // middle. The scroll view is just a safety net for if
                // a 5th tool gets added later and overflows a small
                // screen.
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ToolButton(
                      icon: Icons.palette,
                      // Force two lines so the label stays readable
                      // inside the 72 px button — `Match Color` on one
                      // line gets truncated to `Match C…`.
                      label: 'Match\nColor',
                      enabled: hasReference && !_processing,
                      disabledHint:
                          hasReference ? null : 'No reference image',
                      selected: activeTool == 'match',
                      applied: _appliedTools.contains('match'),
                      onTap: () => _runMatch(
                        'match',
                        reinhardMatch,
                        storeMatchedBase: true,
                      ),
                    ),
                    _ToolButton(
                      icon: Icons.brightness_6,
                      label: 'Brightness',
                      enabled: !_processing,
                      selected: activeTool == 'brightness',
                      applied: _appliedTools.contains('brightness'),
                      onTap: _runBrightness,
                    ),
                    _ToolButton(
                      icon: Icons.deblur,
                      label: 'Sharpness',
                      enabled: !_processing,
                      selected: activeTool == 'sharpness',
                      applied: _appliedTools.contains('sharpness'),
                      onTap: _runSharpness,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the centered slider widget for the currently-active tool,
  /// or `null` when the active tool has no continuous param or the
  /// editor isn't in edit submode (sliders only appear while the user
  /// is dialling in a tool; the dialled-in result is shown in main
  /// mode without the slider so the canvas can take the full height).
  Widget? _activeSliderForTool(String? activeTool, ThemeData theme) {
    if (!_inEditMode) return null;
    switch (activeTool) {
      case 'match':
        if (_current.matchedBaseBytes == null) return null;
        return _LabelledSlider(
          label: 'Strength',
          value: _current.strength.clamp(0.0, 1.0),
          min: 0,
          max: 1,
          theme: theme,
          onChanged: _setStrength,
        );
      case 'brightness':
        return _LabelledSlider(
          label: 'Brightness',
          value: _current.brightness.clamp(-0.5, 0.5),
          min: -0.5,
          max: 0.5,
          centerZero: true,
          theme: theme,
          onChanged: _setBrightness,
        );
      case 'sharpness':
        return _LabelledSlider(
          label: 'Sharpness',
          value: _current.sharpness.clamp(0.0, 1.0),
          min: 0,
          max: 1,
          theme: theme,
          onChanged: _setSharpness,
          onChangeEnd: _commitSharpness,
        );
      default:
        return null;
    }
  }

  /// Builds the edited captured image.
  ///
  /// In edit submode the preview chains on top of the current step's
  /// `toolBaseBytes` (= the previous filter's committed result). That
  /// way a Match Color → Brightness → Sharpness sequence visibly
  /// stacks instead of resetting to the source each time. Outside of
  /// edit mode the canvas just renders the current step's committed
  /// `bytes`, or the editing base when nothing has been committed.
  Widget _buildEditingCanvas(Uint8List? currentBytes) {
    final tool = _current.tool;
    final base = _editingBaseBytes;
    Widget baseDisplay() => base != null
        ? Image.memory(
            base,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          )
        : Image.file(_sourceFile, fit: BoxFit.contain);

    if (_inEditMode) {
      final toolBase = _current.toolBaseBytes ?? base;
      Widget toolBaseDisplay() => toolBase != null
          ? Image.memory(toolBase,
              fit: BoxFit.contain, gaplessPlayback: true)
          : baseDisplay();

      if (tool == 'match' && _current.matchedBaseBytes != null) {
        return Stack(
          alignment: Alignment.center,
          children: [
            toolBaseDisplay(),
            Opacity(
              opacity: _current.strength.clamp(0.0, 1.0),
              child: Image.memory(
                _current.matchedBaseBytes!,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          ],
        );
      }
      if (tool == 'brightness') {
        final b = _current.brightness.clamp(-0.5, 0.5);
        final s = 1 + b;
        return ColorFiltered(
          colorFilter: ColorFilter.matrix(<double>[
            s, 0, 0, 0, 0,
            0, s, 0, 0, 0,
            0, 0, s, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: toolBaseDisplay(),
        );
      }
      if (tool == 'sharpness') {
        // Until the user releases the slider, the canvas shows the
        // `toolBaseBytes` (no effect yet); after release `bytes` is
        // populated and we show that.
        return currentBytes != null
            ? Image.memory(currentBytes,
                fit: BoxFit.contain, gaplessPlayback: true)
            : toolBaseDisplay();
      }
    }

    // Main mode — display the committed chain result.
    return currentBytes != null
        ? Image.memory(currentBytes,
            fit: BoxFit.contain, gaplessPlayback: true)
        : baseDisplay();
  }

  /// Default-mode AppBar: back/undo/redo on the left, change-ref +
  /// overlay + Save on the right. Use while no tool is being dialled
  /// in, so the user can step through edit history and commit to disk.
  PreferredSizeWidget _buildMainAppBar(
    ThemeData theme,
    bool hasReference,
  ) {
    return AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      // Wider leading slot to fit back + undo + redo in a row without
      // pushing the title.
      leadingWidth: 168,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: _back,
          ),
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: _canUndo && !_processing ? _undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: 'Redo',
            onPressed: _canRedo && !_processing ? _redo : null,
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.photo_library),
          tooltip:
              hasReference ? 'Change reference image' : 'Add reference image',
          onPressed: _processing ? null : _changeReference,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: hasReference
              ? TextButton(
                  // With a reference, the forward action is Compose (cutout +
                  // overlay layers); Save lives on the Compose page, which
                  // flattens base + layers into the saved photo.
                  onPressed: (_processing || _editingBaseBytes == null)
                      ? null
                      : () => setState(() => _collagePage = true),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    disabledForegroundColor: Colors.white38,
                  ),
                  child: const Text('Compose →'),
                )
              : TextButton(
                  // No reference to compose against — save the edited photo
                  // directly.
                  onPressed: _saving ? null : _save,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    disabledForegroundColor: Colors.white38,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
        ),
      ],
    );
  }

  /// Edit-submode AppBar: Cancel ✕ on the left, tool name in the
  /// title, Confirm on the right. Undo/Redo and the "Save the disk
  /// version" affordance disappear — the only way out of this
  /// AppBar is Cancel (discard) or Confirm (keep), matching the
  /// modal feel of Google Photos' per-tool editing.
  PreferredSizeWidget _buildEditModeAppBar(
    ThemeData theme,
    bool hasReference,
  ) {
    return AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancel edit',
        onPressed: _processing ? null : _cancelEdit,
      ),
      title: Text(
        _editModeTitle(),
        style: const TextStyle(fontSize: 16),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.photo_library),
          tooltip:
              hasReference ? 'Change reference image' : 'Add reference image',
          onPressed: _processing ? null : _changeReference,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextButton(
            onPressed: _processing ? null : _confirmEdit,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              disabledForegroundColor: Colors.white38,
            ),
            child: const Text('Confirm'),
          ),
        ),
      ],
    );
  }

  /// Outer canvas wrapper: the single edited captured, with the
  /// optional translucent reference overlay layered on top.
  Widget _buildCanvasContent(Uint8List? currentBytes, File? reference) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: _buildEditingCanvas(currentBytes)),
        if (_showOverlay && reference != null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onScaleStart: (details) {
                _gestureStartOffset = _overlayOffset;
                _gestureStartFocalPoint = details.focalPoint;
                _gestureStartScale = _overlayScale;
              },
              onScaleUpdate: (details) {
                setState(() {
                  _overlayOffset = _gestureStartOffset +
                      (details.focalPoint - _gestureStartFocalPoint);
                  _overlayScale =
                      (_gestureStartScale * details.scale)
                          .clamp(0.35, 4)
                          .toDouble();
                });
              },
              child: Center(
                child: Transform.translate(
                  offset: _overlayOffset,
                  child: Transform.scale(
                    scale: _overlayScale,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      child: Opacity(
                        opacity: _overlayOpacity,
                        child: Image.file(reference, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasReference = _hasReference;
    final reference = _referenceFile;
    final currentBytes = _current.bytes;
    final activeTool = _current.tool;

    final adjust = Scaffold(
      backgroundColor: Colors.black,
      appBar: _inEditMode
          ? _buildEditModeAppBar(theme, hasReference)
          : _buildMainAppBar(theme, hasReference),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCanvasContent(currentBytes, reference),
                  if (_processing || _preparingEditingBase)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x66000000),
                        child: Center(
                          child:
                              CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                    ),
                  // Floating opacity bar — only when a reference image
                  // is in play to overlay.
                  if (hasReference)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: _FloatingOverlayBar(
                        overlayVisible: _showOverlay,
                        opacity: _overlayOpacity,
                        theme: theme,
                        onOpacityChanged: (v) =>
                            setState(() => _overlayOpacity = v),
                        onReset: _resetOverlay,
                        onToggleVisibility: () =>
                            setState(() => _showOverlay = !_showOverlay),
                      ),
                    ),
                ],
              ),
            ),
            _buildBottomStrip(theme, hasReference, activeTool),
          ],
        ),
      ),
    );

    // Adjust → Compose → Save. Keep Compose alive in an IndexedStack so going
    // Back to Adjust doesn't lose placed layers. Compose needs a reference
    // (the cutout source) + the prepared base; without one, Adjust saves
    // directly and there's no Compose page.
    final base = _editingBaseBytes;
    final refPath = _referencePath;
    if (base == null || refPath == null) {
      if (_collagePage) _collagePage = false;
      return adjust;
    }
    return IndexedStack(
      index: _collagePage ? 1 : 0,
      sizing: StackFit.expand,
      children: [
        adjust,
        CollagePage(
          basePreview: _chainBase ?? base,
          resolveFullResBase: () async =>
              await _resolveBytesForSave() ?? await _sourceFile.readAsBytes(),
          referencePath: refPath,
          poiId: widget.poiId,
          onBack: () => setState(() => _collagePage = false),
        ),
      ],
    );
  }
}

/// Floating overlay control bar — sits at the bottom edge of the
/// canvas whenever a reference image is in play. Layout matches the
/// camera screen's bottom row:
///
///   visible:  [🗏] [slider────────] [↻ reset] [👁‍🗨 hide]
///   hidden:                                   [👁 show]
///
/// so the two screens share the same controls in the same order. The
/// AppBar no longer carries an overlay toggle — this bar is the only
/// way in and out of the overlay state, and that makes the two
/// surfaces feel like the same tool.
class _FloatingOverlayBar extends StatelessWidget {
  final bool overlayVisible;
  final double opacity;
  final ThemeData theme;
  final ValueChanged<double> onOpacityChanged;
  final VoidCallback onReset;
  final VoidCallback onToggleVisibility;

  const _FloatingOverlayBar({
    required this.overlayVisible,
    required this.opacity,
    required this.theme,
    required this.onOpacityChanged,
    required this.onReset,
    required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            if (overlayVisible) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child:
                    Icon(Icons.layers, color: Colors.white70, size: 18),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: theme.colorScheme.primary,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: theme.colorScheme.primary,
                    overlayColor:
                        theme.colorScheme.primary.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: opacity.clamp(0.1, 1),
                    min: 0.1,
                    max: 1,
                    onChanged: onOpacityChanged,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.restart_alt),
                color: Colors.white,
                tooltip: 'Reset overlay',
                onPressed: onReset,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
              ),
            ] else
              const Spacer(),
            IconButton(
              icon: Icon(
                overlayVisible
                    ? Icons.visibility_off
                    : Icons.visibility,
              ),
              color: Colors.white,
              tooltip:
                  overlayVisible ? 'Hide reference overlay' : 'Show reference overlay',
              onPressed: onToggleVisibility,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: 36,
                height: 36,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Label + centered Slider + value indicator. Used for the active
/// tool's slider strip (Match Color strength, Brightness, Sharpness)
/// and for the floating overlay-opacity bar.
///
/// When [centerZero] is true the indicator shows signed percentages
/// (`-50%` / `+25%`) so a slider whose default is the midpoint reads
/// the way Lightroom / Google Photos do; otherwise it shows
/// `0%`–`100%` over the [min]–[max] range.
class _LabelledSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final bool centerZero;
  final ThemeData theme;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const _LabelledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.theme,
    required this.onChanged,
    this.centerZero = false,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final String readout;
    if (centerZero) {
      final extent = (max - min).abs() / 2;
      final percent = extent > 0 ? (value / extent) * 100 : 0;
      readout =
          '${percent >= 0 ? '+' : ''}${percent.round()}%';
    } else {
      final span = (max - min);
      final percent = span > 0 ? ((value - min) / span) * 100 : 0;
      readout = '${percent.round()}%';
    }

    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 6),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: theme.colorScheme.primary,
              inactiveTrackColor: Colors.white24,
              thumbColor: theme.colorScheme.primary,
              overlayColor:
                  theme.colorScheme.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            readout,
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// Google-Photos-style edit tool button: icon on top, label below,
/// no border. The active tool's foreground colour goes primary; the
/// rest sit in dim white so the selection reads at a glance against
/// the canvas's typically dark surroundings.
class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final bool selected;
  final bool applied;
  final String? disabledHint;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.selected,
    required this.onTap,
    this.applied = false,
    this.disabledHint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // disabled > selected (being dialled in) > applied (committed) > idle.
    final fg = !enabled
        ? Colors.white24
        : selected
            ? theme.colorScheme.primary
            : applied
                ? Colors.lightBlueAccent
                : Colors.white70;
    final tile = Container(
      width: 72,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 26),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: fg, fontSize: 11, height: 1.15),
            textAlign: TextAlign.center,
            // Two lines so labels like "Match\nColor" wrap cleanly;
            // single-word labels just stay one line.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
    return Tooltip(
      message: enabled ? '' : (disabledHint ?? ''),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: tile,
        ),
      ),
    );
  }
}
