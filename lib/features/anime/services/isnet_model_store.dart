import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Manages the on-device copy of the isnet-anime ONNX model.
///
/// The model is ~176 MB — too large to commit (GitHub rejects >100 MB) and
/// wasteful to bundle into every build. Instead we fetch it once, on first use,
/// from the public rembg release and cache it under the app's support directory.
/// Subsequent runs load it straight from disk; offline users who haven't fetched
/// it yet fall back to the ML Kit engine.
class IsnetModelStore {
  /// Public, stable source for the anime-tuned ISNet weights (rembg release).
  static const String modelUrl =
      'https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-anime.onnx';

  static const String _fileName = 'isnet-anime.onnx';

  /// A complete download is ~176 MB. Anything well below this is a truncated
  /// transfer or an HTML error page masquerading as the file — reject it so we
  /// never hand a corrupt blob to ONNX Runtime.
  static const int _minValidBytes = 100 * 1024 * 1024;

  Future<File> _resolveFile() async {
    final dir = await getApplicationSupportDirectory();
    final modelsDir = Directory('${dir.path}/models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return File('${modelsDir.path}/$_fileName');
  }

  /// The cached model file if a valid copy is already on disk, else null.
  Future<File?> existing() async {
    final f = await _resolveFile();
    if (await f.exists() && await f.length() >= _minValidBytes) return f;
    return null;
  }

  /// Whether a usable model is already cached (no network).
  Future<bool> isReady() async => (await existing()) != null;

  /// Returns the cached model, downloading it first if absent. Streams progress
  /// via [onProgress] (received bytes, total bytes or null if the server omits
  /// Content-Length). Downloads to a `.part` file and atomically renames on
  /// success so an interrupted transfer never leaves a half-written model.
  Future<File> ensure({void Function(int received, int? total)? onProgress}) async {
    final cached = await existing();
    if (cached != null) return cached;

    final target = await _resolveFile();
    final tmp = File('${target.path}.part');
    if (await tmp.exists()) await tmp.delete();

    final client = http.Client();
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(modelUrl)));
      if (resp.statusCode != 200) {
        throw Exception('Model download failed: HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength;
      final sink = tmp.openWrite();
      var received = 0;
      try {
        await for (final chunk in resp.stream) {
          received += chunk.length;
          sink.add(chunk);
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }

      final size = await tmp.length();
      if (size < _minValidBytes) {
        await tmp.delete();
        throw Exception(
            'Downloaded model is only $size bytes — likely an error page, not the model.');
      }
      await tmp.rename(target.path);
      return target;
    } catch (_) {
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {
          // best-effort cleanup
        }
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Removes the cached model (e.g. to reclaim space or force a re-fetch).
  Future<void> delete() async {
    final f = await _resolveFile();
    if (await f.exists()) await f.delete();
  }
}
