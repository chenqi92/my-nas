import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/m3u_parser.dart';
import 'package:my_nas/features/video/domain/entities/live_stream_models.dart';

/// 直播流服务
///
/// 管理直播源的 CRUD 操作和持久化存储
class LiveStreamService {

  factory LiveStreamService() => _instance;
  LiveStreamService._();

  static final LiveStreamService _instance = LiveStreamService._();
  static LiveStreamService get instance => _instance;

  static const String _boxName = 'live_stream_settings';
  static const String _settingsKey = 'settings';

  Box<dynamic>? _box;
  bool _initialized = false;

  final _settingsController = StreamController<LiveStreamSettings>.broadcast();
  final _dio = Dio();

  /// 设置变化流
  Stream<LiveStreamSettings> get settingsStream => _settingsController.stream;

  /// 当前设置
  LiveStreamSettings? _currentSettings;
  LiveStreamSettings get settings =>
      _currentSettings ?? LiveStreamSettings.empty();

  /// 获取所有源（已排序）
  List<LiveStreamSource> get sources => settings.sortedSources;

  /// 获取启用的源
  List<LiveStreamSource> get enabledSources => settings.enabledSources;

  /// 获取所有频道
  List<LiveChannel> get allChannels => settings.allChannels;

  /// 获取所有分类
  Set<String> get allCategories => settings.allCategories;

  /// 初始化
  Future<void> init() async {
    if (_initialized) return;

    try {
      _box = await Hive.openBox(_boxName);
      _loadSettings();
      _initialized = true;
      logger.i('LiveStreamService: 初始化完成');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'LiveStreamService.init');
      _currentSettings = LiveStreamSettings.empty();
    }
  }

  /// 加载设置
  void _loadSettings() {
    try {
      final jsonStr = _box?.get(_settingsKey) as String?;
      if (jsonStr != null) {
        final map = json.decode(jsonStr) as Map<String, dynamic>;
        _currentSettings = LiveStreamSettings.fromMap(map);
        logger.d('LiveStreamService: 加载配置成功，'
            '${_currentSettings!.sources.length} 个直播源');
      } else {
        _currentSettings = LiveStreamSettings.empty();
        logger.d('LiveStreamService: 使用默认空配置');
      }
    } on Exception catch (e) {
      logger.w('LiveStreamService: 加载配置失败，使用默认配置', e);
      _currentSettings = LiveStreamSettings.empty();
    }
  }

  /// 保存设置
  Future<void> _saveSettings() async {
    if (_currentSettings == null) return;

    try {
      final jsonStr = json.encode(_currentSettings!.toMap());
      await _box?.put(_settingsKey, jsonStr);
      _settingsController.add(_currentSettings!);
      logger.d('LiveStreamService: 配置已保存');
    } on Exception catch (e) {
      logger.e('LiveStreamService: 保存配置失败', e);
    }
  }

  /// 添加直播源
  ///
  /// [name] 源名称
  /// [playlistUrl] M3U 播放列表 URL
  /// [autoRefresh] 是否自动刷新频道列表（默认 true）
  Future<LiveStreamSource> addSource({
    required String name,
    required String playlistUrl,
    bool autoRefresh = true,
  }) async {
    await init();

    var source = LiveStreamSource(
      name: name,
      playlistUrl: playlistUrl,
    );

    // 自动获取频道列表
    if (autoRefresh) {
      try {
        final channels = await fetchChannels(playlistUrl);
        source = source.copyWith(channels: channels);
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '添加源时获取频道失败，稍后可手动刷新');
      }
    }

    _currentSettings = settings.addSource(source);
    await _saveSettings();

    logger.i('LiveStreamService: 添加直播源 "$name"，${source.channelCount} 个频道');
    return source;
  }

  /// 更新直播源
  Future<void> updateSource(LiveStreamSource source) async {
    await init();
    _currentSettings = settings.updateSource(source);
    await _saveSettings();
    logger.i('LiveStreamService: 更新直播源 "${source.name}"');
  }

  /// 删除直播源
  Future<void> removeSource(String sourceId) async {
    await init();
    _currentSettings = settings.removeSource(sourceId);
    await _saveSettings();
    logger.i('LiveStreamService: 删除直播源 $sourceId');
  }

  /// 切换源启用状态
  Future<void> toggleEnabled(String sourceId, {bool? enabled}) async {
    await init();
    _currentSettings = settings.toggleEnabled(sourceId, enabled: enabled);
    await _saveSettings();
  }

  /// 重新排序
  Future<void> reorder(int oldIndex, int newIndex) async {
    await init();
    // 处理 Flutter ReorderableListView 的索引行为
    var actualNewIndex = newIndex;
    if (newIndex > oldIndex) {
      actualNewIndex -= 1;
    }
    _currentSettings = settings.reorder(oldIndex, actualNewIndex);
    await _saveSettings();
  }

  /// 刷新源的频道列表
  Future<LiveStreamSource> refreshSource(String sourceId) async {
    await init();

    final source = sources.firstWhere(
      (s) => s.id == sourceId,
      orElse: () => throw Exception('源不存在: $sourceId'),
    );

    final channels = await fetchChannels(source.playlistUrl);
    final updatedSource = source.copyWith(channels: channels);

    _currentSettings = settings.updateSource(updatedSource);
    await _saveSettings();

    logger.i('LiveStreamService: 刷新直播源 "${source.name}"，${channels.length} 个频道');
    return updatedSource;
  }

  /// 从 URL 获取频道列表
  ///
  /// [url] M3U 播放列表 URL
  /// 返回解析后的 [LiveChannel] 列表
  Future<List<LiveChannel>> fetchChannels(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'User-Agent': 'Mozilla/5.0 (compatible; MyNAS/1.0)',
          },
        ),
      );

      if (response.data == null || response.data!.isEmpty) {
        throw Exception('播放列表内容为空');
      }

      return M3UParser.parse(response.data!);
    } on DioException catch (e) {
      throw Exception('获取播放列表失败: ${e.message}');
    }
  }

  /// 预览 M3U URL（不保存）
  ///
  /// 用于添加源前的预览
  Future<List<LiveChannel>> previewChannels(String url) async => fetchChannels(url);

  /// 获取指定源
  LiveStreamSource? getSource(String sourceId) {
    try {
      return sources.firstWhere((s) => s.id == sourceId);
    } catch (_) {
      return null;
    }
  }

  /// 获取指定频道
  LiveChannel? getChannel(String channelId) {
    for (final source in enabledSources) {
      for (final channel in source.channels) {
        if (channel.id == channelId) {
          return channel;
        }
      }
    }
    return null;
  }

  /// 按分类获取频道
  List<LiveChannel> getChannelsByCategory(String category) => allChannels.where((c) => c.category == category).toList();

  /// 搜索频道
  List<LiveChannel> searchChannels(String query) {
    if (query.isEmpty) return allChannels;
    final lowerQuery = query.toLowerCase();
    return allChannels.where((c) => c.name.toLowerCase().contains(lowerQuery) ||
          (c.category?.toLowerCase().contains(lowerQuery) ?? false)).toList();
  }

  /// 关闭
  Future<void> close() async {
    await _settingsController.close();
    await _box?.close();
  }
}
