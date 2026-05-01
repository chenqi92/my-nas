import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/features/music/data/services/music_scraper_factory.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/domain/interfaces/music_scraper.dart';

/// 音乐刮削管理服务
///
/// 管理多个刮削源，提供统一的搜索、获取元数据、封面、歌词接口
class MusicScraperManagerService {
  MusicScraperManagerService() {
    _secureStorage = const FlutterSecureStorage();
  }

  static const String _boxName = 'music_scrapers';
  static const String _credentialPrefix = 'music_scraper_credential_';

  /// 一次性合规迁移标记（写入 Hive box 自身的特殊 key）
  /// 旧版本默认启用了商业平台刮削源；该迁移会把高风险源置为禁用状态。
  static const String _migrationKeyComplianceV1 = '__migration_compliance_v1__';

  late final FlutterSecureStorage _secureStorage;
  Box<dynamic>? _box;
  final Map<String, MusicScraper> _scraperCache = {};

  /// 初始化
  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  /// 确保已初始化
  Future<void> _ensureInit() async {
    if (_box == null || !_box!.isOpen) {
      await init();
    }
  }

  // ===== 刮削源 CRUD =====

  /// 获取所有刮削源（按优先级排序）
  Future<List<MusicScraperSourceEntity>> getSources() async {
    await _ensureInit();

    // 检查是否需要初始化默认源
    if (_box!.isEmpty) {
      await _initDefaultSources();
    } else {
      // 为已有用户添加新的刮削源类型
      await _addMissingDefaultSources();
      // 一次性合规迁移：将高风险源（绕过加密的网易云）置为禁用
      await _runComplianceMigrationV1();
    }

    final sources = <MusicScraperSourceEntity>[];
    for (final key in _box!.keys) {
      // 跳过迁移标记之类的内部 key
      if (key is String && key.startsWith('__')) continue;
      final data = _box!.get(key);
      if (data != null && data is Map) {
        try {
          final source = MusicScraperSourceEntity.fromJson(
            Map<String, dynamic>.from(data),
          );
          // 加载凭证
          final credential = await getCredential(source.id);
          if (credential != null && !credential.isEmpty) {
            sources.add(source.copyWith(
              apiKey: credential.apiKey ?? source.apiKey,
              cookie: credential.cookie ?? source.cookie,
            ));
          } else {
            sources.add(source);
          }
        } on Exception catch (e, st) {
          AppError.ignore(e, st, '解析刮削源配置失败: $key');
        }
      }
    }

    // 按优先级排序
    sources.sort((a, b) => a.priority.compareTo(b.priority));
    return sources;
  }

  /// 初始化默认刮削源（不需要配置的源）
  Future<void> _initDefaultSources() async {
    // 优先级：开放数据源（MusicBrainz / AcoustID）放最前；
    // 商业平台刮削源默认禁用，用户需在阅读风险提示后手动启用。
    final defaultTypes = [
      (MusicScraperType.musicBrainz, true),    // 开放音乐数据库（CC0 元数据）
      (MusicScraperType.acoustId, false),      // 声纹识别（需用户填入 API Key 后启用）
      (MusicScraperType.kugouMusic, false),    // 商业平台 ToS 风险，默认禁用
      (MusicScraperType.kuwoMusic, false),
      (MusicScraperType.miguMusic, false),
      (MusicScraperType.qqMusic, false),
      (MusicScraperType.neteaseMusic, false),  // 加密绕过风险最高，默认禁用
    ];

    for (var i = 0; i < defaultTypes.length; i++) {
      final (type, isEnabled) = defaultTypes[i];
      final source = MusicScraperSourceEntity(
        name: '',
        type: type,
        isEnabled: isEnabled,
        priority: i,
      );
      // 直接保存，不通过 addSource 避免重复计算优先级
      await _box!.put(source.id, source.toJson());
    }

    // 新装即视为已完成合规迁移，避免后续重复处理
    await _box!.put(_migrationKeyComplianceV1, true);
  }

