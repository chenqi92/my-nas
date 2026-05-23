import 'package:uuid/uuid.dart';

/// 书源类型
enum BookSourceType {
  text(0, '文字'),
  audio(1, '音频');

  const BookSourceType(this.value, this.label);

  final int value;
  final String label;

  static BookSourceType fromValue(int value) =>
      BookSourceType.values.firstWhere(
        (t) => t.value == value,
        orElse: () => BookSourceType.text,
      );
}

/// 搜索规则
class SearchRule {
  const SearchRule({
    this.bookList,
    this.name,
    this.author,
    this.bookUrl,
    this.coverUrl,
    this.intro,
    this.kind,
    this.lastChapter,
    this.wordCount,
  });

  factory SearchRule.fromJson(Map<String, dynamic> json) => SearchRule(
        bookList: json['bookList'] as String?,
        name: json['name'] as String?,
        author: json['author'] as String?,
        bookUrl: json['bookUrl'] as String?,
        coverUrl: json['coverUrl'] as String?,
        intro: json['intro'] as String?,
        kind: json['kind'] as String?,
        lastChapter: json['lastChapter'] as String?,
        wordCount: json['wordCount'] as String?,
      );

  /// 书籍列表规则
  final String? bookList;

  /// 书名规则
  final String? name;

  /// 作者规则
  final String? author;

  /// 书籍URL规则
  final String? bookUrl;

  /// 封面URL规则
  final String? coverUrl;

  /// 简介规则
  final String? intro;

  /// 分类规则
  final String? kind;

  /// 最新章节规则
  final String? lastChapter;

  /// 字数规则
  final String? wordCount;

  Map<String, dynamic> toJson() => {
        if (bookList != null) 'bookList': bookList,
        if (name != null) 'name': name,
        if (author != null) 'author': author,
        if (bookUrl != null) 'bookUrl': bookUrl,
        if (coverUrl != null) 'coverUrl': coverUrl,
        if (intro != null) 'intro': intro,
        if (kind != null) 'kind': kind,
        if (lastChapter != null) 'lastChapter': lastChapter,
        if (wordCount != null) 'wordCount': wordCount,
      };
}

/// 书籍详情规则
class BookInfoRule {
  const BookInfoRule({
    this.name,
    this.author,
    this.coverUrl,
    this.intro,
    this.kind,
    this.lastChapter,
    this.tocUrl,
    this.wordCount,
  });

  factory BookInfoRule.fromJson(Map<String, dynamic> json) => BookInfoRule(
        name: json['name'] as String?,
        author: json['author'] as String?,
        coverUrl: json['coverUrl'] as String?,
        intro: json['intro'] as String?,
        kind: json['kind'] as String?,
        lastChapter: json['lastChapter'] as String?,
        tocUrl: json['tocUrl'] as String?,
        wordCount: json['wordCount'] as String?,
      );

  final String? name;
  final String? author;
  final String? coverUrl;
  final String? intro;
  final String? kind;
  final String? lastChapter;
  final String? tocUrl;
  final String? wordCount;

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (author != null) 'author': author,
        if (coverUrl != null) 'coverUrl': coverUrl,
        if (intro != null) 'intro': intro,
        if (kind != null) 'kind': kind,
        if (lastChapter != null) 'lastChapter': lastChapter,
        if (tocUrl != null) 'tocUrl': tocUrl,
        if (wordCount != null) 'wordCount': wordCount,
      };
}

/// 目录规则
class TocRule {
  const TocRule({
    this.chapterList,
    this.chapterName,
    this.chapterUrl,
    this.isVolume,
    this.updateTime,
    this.nextTocUrl,
  });

  factory TocRule.fromJson(Map<String, dynamic> json) => TocRule(
        chapterList: json['chapterList'] as String?,
        chapterName: json['chapterName'] as String?,
        chapterUrl: json['chapterUrl'] as String?,
        isVolume: json['isVolume'] as String?,
        updateTime: json['updateTime'] as String?,
        nextTocUrl: json['nextTocUrl'] as String?,
      );

  /// 章节列表规则
  final String? chapterList;

  /// 章节名称规则
  final String? chapterName;

  /// 章节URL规则
  final String? chapterUrl;

  /// 是否卷名规则
  final String? isVolume;

  /// 更新时间规则
  final String? updateTime;

  /// 下一页目录URL规则
  final String? nextTocUrl;

