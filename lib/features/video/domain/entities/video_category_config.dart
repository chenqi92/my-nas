import 'package:my_nas/core/i18n/app_l10n.dart';
/// 视频首页分类类型
///
/// 定义所有可以在视频首页显示的分类区块
/// 用户可以调整这些分类的显示顺序和可见性
enum VideoHomeCategory {
  /// 顶部轮播推荐（Hero Banner）
  heroBanner,

  /// 继续观看
  continueWatching,

  /// 最近添加
  recentlyAdded,

  /// 电影
  movies,

  /// 剧集
  tvShows,

  /// 电影系列/合集
  movieCollections,

  /// 每日推荐（基于日期的随机推荐）
  topRated,

  /// 未观看
  unwatched,

  /// 其他（未识别的视频）
  others,

  /// 按电影类型分类（动态生成）
  byMovieGenre,

  /// 按电影地区分类（动态生成）
  byMovieRegion,

  /// 按电视剧类型分类（动态生成）
  byTvGenre,

  /// 按电视剧地区分类（动态生成）
  byTvRegion,

  /// 浏览电影类型（卡片式分类入口）
  browseMovieGenres,

  /// 浏览电影地区（卡片式分类入口）
  browseMovieRegions,

  /// 浏览电视剧类型（卡片式分类入口）
  browseTvGenres,

  /// 浏览电视剧地区（卡片式分类入口）
  browseTvRegions,

  /// 直播
  liveStreaming,
}

/// 分类类型的扩展方法
extension VideoHomeCategoryExtension on VideoHomeCategory {
  /// 显示名称
  String get displayName {
    switch (this) {
      case VideoHomeCategory.heroBanner:
        return appL10n.videoCategoryHeroBannerDisplay;
      case VideoHomeCategory.continueWatching:
        return appL10n.videoCategoryContinueWatchingDisplay;
      case VideoHomeCategory.recentlyAdded:
        return appL10n.videoCategoryRecentlyAddedDisplay;
      case VideoHomeCategory.movies:
        return appL10n.videoCategoryMoviesDisplay;
      case VideoHomeCategory.tvShows:
        return appL10n.videoCategoryTvShowsDisplay;
      case VideoHomeCategory.movieCollections:
        return appL10n.videoCategoryMovieCollectionsDisplay;
      case VideoHomeCategory.topRated:
        return appL10n.videoCategoryTopRatedDisplay;
      case VideoHomeCategory.unwatched:
        return appL10n.videoCategoryUnwatchedDisplay;
      case VideoHomeCategory.others:
        return appL10n.videoCategoryOthersDisplay;
      case VideoHomeCategory.byMovieGenre:
        return appL10n.videoCategoryByMovieGenreDisplay;
      case VideoHomeCategory.byMovieRegion:
        return appL10n.videoCategoryByMovieRegionDisplay;
      case VideoHomeCategory.byTvGenre:
        return appL10n.videoCategoryByTvGenreDisplay;
      case VideoHomeCategory.byTvRegion:
        return appL10n.videoCategoryByTvRegionDisplay;
      case VideoHomeCategory.browseMovieGenres:
        return appL10n.videoCategoryBrowseMovieGenresDisplay;
      case VideoHomeCategory.browseMovieRegions:
        return appL10n.videoCategoryBrowseMovieRegionsDisplay;
      case VideoHomeCategory.browseTvGenres:
        return appL10n.videoCategoryBrowseTvGenresDisplay;
      case VideoHomeCategory.browseTvRegions:
        return appL10n.videoCategoryBrowseTvRegionsDisplay;
      case VideoHomeCategory.liveStreaming:
        return appL10n.videoCategoryLiveStreamingDisplay;
    }
  }

