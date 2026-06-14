import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/pt_sites/data/services/pt_site_api.dart';
import 'package:my_nas/features/pt_sites/domain/entities/pt_torrent.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';

/// 影视详情「在 PT 搜索」携带过来的待搜索关键词。
/// PT 桌面页首帧消费后置空，避免重复触发。
final ptPendingSearchProvider = StateProvider<String?>((ref) => null);

/// PT 站点连接状态
enum PTSiteConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// PT 站点连接信息
class PTSiteConnection {
  const PTSiteConnection({
    required this.source,
    this.api,
    this.status = PTSiteConnectionStatus.disconnected,
    this.userInfo,
    this.errorMessage,
  });

  final SourceEntity source;
  final PTSiteApi? api;
  final PTSiteConnectionStatus status;
  final PTUserInfo? userInfo;
  final String? errorMessage;

  PTSiteConnection copyWith({
    SourceEntity? source,
    PTSiteApi? api,
    PTSiteConnectionStatus? status,
    PTUserInfo? userInfo,
    String? errorMessage,
  }) =>
      PTSiteConnection(
        source: source ?? this.source,
        api: api ?? this.api,
        status: status ?? this.status,
        userInfo: userInfo ?? this.userInfo,
        errorMessage: errorMessage,
      );
}

/// PT 站点连接 Provider
final ptSiteConnectionProvider = StateNotifierProvider.family<
    PTSiteConnectionNotifier, PTSiteConnection, String>(
  PTSiteConnectionNotifier.new,
);

class PTSiteConnectionNotifier extends StateNotifier<PTSiteConnection> {
  PTSiteConnectionNotifier(Ref _, String sourceId)
      : super(PTSiteConnection(
          source: SourceEntity(
            id: sourceId,
            name: '',
            type: SourceType.ptSite,
            host: '',
            port: 443,
            username: '',
          ),
        ));

  Future<void> connect(SourceEntity source) async {
    state = state.copyWith(
      source: source,
      status: PTSiteConnectionStatus.connecting,
    );

    try {
      final api = PTSiteApiFactory.create(source);
      final connected = await api.testConnection();

      if (!connected) {
        state = state.copyWith(
          status: PTSiteConnectionStatus.error,
          errorMessage: '连接失败，请检查认证信息',
        );
        return;
      }

      // 获取用户信息
      PTUserInfo? userInfo;
      try {
        userInfo = await api.getUserInfo();
      } on Exception {
        // 获取用户信息失败不影响连接状态
      }

      state = state.copyWith(
        api: api,
        status: PTSiteConnectionStatus.connected,
        userInfo: userInfo,
      );
    } on Exception catch (e) {
      state = state.copyWith(
        status: PTSiteConnectionStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  void disconnect() {
    state.api?.dispose();
    state = state.copyWith(
      api: null,
      status: PTSiteConnectionStatus.disconnected,
      userInfo: null,
    );
  }
}

/// 种子列表状态
class PTTorrentListState {
  const PTTorrentListState({
    this.torrents = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.currentPage = 1,
    this.hasMore = true,
    this.keyword,
    this.category,
    this.sortBy = PTTorrentSortBy.uploadTime,
    this.descending = true,
  });

  final List<PTTorrent> torrents;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final int currentPage;
  final bool hasMore;
  final String? keyword;
  final String? category;
  final PTTorrentSortBy sortBy;
  final bool descending;

  PTTorrentListState copyWith({
    List<PTTorrent>? torrents,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    int? currentPage,
    bool? hasMore,
    String? keyword,
    String? category,
    PTTorrentSortBy? sortBy,
    bool? descending,
  }) =>
      PTTorrentListState(
        torrents: torrents ?? this.torrents,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        error: error,
        currentPage: currentPage ?? this.currentPage,
        hasMore: hasMore ?? this.hasMore,
        keyword: keyword ?? this.keyword,
        category: category ?? this.category,
        sortBy: sortBy ?? this.sortBy,
        descending: descending ?? this.descending,
      );
}

/// 种子列表 Provider
final ptTorrentListProvider = StateNotifierProvider.family<
    PTTorrentListNotifier, PTTorrentListState, String>(
  PTTorrentListNotifier.new,
);

class PTTorrentListNotifier extends StateNotifier<PTTorrentListState> {
  PTTorrentListNotifier(this._ref, this._sourceId)
      : super(const PTTorrentListState());

  final Ref _ref;
  final String _sourceId;

  PTSiteApi? get _api =>
      _ref.read(ptSiteConnectionProvider(_sourceId)).api;

  Future<void> loadTorrents({bool refresh = false}) async {
    final api = _api;
    if (api == null) return;

    if (refresh) {
      state = state.copyWith(
        isLoading: true,
        currentPage: 1,
        torrents: [],
      );
    } else {
      state = state.copyWith(isLoading: true);
    }

    try {
      final torrents = await api.getTorrents(
        page: 1,
        keyword: state.keyword,
        category: state.category,
        sortBy: state.sortBy,
        descending: state.descending,
      );

      state = state.copyWith(
        torrents: torrents,
        isLoading: false,
        currentPage: 1,
        hasMore: torrents.length >= 50,
      );
    } on Exception catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadMore() async {
    final api = _api;
    if (api == null || state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final nextPage = state.currentPage + 1;
      final torrents = await api.getTorrents(
        page: nextPage,
        keyword: state.keyword,
        category: state.category,
        sortBy: state.sortBy,
        descending: state.descending,
      );

      state = state.copyWith(
        torrents: [...state.torrents, ...torrents],
        isLoadingMore: false,
        currentPage: nextPage,
        hasMore: torrents.length >= 50,
      );
    } on Exception catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        error: e.toString(),
      );
    }
  }

  void setKeyword(String? keyword) {
    state = state.copyWith(keyword: keyword, torrents: [], currentPage: 1);
  }

  void setCategory(String? category) {
    state = state.copyWith(category: category, torrents: [], currentPage: 1);
  }

  void setSortBy(PTTorrentSortBy sortBy, {bool? descending}) {
    state = state.copyWith(
      sortBy: sortBy,
      descending: descending ?? state.descending,
      torrents: [],
      currentPage: 1,
    );
  }

  void toggleSortDirection() {
    state = state.copyWith(
      descending: !state.descending,
      torrents: [],
      currentPage: 1,
    );
  }
}

/// 分类列表 Provider
final ptCategoriesProvider = FutureProvider.family<List<PTCategory>, String>(
  (ref, sourceId) async {
    final connection = ref.watch(ptSiteConnectionProvider(sourceId));
    if (connection.api == null) return [];
    return connection.api!.getCategories();
  },
);
