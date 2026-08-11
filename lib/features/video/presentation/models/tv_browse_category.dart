import 'package:my_nas/l10n/app_localizations.dart';

/// TV 浏览页的分类枚举（影视库网格入口）。
///
/// 对应 [VideoListLoaded] 的五个数据源：电影 / 剧集 / 其他 / 最近 / 全部。
enum TvBrowseCategory {
  movies,
  tvShows,
  others,
  recent,
  all,
}

/// 分类标题。复用影视页 tab 的既有文案，避免同一个词两套翻译。
String tvBrowseCategoryLabel(AppLocalizations l, TvBrowseCategory category) =>
    switch (category) {
      TvBrowseCategory.movies => l.videoPageTabMovies,
      TvBrowseCategory.tvShows => l.videoPageTabTvShows,
      TvBrowseCategory.others => l.videoPageTabOther,
      TvBrowseCategory.recent => l.videoPageTabRecent,
      TvBrowseCategory.all => l.videoPageTabAll,
    };