  /// 分类组名称（用于设置界面分组显示）
  String get groupName {
    switch (this) {
      case VideoHomeCategory.byMovieGenre:
      case VideoHomeCategory.byMovieRegion:
      case VideoHomeCategory.browseMovieGenres:
      case VideoHomeCategory.browseMovieRegions:
        return appL10n.videoCategoryMovieGroupName;
      case VideoHomeCategory.byTvGenre:
      case VideoHomeCategory.byTvRegion:
      case VideoHomeCategory.browseTvGenres:
      case VideoHomeCategory.browseTvRegions:
        return appL10n.videoCategoryTvGroupName;
      default:
        return appL10n.videoCategoryBasicGroupName;
    }
  }

  /// 图标
  String get iconName {
    switch (this) {
      case VideoHomeCategory.heroBanner:
        return 'auto_awesome';
      case VideoHomeCategory.continueWatching:
        return 'play_circle_filled';
      case VideoHomeCategory.recentlyAdded:
        return 'fiber_new';
      case VideoHomeCategory.movies:
        return 'movie_filter';
      case VideoHomeCategory.tvShows:
        return 'tv';
      case VideoHomeCategory.movieCollections:
        return 'video_library';
      case VideoHomeCategory.topRated:
        return 'star';
      case VideoHomeCategory.unwatched:
        return 'remove_red_eye';
      case VideoHomeCategory.others:
        return 'folder_special';
      case VideoHomeCategory.byMovieGenre:
      case VideoHomeCategory.browseMovieGenres:
        return 'theater_comedy';
      case VideoHomeCategory.byMovieRegion:
      case VideoHomeCategory.browseMovieRegions:
        return 'language';
      case VideoHomeCategory.byTvGenre:
      case VideoHomeCategory.browseTvGenres:
        return 'theaters';
      case VideoHomeCategory.byTvRegion:
      case VideoHomeCategory.browseTvRegions:
        return 'flag';
      case VideoHomeCategory.liveStreaming:
        return 'live_tv';
    }
  }

  /// 是否为动态分类（需要额外配置筛选条件）
  bool get isDynamic => this == VideoHomeCategory.byMovieGenre ||
      this == VideoHomeCategory.byMovieRegion ||
      this == VideoHomeCategory.byTvGenre ||
      this == VideoHomeCategory.byTvRegion;

  /// 是否为浏览分类（卡片式分类入口）
  bool get isBrowseCategory =>
      this == VideoHomeCategory.browseMovieGenres ||
      this == VideoHomeCategory.browseMovieRegions ||
      this == VideoHomeCategory.browseTvGenres ||
      this == VideoHomeCategory.browseTvRegions;

  /// 是否为类型分类
  bool get isGenreCategory =>
      this == VideoHomeCategory.byMovieGenre ||
      this == VideoHomeCategory.byTvGenre ||
      this == VideoHomeCategory.browseMovieGenres ||
      this == VideoHomeCategory.browseTvGenres;

  /// 是否为地区分类
  bool get isRegionCategory =>
      this == VideoHomeCategory.byMovieRegion ||
      this == VideoHomeCategory.byTvRegion ||
      this == VideoHomeCategory.browseMovieRegions ||
      this == VideoHomeCategory.browseTvRegions;

  /// 是否为电影相关分类
  bool get isMovieCategory =>
      this == VideoHomeCategory.byMovieGenre ||
      this == VideoHomeCategory.byMovieRegion ||
      this == VideoHomeCategory.browseMovieGenres ||
      this == VideoHomeCategory.browseMovieRegions;

  /// 是否为电视剧相关分类
  bool get isTvCategory =>
      this == VideoHomeCategory.byTvGenre ||
      this == VideoHomeCategory.byTvRegion ||
      this == VideoHomeCategory.browseTvGenres ||
      this == VideoHomeCategory.browseTvRegions;

