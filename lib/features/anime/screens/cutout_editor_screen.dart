import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../widgets/isnet_cutout_panel.dart';
import '../widgets/mlkit_cutout_panel.dart';

/// Cuts a transparent-PNG subject out of [sourcePath] (e.g. an anime reference
/// frame) and pops the result bytes back to the caller via `Navigator.pop`.
/// User picks the engine: isnet-anime (ONNX, box/brush/refine) or ML Kit
/// (Google subject detection, box/pick/feather). Used by the collage tool to
/// grab a character to paste onto a photo.
enum CutoutEngine { isnet, mlkit }

class CutoutEditorScreen extends StatefulWidget {
  final String sourcePath;
  const CutoutEditorScreen({super.key, required this.sourcePath});

  @override
  State<CutoutEditorScreen> createState() => _CutoutEditorScreenState();
}

class _CutoutEditorScreenState extends State<CutoutEditorScreen> {
  CutoutEngine _engine = CutoutEngine.isnet;
  Uint8List? _result;

  void _onResult(Uint8List? png) => setState(() => _result = png);

  @override
  Widget build(BuildContext context) {
    final source = File(widget.sourcePath);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cut out character'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton(
              onPressed:
                  _result == null ? null : () => Navigator.of(context).pop(_result),
              child: const Text('Use cutout'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<CutoutEngine>(
              segments: const [
                ButtonSegment(
                    value: CutoutEngine.isnet,
                    icon: Icon(Icons.auto_fix_high),
                    label: Text('isnet')),
                ButtonSegment(
                    value: CutoutEngine.mlkit,
                    icon: Icon(Icons.android),
                    label: Text('ML Kit')),
              ],
              selected: {_engine},
              onSelectionChanged: (s) => setState(() {
                _engine = s.first;
                _result = null; // different engine → different result
              }),
            ),
          ),
          Expanded(
            // Key by engine so switching rebuilds the panel fresh.
            child: _engine == CutoutEngine.isnet
                ? IsnetCutoutPanel(
                    key: const ValueKey('isnet'),
                    source: source,
                    onResult: _onResult,
                  )
                : MlkitCutoutPanel(
                    key: const ValueKey('mlkit'),
                    source: source,
                    onResult: _onResult,
                  ),
          ),
        ],
      ),
    );
  }
}
