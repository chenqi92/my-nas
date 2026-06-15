import 'package:flutter/material.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/desktop_settings_screen.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/about_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/advanced_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/appearance_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/cast_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/favorites_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/language_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/libmap_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/live_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/maint_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/music_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/reading_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/remotedl_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/scraper_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/security_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/sites_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/sources_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/sync_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/transfer_pane.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/panes/video_pane.dart';
import 'package:my_nas/l10n/app_localizations.dart';

/// 一个设置分类（对齐设计稿 `settings.jsx` 的 SET_CATS item）。
class SettingsCat {
  const SettingsCat({
    required this.id,
    required this.icon,
    required this.label,
    this.subtitle = '',
    this.planned = false,
  });

  final String id;
  final IconData icon;
  final String label;

  /// pane 顶部 SetHead 副标题（占位/默认用）。
  final String subtitle;

  /// 是否带「规划」角标。
  final bool planned;
}

/// 一个分组（对齐 SET_CATS 的 group）。
class SettingsGroup {
  const SettingsGroup({required this.title, required this.cats});
  final String title;
  final List<SettingsCat> cats;
}

/// 设计稿设置分组：通用 / 连接 / 播放与媒体 / 服务与自动化 / 数据 / 高级。
List<SettingsGroup> settingsGroups(AppLocalizations l) => [
      SettingsGroup(title: l.setShellGroupGeneral, cats: [
        SettingsCat(
          id: 'appearance',
          icon: Icons.palette_outlined,
          label: l.setShellCatAppearanceLabel,
          subtitle: l.setShellCatAppearanceSubtitle,
        ),
        SettingsCat(
          id: 'language',
          icon: Icons.language_rounded,
          label: l.setShellCatLanguageLabel,
          subtitle: l.setShellCatLanguageSubtitle,
        ),
        SettingsCat(
          id: 'security',
          icon: Icons.shield_outlined,
          label: l.setShellCatSecurityLabel,
          subtitle: l.setShellCatSecuritySubtitle,
        ),
      ]),
      SettingsGroup(title: l.setShellGroupConnection, cats: [
        SettingsCat(
          id: 'sources',
          icon: Icons.dns_rounded,
          label: l.setShellCatSourcesLabel,
          subtitle: l.setShellCatSourcesSubtitle,
        ),
        SettingsCat(
          id: 'libmap',
          icon: Icons.folder_outlined,
          label: l.setShellCatLibmapLabel,
          subtitle: l.setShellCatLibmapSubtitle,
        ),
      ]),
      SettingsGroup(title: l.setShellGroupPlayback, cats: [
        SettingsCat(
          id: 'video',
          icon: Icons.movie_outlined,
          label: l.setShellCatVideoLabel,
          subtitle: l.setShellCatVideoSubtitle,
        ),
        SettingsCat(
          id: 'music',
          icon: Icons.library_music_outlined,
          label: l.setShellCatMusicLabel,
          subtitle: l.setShellCatMusicSubtitle,
        ),
        SettingsCat(
          id: 'reading',
          icon: Icons.menu_book_outlined,
          label: l.setShellCatReadingLabel,
          subtitle: l.setShellCatReadingSubtitle,
        ),
        SettingsCat(
          id: 'cast',
          icon: Icons.cast_rounded,
          label: l.setShellCatCastLabel,
          subtitle: l.setShellCatCastSubtitle,
        ),
      ]),
      SettingsGroup(title: l.setShellGroupServices, cats: [
        SettingsCat(
          id: 'sites',
          icon: Icons.flag_circle_outlined,
          label: l.setShellCatSitesLabel,
          subtitle: l.setShellCatSitesSubtitle,
        ),
        SettingsCat(
          id: 'live',
          icon: Icons.live_tv_outlined,
          label: l.setShellCatLiveLabel,
          subtitle: l.setShellCatLiveSubtitle,
        ),
        SettingsCat(
          id: 'scraper',
          icon: Icons.auto_awesome_outlined,
          label: l.setShellCatScraperLabel,
          subtitle: l.setShellCatScraperSubtitle,
        ),
        SettingsCat(
          id: 'remotedl',
          icon: Icons.download_rounded,
          label: l.setShellCatRemotedlLabel,
          subtitle: l.setShellCatRemotedlSubtitle,
        ),
      ]),
      SettingsGroup(title: l.setShellGroupData, cats: [
        SettingsCat(
          id: 'sync',
          icon: Icons.sync_rounded,
          label: l.setShellCatSyncLabel,
          subtitle: l.setShellCatSyncSubtitle,
        ),
        SettingsCat(
          id: 'transfer',
          icon: Icons.swap_horiz_rounded,
          label: l.setShellCatTransferLabel,
          subtitle: l.setShellCatTransferSubtitle,
        ),
        SettingsCat(
          id: 'maint',
          icon: Icons.insights_outlined,
          label: l.setShellCatMaintLabel,
          subtitle: l.setShellCatMaintSubtitle,
        ),
        SettingsCat(
          id: 'favorites',
          icon: Icons.favorite_outline_rounded,
          label: l.setShellCatFavoritesLabel,
          subtitle: l.setShellCatFavoritesSubtitle,
        ),
      ]),
      SettingsGroup(title: l.setShellGroupAdvanced, cats: [
        SettingsCat(
          id: 'advanced',
          icon: Icons.terminal_rounded,
          label: l.setShellCatAdvancedLabel,
          subtitle: l.setShellCatAdvancedSubtitle,
        ),
        SettingsCat(
          id: 'about',
          icon: Icons.info_outline_rounded,
          label: l.setShellCatAboutLabel,
          subtitle: l.setShellCatAboutSubtitle,
        ),
      ]),
    ];

/// 扁平化的全部分类。
List<SettingsCat> allSettingsCats(AppLocalizations l) =>
    settingsGroups(l).expand((g) => g.cats).toList();

/// 根据分类 id 构造对应 pane。pane 逐个迁移完成后在此处路由到真实实现；
/// 未迁移的回退为 [StubPane]。
Widget buildSettingsPane(String id, AppLocalizations l) {
  switch (id) {
    case 'appearance':
      return const AppearancePane();
    case 'language':
      return const LanguagePane();
    case 'security':
      return const SecurityPane();
    case 'sources':
      return const SourcesPane();
    case 'libmap':
      return const LibMapPane();
    case 'video':
      return const VideoPane();
    case 'music':
      return const MusicPane();
    case 'reading':
      return const ReadingPane();
    case 'cast':
      return const CastPane();
    case 'sites':
      return const SitesPane();
    case 'live':
      return const LivePane();
    case 'scraper':
      return const ScraperPane();
    case 'remotedl':
      return const RemoteDlPane();
    case 'sync':
      return const SyncPane();
    case 'transfer':
      return const TransferPane();
    case 'maint':
      return const MaintPane();
    case 'favorites':
      return const FavoritesPane();
    case 'advanced':
      return const AdvancedPane();
    case 'about':
      return const AboutPane();
  }
  final cats = allSettingsCats(l);
  final cat = cats.firstWhere(
    (c) => c.id == id,
    orElse: () => cats.first,
  );
  return StubPane(cat: cat);
}
