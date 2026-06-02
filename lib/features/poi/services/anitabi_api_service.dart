import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:trip_planner/core/database/database.dart';
import 'package:trip_planner/core/utils/image_storage.dart';

class AnitabiImportResult {
  final String animeId;
  final String animeName;
  final int poisImported;
  final int poisSkipped;

  /// Number of POIs whose cover image will be fetched in the background.
  /// Reflects the queue size when this result was returned — downloads
  /// happen asynchronously via [coverDownloadCompletion].
  final int coversPending;

  /// Completes once every queued cover download has either succeeded or
  /// failed. The Future's int is the number of covers that successfully
  /// landed on local storage; failures silently leave the original URL
  /// on the POI. Callers can ignore this if they're happy to let covers
  /// appear via Drift's reactive streams as each download finishes.
  final Future<void> coverDownloadCompletion;

  const AnitabiImportResult({
    required this.animeId,
    required this.animeName,
    required this.poisImported,
    required this.poisSkipped,
    required this.coversPending,
    required this.coverDownloadCompletion,
  });
}

/// Thrown when Anitabi can't be reached (network error or repeated
/// timeouts), as distinct from a subject that simply has no POIs. Lets the
/// UI tell "check your connection" apart from "this anime has none".
class AnitabiUnavailableException implements Exception {
  final String message;
  const AnitabiUnavailableException([this.message = 'Anitabi is unreachable']);
  @override
  String toString() => 'AnitabiUnavailableException: $message';
}

class AnitabiApiService {
  static const String _apiBaseUrl = 'https://api.anitabi.cn';
  static const int _coverDownloadConcurrency = 5;

  /// Warm the DNS + TLS path to Anitabi for this session. The first network
  /// call after launch pays DNS resolution, a TLS handshake, and (on
  /// cellular) the radio waking up, which is why the very first import of a
  /// session is slow while every later one reuses the cached connection.
  /// Calling this when the search screen opens pays that cost up front, off
  /// the import's critical path. Fire-and-forget.
  static void prewarmConnection() {
    final client = http.Client();
    client
        .get(Uri.parse(_apiBaseUrl))
        .timeout(const Duration(seconds: 10))
        .then((_) {}, onError: (_) {})
        .whenComplete(client.close);
  }

