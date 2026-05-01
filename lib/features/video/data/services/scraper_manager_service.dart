import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/utils/hive_utils.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/scraper_factory.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/domain/entities/scraper_result.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/domain/interfaces/media_scraper.dart';

/// 刮削源变更事件类型
enum ScraperSourceEventType {
  /// 添加了新刮削源
  added,

  /// 更新了刮削源
  updated,

  /// 删除了刮削源
  removed,
}

/// 刮削源变更事件
class ScraperSourceEvent {
  const ScraperSourceEvent({
    required this.type,
    required this.source,
  });

  final ScraperSourceEventType type;
  final ScraperSourceEntity source;
}

/// 刮削源管理服务
///
/// 管理刮削源的 CRUD 操作，以及按优先级执行刮削
class ScraperManagerService {
  factory ScraperManagerService() => _instance ??= ScraperManagerService._();
  ScraperManagerService._();

  static ScraperManagerService? _instance;

  static const String _boxName = 'scrapers';
  static const String _listKey = 'list';
  static const String _credentialPrefix = 'scraper_credential_';

  late Box<dynamic> _box;
  bool _initialized = false;
  Future<void>? _initFuture;

  /// 刮削器实例缓存
  final Map<String, MediaScraper> _scraperInstances = {};

  /// 刮削源变更事件流控制器
  final _eventController = StreamController<ScraperSourceEvent>.broadcast();

  /// 刮削源变更事件流
  ///
  /// 当刮削源被添加、更新或删除时发出事件，
  /// 可用于触发元数据增强等后续操作
  Stream<ScraperSourceEvent> get onSourceChanged => _eventController.stream;

  /// 安全存储（用于存储 API Key、Cookie 等敏感信息）
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  /// 初始化服务
  Future<void> init() async {
    if (_initialized) return;
    if (_initFuture != null) {
      await _initFuture;
      return;
    }

    _initFuture = _doInit();
    await _initFuture;
    _initFuture = null;
  }

  Future<void> _doInit() async {
    try {
      _box = await Hive.openBox<dynamic>(_boxName);
      _initialized = true;
      logger.i('ScraperManagerService 初始化完成');

      // 同步已有的 TMDB 刮削源配置到 TmdbService
      await _syncExistingTmdbConfig();
    } on Exception catch (e, st) {
      logger.e('ScraperManagerService 初始化失败', e, st);
      rethrow;
    }
  }

  /// 初始化时同步已有的 TMDB 配置
  Future<void> _syncExistingTmdbConfig() async {
    try {
      final sources = await getSources();
      final tmdbSource = sources.where((s) => s.type == ScraperType.tmdb).firstOrNull;
      if (tmdbSource != null) {
        final credential = await getCredential(tmdbSource.id);
        if (credential?.apiKey != null && credential!.apiKey!.isNotEmpty) {
          await _syncTmdbConfig(
            apiKey: credential.apiKey!,
            apiUrl: tmdbSource.apiUrl,
            imageProxy: tmdbSource.extraConfig?['imageProxy'] as String?,
          );
        }
      }
    } on Exception catch (e, st) {
      logger.w('同步已有 TMDB 配置失败', e, st);
    }
  }