  /// 获取对应的动态分类类型（用于浏览分类 -> 动态分类转换）
  VideoHomeCategory? get correspondingDynamicCategory {
    switch (this) {
      case VideoHomeCategory.browseMovieGenres:
        return VideoHomeCategory.byMovieGenre;
      case VideoHomeCategory.browseMovieRegions:
        return VideoHomeCategory.byMovieRegion;
      case VideoHomeCategory.browseTvGenres:
        return VideoHomeCategory.byTvGenre;
      case VideoHomeCategory.browseTvRegions:
        return VideoHomeCategory.byTvRegion;
      default:
        return null;
    }
  }
}

/// 单个分类区块的配置
class VideoCategorySectionConfig {
  VideoCategorySectionConfig({
    required this.category,
    required this.order,
    this.visible = true,
    this.filter,
  });

  /// 从 Map 创建
  factory VideoCategorySectionConfig.fromMap(Map<String, dynamic> map) {
    // 兼容旧版数据
    final categoryIndex = map['category'] as int;
    var category = VideoHomeCategory.values[categoryIndex];

    // 处理旧版 byGenre -> 新版 byMovieGenre 的迁移
    // 旧版 byGenre 的 index 是 9，新版已被 byMovieGenre 取代
    if (categoryIndex >= VideoHomeCategory.values.length) {
      category = VideoHomeCategory.byMovieGenre;
    }

    return VideoCategorySectionConfig(
      category: category,
      order: map['order'] as int,
      visible: map['visible'] as bool? ?? true,
      // 兼容旧版 genreFilter 字段
      filter: map['filter'] as String? ?? map['genreFilter'] as String?,
    );
  }

  /// 分类类型
  final VideoHomeCategory category;

  /// 排序顺序（数字越小越靠前）
  final int order;

  /// 是否可见
  final bool visible;

  /// 筛选条件（用于动态分类）
  /// - 对于类型分类：例如 '动作', '科幻', '喜剧'
  /// - 对于地区分类：例如 '美国', '中国', '日本'
  final String? filter;

  /// 获取显示名称（考虑筛选条件）
  String get displayName {
    if (category.isDynamic && filter != null) {
      return filter!;
    }
    return category.displayName;
  }

  /// 获取副标题（分类类型描述）
  String get subtitle {
    switch (category) {
      case VideoHomeCategory.byMovieGenre:
        return appL10n.videoCategoryByMovieGenreDisplay;
      case VideoHomeCategory.byMovieRegion:
        return appL10n.videoCategoryByMovieRegionDisplay;
      case VideoHomeCategory.byTvGenre:
        return appL10n.videoCategoryByTvGenreDisplay;
      case VideoHomeCategory.byTvRegion:
        return appL10n.videoCategoryByTvRegionDisplay;
      default:
        return '';
    }
  }

  /// 生成唯一标识（用于 Map key）
  String get uniqueKey {
    if (category.isDynamic && filter != null) {
      return '${category.name}_$filter';
    }
    return category.name;
  }

  /// 转为 Map
  Map<String, dynamic> toMap() => {
        'category': category.index,
        'order': order,
        'visible': visible,
        'filter': filter,
      };

  /// 复制并修改
  VideoCategorySectionConfig copyWith({
    VideoHomeCategory? category,
    int? order,
    bool? visible,
    String? filter,
  }) =>
      VideoCategorySectionConfig(
        category: category ?? this.category,
        order: order ?? this.order,
        visible: visible ?? this.visible,
        filter: filter ?? this.filter,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VideoCategorySectionConfig &&
          runtimeType == other.runtimeType &&
          uniqueKey == other.uniqueKey;

  @override
  int get hashCode => uniqueKey.hashCode;
}

/// 完整的分类设置
class VideoCategorySettings {
  VideoCategorySettings({
    required this.sections,
  });