  Map<String, dynamic> toJson() => {
        if (chapterList != null) 'chapterList': chapterList,
        if (chapterName != null) 'chapterName': chapterName,
        if (chapterUrl != null) 'chapterUrl': chapterUrl,
        if (isVolume != null) 'isVolume': isVolume,
        if (updateTime != null) 'updateTime': updateTime,
        if (nextTocUrl != null) 'nextTocUrl': nextTocUrl,
      };
}

/// 正文规则
class ContentRule {
  const ContentRule({
    this.content,
    this.replaceRegex,
    this.nextContentUrl,
    this.webJs,
    this.sourceRegex,
    this.imageStyle,
    this.payAction,
  });

  factory ContentRule.fromJson(Map<String, dynamic> json) => ContentRule(
        content: json['content'] as String?,
        replaceRegex: json['replaceRegex'] as String?,
        nextContentUrl: json['nextContentUrl'] as String?,
        webJs: json['webJs'] as String?,
        sourceRegex: json['sourceRegex'] as String?,
        imageStyle: json['imageStyle'] as String?,
        payAction: json['payAction'] as String?,
      );

  /// 正文规则
  final String? content;

  /// 替换规则（用于净化内容）
  final String? replaceRegex;

  /// 下一页正文URL规则
  final String? nextContentUrl;

  /// 网页JS脚本
  final String? webJs;

  /// 资源正则
  final String? sourceRegex;

  /// 图片样式
  final String? imageStyle;

  /// 付费操作
  final String? payAction;

  Map<String, dynamic> toJson() => {
        if (content != null) 'content': content,
        if (replaceRegex != null) 'replaceRegex': replaceRegex,
        if (nextContentUrl != null) 'nextContentUrl': nextContentUrl,
        if (webJs != null) 'webJs': webJs,
        if (sourceRegex != null) 'sourceRegex': sourceRegex,
        if (imageStyle != null) 'imageStyle': imageStyle,
        if (payAction != null) 'payAction': payAction,
      };
}

/// 探索规则
class ExploreRule {
  const ExploreRule({
    this.bookList,
    this.name,
    this.author,
    this.bookUrl,
    this.coverUrl,
    this.intro,
    this.kind,
    this.lastChapter,
    this.wordCount,
  });

  factory ExploreRule.fromJson(Map<String, dynamic> json) => ExploreRule(
        bookList: json['bookList'] as String?,
        name: json['name'] as String?,
        author: json['author'] as String?,
        bookUrl: json['bookUrl'] as String?,
        coverUrl: json['coverUrl'] as String?,
        intro: json['intro'] as String?,
        kind: json['kind'] as String?,
        lastChapter: json['lastChapter'] as String?,
        wordCount: json['wordCount'] as String?,
      );

  final String? bookList;
  final String? name;
  final String? author;
  final String? bookUrl;
  final String? coverUrl;
  final String? intro;
  final String? kind;
  final String? lastChapter;
  final String? wordCount;

  Map<String, dynamic> toJson() => {
        if (bookList != null) 'bookList': bookList,
        if (name != null) 'name': name,
        if (author != null) 'author': author,
        if (bookUrl != null) 'bookUrl': bookUrl,
        if (coverUrl != null) 'coverUrl': coverUrl,
        if (intro != null) 'intro': intro,
        if (kind != null) 'kind': kind,
        if (lastChapter != null) 'lastChapter': lastChapter,
        if (wordCount != null) 'wordCount': wordCount,
      };
}

/// 书源实体（兼容 Legado 格式）
class BookSource {
  BookSource({
    String? id,
    required this.bookSourceUrl,
    required this.bookSourceName,
    this.bookSourceGroup,
    this.bookSourceType = BookSourceType.text,
    this.bookSourceComment,
    this.loginUrl,
    this.loginUi,
    this.loginCheckJs,
    this.header,
    this.concurrentRate,
    this.enabled = true,
    this.enabledExplore = true,
    this.weight = 0,
    this.customOrder = 0,
    this.lastUpdateTime = 0,
    this.respondTime = 180000,
    this.searchUrl,
    this.exploreUrl,
    this.ruleSearch,
    this.ruleExplore,
    this.ruleBookInfo,
    this.ruleToc,
    this.ruleContent,
  }) : id = id ?? const Uuid().v4();

