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
const List<SettingsGroup> settingsGroups = [
  SettingsGroup(title: '通用', cats: [
    SettingsCat(
      id: 'appearance',
      icon: Icons.palette_outlined,
      label: '外观',
      subtitle: '主题、配色与 UI 风格。Glass / Classic 为实时全局开关。',
    ),
    SettingsCat(
      id: 'language',
      icon: Icons.language_rounded,
      label: '语言与地区',
      subtitle: '界面语言与元数据 / 音轨 / 字幕语言优先级。',
    ),
    SettingsCat(
      id: 'security',
      icon: Icons.shield_outlined,
      label: '隐私与安全',
      subtitle: '应用锁、PIN、生物识别与自动锁定。',
    ),
  ]),
  SettingsGroup(title: '连接', cats: [
    SettingsCat(
      id: 'sources',
      icon: Icons.dns_rounded,
      label: '数据源',
      subtitle: '添加 / 编辑 / 删除源，测试连接、2FA 与凭据存储。',
    ),
    SettingsCat(
      id: 'libmap',
      icon: Icons.folder_outlined,
      label: '媒体库映射',
      subtitle: '把源里的目录标记为 视频 / 音乐 / 照片 / 漫画 / 图书 库。',
    ),
  ]),
  SettingsGroup(title: '播放与媒体', cats: [
    SettingsCat(
      id: 'video',
      icon: Icons.movie_outlined,
      label: '视频播放',
      subtitle: '清晰度、HDR、音频直通、投屏转码与字幕。',
    ),
    SettingsCat(
      id: 'music',
      icon: Icons.library_music_outlined,
      label: '音乐播放',
      subtitle: '解码引擎、均衡器、无缝淡入淡出、歌词与 Scrobble。',
    ),
    SettingsCat(
      id: 'reading',
      icon: Icons.menu_book_outlined,
      label: '阅读',
      subtitle: '阅读器引擎、在线书源与全局阅读偏好。',
    ),
    SettingsCat(
      id: 'cast',
      icon: Icons.cast_rounded,
      label: '投屏与输出',
      subtitle: '音频输出、本地媒体代理、投屏与桌面歌词浮窗。',
    ),
  ]),
  SettingsGroup(title: '服务与自动化', cats: [
    SettingsCat(
      id: 'sites',
      icon: Icons.flag_circle_outlined,
      label: '站点与追踪',
      subtitle: 'PT 站点、Trakt 追踪与媒体管理后端。',
    ),
    SettingsCat(
      id: 'live',
      icon: Icons.live_tv_outlined,
      label: '直播源',
      subtitle: 'IPTV / M3U / HLS 直播源管理。',
    ),
    SettingsCat(
      id: 'scraper',
      icon: Icons.auto_awesome_outlined,
      label: '刮削源',
      subtitle: '影视、字幕与音乐的元数据来源与优先级。',
    ),
    SettingsCat(
      id: 'remotedl',
      icon: Icons.download_rounded,
      label: '远程下载服务',
      subtitle: 'aria2 / qBittorrent / Transmission 客户端连接与偏好。',
    ),
  ]),
  SettingsGroup(title: '数据', cats: [
    SettingsCat(
      id: 'sync',
      icon: Icons.sync_rounded,
      label: '云同步',
      subtitle: '基于 WebDAV 的跨设备同步（非云厂商专有）。',
    ),
    SettingsCat(
      id: 'transfer',
      icon: Icons.swap_horiz_rounded,
      label: '传输与缓存',
      subtitle: '上传 / 下载 / 缓存三类任务的并发与缓存策略。',
    ),
    SettingsCat(
      id: 'maint',
      icon: Icons.insights_outlined,
      label: '维护与统计',
      subtitle: '听歌统计、重复检测与回收站。',
    ),
    SettingsCat(
      id: 'favorites',
      icon: Icons.favorite_outline_rounded,
      label: '我的收藏',
      subtitle: '跨类型聚合的收藏内容。',
    ),
  ]),
  SettingsGroup(title: '高级', cats: [
    SettingsCat(
      id: 'advanced',
      icon: Icons.terminal_rounded,
      label: '高级',
      subtitle: 'Hosts 映射、系统索引集成与诊断。',
    ),
    SettingsCat(
      id: 'about',
      icon: Icons.info_outline_rounded,
      label: '关于',
      subtitle: '版本信息、更新与开源许可。',
    ),
  ]),
];

/// 扁平化的全部分类。
final List<SettingsCat> allSettingsCats =
    settingsGroups.expand((g) => g.cats).toList();

/// 根据分类 id 构造对应 pane。pane 逐个迁移完成后在此处路由到真实实现；
/// 未迁移的回退为 [StubPane]。
Widget buildSettingsPane(String id) {
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
  final cat = allSettingsCats.firstWhere(
    (c) => c.id == id,
    orElse: () => allSettingsCats.first,
  );
  return StubPane(cat: cat);
}
