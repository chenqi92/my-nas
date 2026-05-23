import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/data/services/live_stream_service.dart';
import 'package:my_nas/features/video/domain/entities/live_stream_models.dart';

/// 直播流设置 Provider
final liveStreamSettingsProvider =
    StateNotifierProvider<LiveStreamSettingsNotifier, LiveStreamSettings>(
  (ref) => LiveStreamSettingsNotifier(),
);

/// 启用的直播源 Provider
final enabledLiveSourcesProvider = Provider<List<LiveStreamSource>>((ref) {
  final settings = ref.watch(liveStreamSettingsProvider);
  return settings.enabledSources;
});

/// 所有直播频道 Provider
final allLiveChannelsProvider = Provider<List<LiveChannel>>((ref) {
  final settings = ref.watch(liveStreamSettingsProvider);
  return settings.allChannels;
});

/// 所有直播分类 Provider
final liveChannelCategoriesProvider = Provider<Set<String>>((ref) {
  final settings = ref.watch(liveStreamSettingsProvider);
  return settings.allCategories;
});

/// 按分类分组的频道 Provider
final liveChannelsByCategoryProvider =
    Provider<Map<String, List<LiveChannel>>>((ref) {
  final settings = ref.watch(liveStreamSettingsProvider);
  return settings.channelsByCategory;
});

/// 是否有直播源 Provider
final hasLiveSourcesProvider = Provider<bool>((ref) {
  final settings = ref.watch(liveStreamSettingsProvider);
  return settings.enabledSources.isNotEmpty;
});

/// 首页展示的频道 Provider（取前 N 个）
final featuredLiveChannelsProvider =
    Provider.family<List<LiveChannel>, int>((ref, count) {
  final channels = ref.watch(allLiveChannelsProvider);
  return channels.take(count).toList();
});

/// 直播流设置 Notifier
class LiveStreamSettingsNotifier extends StateNotifier<LiveStreamSettings> {
  LiveStreamSettingsNotifier() : super(LiveStreamSettings.empty()) {
    _init();
  }

  final _service = LiveStreamService();
  StreamSubscription<LiveStreamSettings>? _subscription;

  Future<void> _init() async {
    await _service.init();
    state = _service.settings;

    // 监听设置变化
    _subscription = _service.settingsStream.listen((settings) {
      state = settings;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// 添加直播源
  Future<LiveStreamSource> addSource({
    required String name,
    required String playlistUrl,
    bool autoRefresh = true,
  }) async => _service.addSource(
      name: name,
      playlistUrl: playlistUrl,
      autoRefresh: autoRefresh,
    );

  /// 更新直播源
  Future<void> updateSource(LiveStreamSource source) async {
    await _service.updateSource(source);
  }

  /// 删除直播源
  Future<void> removeSource(String sourceId) async {
    await _service.removeSource(sourceId);
  }

  /// 切换源启用状态
  Future<void> toggleEnabled(String sourceId, {bool? enabled}) async {
    await _service.toggleEnabled(sourceId, enabled: enabled);
  }

  /// 重新排序
  Future<void> reorder(int oldIndex, int newIndex) async {
    await _service.reorder(oldIndex, newIndex);
  }

  /// 刷新源的频道列表
  Future<LiveStreamSource> refreshSource(String sourceId) async => _service.refreshSource(sourceId);

  /// 预览 M3U URL（不保存）
  Future<List<LiveChannel>> previewChannels(String url) async => _service.previewChannels(url);

  /// 搜索频道
  List<LiveChannel> searchChannels(String query) => _service.searchChannels(query);

  /// 按分类获取频道
  List<LiveChannel> getChannelsByCategory(String category) => _service.getChannelsByCategory(category);

  /// 获取指定频道
  LiveChannel? getChannel(String channelId) => _service.getChannel(channelId);
}

/// 当前选中的直播分类 Provider
final selectedLiveCategoryProvider = StateProvider<String?>((ref) => null);

/// 过滤后的频道列表 Provider
final filteredLiveChannelsProvider = Provider<List<LiveChannel>>((ref) {
  final selectedCategory = ref.watch(selectedLiveCategoryProvider);
  final allChannels = ref.watch(allLiveChannelsProvider);

  if (selectedCategory == null) {
    return allChannels;
  }

  return allChannels.where((c) => c.category == selectedCategory).toList();
});

/// 直播频道搜索 Provider
final liveChannelSearchQueryProvider = StateProvider<String>((ref) => '');

/// 搜索结果 Provider
final searchedLiveChannelsProvider = Provider<List<LiveChannel>>((ref) {
  final query = ref.watch(liveChannelSearchQueryProvider);
  final channels = ref.watch(filteredLiveChannelsProvider);

  if (query.isEmpty) {
    return channels;
  }

  final lowerQuery = query.toLowerCase();
  return channels.where((c) => c.name.toLowerCase().contains(lowerQuery) ||
        (c.category?.toLowerCase().contains(lowerQuery) ?? false)).toList();
});
