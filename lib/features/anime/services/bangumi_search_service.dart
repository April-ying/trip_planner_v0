import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/bangumi_subject.dart';

class BangumiSearchService {
  static const String _baseUrl = 'https://api.bgm.tv';

  /// Search Bangumi for anime matching [keyword].
  ///
  /// Filters to `type=2` (anime) and orders by `match` so the first results
  /// are the most relevant. Returns an empty list on any HTTP, parsing, or
  /// network failure; the screen treats "no results" and "search failed"
  /// the same way visually.
  ///
  /// The optional [client] parameter exists so tests can inject a
  /// `MockClient`; production callers should leave it as the default.
  static Future<List<BangumiSubject>> searchByName(
    String keyword, {
    int limit = 20,
    http.Client? client,
  }) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return const [];

    final httpClient = client ?? http.Client();
    final ownsClient = client == null;

    try {
      final uri = Uri.parse('$_baseUrl/v0/search/subjects?limit=$limit');
      final response = await httpClient
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': 'trip_planner/1.0',
            },
            body: jsonEncode({
              'keyword': trimmed,
              'sort': 'match',
              'filter': {
                'type': [2],
              },
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return const [];

      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) return const [];

      final data = body['data'];
      if (data is! List) return const [];

      final results = <BangumiSubject>[];
      for (final raw in data) {
        if (raw is! Map<String, dynamic>) continue;
        final parsed = BangumiSubject.fromJson(raw);
        if (parsed != null) results.add(parsed);
      }
      return results;
    } catch (_) {
      return const [];
    } finally {
      if (ownsClient) httpClient.close();
    }
  }
}