  /// 确保已初始化
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await init();
    }
  }

  // === CRUD 操作 ===

  /// 获取所有刮削源（按优先级排序）
  Future<List<ScraperSourceEntity>> getSources() async {
    await _ensureInitialized();

    final data = _box.get(_listKey);
    if (data == null) return [];

    try {
      final list = (data as List).cast<Map<dynamic, dynamic>>();
      final sources = list
          .map((e) => ScraperSourceEntity.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => a.priority.compareTo(b.priority));
      return sources;
    } on Exception catch (e, st) {
      logger.e('解析刮削源列表失败', e, st);
      return [];
    }
  }

  /// 添加刮削源
  Future<void> addSource(ScraperSourceEntity source) async {
    await _ensureInitialized();

    final sources = await getSources();

    // 设置优先级为最后
    final newSource = source.copyWith(priority: sources.length);
    sources.add(newSource);

    await _saveSources(sources);

    // 如果有凭证，保存到安全存储
    if (source.apiKey != null || source.cookie != null) {
      await saveCredential(
        source.id,
        ScraperCredential(
          apiKey: source.apiKey,
          cookie: source.cookie,
        ),
      );
    }

    // 同步 TMDB 配置到 TmdbService（用于推荐内容等功能）
    if (source.type == ScraperType.tmdb && source.apiKey != null) {
      await _syncTmdbConfig(
        apiKey: source.apiKey!,
        apiUrl: source.apiUrl,
        imageProxy: source.extraConfig?['imageProxy'] as String?,
      );
    }

    logger.i('添加刮削源: ${source.displayName}');

    // 发出添加事件，用于触发元数据增强等后续操作
    _eventController.add(ScraperSourceEvent(
      type: ScraperSourceEventType.added,
      source: newSource,
    ));
  }

  /// 更新刮削源
  Future<void> updateSource(ScraperSourceEntity source) async {
    await _ensureInitialized();

    final sources = await getSources();
    final index = sources.indexWhere((s) => s.id == source.id);
    if (index == -1) {
      throw Exception('刮削源不存在: ${source.id}');
    }

    sources[index] = source;
    await _saveSources(sources);

    // 更新凭证
    if (source.apiKey != null || source.cookie != null) {
      await saveCredential(
        source.id,
        ScraperCredential(
          apiKey: source.apiKey,
          cookie: source.cookie,
        ),
      );
    }

    // 同步 TMDB 配置到 TmdbService（用于推荐内容等功能）
    if (source.type == ScraperType.tmdb && source.apiKey != null) {
      await _syncTmdbConfig(
        apiKey: source.apiKey!,
        apiUrl: source.apiUrl,
        imageProxy: source.extraConfig?['imageProxy'] as String?,
      );
    }

    // 清除缓存的刮削器实例
    _scraperInstances.remove(source.id)?.dispose();

    logger.i('更新刮削源: ${source.displayName}');

    // 发出更新事件
    _eventController.add(ScraperSourceEvent(
      type: ScraperSourceEventType.updated,
      source: source,
    ));
  }

  /// 删除刮削源
  Future<void> removeSource(String sourceId) async {
    await _ensureInitialized();

    final sources = await getSources();
    final removedSource = sources.where((s) => s.id == sourceId).firstOrNull;
    sources.removeWhere((s) => s.id == sourceId);

    // 重新计算优先级
    for (var i = 0; i < sources.length; i++) {
      sources[i] = sources[i].copyWith(priority: i);
    }

    await _saveSources(sources);

    // 删除凭证
    await removeCredential(sourceId);

    // 清除缓存的刮削器实例
    _scraperInstances.remove(sourceId)?.dispose();

    logger.i('删除刮削源: $sourceId');

    // 发出删除事件
    if (removedSource != null) {
      _eventController.add(ScraperSourceEvent(
        type: ScraperSourceEventType.removed,
        source: removedSource,
      ));
    }
  }

  /// 重新排序刮削源
  Future<void> reorderSources(int oldIndex, int newIndex) async {
    await _ensureInitialized();

    final sources = await getSources();
    if (oldIndex < 0 ||
        oldIndex >= sources.length ||
        newIndex < 0 ||
        newIndex >= sources.length) {
      return;
    }

    final source = sources.removeAt(oldIndex);
    sources.insert(newIndex, source);

    // 重新计算优先级
    for (var i = 0; i < sources.length; i++) {
      sources[i] = sources[i].copyWith(priority: i);
    }

    await _saveSources(sources);
    logger.i('重新排序刮削源: $oldIndex -> $newIndex');
  }

  /// 启用/禁用刮削源
  Future<void> toggleSource(String sourceId, {required bool enabled}) async {
    await _ensureInitialized();

    final sources = await getSources();
    final index = sources.indexWhere((s) => s.id == sourceId);
    if (index == -1) return;

    sources[index] = sources[index].copyWith(isEnabled: enabled);
    await _saveSources(sources);

    logger.i('${enabled ? "启用" : "禁用"}刮削源: ${sources[index].displayName}');
  }

  /// 保存刮削源列表
  Future<void> _saveSources(List<ScraperSourceEntity> sources) async {
    // 保存时不包含敏感信息
    final data = sources.map((s) {
      final json = s.toJson()
      // 移除敏感字段（存储在安全存储中）
      ..remove('apiKey')
      ..remove('cookie');
      return json;
    }).toList();

    await _box.put(_listKey, data);
  }

  // === 凭证管理 ===

  /// 同步 TMDB 配置到 TmdbService 和 Hive 存储
  ///
  /// TmdbService 用于获取推荐内容、相似内容等功能，需要独立的配置
  /// [apiKey] API Key
  /// [apiUrl] 自定义 API URL（如 https://api.tmdb.org）
  /// [imageProxy] 图片代理 URL
  Future<void> _syncTmdbConfig({
    required String apiKey,
    String? apiUrl,
    String? imageProxy,
  }) async {
    try {
      // TmdbService 是单例——cascade 用来配置全局实例
      TmdbService()
        ..setApiKey(apiKey)
        ..setApiUrl(apiUrl)
        ..setImageUrl(imageProxy);

      // 同步到 Hive 存储（用于 app 重启后恢复）
      final box = await HiveUtils.getSettingsBox();
      await box.put('tmdb_api_key', apiKey);
      if (apiUrl != null && apiUrl.isNotEmpty) {
        await box.put('tmdb_api_url', apiUrl);
      }
      if (imageProxy != null && imageProxy.isNotEmpty) {
        await box.put('tmdb_image_url', imageProxy);
      }

      logger.i('TMDB 配置已同步: apiUrl=$apiUrl, imageProxy=$imageProxy');
    } on Exception catch (e, st) {
      logger.e('同步 TMDB 配置失败', e, st);
    }
  }

  /// 保存凭证到安全存储
  Future<void> saveCredential(String sourceId, ScraperCredential credential) async {
    try {
      final key = '$_credentialPrefix$sourceId';
      final value = jsonEncode(credential.toJson());
      await _secureStorage.write(key: key, value: value);
    } on Exception catch (e, st) {
      logger.e('保存刮削源凭证失败', e, st);
    }
  }

  /// 获取凭证
  Future<ScraperCredential?> getCredential(String sourceId) async {
    try {
      final key = '$_credentialPrefix$sourceId';
      final value = await _secureStorage.read(key: key);
      if (value == null) return null;

      final json = jsonDecode(value) as Map<String, dynamic>;
      return ScraperCredential.fromJson(json);
    } on Exception catch (e, st) {
      logger.e('读取刮削源凭证失败', e, st);
      return null;
    }
  }

  /// 删除凭证
  Future<void> removeCredential(String sourceId) async {
    try {
      final key = '$_credentialPrefix$sourceId';
      await _secureStorage.delete(key: key);
    } on Exception catch (e, st) {
      logger.e('删除刮削源凭证失败', e, st);
    }
  }

  // === 刮削器访问 ===

  /// 获取指定源的刮削器实例（带凭证）
  Future<MediaScraper?> getScraper(String sourceId) async {
    // 检查缓存
    if (_scraperInstances.containsKey(sourceId)) {
      return _scraperInstances[sourceId];
    }

    final sources = await getSources();
    final source = sources.where((s) => s.id == sourceId).firstOrNull;
    if (source == null) return null;

    // 获取凭证
    final credential = await getCredential(sourceId);

    // 创建完整的源实体（包含凭证）
    final fullSource = source.copyWith(
      apiKey: credential?.apiKey ?? source.apiKey,
      cookie: credential?.cookie ?? source.cookie,
    );

    // 创建刮削器实例
    final scraper = ScraperFactory.create(fullSource);
    _scraperInstances[sourceId] = scraper;

    return scraper;
  }

  /// 获取所有已启用且已配置的刮削器（按优先级排序）
  Future<List<MediaScraper>> getEnabledScrapers() async {
    final sources = await getSources();
    final enabledSources = sources.where((s) => s.isEnabled).toList();

    final scrapers = <MediaScraper>[];
    for (final source in enabledSources) {
      final scraper = await getScraper(source.id);
      if (scraper != null && scraper.isConfigured) {
        scrapers.add(scraper);
      }
    }

    return scrapers;
  }

  // === 按优先级刮削 ===

  /// 搜索电影（按优先级尝试所有刮削源）
  ///
  /// 第一个返回非空结果的刮削源将被使用
  Future<ScraperSearchResult> searchMovies(
    String query, {
    int page = 1,
    String? language,
    int? year,
  }) async {
    final scrapers = await getEnabledScrapers();

    for (final scraper in scrapers) {
      try {
        final result = await scraper.searchMovies(
          query,
          page: page,
          language: language,
          year: year,
        );
        if (result.isNotEmpty) {
          logger.d('使用 ${scraper.type.displayName} 搜索电影成功: $query');
          return result;
        }
      } on Exception catch (e) {
        logger.w('${scraper.type.displayName} 搜索电影失败: $e');
        continue;
      }
    }

    logger.w('所有刮削源搜索电影失败: $query');
    return ScraperSearchResult.empty();
  }

  /// 搜索电视剧（按优先级尝试所有刮削源）
  Future<ScraperSearchResult> searchTvShows(
    String query, {
    int page = 1,
    String? language,
    int? year,
  }) async {
    final scrapers = await getEnabledScrapers();

    for (final scraper in scrapers) {
      try {
        final result = await scraper.searchTvShows(
          query,
          page: page,
          language: language,
          year: year,
        );
        if (result.isNotEmpty) {
          logger.d('使用 ${scraper.type.displayName} 搜索电视剧成功: $query');
          return result;
        }
      } on Exception catch (e) {
        logger.w('${scraper.type.displayName} 搜索电视剧失败: $e');
        continue;
      }
    }

    logger.w('所有刮削源搜索电视剧失败: $query');
    return ScraperSearchResult.empty();
  }

  /// 获取电影详情（按优先级尝试）
  ///
  /// [query] 电影名称（用于搜索）
  /// [externalId] 如果已知外部 ID，可直接获取详情
  /// [source] 指定刮削源类型
  Future<ScraperMovieDetail?> getMovieDetail({
    String? query,
    String? externalId,
    ScraperType? source,
    String? language,
    int? year,
  }) async {
    // 如果指定了 ID 和来源，直接获取
    if (externalId != null && source != null) {
      final scrapers = await getEnabledScrapers();
      final scraper = scrapers.where((s) => s.type == source).firstOrNull;
      if (scraper != null) {
        return scraper.getMovieDetail(externalId, language: language);
      }
    }

    // 否则搜索然后获取详情
    if (query != null) {
      final searchResult = await searchMovies(
        query,
        language: language,
        year: year,
      );

      if (searchResult.isNotEmpty) {
        final item = searchResult.items.first;
        final scrapers = await getEnabledScrapers();
        final scraper = scrapers.where((s) => s.type == item.source).firstOrNull;
        if (scraper != null) {
          return scraper.getMovieDetail(item.externalId, language: language);
        }
      }
    }

    return null;
  }

  /// 获取电视剧详情（按优先级尝试）
  Future<ScraperTvDetail?> getTvDetail({
    String? query,
    String? externalId,
    ScraperType? source,
    String? language,
    int? year,
  }) async {
    // 如果指定了 ID 和来源，直接获取
    if (externalId != null && source != null) {
      final scrapers = await getEnabledScrapers();
      final scraper = scrapers.where((s) => s.type == source).firstOrNull;
      if (scraper != null) {
        return scraper.getTvDetail(externalId, language: language);
      }
    }

    // 否则搜索然后获取详情
    if (query != null) {
      final searchResult = await searchTvShows(
        query,
        language: language,
        year: year,
      );

      if (searchResult.isNotEmpty) {
        final item = searchResult.items.first;
        final scrapers = await getEnabledScrapers();
        final scraper = scrapers.where((s) => s.type == item.source).firstOrNull;
        if (scraper != null) {
          return scraper.getTvDetail(item.externalId, language: language);
        }
      }
    }

    return null;
  }

  /// 获取剧集详情
  Future<ScraperEpisodeDetail?> getEpisodeDetail({
    required String tvId,
    required int seasonNumber,
    required int episodeNumber,
    required ScraperType source,
    String? language,
  }) async {
    final scrapers = await getEnabledScrapers();
    final scraper = scrapers.where((s) => s.type == source).firstOrNull;
    if (scraper != null) {
      return scraper.getEpisodeDetail(
        tvId,
        seasonNumber,
        episodeNumber,
        language: language,
      );
    }
    return null;
  }

  /// 获取季详情
  Future<ScraperSeasonDetail?> getSeasonDetail({
    required String tvId,
    required int seasonNumber,
    required ScraperType source,
    String? language,
  }) async {
    final scrapers = await getEnabledScrapers();
    final scraper = scrapers.where((s) => s.type == source).firstOrNull;
    if (scraper != null) {
      return scraper.getSeasonDetail(tvId, seasonNumber, language: language);
    }
    return null;
  }

  // === 数据迁移 ===

  /// 从旧的 TMDB API Key 配置迁移
  ///
  /// 检查 settings box 中是否有旧的 tmdb_api_key 配置，
  /// 如果有且刮削源列表为空，则自动创建 TMDB 刮削源
  Future<void> migrateFromLegacyConfig() async {
    await _ensureInitialized();

    final sources = await getSources();
    if (sources.isNotEmpty) {
      // 已有刮削源配置，不需要迁移
      return;
    }

    try {
      final settingsBox = await HiveUtils.getSettingsBox();
      final oldApiKey = settingsBox.get('tmdb_api_key') as String?;

      if (oldApiKey != null && oldApiKey.isNotEmpty) {
        // 创建 TMDB 刮削源
        final tmdbSource = ScraperSourceEntity(
          name: 'TMDB',
          type: ScraperType.tmdb,
          apiKey: oldApiKey,
          isEnabled: true,
          priority: 0,
        );

        await addSource(tmdbSource);
        logger.i('已从旧配置迁移 TMDB API Key');

        // 可选：删除旧配置
        // await settingsBox.delete('tmdb_api_key');
      }
    } on Exception catch (e, st) {
      logger.e('迁移旧 TMDB 配置失败', e, st);
    }
  }

  /// 释放资源
  void dispose() {
    for (final scraper in _scraperInstances.values) {
      scraper.dispose();
    }
    _scraperInstances.clear();
    _eventController.close();
  }
}