  /// Fetch POIs for a bangumi subject from Anitabi, upsert the Anime row by
  /// bangumi_id (so re-import dedupes), insert each POI, link them via the
  /// PoiAnimes junction, then kick off cover-image downloads in the
  /// background. The returned result is yielded as soon as the database
  /// rows are in place — covers stream in afterwards and the POI screens
  /// pick them up via Drift's reactive watches.
  ///
  /// The optional [client] parameter exists so tests can inject a single
  /// shared `MockClient` that answers both the Anitabi API calls and the
  /// later image-download calls.
  static Future<AnitabiImportResult?> importBangumiSubject(
    AppDatabase db,
    String subjectId, {
    String? fallbackName,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    final ownsClient = client == null;
    var handedOff = false;

    try {
      // Anitabi's title is the Japanese name, which matches the POI data, so
      // it stays the source of truth. But the title call is a 5s, no-retry
      // request that on a cold first import times out and leaves the anime
      // named "Bangumi <id>". When that happens, fall back to the name the
      // caller already has from Bangumi search (its original/Japanese
      // `name`, not the Chinese `name_cn`) instead of the placeholder.
      //
      // Title and points are independent — fire them in parallel so the
      // slower of the two becomes the wall-clock cost instead of the sum.
      final futures = await Future.wait([
        _fetchSubjectTitle(subjectId, httpClient, fallbackName: fallbackName),
        _fetchPointsList(subjectId, httpClient),
      ]);
      final animeName = futures[0] as String;
      final jsonList = futures[1] as List<dynamic>?;

      // Distinguish "couldn't reach Anitabi" (null = network error / timeout
      // after retries) from "subject genuinely has no POIs" (empty list), so
      // the UI shows the right message instead of a misleading "no POIs".
      if (jsonList == null) {
        throw const AnitabiUnavailableException();
      }
      if (jsonList.isEmpty) return null;

      final animeId = await db.upsertAnimeByBangumiId(
        bangumiId: subjectId,
        name: animeName,
      );

      int imported = 0;
      int skipped = 0;
      final pendingDownloads = <_PendingCover>[];

      await db.transaction(() async {
        for (final raw in jsonList) {
          if (raw is! Map<String, dynamic>) {
            skipped++;
            continue;
          }

          PoisCompanion? companion;
          try {
            companion = _parsePoi(raw);
          } catch (e) {
            companion = null;
          }
          if (companion == null) {
            skipped++;
            continue;
          }

          try {
            final poiId = companion.id.value;
            final alreadyImported = await (db.select(db.pois)
                  ..where((t) => t.id.equals(poiId)))
                .getSingleOrNull();

            await db.into(db.pois).insert(
                  companion,
                  mode: InsertMode.insertOrIgnore,
                );
            // Anime link is idempotent (insertOrIgnore), so it's safe to
            // re-run; this keeps a shared location linked if it shows up
            // under another subject.
            await db.addAnimeToPoi(poiId, animeId);

            if (alreadyImported != null) {
              // Seen in a previous import: don't re-queue the cover (which
              // would add another reference_images row) or double-count it.
              skipped++;
              continue;
            }
            imported++;

            final rawImage = (raw['image'] ?? '').toString();
            if (rawImage.isNotEmpty) {
              final url =
                  rawImage.replaceAll('?plan=h160', '?plan=h360');
              pendingDownloads.add(_PendingCover(
                poiId: poiId,
                url: url,
                metadata: _referenceMetadata(raw),
              ));
            }
          } catch (_) {
            skipped++;
          }
        }
      });

      // Hand the client off to the background downloader; it closes the
      // client (when we own it) once every worker is done.
      final completion = _downloadCoversInBackground(
        db: db,
        pending: pendingDownloads,
        httpClient: httpClient,
        closeClientWhenDone: ownsClient,
      );
      handedOff = true;

      return AnitabiImportResult(
        animeId: animeId,
        animeName: animeName,
        poisImported: imported,
        poisSkipped: skipped,
        coversPending: pendingDownloads.length,
        coverDownloadCompletion: completion,
      );
    } finally {
      if (ownsClient && !handedOff) httpClient.close();
    }
  }

  /// Drains the cover queue with [_coverDownloadConcurrency] simultaneous
  /// workers. Each worker pulls the next pending download off the shared
  /// queue, fetches the bytes, writes them locally, and updates the POI
  /// row's `coverImageUri`. Per-item failures are swallowed so one bad
  /// CDN response cannot stop the rest of the queue.
  static Future<void> _downloadCoversInBackground({
    required AppDatabase db,
    required List<_PendingCover> pending,
    required http.Client httpClient,
    required bool closeClientWhenDone,
  }) async {
    

    final queue = List<_PendingCover>.from(pending);

    Future<void> worker(int workerId) async {
      while (queue.isNotEmpty) {
        final next = queue.removeAt(0);
        try {
          final localPath = await downloadCoverImage(
            next.url,
            subdir: 'reference_images',
            client: httpClient,
          );
          if (localPath != null) {
            await db.insertReferenceImage(
              ReferenceImagesCompanion.insert(
                id: const Uuid().v4(),
                poiId: next.poiId,
                localUri: localPath,
                remoteUrl: Value(next.url),
                metadata: Value(next.metadata),
              ),
            );
          } 
        } catch (_) {
          
          // Leave this POI without a reference image; others continue.
        }    
      }
    }

    try {
      await Future.wait(
        List.generate(_coverDownloadConcurrency, (i) => worker(i)),
      );
    } finally {
      if (closeClientWhenDone) httpClient.close();
    }
  }

  static Future<List<dynamic>?> _fetchPointsList(
    String subjectId,
    http.Client httpClient,
  ) async {
    // Anitabi's cache is cold on the first request for a subject the
    // server hasn't touched recently — the very first try often times
    // out at 15 s but a follow-up hits the now-warm cache in ~2-3 s. Try
    // up to three times before giving up.
    for (var attempt = 1; attempt <= 3; attempt++) {
      final result = await _fetchPointsListOnce(subjectId, httpClient);
      if (result != null) return result;
    }
    return null;
  }

  static Future<List<dynamic>?> _fetchPointsListOnce(
    String subjectId,
    http.Client httpClient,
  ) async {
    try {
      // Intentionally NOT passing ?haveImage=true. Many subjects on
      // Anitabi (e.g., crowdsourced ones with only Google Maps origins)
      // have plenty of POI rows but no reference screenshots — that
      // filter dropped every POI for those animes and surfaced as a
      // misleading "no POIs found". POIs without an image just won't
      // have a reference_images row attached.
      final pointsUrl = Uri.parse(
        '$_apiBaseUrl/bangumi/$subjectId/points/detail',
      );
      final response =
          await httpClient.get(pointsUrl).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! List) return null;
      return body;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _fetchSubjectTitle(
    String subjectId,
    http.Client httpClient, {
    String? fallbackName,
  }) async {
    try {
      final response = await httpClient
          .get(Uri.parse('$_apiBaseUrl/bangumi/$subjectId'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        if (body is Map<String, dynamic>) {
          final title = body['title'];
          if (title is String && title.isNotEmpty) return title;
        }
      }
    } catch (_) {
      // fall through to fallback
    }
    // Anitabi title unavailable: prefer the caller's Bangumi name over the
    // bare "Bangumi <id>" placeholder.
    final fb = fallbackName?.trim();
    return (fb != null && fb.isNotEmpty) ? fb : 'Bangumi $subjectId';
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int _toInt(dynamic v, {int fallback = 0}) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static PoisCompanion? _parsePoi(Map<String, dynamic> json) {
    final rawId = json['id'];
    if (rawId == null) return null;
    final id = rawId.toString();
    if (id.isEmpty) return null;

    final geo = json['geo'];
    if (geo is! List || geo.length < 2) return null;
    final lat = _toDouble(geo[0]);
    final lng = _toDouble(geo[1]);
    if (lat == null || lng == null) return null;

    final name = (json['cn'] ?? json['name'] ?? '').toString();
    if (name.isEmpty) return null;

    var imageUrl = (json['image'] ?? '').toString();
    imageUrl = imageUrl.replaceAll('?plan=h160', '?plan=h360');

    final seconds = _toInt(json['s']);
    final timeString =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

    final origin = (json['origin'] ?? 'Unknown').toString();
    final originUrl = (json['originURL'] ?? '').toString();
    final ep = json['ep'];
    final description =
        'Ep $ep - $timeString\nSource: $origin\n$originUrl'.trim();

    return PoisCompanion(
      // Deterministic id derived from the Anitabi point id so re-importing
      // the same subject hits insertOrIgnore instead of creating a fresh
      // UUID (and a duplicate POI) every run.
      id: Value('anitabi:$id'),
      name: Value(name),
      lat: Value(lat),
      lng: Value(lng),
      // Anitabi's `image` is the anime scene reference shot, not a place
      // photo. It goes to the reference_images table; the POI cover stays
      // null until the user takes their own photo or the camera flow sets
      // it.
      coverImageUri: const Value(null),
      description: Value(description),
      address: const Value(null),
      businessHours: const Value(null),
      contactInfo: const Value(null),
      roiId: const Value(null),
    );
  }

  /// Pulls the Anitabi-side fields we want to carry along with the
  /// downloaded reference image: episode and timestamp let future screens
  /// sort or filter without re-fetching.
  static String _referenceMetadata(Map<String, dynamic> json) {
    return jsonEncode({
      'source': 'anitabi',
      'ep': ?json['ep'],
      's': ?json['s'],
    });
  }
}

class _PendingCover {
  final String poiId;
  final String url;
  final String metadata;

  const _PendingCover({
    required this.poiId,
    required this.url,
    required this.metadata,
  });
}
