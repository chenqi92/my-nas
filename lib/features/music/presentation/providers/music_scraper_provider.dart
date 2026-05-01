import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/music/data/services/music_scraper_manager_service.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';

/// 音乐刮削管理服务 Provider
final musicScraperManagerProvider = Provider<MusicScraperManagerService>((ref) {
  final service = MusicScraperManagerService();
  ref.onDispose(service.dispose);
  return service;
});

/// 音乐刮削源列表状态
class MusicScraperSourcesState {
  const MusicScraperSourcesState({
    this.sources = const [],
    this.isLoading = false,
    this.error,
  });

  final List<MusicScraperSourceEntity> sources;
  final bool isLoading;
  final String? error;

  /// 拷贝并更新字段。
  ///
  /// 注意：error 默认遵循"未传则保留原值"，与其它字段一致。
  /// 若需要清空 error（例如开始一次新加载），传 [clearError]: true。
  MusicScraperSourcesState copyWith({
    List<MusicScraperSourceEntity>? sources,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) =>
      MusicScraperSourcesState(
        sources: sources ?? this.sources,
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// 音乐刮削源列表 Notifier
class MusicScraperSourcesNotifier extends StateNotifier<MusicScraperSourcesState> {
  MusicScraperSourcesNotifier(this._manager) : super(const MusicScraperSourcesState()) {
    load();
  }

  final MusicScraperManagerService _manager;

  /// 加载刮削源列表
  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _manager.init();
      final sources = await _manager.getSources();
      state = state.copyWith(sources: sources, isLoading: false, clearError: true);
    } on Exception catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 添加刮削源
  Future<void> addSource(MusicScraperSourceEntity source) async {
    try {
      await _manager.addSource(source);
      await load();
    } on Exception catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// 更新刮削源
  Future<void> updateSource(MusicScraperSourceEntity source) async {
    try {
      await _manager.updateSource(source);
      await load();
    } on Exception catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// 删除刮削源
  Future<void> removeSource(String id) async {
    try {
      await _manager.removeSource(id);
      await load();
    } on Exception catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// 切换启用状态
  Future<void> toggleSource(String id, {required bool isEnabled}) async {
    try {
      await _manager.toggleSource(id, isEnabled: isEnabled);
      await load();
    } on Exception catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  /// 调整顺序
  /// [oldIndex] 和 [newIndex] 都是已调整后的索引（不需要再次调整）
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;

    final sources = List<MusicScraperSourceEntity>.from(state.sources);
    final item = sources.removeAt(oldIndex);
    sources.insert(newIndex, item);

    // 更新本地状态
    state = state.copyWith(sources: sources);

    // 保存到存储
    try {
      await _manager.reorderSources(sources.map((s) => s.id).toList());
    } on Exception catch (e) {
      // 恢复原状态
      await load();
      state = state.copyWith(error: e.toString());
    }
  }
}

/// 音乐刮削源列表 Provider
final musicScraperSourcesProvider =
    StateNotifierProvider<MusicScraperSourcesNotifier, MusicScraperSourcesState>(
  (ref) => MusicScraperSourcesNotifier(ref.watch(musicScraperManagerProvider)),
);

/// 已启用的刮削源数量
final enabledMusicScraperCountProvider = Provider<int>((ref) {
  final state = ref.watch(musicScraperSourcesProvider);
  return state.sources.where((s) => s.isEnabled).length;
});

/// 总刮削源类型数量（所有可用的刮削器类型）
final totalMusicScraperCountProvider = Provider<int>((ref) => MusicScraperType.values.length);

/// 音乐搜索参数
class MusicSearchParams {
  const MusicSearchParams({
    required this.query,
    this.artist,
    this.album,
    this.limit = 20,
  });

  final String query;
  final String? artist;
  final String? album;
  final int limit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicSearchParams &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          artist == other.artist &&
          album == other.album &&
          limit == other.limit;

  @override
  int get hashCode => Object.hash(query, artist, album, limit);
}

/// 音乐搜索 Provider
final musicSearchProvider = FutureProvider.autoDispose
    .family<List<MusicScraperSearchResult>, MusicSearchParams>(
  (ref, params) async {
    final manager = ref.watch(musicScraperManagerProvider);
    await manager.init();
    return manager.search(
      params.query,
      artist: params.artist,
      album: params.album,
      limit: params.limit,
    );
  },
);

/// 综合刮削参数
class MusicScrapeParams {
  const MusicScrapeParams({
    required this.title,
    this.artist,
    this.album,
    this.getCover = true,
    this.getLyrics = true,
  });

  final String title;
  final String? artist;
  final String? album;
  final bool getCover;
  final bool getLyrics;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicScrapeParams &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          artist == other.artist &&
          album == other.album &&
          getCover == other.getCover &&
          getLyrics == other.getLyrics;

  @override
  int get hashCode => Object.hash(title, artist, album, getCover, getLyrics);
}

/// 综合刮削 Provider
final musicScrapeProvider = FutureProvider.autoDispose
    .family<MusicScrapeResult, MusicScrapeParams>(
  (ref, params) async {
    final manager = ref.watch(musicScraperManagerProvider);
    await manager.init();
    return manager.scrape(
      title: params.title,
      artist: params.artist,
      album: params.album,
      getCover: params.getCover,
      getLyrics: params.getLyrics,
    );
  },
);
