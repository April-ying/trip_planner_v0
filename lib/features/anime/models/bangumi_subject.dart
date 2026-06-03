/// A single anime subject returned by the Bangumi.tv search API.
///
/// Field shapes intentionally accept loose JSON — the upstream sometimes
/// omits fields entirely (e.g., for placeholder entries) and missing data
/// should leave the corresponding getter null rather than throwing.
class BangumiSubject {
  /// Bangumi subject id (used to look the title up on both Bangumi and
  /// Anitabi — the two services share the id space).
  final String id;

  /// Original (usually Japanese) title.
  final String name;

  /// Localised (usually Chinese) title, may be empty.
  final String? nameCn;

  /// Cover image URL hosted by Bangumi. Safe to render via `Image.network`
  /// inside the search screen (no offline guarantee — only used while the
  /// user is choosing what to import).
  final String? imageUrl;

  /// Short description from Bangumi. Often Chinese, sometimes empty.
  final String? summary;

  /// Release date, ISO-like string ("2009-04-02") or null when unknown.
  final String? date;

  /// `TV`, `OVA`, `剧场版`, `Web`, etc. Helps the user disambiguate seasons
  /// vs. specials when multiple matches share a base title.
  final String? platform;

  /// Score from Bangumi's rating system, 0–10. Null when no ratings exist.
  final double? score;

  const BangumiSubject({
    required this.id,
    required this.name,
    this.nameCn,
    this.imageUrl,
    this.summary,
    this.date,
    this.platform,
    this.score,
  });

  static BangumiSubject? fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    if (rawId == null) return null;
    final id = rawId.toString();
    if (id.isEmpty) return null;

    final name = (json['name'] ?? '').toString();
    if (name.isEmpty) return null;

    final rawNameCn = json['name_cn'];
    final nameCn = (rawNameCn is String && rawNameCn.isNotEmpty)
        ? rawNameCn
        : null;

    String? imageUrl;
    final images = json['images'];
    if (images is Map<String, dynamic>) {
      final candidate = images['medium'] ?? images['common'] ?? images['large'];
      if (candidate is String && candidate.isNotEmpty) {
        imageUrl = candidate;
      }
    }
    if (imageUrl == null) {
      final direct = json['image'];
      if (direct is String && direct.isNotEmpty) imageUrl = direct;
    }

    final rawSummary = json['summary'];
    final summary = (rawSummary is String && rawSummary.isNotEmpty)
        ? rawSummary
        : null;

    final rawDate = json['date'];
    final date =
        (rawDate is String && rawDate.isNotEmpty) ? rawDate : null;

    final rawPlatform = json['platform'];
    final platform = (rawPlatform is String && rawPlatform.isNotEmpty)
        ? rawPlatform
        : null;

    double? score;
    final rating = json['rating'];
    if (rating is Map<String, dynamic>) {
      final rawScore = rating['score'];
      if (rawScore is num) score = rawScore.toDouble();
    }

    return BangumiSubject(
      id: id,
      name: name,
      nameCn: nameCn,
      imageUrl: imageUrl,
      summary: summary,
      date: date,
      platform: platform,
      score: score,
    );
  }
}
