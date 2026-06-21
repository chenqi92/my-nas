import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 首页区块类型
enum HomeSection {
  heroPlayer, // 开始探索你的音乐
  quickAccess, // 快捷访问
  recommended, // 为你推荐
  playlists, // 歌单
  recentPlays, // 最近播放
  browseLibrary, // 浏览音乐库
}

/// 首页区块配置
class HomeSectionConfig {
  const HomeSectionConfig({
    required this.section,
    this.visible = true,
  });

  factory HomeSectionConfig.fromMap(Map<dynamic, dynamic> map) => HomeSectionConfig(
        section: HomeSection.values[map['section'] as int? ?? 0],
        visible: map['visible'] as bool? ?? true,
      );

  final HomeSection section;
  final bool visible;

  HomeSectionConfig copyWith({
    HomeSection? section,
    bool? visible,
  }) =>
      HomeSectionConfig(
        section: section ?? this.section,
        visible: visible ?? this.visible,
      );

  Map<String, dynamic> toMap() => {
        'section': section.index,
        'visible': visible,
      };
}

/// 首页布局配置状态
class HomeLayoutState {
  const HomeLayoutState({
    required this.sections,
  });

  /// 默认布局顺序
  factory HomeLayoutState.defaultLayout() => const HomeLayoutState(
        sections: [
          HomeSectionConfig(section: HomeSection.heroPlayer),
          HomeSectionConfig(section: HomeSection.quickAccess),
          HomeSectionConfig(section: HomeSection.recommended),
          HomeSectionConfig(section: HomeSection.playlists),
          HomeSectionConfig(section: HomeSection.recentPlays),
          HomeSectionConfig(section: HomeSection.browseLibrary),
        ],
      );

  factory HomeLayoutState.fromMap(Map<dynamic, dynamic> map) {
    final sectionsData = map['sections'] as List<dynamic>?;
    if (sectionsData == null || sectionsData.isEmpty) {
      return HomeLayoutState.defaultLayout();
    }

    final sections = sectionsData
        .map((e) => HomeSectionConfig.fromMap(e as Map<dynamic, dynamic>))
        .toList();

    // 确保所有区块都存在
    final existingSections = sections.map((s) => s.section).toSet();
    for (final section in HomeSection.values) {
      if (!existingSections.contains(section)) {
        sections.add(HomeSectionConfig(section: section));
      }
    }

    return HomeLayoutState(sections: sections);
  }

  final List<HomeSectionConfig> sections;

  HomeLayoutState copyWith({
    List<HomeSectionConfig>? sections,
  }) =>
      HomeLayoutState(
        sections: sections ?? this.sections,
      );

  Map<String, dynamic> toMap() => {
        'sections': sections.map((s) => s.toMap()).toList(),
      };
}

/// 首页布局管理
class HomeLayoutNotifier extends StateNotifier<HomeLayoutState> {
  HomeLayoutNotifier() : super(HomeLayoutState.defaultLayout()) {
    _load();
  }

  static const _boxName = 'music_home_layout';
  static const _layoutKey = 'layout';

  Box<Map<dynamic, dynamic>>? _box;
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;

    try {
      _box = await Hive.openBox<Map<dynamic, dynamic>>(_boxName);
      _initialized = true;
    } on Exception catch (e) {
      logger.e('HomeLayoutNotifier: 初始化失败', e);
    }
  }

  Future<void> _load() async {
    await _init();
    if (_box == null) return;

    final data = _box!.get(_layoutKey);
    if (data != null) {
      state = HomeLayoutState.fromMap(data);
      logger.i('HomeLayoutNotifier: 加载布局配置成功');
    }
  }

  Future<void> _save() async {
    await _init();
    if (_box == null) return;

    await _box!.put(_layoutKey, state.toMap());
  }

  /// 重新排序区块
  Future<void> reorderSections(int oldIndex, int newIndex) async {
    final sections = List<HomeSectionConfig>.from(state.sections);
    final item = sections.removeAt(oldIndex);
    sections.insert(newIndex < oldIndex ? newIndex : newIndex, item);
    state = state.copyWith(sections: sections);
    await _save();
  }

  /// 切换区块可见性
  Future<void> toggleSectionVisibility(HomeSection section) async {
    final sections = state.sections.map((s) {
      if (s.section == section) {
        return s.copyWith(visible: !s.visible);
      }
      return s;
    }).toList();
    state = state.copyWith(sections: sections);
    await _save();
  }

  /// 重置为默认布局
  Future<void> reset() async {
    state = HomeLayoutState.defaultLayout();
    await _save();
  }
}

/// 首页布局 provider
final homeLayoutProvider =
    StateNotifierProvider<HomeLayoutNotifier, HomeLayoutState>(
  (_) => HomeLayoutNotifier(),
);

/// 获取区块显示名称
String getHomeSectionName(HomeSection section) => switch (section) {
      HomeSection.heroPlayer => appL10n.musicHomeSectionHeroPlayer,
      HomeSection.quickAccess => appL10n.musicHomeSectionQuickAccess,
      HomeSection.recommended => appL10n.musicHomeSectionRecommended,
      HomeSection.playlists => appL10n.musicHomeSectionPlaylists,
      HomeSection.recentPlays => appL10n.musicHomeSectionRecentPlays,
      HomeSection.browseLibrary => appL10n.musicHomeSectionBrowseLibrary,
    };

/// 获取区块图标
IconData getHomeSectionIcon(HomeSection section) => switch (section) {
      HomeSection.heroPlayer => Icons.play_circle_rounded,
      HomeSection.quickAccess => Icons.flash_on_rounded,
      HomeSection.recommended => Icons.recommend_rounded,
      HomeSection.playlists => Icons.playlist_play_rounded,
      HomeSection.recentPlays => Icons.history_rounded,
      HomeSection.browseLibrary => Icons.library_music_rounded,
    };