  /// 从 Map 创建
  /// 
  /// 自动迁移：如果用户保存的配置缺少新添加的分类，会自动补充
  factory VideoCategorySettings.fromMap(Map<String, dynamic> map) {
    final sectionsData = map['sections'] as List<dynamic>? ?? [];
    final sections = sectionsData
        .map((s) => VideoCategorySectionConfig.fromMap(s as Map<String, dynamic>))
        .toList();
    
    // 迁移逻辑：检查是否缺少默认分类中的基础分类（非动态分类）
    final defaults = VideoCategorySettings.defaults();
    final existingCategories = sections
        .where((s) => !s.category.isDynamic)
        .map((s) => s.category)
        .toSet();
    
    // 获取当前最大 order
    var maxOrder = sections.isEmpty 
        ? 0 
        : sections.map((s) => s.order).reduce((a, b) => a > b ? a : b);
    
    // 添加缺失的基础分类
    for (final defaultSection in defaults.sections) {
      if (!defaultSection.category.isDynamic && 
          !existingCategories.contains(defaultSection.category)) {
        maxOrder++;
        sections.add(VideoCategorySectionConfig(
          category: defaultSection.category,
          order: maxOrder,
          visible: defaultSection.visible,
        ));
      }
    }
    
    return VideoCategorySettings(sections: sections);
  }

  /// 默认配置
  factory VideoCategorySettings.defaults() => VideoCategorySettings(
        sections: [
          VideoCategorySectionConfig(
            category: VideoHomeCategory.heroBanner,
            order: 0,
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.continueWatching,
            order: 1,
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.recentlyAdded,
            order: 2,
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.movies,
            order: 3,
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.tvShows,
            order: 4,
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.movieCollections,
            order: 5,
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.topRated,
            order: 6,
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.unwatched,
            order: 7,
            visible: false, // 默认不显示
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.others,
            order: 8,
            visible: false, // 默认不显示
          ),
          // 四个分类浏览入口（默认不显示，需要用户选择筛选条件后开启）
          VideoCategorySectionConfig(
            category: VideoHomeCategory.browseMovieGenres,
            order: 9,
            visible: false,
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.browseMovieRegions,
            order: 10,
            visible: false,
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.browseTvGenres,
            order: 11,
            visible: false,
          ),
          VideoCategorySectionConfig(
            category: VideoHomeCategory.browseTvRegions,
            order: 12,
            visible: false,
          ),
          // 直播区块（默认显示，如果有配置直播源）
          VideoCategorySectionConfig(
            category: VideoHomeCategory.liveStreaming,
            order: 13,
          ),
        ],
      );

  /// 所有分类配置
  final List<VideoCategorySectionConfig> sections;

  /// 获取可见的分类（已排序）
  List<VideoCategorySectionConfig> get visibleSections {
    final visible = sections.where((s) => s.visible).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
    return visible;
  }

  /// 获取当前资料库应展示的分类。
  ///
  /// 用户仍可隐藏“其他视频”；但当资料库只有未识别视频时，继续隐藏会让
  /// 首页只剩统计数字而没有任何可操作内容，因此临时补回该分类作为兜底。
  List<VideoCategorySectionConfig> visibleSectionsForLibrary({
    required int movieCount,
    required int tvShowCount,
    required int otherCount,
  }) {
    final visible = visibleSections;
    final onlyHasOtherVideos =
        movieCount == 0 && tvShowCount == 0 && otherCount > 0;
    final alreadyShowsOthers = visible.any(
      (section) => section.category == VideoHomeCategory.others,
    );
    if (!onlyHasOtherVideos || alreadyShowsOthers) {
      return visible;
    }

    VideoCategorySectionConfig? othersSection;
    for (final section in sections) {
      if (section.category == VideoHomeCategory.others) {
        othersSection = section;
        break;
      }
    }

    final resolved = <VideoCategorySectionConfig>[
      ...visible,
      (othersSection ??
              VideoCategorySectionConfig(
                category: VideoHomeCategory.others,
                order: sections.length,
              ))
          .copyWith(visible: true),
    ]..sort((a, b) => a.order.compareTo(b.order));
    return resolved;
  }

