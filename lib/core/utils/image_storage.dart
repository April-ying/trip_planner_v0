import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Downloads an image at [url] into the app's documents directory and returns
/// the absolute path on success. Returns null on any HTTP, network, or file
/// system failure — callers should treat null as "leave existing URI alone".
///
/// Files go under `${appDocs}/$subdir/<uuid>.<ext>` where the extension is
/// inferred from the URL path (falling back to `.jpg` for query-string heavy
/// CDN URLs like Anitabi's `?plan=h360`).
///
/// [client] is injectable so tests can supply a `MockClient`; production
/// callers leave it null and get a one-shot `http.Client`.
Future<String?> downloadCoverImage(
  String url, {
  String subdir = 'poi_covers',
  http.Client? client,
}) async {
  if (url.isEmpty) return null;

  final httpClient = client ?? http.Client();
  final ownsClient = client == null;

  try {
    final response = await httpClient
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    if (response.bodyBytes.isEmpty) return null;

    final dir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(p.join(dir.path, subdir));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final extension = _extensionFromUrl(url);
    final fileName = '${const Uuid().v4()}$extension';
    final fullPath = p.join(targetDir.path, fileName);
    final file = File(fullPath);
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return fullPath;
  } catch (_) {
    return null;
  } finally {
    if (ownsClient) httpClient.close();
  }
}

String _extensionFromUrl(String url) {
  try {
    final pathOnly = Uri.parse(url).path;
    final ext = p.extension(pathOnly).toLowerCase();
    const known = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.heic'};
    if (known.contains(ext)) return ext;
  } catch (_) {
    // fall through
  }
  return '.jpg';
}
