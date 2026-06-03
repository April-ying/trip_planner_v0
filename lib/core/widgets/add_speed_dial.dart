import 'package:flutter/material.dart';

/// A single action for [AddSpeedDial].
///
/// Each action shows an icon mini-FAB with a label chip on its left.
/// The [onTap] callback fires after the dial collapses. Use it to push
/// a route, show a dialog, or run any arbitrary action.
class SpeedDialAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const SpeedDialAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

/// A speed-dial floating action button.
///
/// Idle state: a single FAB with a `+` icon. Tap it and the `+` rotates 45deg
/// into an `x`, while the supplied [actions] animate out vertically above the
/// main FAB (bottom-up, staggered). Each mini-FAB shows a label chip on its
/// left. Tap the main FAB again or tap the scrim to collapse.
///
/// Actions are rendered bottom-up: the first action in the list sits closest
/// to the main FAB, the last action is furthest away.
class AddSpeedDial extends StatefulWidget {
  final List<SpeedDialAction> actions;

  const AddSpeedDial({super.key, required this.actions});

  @override
  State<AddSpeedDial> createState() => _AddSpeedDialState();
}

class _AddSpeedDialState extends State<AddSpeedDial>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _rotation;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  static const Duration _baseDuration = Duration(milliseconds: 250);
  static const double _itemSpacing = 64.0;
  static const double _firstItemOffset = 72.0;
  static const double _mainFabSize = 56.0;

  @override
  void initState() {
    super.initState();
    final int count = widget.actions.length;
    // Extend total duration so staggered items have room to animate.
    final int totalMs =
        _baseDuration.inMilliseconds + (count > 0 ? (count - 1) * 50 : 0);
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );
    _rotation = Tween<double>(begin: 0, end: 0.125).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.addStatusListener(_handleStatus);
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      _removeOverlay();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _removeOverlay();
    _controller.dispose();
    super.dispose();
  }

  bool get _isOpen =>
      _controller.status == AnimationStatus.completed ||
      _controller.status == AnimationStatus.forward;

  void _toggle() {
    if (_isOpen) {
      _controller.reverse();
    } else {
      _insertOverlay();
      _controller.forward();
    }
  }

  void _close() {
    if (_isOpen) _controller.reverse();
  }

  /// Used when an action callback navigates / fires a side-effect: the
  /// scrim-bearing overlay is removed *synchronously* so it cannot keep
  /// absorbing taps on the destination screen while the close animation
  /// is still in flight (which previously made pushed screens look frozen).
  void _runAction(VoidCallback callback) {
    _controller.value = 0;
    _removeOverlay();
    callback();
  }

  void _insertOverlay() {
    if (_overlayEntry != null) return;
    _overlayEntry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Stack(
          children: [
            // Scrim covering the whole screen.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: Container(
                  color: Colors.black
                      .withValues(alpha: 0.25 * _controller.value),
                ),
              ),
            ),
            // Mini-FABs anchored to the main FAB via CompositedTransformFollower.
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              // Anchor the follower's BOTTOM-right corner to the main FAB's
              // TOP-right corner. The follower then has real, positive
              // height (see _buildMiniActions) so its children get proper
              // hit tests — versus the older zero-height anchor, where the
              // children rendered but every tap fell through to the scrim.
              targetAnchor: Alignment.topRight,
              followerAnchor: Alignment.bottomRight,
              child: _buildMiniActions(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMiniActions() {
    final int count = widget.actions.length;
    final int totalMs = _controller.duration?.inMilliseconds ?? _baseDuration.inMilliseconds;
    // Give the follower enough height to contain every mini-FAB so that
    // hit tests reach the children. The follower sits with its bottom edge
    // on the main FAB's top edge, and the top-most item sits at
    // `_firstItemOffset + (count-1)*_itemSpacing` above the bottom — we
    // add the mini-FAB height (48) so the FAB itself fits inside.
    final double height =
        _firstItemOffset + (count > 0 ? (count - 1) * _itemSpacing : 0) + 48;
    return SizedBox(
      width: 280, // enough room for label chip + mini-FAB
      height: height,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          for (int i = 0; i < count; i++)
            _buildMiniAction(
              index: i,
              totalMs: totalMs,
              action: widget.actions[i],
            ),
        ],
      ),
    );
  }

  Widget _buildMiniAction({
    required int index,
    required int totalMs,
    required SpeedDialAction action,
  }) {
    // Stagger: each item starts ~50ms after the previous, finishes within
    // the parent controller's duration.
    final int startMs = index * 50;
    final double start = startMs / totalMs;
    final double end = (startMs + _baseDuration.inMilliseconds) / totalMs;
    final Animation<double> curved = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        start.clamp(0.0, 1.0),
        end.clamp(0.0, 1.0),
        curve: Curves.easeOutBack,
      ),
      reverseCurve: Interval(
        start.clamp(0.0, 1.0),
        end.clamp(0.0, 1.0),
        curve: Curves.easeIn,
      ),
    );

    final double targetOffset = _firstItemOffset + index * _itemSpacing;
    final double offset = targetOffset * curved.value;
    final double opacity = curved.value.clamp(0.0, 1.0);

    // Anchor each item by its bottom: at full open, the i-th item sits
    // `_firstItemOffset + i*_itemSpacing` above the bottom of the follower
    // (which is itself sitting on the main FAB). We offset right by
    // (main FAB size - mini FAB size) / 2 = (56 - 48) / 2 = 4 so the mini
    // FAB aligns horizontally with the main FAB's center.
    return Positioned(
      right: 4,
      bottom: offset,
      child: IgnorePointer(
        ignoring: opacity < 0.05,
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: 0.6 + 0.4 * opacity,
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LabelChip(
                  label: action.label,
                  onTap: () => _runAction(action.onTap),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FloatingActionButton(
                    heroTag: 'speed_dial_${action.label}_$index',
                    mini: true,
                    onPressed: () => _runAction(action.onTap),
                    child: Icon(action.icon),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: SizedBox(
        width: _mainFabSize,
        height: _mainFabSize,
        child: FloatingActionButton(
          tooltip: _isOpen ? 'Close' : 'Add',
          onPressed: _toggle,
          child: RotationTransition(
            turns: _rotation,
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }
}

class _LabelChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _LabelChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}