  /// 获取所有分类（已排序）
  List<VideoCategorySectionConfig> get sortedSections {
    final sorted = List<VideoCategorySectionConfig>.from(sections)
    ..sort((a, b) => a.order.compareTo(b.order));
    return sorted;
  }

  /// 获取所有动态分类
  List<VideoCategorySectionConfig> get dynamicSections =>
      sections.where((s) => s.category.isDynamic).toList();

  /// 获取电影类型分类
  List<VideoCategorySectionConfig> get movieGenreSections => sections
      .where((s) => s.category == VideoHomeCategory.byMovieGenre)
      .toList();

  /// 获取电影地区分类
  List<VideoCategorySectionConfig> get movieRegionSections => sections
      .where((s) => s.category == VideoHomeCategory.byMovieRegion)
      .toList();

  /// 获取电视剧类型分类
  List<VideoCategorySectionConfig> get tvGenreSections => sections
      .where((s) => s.category == VideoHomeCategory.byTvGenre)
      .toList();

  /// 获取电视剧地区分类
  List<VideoCategorySectionConfig> get tvRegionSections => sections
      .where((s) => s.category == VideoHomeCategory.byTvRegion)
      .toList();

  /// 获取指定类型的分类筛选值集合
  Set<String?> getFiltersForCategory(VideoHomeCategory category) =>
      sections.where((s) => s.category == category).map((s) => s.filter).toSet();

  /// 转为 Map
  Map<String, dynamic> toMap() => {
        'sections': sections.map((s) => s.toMap()).toList(),
      };

  /// 复制并修改
  VideoCategorySettings copyWith({
    List<VideoCategorySectionConfig>? sections,
  }) =>
      VideoCategorySettings(
        sections: sections ?? this.sections,
      );

  /// 更新单个分类的可见性
  VideoCategorySettings toggleVisibility(String uniqueKey) {
    final newSections = sections.map((s) {
      if (s.uniqueKey == uniqueKey) {
        return s.copyWith(visible: !s.visible);
      }
      return s;
    }).toList();
    return copyWith(sections: newSections);
  }

  /// 重新排序分类
  VideoCategorySettings reorder(int oldIndex, int newIndex) {
    final sorted = sortedSections;
    final item = sorted.removeAt(oldIndex);
    sorted.insert(newIndex, item);

    // 更新所有 order 值
    final newSections = <VideoCategorySectionConfig>[];
    for (var i = 0; i < sorted.length; i++) {
      newSections.add(sorted[i].copyWith(order: i));
    }

    return copyWith(sections: newSections);
  }

  /// 添加动态分类
  VideoCategorySettings addDynamicCategory(
    VideoHomeCategory category,
    String filter,
  ) {
    // 检查是否已存在
    if (sections.any((s) => s.category == category && s.filter == filter)) {
      return this;
    }

    final maxOrder = sections.fold<int>(
      0,
      (max, s) => s.order > max ? s.order : max,
    );

    final newSection = VideoCategorySectionConfig(
      category: category,
      order: maxOrder + 1,
      filter: filter,
    );

    return copyWith(sections: [...sections, newSection]);
  }

  /// 移除动态分类
  VideoCategorySettings removeDynamicCategory(
    VideoHomeCategory category,
    String filter,
  ) {
    final newSections = sections
        .where((s) => !(s.category == category && s.filter == filter))
        .toList();
    return copyWith(sections: newSections);
  }

  /// 批量添加动态分类
  VideoCategorySettings addDynamicCategories(
    VideoHomeCategory category,
    List<String> filters,
  ) {
    var settings = this;
    for (final filter in filters) {
      settings = settings.addDynamicCategory(category, filter);
    }
    return settings;
  }

  /// 批量移除某类型的所有动态分类
  VideoCategorySettings removeAllDynamicCategoriesOfType(
    VideoHomeCategory category,
  ) {
    final newSections =
        sections.where((s) => s.category != category).toList();
    return copyWith(sections: newSections);
  }
}