  /// 为已有用户添加缺失的默认刮削源
  Future<void> _addMissingDefaultSources() async {
    // 新增源时遵循同样的安全默认：开放源默认启用，商业平台默认禁用。
    final defaultTypes = [
      (MusicScraperType.musicBrainz, true),
      (MusicScraperType.acoustId, false),
      (MusicScraperType.kugouMusic, false),
      (MusicScraperType.kuwoMusic, false),
      (MusicScraperType.miguMusic, false),
      (MusicScraperType.qqMusic, false),
      (MusicScraperType.neteaseMusic, false),
    ];

    // 获取当前已有的源类型
    final existingTypes = <MusicScraperType>{};
    for (final key in _box!.keys) {
      if (key is String && key.startsWith('__')) continue;
      final data = _box!.get(key);
      if (data != null && data is Map) {
        try {
          final source = MusicScraperSourceEntity.fromJson(
            Map<String, dynamic>.from(data),
          );
          existingTypes.add(source.type);
        } on Exception {
          // 忽略解析错误
        }
      }
    }

    // 找出缺失的源类型
    final missingTypesWithEnabled = defaultTypes
        .where((t) => !existingTypes.contains(t.$1))
        .toList();
    if (missingTypesWithEnabled.isEmpty) return;

    // 获取当前最大优先级
    var maxPriority = 0;
    for (final key in _box!.keys) {
      if (key is String && key.startsWith('__')) continue;
      final data = _box!.get(key);
      if (data != null && data is Map) {
        final priority = data['priority'] as int? ?? 0;
        if (priority > maxPriority) maxPriority = priority;
      }
    }

    // 添加缺失的源（追加到末尾）
    for (var i = 0; i < missingTypesWithEnabled.length; i++) {
      final (type, isEnabled) = missingTypesWithEnabled[i];
      final source = MusicScraperSourceEntity(
        name: '',
        type: type,
        isEnabled: isEnabled,
        priority: maxPriority + 1 + i,
      );
      await _box!.put(source.id, source.toJson());
    }
  }

  /// 一次性合规迁移：将所有非开放数据源（tosViolation / antiCircumvention）置为禁用。
  ///
  /// 仅在已存在配置且尚未跑过该迁移时执行。用户保留的 cookie / API Key 不受影响，
  /// 重新启用后立即恢复。该迁移只调整 isEnabled 状态。
  Future<void> _runComplianceMigrationV1() async {
    final alreadyDone = _box!.get(_migrationKeyComplianceV1) == true;
    if (alreadyDone) return;

    for (final key in _box!.keys.toList()) {
      if (key is String && key.startsWith('__')) continue;
      final data = _box!.get(key);
      if (data is! Map) continue;

      try {
        final source = MusicScraperSourceEntity.fromJson(
          Map<String, dynamic>.from(data),
        );
        if (source.type.riskLevel == MusicScraperRiskLevel.open) continue;
        if (!source.isEnabled) continue;

        final disabled = source.copyWith(isEnabled: false);
        await _box!.put(source.id, disabled.toJson());
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '合规迁移解析失败: $key');
      }
    }

