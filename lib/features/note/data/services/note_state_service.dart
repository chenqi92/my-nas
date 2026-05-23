import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 笔记交互状态（每条笔记一条记录）。
///
/// 笔记内容本身是 NAS 上的文件，不属于这里。这里只保存"用户对这条笔记做了什么"：
/// 最后打开时间、阅读位置（scrollOffset）、书签。结构与同步格式保持一致，所以
/// `toMap` 同时被本地 Hive 存储与云同步 JSON 复用。
class NoteState {
  const NoteState({
    required this.notePath,
    required this.lastOpenedAt,
    required this.updatedAt,
    this.modifiedAt,
    this.scrollOffset,
    this.bookmarks = const [],
  });

  factory NoteState.fromMap(Map<dynamic, dynamic> m) {
    final bookmarksRaw = (m['bookmarks'] as List?) ?? const [];
    final bookmarks = <NoteBookmark>[];
    for (final raw in bookmarksRaw) {
      if (raw is Map) {
        try {
          bookmarks.add(NoteBookmark.fromMap(raw));
        } on Exception catch (_) {
          continue;
        }
      }
    }
    return NoteState(
      notePath: m['notePath'] as String,
      modifiedAt: _parseDate(m['modifiedAt']),
      scrollOffset: (m['scrollOffset'] as num?)?.toDouble(),
      lastOpenedAt: _parseDate(m['lastOpenedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      bookmarks: bookmarks,
      updatedAt: _parseDate(m['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String notePath;
  final DateTime? modifiedAt;
  final double? scrollOffset;
  final DateTime lastOpenedAt;
  final List<NoteBookmark> bookmarks;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() => {
        'notePath': notePath,
        if (modifiedAt != null) 'modifiedAt': modifiedAt!.toIso8601String(),
        if (scrollOffset != null) 'scrollOffset': scrollOffset,
        'lastOpenedAt': lastOpenedAt.toIso8601String(),
        'bookmarks': bookmarks.map((b) => b.toMap()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  NoteState copyWith({
    DateTime? modifiedAt,
    double? scrollOffset,
    DateTime? lastOpenedAt,
    List<NoteBookmark>? bookmarks,
    DateTime? updatedAt,
  }) =>
      NoteState(
        notePath: notePath,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        scrollOffset: scrollOffset ?? this.scrollOffset,
        lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
        bookmarks: bookmarks ?? this.bookmarks,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  static DateTime? _parseDate(Object? raw) {
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}

/// 笔记书签（按行号定位）。
class NoteBookmark {
  const NoteBookmark({
    required this.line,
    required this.createdAt,
    this.label,
  });

  factory NoteBookmark.fromMap(Map<dynamic, dynamic> m) => NoteBookmark(
        line: (m['line'] as num).toInt(),
        label: m['label'] as String?,
        createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  final int line;
  final String? label;
  final DateTime createdAt;

  /// 用于去重的指纹：line + createdAt（精确到毫秒）。
  String get fingerprint =>
      '$line@${createdAt.millisecondsSinceEpoch}';

  Map<String, dynamic> toMap() => {
        'line': line,
        if (label != null) 'label': label,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// 笔记状态服务。Hive box `note_states`，key = 笔记完整路径。
class NoteStateService {
  factory NoteStateService() => _instance ??= NoteStateService._();
  NoteStateService._();

  static NoteStateService? _instance;

  static const String _boxName = 'note_states';

  Box<dynamic>? _box;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      _box = Hive.isBoxOpen(_boxName)
          ? Hive.box<dynamic>(_boxName)
          : await Hive.openBox<dynamic>(_boxName);
      _initialized = true;
      logger.i('NoteStateService: 初始化完成');
    } on Exception catch (e) {
      logger.e('NoteStateService: 初始化失败', e);
      rethrow;
    }
  }

  NoteState? getState(String notePath) {
    if (!_initialized) return null;
    final raw = _box!.get(notePath);
    if (raw is Map) {
      try {
        return NoteState.fromMap(raw);
      } on Exception catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> saveState(NoteState state) async {
    if (!_initialized) await init();
    await _box!.put(state.notePath, state.toMap());
  }

  List<NoteState> getAllStates() {
    if (!_initialized) return const [];
    final out = <NoteState>[];
    for (final k in _box!.keys) {
      final raw = _box!.get(k);
      if (raw is Map) {
        try {
          out.add(NoteState.fromMap(raw));
        } on Exception catch (_) {
          continue;
        }
      }
    }
    return out;
  }

  /// 标记笔记被打开过：写入 lastOpenedAt 并刷新 updatedAt。
  Future<void> markOpened(String notePath, {DateTime? modifiedAt}) async {
    await init();
    final now = DateTime.now();
    final existing = getState(notePath);
    final next = (existing ??
            NoteState(
              notePath: notePath,
              lastOpenedAt: now,
              updatedAt: now,
              modifiedAt: modifiedAt,
            ))
        .copyWith(
      lastOpenedAt: now,
      modifiedAt: modifiedAt ?? existing?.modifiedAt,
      updatedAt: now,
    );
    await saveState(next);
  }

  /// 记录阅读位置（scrollOffset，以像素为单位）。
  Future<void> setScrollOffset(String notePath, double scrollOffset) async {
    await init();
    final now = DateTime.now();
    final existing = getState(notePath);
    final next = (existing ??
            NoteState(
              notePath: notePath,
              lastOpenedAt: now,
              updatedAt: now,
              scrollOffset: scrollOffset,
            ))
        .copyWith(scrollOffset: scrollOffset, updatedAt: now);
    await saveState(next);
  }

  /// 新增书签（按 (line, createdAt) 去重）。
  Future<void> addBookmark(String notePath, NoteBookmark bookmark) async {
    await init();
    final now = DateTime.now();
    final existing = getState(notePath);
    final bookmarks = <NoteBookmark>[
      if (existing != null) ...existing.bookmarks,
      bookmark,
    ];
    final dedup = <String, NoteBookmark>{
      for (final b in bookmarks) b.fingerprint: b,
    };
    final merged = dedup.values.toList()
      ..sort((a, b) => a.line.compareTo(b.line));
    final next = (existing ??
            NoteState(
              notePath: notePath,
              lastOpenedAt: now,
              updatedAt: now,
            ))
        .copyWith(bookmarks: merged, updatedAt: now);
    await saveState(next);
  }

  /// 移除书签（按 line + createdAt 精确匹配）。
  Future<void> removeBookmark(String notePath, NoteBookmark bookmark) async {
    await init();
    final existing = getState(notePath);
    if (existing == null) return;
    final filtered = existing.bookmarks
        .where((b) => b.fingerprint != bookmark.fingerprint)
        .toList();
    if (filtered.length == existing.bookmarks.length) return;
    await saveState(
      existing.copyWith(bookmarks: filtered, updatedAt: DateTime.now()),
    );
  }
}
