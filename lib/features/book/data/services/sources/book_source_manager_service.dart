import 'dart:async';
import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/network/dio_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';

/// 书源变更事件类型
enum BookSourceEventType {
  /// 添加了新书源
  added,

  /// 更新了书源
  updated,

  /// 删除了书源
  removed,

  /// 重新加载
  reloaded,
}

/// 书源变更事件
class BookSourceEvent {
  const BookSourceEvent(this.type, this.source);

  final BookSourceEventType type;
  final BookSource? source;
}

/// 书源管理服务
///
/// 管理书源的 CRUD 操作
class BookSourceManagerService {
  BookSourceManagerService._();

  static final instance = BookSourceManagerService._();

  static const _boxName = 'book_sources';

  Box<String>? _box;
  bool _initialized = false;
  final _initCompleter = Completer<void>();

  /// 内存缓存
  List<BookSource>? _sourcesCache;

  /// 事件流
  final _eventController = StreamController<BookSourceEvent>.broadcast();

  /// 事件流
  Stream<BookSourceEvent> get events => _eventController.stream;

  /// 初始化服务
  Future<void> init() async {
    if (_initialized) return;

    try {
      await _doInit();
      _initialized = true;
      _initCompleter.complete();
    } catch (e, st) {
      _initCompleter.completeError(e, st);
      rethrow;
    }
  }

  Future<void> _doInit() async {
    if (Hive.isBoxOpen(_boxName)) {
      _box = Hive.box<String>(_boxName);
    } else {
      _box = await Hive.openBox<String>(_boxName);
    }
    // 预加载缓存
    await _loadCache();
    logger.i('书源管理服务初始化完成，已加载 ${_sourcesCache?.length ?? 0} 个书源');
  }

