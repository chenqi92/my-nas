import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';
import 'package:uuid/uuid.dart';

/// 在线书籍书架项
///
/// 存储添加到书架的在线书籍信息
class OnlineBookShelfItem {
  OnlineBookShelfItem({
    String? id,
    required this.name,
    required this.author,
    required this.bookUrl,
    required this.sourceId,
    required this.sourceName,
    required this.sourceUrl,
    this.coverUrl,
    this.intro,
    this.kind,
    this.lastChapter,
    this.wordCount,
    this.addedAt,
    this.lastReadAt,
    this.lastReadChapterIndex = 0,
    this.lastReadChapterName,
    this.lastReadProgress = 0,
    this.cachedChapterCount = 0,
  }) : id = id ?? const Uuid().v4();

  /// 从 OnlineBook 创建
  factory OnlineBookShelfItem.fromOnlineBook(OnlineBook book) => OnlineBookShelfItem(
      name: book.name,
      author: book.author,
      bookUrl: book.bookUrl,
      sourceId: book.source.id,
      sourceName: book.source.displayName,
      sourceUrl: book.source.bookSourceUrl,
      coverUrl: book.coverUrl,
      intro: book.intro,
      kind: book.kind,
      lastChapter: book.lastChapter,
      wordCount: book.wordCount,
      addedAt: DateTime.now(),
    );

  factory OnlineBookShelfItem.fromJson(Map<String, dynamic> json) => OnlineBookShelfItem(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      author: json['author'] as String? ?? '',
      bookUrl: json['bookUrl'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? '',
      sourceUrl: json['sourceUrl'] as String? ?? '',
      coverUrl: json['coverUrl'] as String?,
      intro: json['intro'] as String?,
      kind: json['kind'] as String?,
      lastChapter: json['lastChapter'] as String?,
      wordCount: json['wordCount'] as String?,
      addedAt: json['addedAt'] != null
          ? DateTime.tryParse(json['addedAt'] as String)
          : null,
      lastReadAt: json['lastReadAt'] != null
          ? DateTime.tryParse(json['lastReadAt'] as String)
          : null,
      lastReadChapterIndex: json['lastReadChapterIndex'] as int? ?? 0,
      lastReadChapterName: json['lastReadChapterName'] as String?,
      lastReadProgress: (json['lastReadProgress'] as num?)?.toDouble() ?? 0,
      cachedChapterCount: json['cachedChapterCount'] as int? ?? 0,
    );

  /// 唯一ID
  final String id;

  /// 书名
  final String name;

  /// 作者
  final String author;

  /// 书籍URL（书源中的详情页URL）
  final String bookUrl;

  /// 书源ID
  final String sourceId;

  /// 书源名称（用于显示）
  final String sourceName;

  /// 书源URL（用于重新加载书源规则）
  final String sourceUrl;

  /// 封面URL
  final String? coverUrl;

  /// 简介
  final String? intro;

  /// 分类/标签
  final String? kind;

  /// 最新章节
  final String? lastChapter;

  /// 字数
  final String? wordCount;

  /// 添加时间
  final DateTime? addedAt;

  /// 最后阅读时间
  final DateTime? lastReadAt;

  /// 最后阅读章节索引
  final int lastReadChapterIndex;

  /// 最后阅读章节名称
  final String? lastReadChapterName;

  /// 最后阅读位置（0-1）
  final double lastReadProgress;

  /// 已缓存章节数
  final int cachedChapterCount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'author': author,
        'bookUrl': bookUrl,
        'sourceId': sourceId,
        'sourceName': sourceName,
        'sourceUrl': sourceUrl,
        if (coverUrl != null) 'coverUrl': coverUrl,
        if (intro != null) 'intro': intro,
        if (kind != null) 'kind': kind,
        if (lastChapter != null) 'lastChapter': lastChapter,
        if (wordCount != null) 'wordCount': wordCount,
        if (addedAt != null) 'addedAt': addedAt!.toIso8601String(),
        if (lastReadAt != null) 'lastReadAt': lastReadAt!.toIso8601String(),
        'lastReadChapterIndex': lastReadChapterIndex,
        if (lastReadChapterName != null)
          'lastReadChapterName': lastReadChapterName,
        'lastReadProgress': lastReadProgress,
        'cachedChapterCount': cachedChapterCount,
      };

  OnlineBookShelfItem copyWith({
    String? name,
    String? author,
    String? bookUrl,
    String? sourceId,
    String? sourceName,
    String? sourceUrl,
    String? coverUrl,
    String? intro,
    String? kind,
    String? lastChapter,
    String? wordCount,
    DateTime? addedAt,
    DateTime? lastReadAt,
    int? lastReadChapterIndex,
    String? lastReadChapterName,
    double? lastReadProgress,
    int? cachedChapterCount,
  }) =>
      OnlineBookShelfItem(
        id: id,
        name: name ?? this.name,
        author: author ?? this.author,
        bookUrl: bookUrl ?? this.bookUrl,
        sourceId: sourceId ?? this.sourceId,
        sourceName: sourceName ?? this.sourceName,
        sourceUrl: sourceUrl ?? this.sourceUrl,
        coverUrl: coverUrl ?? this.coverUrl,
        intro: intro ?? this.intro,
        kind: kind ?? this.kind,
        lastChapter: lastChapter ?? this.lastChapter,
        wordCount: wordCount ?? this.wordCount,
        addedAt: addedAt ?? this.addedAt,
        lastReadAt: lastReadAt ?? this.lastReadAt,
        lastReadChapterIndex: lastReadChapterIndex ?? this.lastReadChapterIndex,
        lastReadChapterName: lastReadChapterName ?? this.lastReadChapterName,
        lastReadProgress: lastReadProgress ?? this.lastReadProgress,
        cachedChapterCount: cachedChapterCount ?? this.cachedChapterCount,
      );

