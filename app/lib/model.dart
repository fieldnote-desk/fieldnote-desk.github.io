const topics = ['全部报道', '中国大陆', '港澳台', '亚太', '欧洲', '中东', '美洲', '国际'];

typedef Json = Map<String, dynamic>;

class Edition {
  Edition(
    this.updatedAt,
    this.windowDays,
    this.items,
    this.sources,
    this.brief,
  );

  factory Edition.fromJson(Json json) {
    if (json['version'] != 1) throw const FormatException('Unexpected edition');
    final cutoff = DateTime.now().toUtc().subtract(
      Duration(days: json['windowDays'] as int),
    );
    return Edition(
      DateTime.parse(json['updatedAt'] as String),
      json['windowDays'] as int,
      (json['items'] as List)
          .cast<Json>()
          .map(Article.fromJson)
          .where((article) => !article.publishedAt.isBefore(cutoff))
          .toList(),
      {
        for (final source in (json['sources'] as List).cast<Json>())
          source['id'] as String: Publisher.fromJson(source),
      },
      json['brief'] as Json? ?? const {},
    );
  }

  final DateTime updatedAt;
  final int windowDays;
  final List<Article> items;
  final Map<String, Publisher> sources;
  final Json brief;

  List<Article> get briefArticles {
    final today = hongKong(DateTime.now());
    final available = {
      for (final article in items)
        if (hongKong(article.publishedAt).year == today.year &&
            hongKong(article.publishedAt).month == today.month &&
            hongKong(article.publishedAt).day == today.day)
          article.url.toString(): article,
    };
    return [
      for (final link in (brief['links'] as List? ?? const []))
        if (available[link] case final article?) article,
    ];
  }
}

class Article {
  Article({
    required this.url,
    required this.publisher,
    required this.title,
    required this.summary,
    required this.publishedAt,
    required this.topics,
    required this.lang,
    required this.kind,
    required this.full,
    required this.analysis,
    required this.translation,
  });

  factory Article.fromJson(Json json) => Article(
    url: Uri.parse(json['url'] as String),
    publisher: json['source'] as String,
    title: (json['originalTitle'] ?? json['title']) as String,
    summary: (json['originalSummary'] ?? json['summary']) as String,
    publishedAt: DateTime.parse(json['publishedAt'] as String),
    topics: (json['topics'] as List)
        .cast<String>()
        .map(
          (topic) => switch (topic) {
            '中国政治' => '中国大陆',
            '俄乌与欧洲' => '欧洲',
            _ => topic,
          },
        )
        .toList(),
    lang: json['lang'] as String,
    kind: json['kind'] as String,
    full: json['full'] as Json?,
    analysis: (json['analysis'] as Json?)?.cast<String, String>() ?? const {},
    translation: Translation.fromJson(json['translation'] as Json?),
  );

  final Uri url;
  final String publisher;
  final String title;
  final String summary;
  final DateTime publishedAt;
  final List<String> topics;
  final String lang;
  final String kind;
  final Json? full;
  final Map<String, String> analysis;
  final Translation? translation;

  bool get canTranslate => lang == 'en' || lang == 'ja';

  String get analysisMaterial {
    final body = (full?['body'] as List?)?.cast<String>().join('\n\n') ?? '';
    return body.isEmpty ? summary : body;
  }
}

class Publisher {
  Publisher(
    this.name,
    this.region,
    this.site,
    this.terms,
    this.credit,
    this.health,
  );
  factory Publisher.fromJson(Json json) => Publisher(
    json['name'] as String,
    json['region'] as String,
    Uri.parse(json['site'] as String),
    Uri.tryParse(json['terms'] as String? ?? ''),
    json['credit'] as String?,
    (json['health'] as List).cast<Json>(),
  );
  final String name;
  final String region;
  final Uri site;
  final Uri? terms;
  final String? credit;
  final List<Json> health;
}

class Translation {
  const Translation(this.title, this.summary, this.provider);
  final String title;
  final String summary;
  final String provider;

  static Translation? fromJson(Json? json) {
    if (json == null || json['title'] is! String) return null;
    final provider = switch (json['provider']) {
      'google' => 'Google 翻译',
      _ => 'Mozilla 机器翻译',
    };
    return Translation(
      json['title'] as String,
      json['summary'] as String? ?? '',
      provider,
    );
  }
}

DateTime hongKong(DateTime value) =>
    value.toUtc().add(const Duration(hours: 8));
String _pad(int value) => value.toString().padLeft(2, '0');
String hongKongClock(DateTime value) {
  final date = hongKong(value);
  return '${_pad(date.hour)}:${_pad(date.minute)}';
}

String hongKongDate(DateTime value) {
  final date = hongKong(value);
  return '${date.month}月${date.day}日';
}

String hongKongWeekday(DateTime value) =>
    '星期${'一二三四五六日'[hongKong(value).weekday - 1]}';