  /// 确保已初始化
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await _initCompleter.future;
    }
  }

  /// 加载缓存
  Future<void> _loadCache() async {
    final sources = <BookSource>[];
    
    for (final key in _box!.keys) {
      try {
        final json = _box!.get(key);
        if (json != null) {
          final data = jsonDecode(json) as Map<String, dynamic>;
          sources.add(BookSource.fromJson(data));
        }
      } catch (e, st) {
        logger.w('加载书源失败: $key', e, st);
      }
    }

    // 按 customOrder 排序
    sources.sort((a, b) => a.customOrder.compareTo(b.customOrder));
    _sourcesCache = sources;
  }

  /// 获取所有书源
  Future<List<BookSource>> getSources() async {
    await _ensureInitialized();
    return List.unmodifiable(_sourcesCache ?? []);
  }

  /// 获取已启用的书源
  Future<List<BookSource>> getEnabledSources() async {
    final sources = await getSources();
    return sources.where((s) => s.enabled).toList();
  }

  /// 按分组获取书源
  Future<Map<String, List<BookSource>>> getSourcesByGroup() async {
    final sources = await getSources();
    final grouped = <String, List<BookSource>>{};
    
    for (final source in sources) {
      final groups = source.groups;
      if (groups.isEmpty) {
        grouped.putIfAbsent(appL10n.bookSourceUngrouped, () => []).add(source);
      } else {
        for (final group in groups) {
          grouped.putIfAbsent(group, () => []).add(source);
        }
      }
    }
    
    return grouped;
  }

  /// 根据ID获取书源
  Future<BookSource?> getSourceById(String id) async {
    await _ensureInitialized();
    return _sourcesCache?.firstWhere(
      (s) => s.id == id,
      orElse: () => throw StateError(appL10n.bookSourceNotFoundError),
    );
  }

  /// 根据URL获取书源
  Future<BookSource?> getSourceByUrl(String url) async {
    await _ensureInitialized();
    try {
      return _sourcesCache?.firstWhere((s) => s.bookSourceUrl == url);
    } catch (_) {
      return null;
    }
  }

  /// 添加书源
  Future<void> addSource(BookSource source) async {
    await _ensureInitialized();

    // 检查是否已存在相同URL的书源
    final existing = await getSourceByUrl(source.bookSourceUrl);
    if (existing != null) {
      // 更新已有书源
      await updateSource(source.copyWith(id: existing.id));
      return;
    }

    // 设置排序顺序
    final maxOrder = _sourcesCache?.fold<int>(
          0,
          (max, s) => s.customOrder > max ? s.customOrder : max,
        ) ??
        0;
    final newSource = source.copyWith(customOrder: maxOrder + 1);

    // 保存到Hive
    await _box!.put(newSource.id, jsonEncode(newSource.toJson()));

    // 更新缓存
    _sourcesCache ??= [];
    _sourcesCache!.add(newSource);

    _eventController.add(BookSourceEvent(BookSourceEventType.added, newSource));
    logger.i('添加书源: ${newSource.displayName}');
  }

  /// 批量添加书源
  Future<int> addSources(List<BookSource> sources) async {
    await _ensureInitialized();
    
    var addedCount = 0;
    var maxOrder = _sourcesCache?.fold<int>(
          0,
          (max, s) => s.customOrder > max ? s.customOrder : max,
        ) ??
        0;

    for (final source in sources) {
      try {
        final existing = await getSourceByUrl(source.bookSourceUrl);
        if (existing != null) {
          // 更新已有书源
          await updateSource(source.copyWith(id: existing.id));
        } else {
          maxOrder++;
          final newSource = source.copyWith(customOrder: maxOrder);
          await _box!.put(newSource.id, jsonEncode(newSource.toJson()));
          _sourcesCache ??= [];
          _sourcesCache!.add(newSource);
          addedCount++;
        }
      } catch (e, st) {
        logger.w('添加书源失败: ${source.bookSourceName}', e, st);
      }
    }

    if (addedCount > 0) {
      _eventController.add(const BookSourceEvent(BookSourceEventType.reloaded, null));
      logger.i('批量添加书源完成，新增 $addedCount 个');
    }

    return addedCount;
  }

  /// 更新书源
  Future<void> updateSource(BookSource source) async {
    await _ensureInitialized();

    final index = _sourcesCache?.indexWhere((s) => s.id == source.id) ?? -1;
    if (index == -1) {
      throw StateError(appL10n.bookSourceNotFoundWithIdError(source.id));
    }

    // 保存到Hive
    await _box!.put(source.id, jsonEncode(source.toJson()));

    // 更新缓存
    _sourcesCache![index] = source;

    _eventController.add(BookSourceEvent(BookSourceEventType.updated, source));
    logger.i('更新书源: ${source.displayName}');
  }

  /// 删除书源
  Future<void> removeSource(String sourceId) async {
    await _ensureInitialized();

    final index = _sourcesCache?.indexWhere((s) => s.id == sourceId) ?? -1;
    if (index == -1) return;

    final removed = _sourcesCache!.removeAt(index);
    await _box!.delete(sourceId);

    _eventController.add(BookSourceEvent(BookSourceEventType.removed, removed));
    logger.i('删除书源: ${removed.displayName}');
  }

  /// 重新排序书源
  Future<void> reorderSources(int oldIndex, int newIndex) async {
    await _ensureInitialized();

    if (_sourcesCache == null ||
        oldIndex < 0 ||
        oldIndex >= _sourcesCache!.length ||
        newIndex < 0 ||
        newIndex >= _sourcesCache!.length ||
        oldIndex == newIndex) {
      return;
    }

    final source = _sourcesCache!.removeAt(oldIndex);
    _sourcesCache!.insert(newIndex, source);

    // 更新所有书源的 customOrder
    for (var i = 0; i < _sourcesCache!.length; i++) {
      final updated = _sourcesCache![i].copyWith(customOrder: i);
      _sourcesCache![i] = updated;
      await _box!.put(updated.id, jsonEncode(updated.toJson()));
    }

    _eventController.add(const BookSourceEvent(BookSourceEventType.reloaded, null));
    logger.i('重新排序书源: $oldIndex -> $newIndex');
  }

  /// 启用/禁用书源
  Future<void> toggleSource(String sourceId, {required bool enabled}) async {
    await _ensureInitialized();

    final source = _sourcesCache?.firstWhere((s) => s.id == sourceId);
    if (source == null) return;

    await updateSource(source.copyWith(enabled: enabled));
  }

  /// 从JSON导入书源
  ///
  /// 如果输入内容看起来像URL，自动使用 [importFromUrl] 导入
  Future<List<BookSource>> importFromJson(String json) async {
    // 检测是否为URL（用户可能误将URL粘贴到JSON输入框）
    final trimmed = json.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      logger.i('检测到URL输入，自动切换为URL导入: $trimmed');
      return importFromUrl(trimmed);
    }

    try {
      final data = jsonDecode(trimmed);
      
      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map(BookSource.fromJson)
            .toList();
      } else if (data is Map<String, dynamic>) {
        return [BookSource.fromJson(data)];
      }
      
      return [];
    } catch (e, st) {
      AppError.handle(e, st, 'importBookSourcesFromJson');
      rethrow;
    }
  }

  /// 从URL导入书源
  Future<List<BookSource>> importFromUrl(String url) async {
    try {
      final dio = DioClient.createTlsAware();
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 30);
      
      final response = await dio.get<String>(url);
      
      if (response.data == null || response.data!.isEmpty) {
        throw Exception(appL10n.bookSourceImportUrlFetchError);
      }
      
      return importFromJson(response.data!);
    } catch (e, st) {
      AppError.handle(e, st, 'importBookSourcesFromUrl');
      rethrow;
    }
  }

  /// 导出书源为JSON
  Future<String> exportToJson({List<String>? sourceIds}) async {
    await _ensureInitialized();
    
    List<BookSource> sources;
    if (sourceIds != null && sourceIds.isNotEmpty) {
      sources = _sourcesCache
              ?.where((s) => sourceIds.contains(s.id))
              .toList() ??
          [];
    } else {
      sources = _sourcesCache ?? [];
    }
    
    return jsonEncode(sources.map((s) => s.toJson()).toList());
  }

  /// 清空所有书源
  Future<void> clearAll() async {
    await _ensureInitialized();
    
    await _box!.clear();
    _sourcesCache?.clear();
    
    _eventController.add(const BookSourceEvent(BookSourceEventType.reloaded, null));
    logger.i('清空所有书源');
  }

  /// 释放资源
  void dispose() {
    _eventController.close();
  }
}