  /// 生成唯一标识（用于去重）
  String get uniqueKey => '$bookUrl|$sourceId';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OnlineBookShelfItem &&
          runtimeType == other.runtimeType &&
          uniqueKey == other.uniqueKey;

  @override
  int get hashCode => uniqueKey.hashCode;
}

/// 在线书籍书架服务
///
/// 管理添加到书架的在线书籍
class OnlineBookShelfService {
  OnlineBookShelfService._();

  static final instance = OnlineBookShelfService._();

  static const _boxName = 'online_book_shelf';

  Box<String>? _box;
  bool _initialized = false;

  /// 内存缓存
  List<OnlineBookShelfItem>? _itemsCache;

  /// 初始化服务
  Future<void> init() async {
    if (_initialized) return;

    try {
      if (Hive.isBoxOpen(_boxName)) {
        _box = Hive.box<String>(_boxName);
      } else {
        _box = await Hive.openBox<String>(_boxName);
      }
      await _loadCache();
      _initialized = true;
      logger.i('在线书架服务初始化完成，已加载 ${_itemsCache?.length ?? 0} 本书');
    } catch (e, st) {
      AppError.handle(e, st, 'OnlineBookShelfService.init');
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await init();
    }
  }

  Future<void> _loadCache() async {
    final items = <OnlineBookShelfItem>[];

    for (final key in _box!.keys) {
      try {
        final json = _box!.get(key);
        if (json != null) {
          final data = jsonDecode(json) as Map<String, dynamic>;
          items.add(OnlineBookShelfItem.fromJson(data));
        }
      } catch (e, st) {
        logger.w('加载在线书籍失败: $key', e, st);
      }
    }

    // 按最后阅读时间排序
    items.sort((a, b) {
      final aTime = a.lastReadAt ?? a.addedAt ?? DateTime(2000);
      final bTime = b.lastReadAt ?? b.addedAt ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });

    _itemsCache = items;
  }

  /// 获取所有在线书籍
  Future<List<OnlineBookShelfItem>> getAll() async {
    await _ensureInitialized();
    return List.unmodifiable(_itemsCache ?? []);
  }

  /// 添加在线书籍到书架
  Future<OnlineBookShelfItem> addBook(OnlineBook book) async {
    await _ensureInitialized();

    // 检查是否已存在
    final existing = _itemsCache?.firstWhere(
      (item) => item.bookUrl == book.bookUrl && item.sourceId == book.source.id,
      orElse: () => OnlineBookShelfItem(
        name: '',
        author: '',
        bookUrl: '',
        sourceId: '',
        sourceName: '',
        sourceUrl: '',
      ),
    );

    if (existing != null && existing.bookUrl.isNotEmpty) {
      logger.i('书籍已在书架中: ${book.name}');
      return existing;
    }

    final item = OnlineBookShelfItem.fromOnlineBook(book);

    // 保存到 Hive
    await _box!.put(item.id, jsonEncode(item.toJson()));

    // 更新缓存
    _itemsCache ??= [];
    _itemsCache!.insert(0, item);

    logger.i('添加在线书籍到书架: ${item.name}');
    return item;
  }

  /// 更新阅读进度
  Future<void> updateReadingProgress(
    String itemId, {
    required int chapterIndex,
    required String chapterName,
    required double progress,
  }) async {
    await _ensureInitialized();

    final index = _itemsCache?.indexWhere((item) => item.id == itemId) ?? -1;
    if (index == -1) return;

    final updated = _itemsCache![index].copyWith(
      lastReadAt: DateTime.now(),
      lastReadChapterIndex: chapterIndex,
      lastReadChapterName: chapterName,
      lastReadProgress: progress,
    );

    // 保存到 Hive
    await _box!.put(updated.id, jsonEncode(updated.toJson()));

    // 更新缓存
    _itemsCache![index] = updated;

    logger.d('更新阅读进度: ${updated.name}, 章节: $chapterIndex');
  }

  /// 删除书籍
  Future<void> removeBook(String itemId) async {
    await _ensureInitialized();

    final index = _itemsCache?.indexWhere((item) => item.id == itemId) ?? -1;
    if (index == -1) return;

    final removed = _itemsCache!.removeAt(index);
    await _box!.delete(itemId);

    logger.i('从书架移除: ${removed.name}');
  }

  /// 检查书籍是否在书架中
  Future<bool> isInShelf(String bookUrl, String sourceId) async {
    await _ensureInitialized();
    return _itemsCache?.any(
          (item) => item.bookUrl == bookUrl && item.sourceId == sourceId,
        ) ??
        false;
  }

  /// 根据 bookUrl 和 sourceId 获取书架项
  Future<OnlineBookShelfItem?> getByBookUrl(
      String bookUrl, String sourceId) async {
    await _ensureInitialized();
    try {
      return _itemsCache?.firstWhere(
        (item) => item.bookUrl == bookUrl && item.sourceId == sourceId,
      );
    } catch (_) {
      return null;
    }
  }

  /// 搜索书架中的书籍
  Future<List<OnlineBookShelfItem>> search(String query) async {
    await _ensureInitialized();
    if (query.isEmpty) return [];

    final lowerQuery = query.toLowerCase();
    return _itemsCache
            ?.where((item) =>
                item.name.toLowerCase().contains(lowerQuery) ||
                item.author.toLowerCase().contains(lowerQuery))
            .toList() ??
        [];
  }
}
