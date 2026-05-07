import 'package:flutter/material.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

/// 网格布局类型
enum GridLayoutType {
  /// 音乐列表
  music,

  /// 视频列表
  video,

  /// 相册列表
  photo,

  /// 文件列表
  file,

  /// 海报墙
  poster,

  /// 自定义
  custom,
}

/// 网格布局配置
class GridConfig {
  const GridConfig({
    required this.crossAxisCount,
    required this.mainAxisSpacing,
    required this.crossAxisSpacing,
    required this.childAspectRatio,
    this.padding = EdgeInsets.zero,
  });

  /// 列数
  final int crossAxisCount;

  /// 主轴间距
  final double mainAxisSpacing;

  /// 交叉轴间距
  final double crossAxisSpacing;

  /// 子项宽高比
  final double childAspectRatio;

  /// 内边距
  final EdgeInsets padding;

  /// 复制并修改
  GridConfig copyWith({
    int? crossAxisCount,
    double? mainAxisSpacing,
    double? crossAxisSpacing,
    double? childAspectRatio,
    EdgeInsets? padding,
  }) => GridConfig(
      crossAxisCount: crossAxisCount ?? this.crossAxisCount,
      mainAxisSpacing: mainAxisSpacing ?? this.mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing ?? this.crossAxisSpacing,
      childAspectRatio: childAspectRatio ?? this.childAspectRatio,
      padding: padding ?? this.padding,
    );
}

/// 网格布局帮助类
///
/// 提供统一的网格列数计算和布局配置
/// 根据平台和屏幕宽度自动调整
abstract final class GridHelper {
  // ============================================================================
  // 断点定义
  // ============================================================================

  /// 手机竖屏断点
  static const double compactBreakpoint = 600;

  /// 平板断点
  static const double mediumBreakpoint = 840;

  /// 小桌面断点
  static const double expandedBreakpoint = 1200;

  /// 大桌面断点
  static const double largeBreakpoint = 1600;

  // ============================================================================
  // 通用列数计算
  // ============================================================================

  /// 根据屏幕宽度和最小项宽度计算列数
  ///
  /// [width] 屏幕宽度
  /// [minItemWidth] 最小项宽度
  /// [maxColumns] 最大列数
  /// [minColumns] 最小列数
  static int calculateColumnCount({
    required double width,
    required double minItemWidth,
    int maxColumns = 8,
    int minColumns = 2,
  }) => (width / minItemWidth).floor().clamp(minColumns, maxColumns);

  /// 根据 BuildContext 计算列数
  static int getColumnCount(
    BuildContext context, {
    required double minItemWidth,
    int maxColumns = 8,
    int minColumns = 2,
  }) {
    final width = MediaQuery.of(context).size.width;
    return calculateColumnCount(
      width: width,
      minItemWidth: minItemWidth,
      maxColumns: maxColumns,
      minColumns: minColumns,
    );
  }

  // ============================================================================
  // 预设布局配置
  // ============================================================================

  /// 获取音乐列表的网格配置
  ///
  /// 移动端：2 列卡片
  /// 桌面端：4-6 列卡片或更多
  static GridConfig getMusicGridConfig(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = context.isDesktopLayout;

    if (isDesktop) {
      // 桌面端：更紧凑的布局
      final crossAxisCount = calculateColumnCount(
        width: width,
        minItemWidth: 180, // 桌面端每项最小宽度
        maxColumns: 8,
        minColumns: 4,
      );
      return GridConfig(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.75, // 桌面端更接近正方形
        padding: const EdgeInsets.all(16),
      );
    } else {
      // 移动端：保持 2 列
      return const GridConfig(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.7,
        padding: EdgeInsets.all(12),
      );
    }
  }

  /// 获取艺术家网格配置
  static GridConfig getMusicArtistGridConfig(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = context.isDesktopLayout;

    if (isDesktop) {
      final crossAxisCount = calculateColumnCount(
        width: width,
        minItemWidth: 160,
        maxColumns: 8,
        minColumns: 4,
      );
      return GridConfig(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.85, // 艺术家头像 + 名称
        padding: const EdgeInsets.all(16),
      );
    } else {
      return const GridConfig(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.9,
        padding: EdgeInsets.all(16),
      );
    }
  }