  factory BookSource.fromJson(Map<String, dynamic> json) {
    // 安全解析整数（可能是 String 或 int）
    int parseIntSafe(dynamic value, [int defaultValue = 0]) {
      if (value == null) return defaultValue;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? defaultValue;
      if (value is double) return value.toInt();
      return defaultValue;
    }

    // 安全解析布尔值（可能是 String、bool 或 int）
    bool parseBoolSafe(dynamic value, [bool defaultValue = true]) {
      if (value == null) return defaultValue;
      if (value is bool) return value;
      if (value is int) return value != 0;
      if (value is String) {
        return value.toLowerCase() == 'true' || value == '1';
      }
      return defaultValue;
    }

    return BookSource(
      id: json['id'] as String?,
      bookSourceUrl: json['bookSourceUrl'] as String? ?? '',
      bookSourceName: json['bookSourceName'] as String? ?? '',
      bookSourceGroup: json['bookSourceGroup'] as String?,
      bookSourceType: BookSourceType.fromValue(
        parseIntSafe(json['bookSourceType'], 0),
      ),
      bookSourceComment: json['bookSourceComment'] as String?,
      loginUrl: json['loginUrl'] as String?,
      loginUi: json['loginUi'] as String?,
      loginCheckJs: json['loginCheckJs'] as String?,
      header: json['header'] as String?,
      concurrentRate: json['concurrentRate'] as String?,
      enabled: parseBoolSafe(json['enabled'], true),
      enabledExplore: parseBoolSafe(json['enabledExplore'], true),
      weight: parseIntSafe(json['weight'], 0),
      customOrder: parseIntSafe(json['customOrder'], 0),
      lastUpdateTime: parseIntSafe(json['lastUpdateTime'], 0),
      respondTime: parseIntSafe(json['respondTime'], 180000),
      searchUrl: json['searchUrl'] as String?,
      exploreUrl: json['exploreUrl'] as String?,
      ruleSearch: json['ruleSearch'] != null
          ? SearchRule.fromJson(json['ruleSearch'] as Map<String, dynamic>)
          : null,
      ruleExplore: json['ruleExplore'] != null
          ? ExploreRule.fromJson(json['ruleExplore'] as Map<String, dynamic>)
          : null,
      ruleBookInfo: json['ruleBookInfo'] != null
          ? BookInfoRule.fromJson(
              json['ruleBookInfo'] as Map<String, dynamic>)
          : null,
      ruleToc: json['ruleToc'] != null
          ? TocRule.fromJson(json['ruleToc'] as Map<String, dynamic>)
          : null,
      ruleContent: json['ruleContent'] != null
          ? ContentRule.fromJson(json['ruleContent'] as Map<String, dynamic>)
          : null,
    );
  }

  /// 内部唯一ID
  final String id;

  /// 书源URL（作为书源的唯一标识）
  final String bookSourceUrl;

  /// 书源名称
  final String bookSourceName;

  /// 书源分组
  final String? bookSourceGroup;

  /// 书源类型
  final BookSourceType bookSourceType;

  /// 书源说明
  final String? bookSourceComment;

  /// 登录URL
  final String? loginUrl;

  /// 登录UI配置
  final String? loginUi;

  /// 登录检测JS
  final String? loginCheckJs;

  /// 请求头（JSON格式）
  final String? header;

  /// 并发率
  final String? concurrentRate;

  /// 是否启用
  final bool enabled;

  /// 是否启用探索
  final bool enabledExplore;

  /// 权重（用于排序）
  final int weight;

  /// 自定义排序
  final int customOrder;

  /// 最后更新时间
  final int lastUpdateTime;

  /// 响应时间
  final int respondTime;

  /// 搜索URL
  final String? searchUrl;

  /// 探索URL
  final String? exploreUrl;

  /// 搜索规则
  final SearchRule? ruleSearch;

  /// 探索规则
  final ExploreRule? ruleExplore;

  /// 详情规则
  final BookInfoRule? ruleBookInfo;

  /// 目录规则
  final TocRule? ruleToc;

  /// 正文规则
  final ContentRule? ruleContent;

  /// 获取显示名称
  String get displayName =>
      bookSourceName.isNotEmpty ? bookSourceName : bookSourceUrl;