    await _box!.put(_migrationKeyComplianceV1, true);
  }

  /// 获取单个刮削源
  Future<MusicScraperSourceEntity?> getSource(String id) async {
    await _ensureInit();

    final data = _box!.get(id);
    if (data == null || data is! Map) return null;

    try {
      final source = MusicScraperSourceEntity.fromJson(
        Map<String, dynamic>.from(data),
      );
      final credential = await getCredential(id);
      if (credential != null && !credential.isEmpty) {
        return source.copyWith(
          apiKey: credential.apiKey ?? source.apiKey,
          cookie: credential.cookie ?? source.cookie,
        );
      }
      return source;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '解析刮削源配置失败: $id');
      return null;
    }
  }

  /// 添加刮削源
  Future<MusicScraperSourceEntity> addSource(MusicScraperSourceEntity source) async {
    await _ensureInit();

    // 设置优先级为最低（列表末尾）
    final sources = await getSources();
    final newPriority = sources.isEmpty ? 0 : sources.last.priority + 1;
    final newSource = source.copyWith(priority: newPriority);

    // 保存配置（不含敏感信息）
    await _box!.put(newSource.id, newSource.toJson()
      ..remove('apiKey')
      ..remove('cookie'));

    // 保存凭证
    final hasApiKey = source.apiKey?.isNotEmpty ?? false;
    final hasCookie = source.cookie?.isNotEmpty ?? false;
    if (hasApiKey || hasCookie) {
      await saveCredential(
        newSource.id,
        MusicScraperCredential(
          apiKey: hasApiKey ? source.apiKey : null,
          cookie: hasCookie ? source.cookie : null,
        ),
      );
    } else {
      // 没有凭证时显式清除，避免残留旧值
      await removeCredential(newSource.id);
    }

    // 清除缓存
    _scraperCache.remove(newSource.id);

    return newSource;
  }

  /// 更新刮削源
  Future<void> updateSource(MusicScraperSourceEntity source) async {
    await _ensureInit();

    // 保存配置（不含敏感信息）
    await _box!.put(source.id, source.toJson()
      ..remove('apiKey')
      ..remove('cookie'));

    // 更新凭证
    final hasApiKey = source.apiKey?.isNotEmpty ?? false;
    final hasCookie = source.cookie?.isNotEmpty ?? false;
    if (hasApiKey || hasCookie) {
      await saveCredential(
        source.id,
        MusicScraperCredential(
          apiKey: hasApiKey ? source.apiKey : null,
          cookie: hasCookie ? source.cookie : null,
        ),
      );
    } else {
      // 用户清空了凭证字段：从 secure storage 中移除
      await removeCredential(source.id);
    }

    // 清除缓存（先释放旧实例，避免 HTTP 客户端等资源泄漏）
    _scraperCache.remove(source.id)?.dispose();
  }

  /// 删除刮削源
  Future<void> removeSource(String id) async {
    await _ensureInit();

    await _box!.delete(id);
    await removeCredential(id);

    // 清除缓存
    _scraperCache[id]?.dispose();
    _scraperCache.remove(id);
  }

  /// 切换启用状态
  Future<void> toggleSource(String id, {required bool isEnabled}) async {
    final source = await getSource(id);
    if (source != null) {
      await updateSource(source.copyWith(isEnabled: isEnabled));
    }
  }

  /// 调整优先级顺序
  Future<void> reorderSources(List<String> orderedIds) async {
    await _ensureInit();

    for (var i = 0; i < orderedIds.length; i++) {
      final source = await getSource(orderedIds[i]);
      if (source != null) {
        await updateSource(source.copyWith(priority: i));
      }
    }
  }

  // ===== 凭证管理 =====

  /// 保存凭证到安全存储
  Future<void> saveCredential(String sourceId, MusicScraperCredential credential) async {
    await _secureStorage.write(
      key: '$_credentialPrefix$sourceId',
      value: json.encode(credential.toJson()),
    );
  }

  /// 从安全存储获取凭证
  Future<MusicScraperCredential?> getCredential(String sourceId) async {
    final value = await _secureStorage.read(key: '$_credentialPrefix$sourceId');
    if (value == null) return null;
    try {
      return MusicScraperCredential.fromJson(
        json.decode(value) as Map<String, dynamic>,
      );
    } on Exception {
      return null;
    }
  }

  /// 删除凭证
  Future<void> removeCredential(String sourceId) async {
    await _secureStorage.delete(key: '$_credentialPrefix$sourceId');
  }

  // ===== 刮削器访问 =====

  /// 获取刮削器实例
  Future<MusicScraper?> getScraper(String sourceId) async {
    // 检查缓存
    if (_scraperCache.containsKey(sourceId)) {
      return _scraperCache[sourceId];
    }

    final source = await getSource(sourceId);
    if (source == null || !source.isConfigured) return null;

    // 检查是否已实现
    if (!MusicScraperFactory.isImplemented(source.type)) return null;

    try {
      final scraper = MusicScraperFactory.create(source);
      _scraperCache[sourceId] = scraper;
      return scraper;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '创建刮削器失败: ${source.type}');
      return null;
    }
  }

  /// 获取所有已启用且已配置的刮削器
  Future<List<(MusicScraperSourceEntity, MusicScraper)>> getEnabledScrapers() async {
    final sources = await getSources();
    final result = <(MusicScraperSourceEntity, MusicScraper)>[];

    debugPrint('[MusicScraperManager] 所有源: ${sources.map((s) => '${s.type.name}(enabled=${s.isEnabled},configured=${s.isConfigured})').join(', ')}');

    for (final source in sources) {
      if (!source.isEnabled) {
        debugPrint('[MusicScraperManager] ${source.type.name}: 跳过(未启用)');
        continue;
      }
      if (!source.isConfigured) {
        debugPrint('[MusicScraperManager] ${source.type.name}: 跳过(未配置)');
        continue;
      }
      if (!MusicScraperFactory.isImplemented(source.type)) {
        debugPrint('[MusicScraperManager] ${source.type.name}: 跳过(未实现)');
        continue;
      }

      final scraper = await getScraper(source.id);
      if (scraper != null) {
        result.add((source, scraper));
        debugPrint('[MusicScraperManager] ${source.type.name}: 已加载');
      } else {
        debugPrint('[MusicScraperManager] ${source.type.name}: 创建失败');
      }
    }

    debugPrint('[MusicScraperManager] 可用刮削器: ${result.map((r) => r.$1.type.name).join(', ')}');
    return result;
  }

  // ===== 统一刮削接口 =====

  /// 搜索音乐（按优先级尝试所有已启用的源）
  Future<List<MusicScraperSearchResult>> search(
    String query, {
    String? artist,
    String? album,
    int limit = 20,
  }) async {
    final scrapers = await getEnabledScrapers();
    final results = <MusicScraperSearchResult>[];

    debugPrint('[MusicScraperManager] search: query=$query, artist=$artist, album=$album');
    debugPrint('[MusicScraperManager] Enabled scrapers: ${scrapers.map((s) => s.$1.type.name).join(', ')}');

    for (final (source, scraper) in scrapers) {
      try {
        debugPrint('[MusicScraperManager] Searching with ${source.type.name}...');
        final result = await scraper.search(
          query,
          artist: artist,
          album: album,
          limit: limit,
        );
        debugPrint('[MusicScraperManager] ${source.type.name}: found ${result.items.length} results');
        if (result.isNotEmpty) {
          results.add(result);
        }
      } on Exception catch (e, st) {
        debugPrint('[MusicScraperManager] ${source.type.name} search failed: $e');
        AppError.ignore(e, st, '搜索失败: ${source.type}');
      }
    }

    debugPrint('[MusicScraperManager] Total results from ${results.length} sources');
    return results;
  }

  /// 获取第一个搜索结果
  Future<MusicScraperSearchResult?> searchFirst(
    String query, {
    String? artist,
    String? album,
    int limit = 20,
  }) async {
    final scrapers = await getEnabledScrapers();

    for (final (source, scraper) in scrapers) {
      try {
        final result = await scraper.search(
          query,
          artist: artist,
          album: album,
          limit: limit,
        );
        if (result.isNotEmpty) {
          return result;
        }
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '搜索失败: ${source.type}');
      }
    }

    return null;
  }

  /// 获取音乐详情（按优先级尝试）
  Future<MusicScraperDetail?> getDetail(
    String externalId,
    MusicScraperType sourceType,
  ) async {
    // getSources() 已按 priority 升序，firstOrNull 即拿到优先级最高的可用源
    final sources = await getSources();
    final source = sources
        .where((s) => s.type == sourceType && s.isEnabled && s.isConfigured)
        .firstOrNull;
    if (source == null) return null;

    final scraper = await getScraper(source.id);
    if (scraper == null) return null;

    try {
      return await scraper.getDetail(externalId);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '获取详情失败: $sourceType');
      return null;
    }
  }

  /// 获取封面（尝试所有支持封面的源）
  Future<CoverScraperResult?> getCover({
    String? title,
    String? artist,
    String? album,
  }) async {
    if (title == null && artist == null && album == null) return null;

    final scrapers = await getEnabledScrapers();

    for (final (source, scraper) in scrapers) {
      if (!source.type.supportsCover) continue;

      try {
        // 先搜索
        final searchResult = await scraper.search(
          title ?? '',
          artist: artist,
          album: album,
          limit: 1,
        );

        if (searchResult.isEmpty) continue;

        // 获取封面
        final covers = await scraper.getCoverArt(searchResult.items.first.externalId);
        if (covers.isNotEmpty) {
          return covers.first;
        }

        // 如果搜索结果有封面URL
        final item = searchResult.items.first;
        if (item.coverUrl != null) {
          return CoverScraperResult(
            source: source.type,
            coverUrl: item.coverUrl!,
          );
        }
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '获取封面失败: ${source.type}');
      }
    }

    return null;
  }

  /// 获取歌词（尝试所有支持歌词的源）
  Future<LyricScraperResult?> getLyrics({
    String? title,
    String? artist,
  }) async {
    if (title == null) return null;

    final scrapers = await getEnabledScrapers();

    for (final (source, scraper) in scrapers) {
      if (!source.type.supportsLyrics) continue;

      try {
        // 先搜索
        final searchResult = await scraper.search(
          title,
          artist: artist,
          limit: 1,
        );

        if (searchResult.isEmpty) continue;

        // 获取歌词
        final lyrics = await scraper.getLyrics(searchResult.items.first.externalId);
        if (lyrics != null && lyrics.hasLyrics) {
          return lyrics;
        }
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '获取歌词失败: ${source.type}');
      }
    }

    return null;
  }

  /// 综合刮削（获取所有可用数据）
  Future<MusicScrapeResult> scrape({
    required String title,
    String? artist,
    String? album,
    bool getCover = true,
    bool getLyrics = true,
  }) async {
    MusicScraperDetail? detail;
    CoverScraperResult? cover;
    LyricScraperResult? lyrics;
    final errors = <String>[];

    final scrapers = await getEnabledScrapers();

    // 1. 搜索并获取详情
    for (final (source, scraper) in scrapers) {
      if (detail != null) break;

      try {
        final searchResult = await scraper.search(
          title,
          artist: artist,
          album: album,
          limit: 1,
        );

        if (searchResult.isNotEmpty) {
          detail = await scraper.getDetail(searchResult.items.first.externalId);
        }
      } on Exception catch (e) {
        errors.add('[${source.type.displayName}] 搜索失败: $e');
      }
    }

    // 2. 获取封面
    if (getCover) {
      for (final (source, scraper) in scrapers) {
        if (cover != null) break;
        if (!source.type.supportsCover) continue;

        try {
          final searchResult = await scraper.search(
            title,
            artist: artist,
            album: album,
            limit: 1,
          );

          if (searchResult.isNotEmpty) {
            final item = searchResult.items.first;
            final covers = await scraper.getCoverArt(item.externalId);
            if (covers.isNotEmpty) {
              cover = covers.first;
            } else if (item.coverUrl != null) {
              cover = CoverScraperResult(
                source: source.type,
                coverUrl: item.coverUrl!,
              );
            }
          }
        } on Exception catch (e) {
          errors.add('[${source.type.displayName}] 获取封面失败: $e');
        }
      }
    }

    // 3. 获取歌词
    if (getLyrics) {
      for (final (source, scraper) in scrapers) {
        if (lyrics != null) break;
        if (!source.type.supportsLyrics) continue;

        try {
          final searchResult = await scraper.search(
            title,
            artist: artist,
            limit: 1,
          );

          if (searchResult.isNotEmpty) {
            lyrics = await scraper.getLyrics(searchResult.items.first.externalId);
          }
        } on Exception catch (e) {
          errors.add('[${source.type.displayName}] 获取歌词失败: $e');
        }
      }
    }

    return MusicScrapeResult(
      detail: detail,
      cover: cover,
      lyrics: lyrics,
      errors: errors,
    );
  }

  /// 通过音频指纹查找音乐信息
  ///
  /// [fingerprint] Chromaprint 生成的指纹字符串
  /// [duration] 音频时长（秒）
  ///
  /// 返回 [FingerprintResult] 或 null（如果没有启用的 AcoustID 源）
  Future<FingerprintResult?> lookupByFingerprint(
    String fingerprint,
    int duration,
  ) async {
    final scrapers = await getEnabledScrapers();

    // 查找 AcoustID 刮削器
    for (final (source, scraper) in scrapers) {
      if (source.type != MusicScraperType.acoustId) continue;

      if (scraper is FingerprintScraper) {
        try {
          return await scraper.lookupByFingerprint(fingerprint, duration);
        } on Exception catch (e, st) {
          AppError.ignore(e, st, 'AcoustID 查询失败');
        }
      }
    }

    return null;
  }

  /// 释放资源
  void dispose() {
    for (final scraper in _scraperCache.values) {
      scraper.dispose();
    }
    _scraperCache.clear();
  }
}