  /// 获取专辑网格配置
  static GridConfig getMusicAlbumGridConfig(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = context.isDesktopLayout;

    if (isDesktop) {
      final crossAxisCount = calculateColumnCount(
        width: width,
        minItemWidth: 180,
        maxColumns: 8,
        minColumns: 4,
      );
      return GridConfig(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.8, // 专辑封面 + 标题
        padding: const EdgeInsets.all(16),
      );
    } else {
      return const GridConfig(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
        padding: EdgeInsets.all(16),
      );
    }
  }

  /// 获取流派/年代分类网格配置
  static GridConfig getMusicCategoryGridConfig(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = context.isDesktopLayout;

    if (isDesktop) {
      final crossAxisCount = calculateColumnCount(
        width: width,
        minItemWidth: 200,
        maxColumns: 6,
        minColumns: 3,
      );
      return GridConfig(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.5, // 分类卡片更宽
        padding: const EdgeInsets.all(16),
      );
    } else {
      return const GridConfig(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.3,
        padding: EdgeInsets.all(16),
      );
    }
  }

  /// 获取视频列表的网格配置（海报竖向布局）
  static GridConfig getVideoGridConfig(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = context.isDesktopLayout;

    if (isDesktop) {
      final crossAxisCount = calculateColumnCount(
        width: width,
        minItemWidth: 240,
        maxColumns: 6,
        minColumns: 3,
      );
      return GridConfig(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.52, // 视频封面比例
        padding: const EdgeInsets.all(16),
      );
    } else {
      // 移动端响应式
      int crossAxisCount;
      if (width > 600) {
        crossAxisCount = 3;
      } else {
        crossAxisCount = 2;
      }
      return GridConfig(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.48,
        padding: const EdgeInsets.all(10),
      );
    }
  }

  /// 获取视频缩略图网格配置（横向 16:9 布局）
  static GridConfig getVideoThumbnailGridConfig(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = context.isDesktopLayout;

    if (isDesktop) {
      final crossAxisCount = calculateColumnCount(
        width: width,
        minItemWidth: 280,
        maxColumns: 5,
        minColumns: 3,
      );
      return GridConfig(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 1.4, // 16:9 + 标题区域
        padding: const EdgeInsets.all(16),
      );
    } else {
      int crossAxisCount;
      if (width > 600) {
        crossAxisCount = 3;
      } else {
        crossAxisCount = 2;
      }
      return GridConfig(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 1.4,
        padding: const EdgeInsets.all(16),
      );
    }
  }

  /// 获取相册列表的网格配置
  static GridConfig getPhotoGridConfig(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = context.isDesktopLayout;

    if (isDesktop) {
      final crossAxisCount = calculateColumnCount(
        width: width,
        minItemWidth: 150,
        maxColumns: 10,
        minColumns: 4,
      );
      return GridConfig(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1.0, // 正方形缩略图
        padding: const EdgeInsets.all(8),
      );
    } else {
      return const GridConfig(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1.0,
        padding: EdgeInsets.all(4),
      );
    }
  }

  /// 获取文件列表的网格配置
  static GridConfig getFileGridConfig(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = context.isDesktopLayout;

    if (isDesktop) {
      final crossAxisCount = calculateColumnCount(
        width: width,
        minItemWidth: 120,
        maxColumns: 10,
        minColumns: 4,
      );
      return GridConfig(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
        padding: const EdgeInsets.all(16),
      );
    } else {
      return const GridConfig(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.85,
        padding: EdgeInsets.all(8),
      );
    }
  }

  /// 获取海报墙的网格配置
  static GridConfig getPosterGridConfig(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = context.isDesktopLayout;

    if (isDesktop) {
      final crossAxisCount = calculateColumnCount(
        width: width,
        minItemWidth: 160,
        maxColumns: 8,
        minColumns: 4,
      );
      return GridConfig(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.67, // 电影海报比例 2:3
        padding: const EdgeInsets.all(16),
      );
    } else {
      int crossAxisCount;
      if (width > 600) {
        crossAxisCount = 4;
      } else if (width > 400) {
        crossAxisCount = 3;
      } else {
        crossAxisCount = 2;
      }
      return GridConfig(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.67,
        padding: const EdgeInsets.all(10),
      );
    }
  }