  /// 获取分组列表
  List<String> get groups =>
      bookSourceGroup?.split(RegExp('[,;，；]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList() ??
      [];

  /// 解析请求头
  Map<String, String>? get parsedHeader {
    if (header == null || header!.isEmpty) return null;
    try {
      // ignore: avoid_dynamic_calls
      final parsed =
          Map<String, dynamic>.from(Uri.splitQueryString(header!));
      return parsed.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return null;
    }
  }

  BookSource copyWith({
    String? id,
    String? bookSourceUrl,
    String? bookSourceName,
    String? bookSourceGroup,
    BookSourceType? bookSourceType,
    String? bookSourceComment,
    String? loginUrl,
    String? loginUi,
    String? loginCheckJs,
    String? header,
    String? concurrentRate,
    bool? enabled,
    bool? enabledExplore,
    int? weight,
    int? customOrder,
    int? lastUpdateTime,
    int? respondTime,
    String? searchUrl,
    String? exploreUrl,
    SearchRule? ruleSearch,
    ExploreRule? ruleExplore,
    BookInfoRule? ruleBookInfo,
    TocRule? ruleToc,
    ContentRule? ruleContent,
  }) =>
      BookSource(
        id: id ?? this.id,
        bookSourceUrl: bookSourceUrl ?? this.bookSourceUrl,
        bookSourceName: bookSourceName ?? this.bookSourceName,
        bookSourceGroup: bookSourceGroup ?? this.bookSourceGroup,
        bookSourceType: bookSourceType ?? this.bookSourceType,
        bookSourceComment: bookSourceComment ?? this.bookSourceComment,
        loginUrl: loginUrl ?? this.loginUrl,
        loginUi: loginUi ?? this.loginUi,
        loginCheckJs: loginCheckJs ?? this.loginCheckJs,
        header: header ?? this.header,
        concurrentRate: concurrentRate ?? this.concurrentRate,
        enabled: enabled ?? this.enabled,
        enabledExplore: enabledExplore ?? this.enabledExplore,
        weight: weight ?? this.weight,
        customOrder: customOrder ?? this.customOrder,
        lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
        respondTime: respondTime ?? this.respondTime,
        searchUrl: searchUrl ?? this.searchUrl,
        exploreUrl: exploreUrl ?? this.exploreUrl,
        ruleSearch: ruleSearch ?? this.ruleSearch,
        ruleExplore: ruleExplore ?? this.ruleExplore,
        ruleBookInfo: ruleBookInfo ?? this.ruleBookInfo,
        ruleToc: ruleToc ?? this.ruleToc,
        ruleContent: ruleContent ?? this.ruleContent,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookSourceUrl': bookSourceUrl,
        'bookSourceName': bookSourceName,
        if (bookSourceGroup != null) 'bookSourceGroup': bookSourceGroup,
        'bookSourceType': bookSourceType.value,
        if (bookSourceComment != null) 'bookSourceComment': bookSourceComment,
        if (loginUrl != null) 'loginUrl': loginUrl,
        if (loginUi != null) 'loginUi': loginUi,
        if (loginCheckJs != null) 'loginCheckJs': loginCheckJs,
        if (header != null) 'header': header,
        if (concurrentRate != null) 'concurrentRate': concurrentRate,
        'enabled': enabled,
        'enabledExplore': enabledExplore,
        'weight': weight,
        'customOrder': customOrder,
        'lastUpdateTime': lastUpdateTime,
        'respondTime': respondTime,
        if (searchUrl != null) 'searchUrl': searchUrl,
        if (exploreUrl != null) 'exploreUrl': exploreUrl,
        if (ruleSearch != null) 'ruleSearch': ruleSearch!.toJson(),
        if (ruleExplore != null) 'ruleExplore': ruleExplore!.toJson(),
        if (ruleBookInfo != null) 'ruleBookInfo': ruleBookInfo!.toJson(),
        if (ruleToc != null) 'ruleToc': ruleToc!.toJson(),
        if (ruleContent != null) 'ruleContent': ruleContent!.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookSource &&
          runtimeType == other.runtimeType &&
          bookSourceUrl == other.bookSourceUrl;

  @override
  int get hashCode => bookSourceUrl.hashCode;
}

/// 在线书籍搜索结果
class OnlineBook {
  const OnlineBook({
    required this.name,
    required this.author,
    required this.bookUrl,
    this.coverUrl,
    this.intro,
    this.kind,
    this.lastChapter,
    this.wordCount,
    required this.source,
  });

  final String name;
  final String author;
  final String bookUrl;
  final String? coverUrl;
  final String? intro;
  final String? kind;
  final String? lastChapter;
  final String? wordCount;
  final BookSource source;

  /// 生成唯一标识（用于去重）
  String get uniqueKey => '$name|$author';
}

/// 在线章节
class OnlineChapter {
  const OnlineChapter({
    required this.name,
    required this.url,
    this.isVolume = false,
    this.updateTime,
    this.index = 0,
  });

  final String name;
  final String url;
  final bool isVolume;
  final String? updateTime;
  final int index;
}
