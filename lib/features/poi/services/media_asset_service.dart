import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';

/// Copies [source] into the app's permanent `camera_photos` directory
/// (filename derived from the current timestamp, suffix added on
/// collision) and inserts a matching `MediaAsset` row pointing at the
/// new path.
///
/// [type] should be `user_photo` for fresh camera captures or
/// `uploaded_image` for gallery-picked photos — the POI detail list
/// chooses its icon from this column.
///
/// Returns `true` on success, `false` on any I/O or database failure
/// — callers decide whether to surface that via a SnackBar.
Future<bool> persistMediaAsset({
  required AppDatabase db,
  required File source,
  required String poiId,
  required String type,
  String? referenceImageId,
}) async {
  try {
    final appDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(appDir.path, 'camera_photos'));
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }

    final timestamp = DateFormat('MMdd-HH-mm-ss').format(DateTime.now());
    final extension =
        p.extension(source.path).isEmpty ? '.jpg' : p.extension(source.path);
    final savedPath =
        await _nextAvailablePath(photosDir.path, timestamp, extension);
    await source.copy(savedPath);

    await db.insertMediaAsset(MediaAssetsCompanion.insert(
      id: const Uuid().v4(),
      poiId: poiId,
      type: type,
      localUri: savedPath,
      remoteUrl: const Value(null),
      metadata: const Value(null),
      referenceImageId: Value(referenceImageId),
    ));
    return true;
  } catch (_) {
    return false;
  }
}

Future<String> _nextAvailablePath(
  String directory,
  String baseName,
  String extension,
) async {
  var candidate = p.join(directory, '$baseName$extension');
  var suffix = 1;
  while (await File(candidate).exists()) {
    candidate = p.join(directory, '$baseName-$suffix$extension');
    suffix += 1;
  }
  return candidate;
}