  /// 根据布局类型获取网格配置
  static GridConfig getGridConfig(
    BuildContext context, {
    required GridLayoutType type,
    double? customMinItemWidth,
    int? customMaxColumns,
    int? customMinColumns,
    double? customAspectRatio,
  }) {
    switch (type) {
      case GridLayoutType.music:
        return getMusicGridConfig(context);
      case GridLayoutType.video:
        return getVideoGridConfig(context);
      case GridLayoutType.photo:
        return getPhotoGridConfig(context);
      case GridLayoutType.file:
        return getFileGridConfig(context);
      case GridLayoutType.poster:
        return getPosterGridConfig(context);
      case GridLayoutType.custom:
        final width = MediaQuery.of(context).size.width;
        final crossAxisCount = calculateColumnCount(
          width: width,
          minItemWidth: customMinItemWidth ?? 200,
          maxColumns: customMaxColumns ?? 6,
          minColumns: customMinColumns ?? 2,
        );
        final isDesktop = context.isDesktopLayout;
        final spacing = isDesktop ? 16.0 : 10.0;
        return GridConfig(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          childAspectRatio: customAspectRatio ?? 1.0,
          padding: EdgeInsets.all(spacing),
        );
    }
  }

  // ============================================================================
  // 间距计算
  // ============================================================================

  /// 获取平台适配的网格间距
  static double getGridSpacing(BuildContext context) {
    final isDesktop = context.isDesktopLayout;
    return isDesktop ? 16.0 : 10.0;
  }

  /// 获取平台适配的列表项间距
  static double getListItemSpacing(BuildContext context) {
    final isDesktop = context.isDesktopLayout;
    return isDesktop ? 8.0 : 4.0;
  }

  /// 获取平台适配的页面内边距
  static EdgeInsets getPagePadding(BuildContext context) {
    final isDesktop = context.isDesktopLayout;
    return isDesktop
        ? const EdgeInsets.all(16)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
  }

  // ============================================================================
  // 列表项尺寸
  // ============================================================================

  /// 获取列表项高度
  ///
  /// 移动端：72dp（触摸友好）
  /// 桌面端：48dp（紧凑）
  static double getListItemHeight(BuildContext context) {
    final isDesktop = context.isDesktopLayout;
    return isDesktop ? 48.0 : 72.0;
  }

  /// 获取紧凑列表项高度
  static double getCompactListItemHeight(BuildContext context) {
    final isDesktop = context.isDesktopLayout;
    return isDesktop ? 40.0 : 56.0;
  }

  /// 获取图标尺寸
  static double getIconSize(BuildContext context) {
    final isDesktop = context.isDesktopLayout;
    return isDesktop ? 20.0 : 24.0;
  }

  /// 获取触摸目标尺寸
  ///
  /// 移动端：48dp（Material Design 规范）
  /// 桌面端：32dp（鼠标点击精度更高）
  static double getTouchTargetSize(BuildContext context) {
    final isDesktop = context.isDesktopLayout;
    return isDesktop ? 32.0 : 48.0;
  }

  // ============================================================================
  // 计算单项尺寸
  // ============================================================================

  /// 根据网格配置计算单个项目的尺寸
  static Size calculateItemSize(
    BuildContext context,
    GridConfig config,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = screenWidth -
        config.padding.horizontal -
        (config.crossAxisCount - 1) * config.crossAxisSpacing;
    final itemWidth = availableWidth / config.crossAxisCount;
    final itemHeight = itemWidth / config.childAspectRatio;
    return Size(itemWidth, itemHeight);
  }
}

/// GridView 扩展方法
extension GridViewExtensions on GridView {
  /// 从 GridConfig 创建 GridView
  static Widget fromConfig({
    required GridConfig config,
    required IndexedWidgetBuilder itemBuilder,
    required int itemCount,
    ScrollController? controller,
    bool shrinkWrap = false,
    ScrollPhysics? physics,
  }) => GridView.builder(
      controller: controller,
      shrinkWrap: shrinkWrap,
      physics: physics,
      padding: config.padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: config.crossAxisCount,
        mainAxisSpacing: config.mainAxisSpacing,
        crossAxisSpacing: config.crossAxisSpacing,
        childAspectRatio: config.childAspectRatio,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
}

/// SliverGrid 扩展方法
extension SliverGridExtensions on SliverGrid {
  /// 从 GridConfig 创建 SliverGridDelegate
  static SliverGridDelegateWithFixedCrossAxisCount delegateFromConfig(
    GridConfig config,
  ) => SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: config.crossAxisCount,
      mainAxisSpacing: config.mainAxisSpacing,
      crossAxisSpacing: config.crossAxisSpacing,
      childAspectRatio: config.childAspectRatio,
    );
}
