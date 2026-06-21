import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/router/routes.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/theme/dynamic_accent_provider.dart';
import 'package:my_nas/core/widgets/keyboard_shortcuts.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/auto_scrape_dialog.dart';
import 'package:my_nas/features/music/presentation/widgets/lyric_view.dart';
import 'package:my_nas/features/music/presentation/widgets/music_progress_bar.dart';
import 'package:my_nas/features/music/presentation/widgets/music_queue_sheet.dart';
import 'package:my_nas/features/music/presentation/widgets/music_settings_sheet.dart';
import 'package:my_nas/features/music/presentation/widgets/unsupported_format_dialog.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/providers/bottom_nav_visibility_provider.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

class MusicPlayerPage extends ConsumerStatefulWidget {
  const MusicPlayerPage({super.key});

  /// 导航锁，防止短时间内重复打开播放器页面
  static bool _isNavigating = false;
  static DateTime? _lastNavigationTime;

  /// 全屏打开音乐播放器（隐藏底部导航栏）
  /// 包含防重复导航机制，避免快速连续点击导致多次打开
  static Future<void> open(BuildContext context) async {
    // 检查 context 是否有效
    if (!context.mounted) {
      return;
    }

    // 检查是否正在导航中
    if (_isNavigating) {
      return;
    }

    // 检查当前路由是否已经是播放器页面
    // 注意：这个检查要在防抖检查之前，因为如果已经在播放器页面，应该直接返回
    final currentRoute = ModalRoute.of(context);
    if (currentRoute?.settings.name == '/music_player') {
      return;
    }

    // 检查上次导航时间，防止短时间内重复导航
    // 使用 100ms 防抖，足够防止意外双击，同时不影响正常的播放歌曲场景
    final now = DateTime.now();
    if (_lastNavigationTime != null &&
        now.difference(_lastNavigationTime!).inMilliseconds < 100) {
      return;
    }

    _isNavigating = true;
    _lastNavigationTime = now;

    try {
      // 使用 rootNavigator: true 确保在根导航器上打开
      // 这样可以覆盖底部导航栏
      final navigator = Navigator.of(context, rootNavigator: true);
      await navigator.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/music_player'),
          builder: (context) => const MusicPlayerPage(),
        ),
      );
    } on Exception catch (e) {
      // 导航失败时记录错误但不抛出异常
      debugPrint('MusicPlayerPage.open: 导航失败 - $e');
    } finally {
      _isNavigating = false;
    }
  }

  @override
  ConsumerState<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends ConsumerState<MusicPlayerPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
  bool _showLyrics = false;

  @override
  void initState() {
    super.initState();
    // 隐藏原生 Tab Bar（iOS 玻璃风格）
    NativeTabBarService.instance.setTabBarVisible(false);
    // 隐藏 Flutter 导航栏（经典风格）
    // 使用 Future 延迟到构建完成后再修改 provider 状态
    // 避免 "Tried to modify a provider while the widget tree was building" 错误
    Future(() {
      BottomNavVisibilityNotifier.instance?.hide();
      // iOS 不支持格式检测回调：当使用 just_audio 引擎播放 FLAC 等格式时
      // 显示切换引擎的提示对话框
      if (mounted) {
        ref.read(musicPlayerControllerProvider.notifier)
            .setupUnsupportedFormatCallback(context);
      }
    });
    _rotationController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    );
  }

  @override
  void dispose() {
    // 清理 iOS 不支持格式检测回调
    // 注意：在某些情况下（如快速导航），widget 可能在 unmount 过程中被销毁
    // 此时 ref 已不可用，需要捕获异常
    try {
      ref.read(musicPlayerControllerProvider.notifier)
          .removeUnsupportedFormatCallback();
    } catch (_) {
      // 忽略 ref 不可用的情况，回调会在 notifier dispose 时自动清理
    }
    _rotationController.dispose();
    // 恢复导航栏可见性
    // 使用 setVisible(true) 而不是 show()，因为 show() 只是减少引用计数
    // setVisible(true) 会直接将计数重置为 0 并强制显示导航栏
    // 这确保无论用户通过什么方式离开（返回按钮、滑动手势、系统导航），导航栏都能正确恢复
    // 注意：不再直接调用 NativeTabBarService，由 MainScaffold 根据 Provider 状态同步
    BottomNavVisibilityNotifier.instance?.setVisible(true);
    super.dispose();
  }

  void _toggleLyricView() {
    setState(() => _showLyrics = !_showLyrics);
  }

  /// 安全处理返回导航
  /// 当从灵动岛深度链接打开时，导航栈可能只有当前页面
  /// 此时直接 pop 会导致黑屏，需要改为导航到音乐主页
  void _handleBack(BuildContext context) {
    // 在导航前先恢复导航栏可见性
    // 使用 setVisible(true) 而不是 show()，因为 show() 只是减少引用计数
    // setVisible(true) 会直接将计数重置为 0 并强制显示导航栏
    // 注意：不再直接调用 NativeTabBarService，由 MainScaffold 根据 Provider 状态同步
    BottomNavVisibilityNotifier.instance?.setVisible(true);

    // 检查是否可以 pop（栈中是否有其他页面）
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      // 无法 pop 时，说明是从深度链接直接打开的
      // 使用 GoRouter 导航到音乐主页
      context.go(Routes.music);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentMusic = ref.watch(currentMusicProvider);
    final playerState = ref.watch(musicPlayerControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 控制封面旋转动画
    // 只在 widget 仍然挂载时操作动画控制器
    // 避免在 widget 销毁后 provider 更新触发时抛出异常
    if (mounted) {
      if (playerState.isPlaying) {
        _rotationController.repeat();
      } else {
        _rotationController.stop();
      }
    }

    if (currentMusic == null) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : null,
        appBar: AppBar(
          leading: const RoundedBackButton(),
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(context.l10n.musicPlayerNowPlaying),
        ),
        body: Center(
          child: Text(context.l10n.musicPlayerNoMusicSelected),
        ),
      );
    }

    final notifier = ref.read(musicPlayerControllerProvider.notifier);

    return KeyboardShortcuts(
      shortcuts: _buildKeyboardShortcuts(notifier, playerState),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[100],
        appBar: _buildAppBar(context, ref, currentMusic, isDark),
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      ref
                          .watch(musicDynamicAccentValueProvider)
                          .accent
                          .withValues(alpha: 0.18),
                      AppColors.darkBackground,
                      AppColors.darkBackground,
                    ]
                  : [
                      ref
                          .watch(musicDynamicAccentValueProvider)
                          .accent
                          .withValues(alpha: 0.12),
                      Colors.white,
                      Colors.grey[100]!,
                    ],
            ),
          ),
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _showLyrics
                ? _buildLyricMode(context, ref, currentMusic, playerState, isDark)
                : _buildCoverMode(context, ref, currentMusic, playerState, isDark),
          ),
        ),
      ),
      ),
    );
  }

  /// 构建键盘快捷键映射
  Map<ShortcutKey, VoidCallback> _buildKeyboardShortcuts(
    MusicPlayerNotifier notifier,
    MusicPlayerState state,
  ) => {
      // 播放/暂停
      CommonShortcuts.playPause: notifier.playOrPause,
      CommonShortcuts.playPauseK: notifier.playOrPause,

      // 上一曲/下一曲
      CommonShortcuts.previous: notifier.playPrevious,
      CommonShortcuts.next: notifier.playNext,

      // 快退/快进 (10秒)
      CommonShortcuts.seekBackward: () {
        final newPosition = state.position - const Duration(seconds: 10);
        notifier.seek(newPosition.isNegative ? Duration.zero : newPosition);
      },
      CommonShortcuts.seekForward: () {
        final newPosition = state.position + const Duration(seconds: 10);
        if (newPosition < state.duration) {
          notifier.seek(newPosition);
        }
      },

      // 音量调整
      CommonShortcuts.volumeUp: () {
        final newVolume = (state.volume + 0.1).clamp(0.0, 1.0);
        notifier.setVolume(newVolume);
      },
      CommonShortcuts.volumeDown: () {
        final newVolume = (state.volume - 0.1).clamp(0.0, 1.0);
        notifier.setVolume(newVolume);
      },
      CommonShortcuts.mute: () {
        if (state.volume > 0) {
          notifier.setVolume(0);
        } else {
          notifier.setVolume(1.0);
        }
      },

      // 播放模式
      CommonShortcuts.repeatMode: notifier.togglePlayMode,
      CommonShortcuts.shuffle: () {
        // 切换到随机模式
        if (state.playMode != PlayMode.shuffle) {
          notifier.togglePlayMode();
          if (state.playMode != PlayMode.shuffle) {
            notifier.togglePlayMode();
          }
        }
      },

      // 歌词切换
      CommonShortcuts.toggleControls: _toggleLyricView,

      // 退出
      CommonShortcuts.escape: () => _handleBack(context),

      // 帮助
      CommonShortcuts.help: _showKeyboardHelp,
    };

  /// 显示键盘快捷键帮助
  void _showKeyboardHelp() {
    KeyboardShortcutsHelpDialog.show(
      context,
      title: context.l10n.musicPlayerKeyboardShortcutsTitle,
      shortcuts: [
        (key: 'Space / K', description: context.l10n.musicPlayerShortcutPlayPause),
        (key: '←', description: context.l10n.musicPlayerShortcutPrevious),
        (key: '→', description: context.l10n.musicPlayerShortcutNext),
        (key: 'J', description: context.l10n.musicPlayerShortcutSeekBackward),
        (key: 'L', description: context.l10n.musicPlayerShortcutSeekForward),
        (key: '↑', description: context.l10n.musicPlayerShortcutVolumeUp),
        (key: '↓', description: context.l10n.musicPlayerShortcutVolumeDown),
        (key: 'M', description: context.l10n.musicPlayerShortcutMute),
        (key: 'R', description: context.l10n.musicPlayerShortcutRepeatMode),
        (key: 'C', description: context.l10n.musicPlayerShortcutShowHideLyrics),
        (key: 'Esc', description: context.l10n.musicPlayerShortcutReturn),
        (key: '?', description: context.l10n.musicPlayerShortcutShowHelp),
      ],
    );
  }

  /// 封面模式
  Widget _buildCoverMode(
    BuildContext context,
    WidgetRef ref,
    MusicItem currentMusic,
    MusicPlayerState playerState,
    bool isDark,
  ) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 700; // 紧凑模式（小屏幕或桌面端窗口较小）

    return Column(
      key: const ValueKey('cover_mode'),
      children: [
        // 可滚动的封面区域
        Expanded(
          flex: isCompact ? 5 : 6,
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(vertical: isCompact ? 8 : 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 封面（点击切换到歌词）
                GestureDetector(
                  onTap: _toggleLyricView,
                  child: _buildCover(context, currentMusic, playerState, isDark),
                ),
                SizedBox(height: isCompact ? 12 : 20),
                // 歌曲信息
                _buildTrackInfo(context, currentMusic, isDark),
                const SizedBox(height: 4),
                // 紧凑歌词显示
                CompactLyricView(onTap: _toggleLyricView),
              ],
            ),
          ),
        ),
        // 固定的控制区域（使用 Flexible 允许在空间不足时收缩）
        Flexible(
          flex: 0, // 优先使用封面区域的空间
          child: Container(
            padding: EdgeInsets.fromLTRB(16, isCompact ? 8 : 12, 16, isCompact ? 8 : 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  (isDark ? AppColors.darkBackground : Colors.grey[100]!)
                      .withValues(alpha: 0.8),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 进度条
                _buildProgressBar(context, ref, playerState, isDark),
                SizedBox(height: isCompact ? 12 : 20),
                // 控制按钮
                _buildControlButtons(context, ref, playerState, isDark),
                SizedBox(height: isCompact ? 8 : 12),
                // 额外控制
                _buildExtraControls(context, playerState, isDark),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 歌词模式
  Widget _buildLyricMode(
    BuildContext context,
    WidgetRef ref,
    MusicItem currentMusic,
    MusicPlayerState playerState,
    bool isDark,
  ) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 700;

    return Column(
      key: const ValueKey('lyric_mode'),
      children: [
        // 歌词视图
        Expanded(
          child: LyricView(
            onTap: _toggleLyricView,
            showFullScreen: true,
          ),
        ),
        // 底部控制区域 - 与封面模式保持一致的布局
        Container(
          padding: EdgeInsets.fromLTRB(16, isCompact ? 8 : 12, 16, isCompact ? 8 : 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                (isDark ? AppColors.darkBackground : Colors.grey[100]!)
                    .withValues(alpha: 0.8),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 进度条
              _buildProgressBar(context, ref, playerState, isDark),
              SizedBox(height: isCompact ? 12 : 20),
              // 控制按钮
              _buildControlButtons(context, ref, playerState, isDark),
              SizedBox(height: isCompact ? 8 : 12),
              // 额外控制
              _buildExtraControls(context, playerState, isDark),
            ],
          ),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    MusicItem currentMusic,
    bool isDark,
  ) {
    final isFavoriteAsync = ref.watch(isMusicFavoriteProvider(currentMusic.path));

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        onPressed: () => _handleBack(context),
        icon: Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 32,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      title: Column(
        children: [
          Text(
            '正在播放',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
          Text(
            currentMusic.folderName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        // 收藏按钮
        isFavoriteAsync.when(
          data: (isFavorite) => IconButton(
            onPressed: () async {
              final result = await ref
                  .read(musicFavoritesProvider.notifier)
                  .toggleFavorite(currentMusic);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result ? context.l10n.musicPlayerFavoriteAdded : context.l10n.musicPlayerFavoriteRemoved),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
            icon: Icon(
              isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isFavorite ? AppColors.error : (isDark ? Colors.white : Colors.black87),
            ),
            tooltip: isFavorite ? context.l10n.musicPlayerFavoriteButtonTooltipRemove : context.l10n.musicPlayerFavoriteButtonTooltip,
          ),
          loading: () => const SizedBox(
            width: 48,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (_, _) => IconButton(
            onPressed: null,
            icon: Icon(
              Icons.favorite_border_rounded,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ),
        // 自动识别按钮
        IconButton(
          onPressed: () => _showAutoScrapeDialog(context, ref, currentMusic),
          icon: Icon(
            Icons.auto_fix_high_rounded,
            color: isDark ? Colors.white : Colors.black87,
          ),
          tooltip: context.l10n.musicPlayerAutoIdentifyTooltip,
        ),
        // 更多选项
        IconButton(
          onPressed: () => showMusicSettingsSheet(context),
          icon: Icon(
            Icons.more_vert_rounded,
            color: isDark ? Colors.white : Colors.black87,
          ),
          tooltip: context.l10n.musicPlayerMoreOptionsTooltip,
        ),
      ],
    );
  }

  Future<void> _showAutoScrapeDialog(
    BuildContext context,
    WidgetRef ref,
    MusicItem currentMusic,
  ) async {
    // 获取文件系统（如果有）
    final connections = ref.read(activeConnectionsProvider);
    final connection = currentMusic.sourceId != null
        ? connections[currentMusic.sourceId]
        : null;
    final fileSystem = (connection != null && connection.status == SourceStatus.connected)
        ? connection.adapter.fileSystem
        : null;

    await AutoScrapeDialog.show(
      context,
      currentMusic,
      fileSystem: fileSystem,
    );
  }

  Widget _buildCover(
    BuildContext context,
    MusicItem currentMusic,
    MusicPlayerState playerState,
    bool isDark,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    // 桌面端限制封面最大尺寸，移动端使用屏幕宽度的60%
    final maxSize = screenHeight * 0.30;
    final size = (screenWidth * 0.60).clamp(140.0, maxSize);
    final tonearmLength = size * 0.6; // 唱针臂长度
    final pivotSize = size * 0.08; // 转轴球大小
    // 唱片和唱针的总区域高度：唱针在上方，唱片在下方
    final tonearmHeight = tonearmLength * 0.4; // 唱针在唱片上方的高度
    final totalHeight = size + tonearmHeight;

    return Center(
      child: SizedBox(
        width: size, // 唱片宽度
        height: totalHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 唱片（居中，先绘制在底层）
            Positioned(
              left: 0,
              top: tonearmHeight, // 唱片在唱针下方
              child: AnimatedBuilder(
                animation: _rotationController,
                builder: (context, child) => Transform.rotate(
                    angle: playerState.isPlaying ? _rotationController.value * 2 * math.pi : 0,
                    child: child,
                  ),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 2,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        blurRadius: 50,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: Size(size, size),
                        painter: _VinylRecordPainter(isDark: isDark),
                      ),
                      Container(
                        width: size * 0.38,
                        height: size * 0.38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.primary, AppColors.secondary],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _buildCoverImage(currentMusic, size * 0.38, isDark),
                      ),
                      Container(
                        width: size * 0.04,
                        height: size * 0.04,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black,
                          border: Border.all(color: Colors.grey[800]!, width: 1.5),
                        ),
                      ),
                      Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: const Alignment(-0.8, -0.8),
                            end: const Alignment(0.8, 0.8),
                            colors: [
                              Colors.white.withValues(alpha: 0.1),
                              Colors.transparent,
                              Colors.transparent,
                              Colors.white.withValues(alpha: 0.03),
                            ],
                            stops: const [0.0, 0.3, 0.7, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 唱针臂（后绘制在顶层，显示在唱片上方）
            Positioned(
              left: size * 0.35, // 转轴在中间偏左
              top: 0,
              child: _CenterTonearmWidget(
                isPlaying: playerState.isPlaying,
                armLength: tonearmLength,
                pivotSize: pivotSize,
                isDark: isDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverPlaceholder(double size, bool isDark) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [Colors.grey[800]!, Colors.grey[900]!]
              : [Colors.grey[200]!, Colors.grey[300]!],
        ),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.4,
        color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
      ),
    );

  /// 构建封面图片，优先使用嵌入的封面数据，其次是封面 URL
  Widget _buildCoverImage(MusicItem music, double size, bool isDark) {
    // 优先使用嵌入的封面数据
    if (music.coverData != null && music.coverData!.isNotEmpty) {
      return Image.memory(
        Uint8List.fromList(music.coverData!),
        key: ValueKey('cover_${music.id}'),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true, // 防止动画时闪烁
        errorBuilder: (_, _, _) => _buildCoverPlaceholder(size, isDark),
      );
    }

    // 其次使用封面 URL（支持 file:// 和网络 URL）
    if (music.coverUrl != null && music.coverUrl!.isNotEmpty) {
      if (music.coverUrl!.startsWith('file://')) {
        final filePath = music.coverUrl!.substring(7); // 移除 'file://' 前缀
        return Image.file(
          File(filePath),
          key: ValueKey('cover_file_${music.id}'),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildCoverPlaceholder(size, isDark),
        );
      }
      return Image.network(
        music.coverUrl!,
        key: ValueKey('cover_url_${music.id}'),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildCoverPlaceholder(size, isDark),
      );
    }

    // 没有封面时显示占位符
    return _buildCoverPlaceholder(size, isDark);
  }

  Widget _buildTrackInfo(BuildContext context, MusicItem currentMusic, bool isDark) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            currentMusic.displayTitle,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            currentMusic.displayArtist,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

  Widget _buildProgressBar(
    BuildContext context,
    WidgetRef ref,
    MusicPlayerState state,
    bool isDark,
  ) =>
      // 使用专门的进度条组件，支持平滑拖动
      MusicProgressBar(isDark: isDark);

  Widget _buildControlButtons(
    BuildContext context,
    WidgetRef ref,
    MusicPlayerState state,
    bool isDark,
  ) {
    final notifier = ref.read(musicPlayerControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 随机/循环模式
          IconButton(
            onPressed: notifier.togglePlayMode,
            iconSize: 28,
            icon: Icon(
              _getPlayModeIcon(state.playMode),
              color: state.playMode != PlayMode.loop
                  ? AppColors.primary
                  : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
            ),
            tooltip: _getPlayModeTooltip(state.playMode),
          ),
          // 上一曲
          IconButton(
            onPressed: notifier.playPrevious,
            iconSize: 44,
            icon: Icon(
              Icons.skip_previous_rounded,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          // 播放/暂停
          GestureDetector(
            onTap: notifier.playOrPause,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.secondary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: state.isBuffering
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  : Icon(
                      state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 40,
                      color: Colors.white,
                    ),
            ),
          ),
          // 下一曲
          IconButton(
            onPressed: notifier.playNext,
            iconSize: 44,
            icon: Icon(
              Icons.skip_next_rounded,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          // 播放列表
          IconButton(
            onPressed: () => showMusicQueueSheet(context),
            iconSize: 28,
            icon: Icon(
              Icons.queue_music_rounded,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
            tooltip: context.l10n.musicPlayerQueueTooltip,
          ),
        ],
      ),
    );
  }

  Widget _buildExtraControls(
    BuildContext context,
    MusicPlayerState state,
    bool isDark,
  ) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 音量控制
          _VolumeButton(
            volume: state.volume,
            isDark: isDark,
          ),
          // 歌词按钮
          IconButton(
            onPressed: _toggleLyricView,
            icon: Icon(
              Icons.lyrics_rounded,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
            tooltip: context.l10n.musicPlayerLyricsTooltip,
          ),
          // 定时关闭
          IconButton(
            onPressed: () => _showSleepTimer(context),
            icon: Icon(
              Icons.timer_outlined,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
            tooltip: context.l10n.musicPlayerSleepTimerTooltip,
          ),
        ],
      ),
    );

  IconData _getPlayModeIcon(PlayMode mode) => switch (mode) {
        PlayMode.loop => Icons.repeat_rounded,
        PlayMode.repeatOne => Icons.repeat_one_rounded,
        PlayMode.shuffle => Icons.shuffle_rounded,
      };

  String _getPlayModeTooltip(PlayMode mode) => switch (mode) {
        PlayMode.loop => context.l10n.musicPlayerPlayModeLoop,
        PlayMode.repeatOne => context.l10n.musicPlayerPlayModeRepeatOne,
        PlayMode.shuffle => context.l10n.musicPlayerPlayModeShuffle,
      };

  void _showSleepTimer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showAdaptiveModalSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetDragHandle(topPadding: 16, bottomPadding: 16),
            Text(
              context.l10n.musicPlayerSleepTimerTitle,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            ...[15, 30, 45, 60, 90].map((minutes) => ListTile(
                title: Text(
                  context.l10n.musicPlayerSleepTimerAfterMinutes(minutes),
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                ),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.l10n.musicPlayerSleepTimerStopPlayback(minutes)),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              )),
            ListTile(
              title: Text(
                context.l10n.musicPlayerSleepTimerAfterCurrentSong,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _VolumeButton extends ConsumerStatefulWidget {
  const _VolumeButton({
    required this.volume,
    required this.isDark,
  });

  final double volume;
  final bool isDark;

  @override
  ConsumerState<_VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends ConsumerState<_VolumeButton> {
  bool _showSlider = false;

  @override
  Widget build(BuildContext context) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => setState(() => _showSlider = !_showSlider),
          icon: Icon(
            widget.volume == 0
                ? Icons.volume_off_rounded
                : widget.volume < 0.5
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
            color: widget.isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
          ),
          tooltip: context.l10n.musicPlayerVolumeTooltip,
        ),
        if (_showSlider)
          SizedBox(
            width: 100,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: widget.isDark ? Colors.grey[800] : Colors.grey[300],
                thumbColor: AppColors.primary,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: widget.volume,
                onChanged: (value) {
                  ref.read(musicPlayerControllerProvider.notifier).setVolume(value);
                },
              ),
            ),
          ),
      ],
    );
}

/// 黑胶唱片绘制器
class _VinylRecordPainter extends CustomPainter {
  _VinylRecordPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 黑胶唱片主体背景
    final basePaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, basePaint);

    // 外边缘高光
    final edgePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.5,
        colors: [
          Colors.transparent,
          Colors.transparent,
          Colors.grey[800]!.withValues(alpha: 0.5),
          Colors.grey[600]!.withValues(alpha: 0.3),
        ],
        stops: const [0.0, 0.96, 0.98, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, edgePaint);

    // 绘制同心圆纹路（唱片凹槽效果）
    final groovePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // 从外到内绘制多圈纹路
    final labelRadius = radius * 0.38; // 标签区域半径
    final grooveStart = radius * 0.95; // 纹路开始位置
    final grooveEnd = labelRadius + radius * 0.02; // 纹路结束位置

    // 绘制粗纹路（较明显的沟槽）
    for (var r = grooveStart; r > grooveEnd; r -= 3) {
      // 交替使用两种颜色来模拟反光效果
      final alpha = 0.05 + (r / radius) * 0.1;
      groovePaint.color = Colors.grey[400]!.withValues(alpha: alpha);
      canvas.drawCircle(center, r, groovePaint);
    }

    // 绘制细纹路（更细的沟槽）
    groovePaint.strokeWidth = 0.3;
    for (var r = grooveStart - 1.5; r > grooveEnd; r -= 3) {
      groovePaint.color = Colors.grey[700]!.withValues(alpha: 0.15);
      canvas.drawCircle(center, r, groovePaint);
    }

    // 标签区域的边缘阴影
    final labelEdgePaint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.5,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.3),
          Colors.transparent,
        ],
        stops: const [0.85, 0.98, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: labelRadius));
    canvas.drawCircle(center, labelRadius, labelEdgePaint);

    // 添加反光效果（模拟光照）
    final shinePaint = Paint()
      ..shader = LinearGradient(
        begin: const Alignment(-0.7, -0.7),
        end: const Alignment(0.7, 0.7),
        colors: [
          Colors.white.withValues(alpha: 0.05),
          Colors.transparent,
          Colors.transparent,
          Colors.white.withValues(alpha: 0.02),
        ],
        stops: const [0.0, 0.4, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, shinePaint);
  }

  @override
  bool shouldRepaint(covariant _VinylRecordPainter oldDelegate) =>
      isDark != oldDelegate.isDark;
}

/// 唱针臂组件
class _TonearmWidget extends StatefulWidget {
  const _TonearmWidget({
    required this.isPlaying,
    required this.length,
    required this.isDark,
  });

  final bool isPlaying;
  final double length;
  final bool isDark;

  @override
  State<_TonearmWidget> createState() => _TonearmWidgetState();
}

class _TonearmWidgetState extends State<_TonearmWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: -0.3, // 离开唱片的角度
      end: 0.0, // 放在唱片上的角度
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    if (widget.isPlaying) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(_TonearmWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Transform(
          alignment: Alignment.topRight,
          transform: Matrix4.identity()
            ..rotateZ(_animation.value),
          child: child,
        ),
      child: CustomPaint(
        size: Size(widget.length, widget.length * 1.2),
        painter: _TonearmPainter(isDark: widget.isDark),
      ),
    );
}

/// 唱针臂绘制器
class _TonearmPainter extends CustomPainter {
  _TonearmPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final armWidth = size.width * 0.06;
    final pivotRadius = size.width * 0.1;
    final headWidth = size.width * 0.08;
    final headHeight = size.width * 0.15;

    // 转轴基座
    final basePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.grey[600]!,
          Colors.grey[800]!,
          Colors.grey[900]!,
        ],
        stops: const [0.0, 0.7, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width - pivotRadius, pivotRadius),
          radius: pivotRadius,
        ),
      );
    canvas.drawCircle(
      Offset(size.width - pivotRadius, pivotRadius),
      pivotRadius,
      basePaint,
    );

    // 转轴中心高光
    final baseCenterPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.grey[400]!,
          Colors.grey[700]!,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width - pivotRadius, pivotRadius),
          radius: pivotRadius * 0.4,
        ),
      );
    canvas.drawCircle(
      Offset(size.width - pivotRadius, pivotRadius),
      pivotRadius * 0.4,
      baseCenterPaint,
    );

    // 唱针臂主体
    final armPath = Path();
    final armStartX = size.width - pivotRadius * 1.5;
    final armStartY = pivotRadius;
    final armEndX = headWidth / 2;
    final armEndY = size.height - headHeight;

    // 绘制臂的渐变
    final armPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.grey[500]!,
          Colors.grey[700]!,
          Colors.grey[800]!,
        ],
      ).createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      )
      ..strokeWidth = armWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    armPath..moveTo(armStartX, armStartY)
    ..quadraticBezierTo(
      armEndX + armWidth,
      armEndY * 0.5,
      armEndX,
      armEndY,
    );
    canvas.drawPath(armPath, armPaint);

    // 唱针头
    final headRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        armEndX - headWidth / 2,
        armEndY,
        headWidth,
        headHeight,
      ),
      const Radius.circular(2),
    );
    final headPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.grey[600]!,
          Colors.grey[800]!,
        ],
      ).createShader(headRect.outerRect);
    canvas.drawRRect(headRect, headPaint);

    // 唱针尖
    final needlePaint = Paint()
      ..color = Colors.grey[400]!
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(armEndX, armEndY + headHeight),
      Offset(armEndX, armEndY + headHeight + 4),
      needlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TonearmPainter oldDelegate) =>
      isDark != oldDelegate.isDark;
}

/// 水平唱针臂组件（顶部右上角，向左下角伸展）
class _HorizontalTonearmWidget extends StatefulWidget {
  const _HorizontalTonearmWidget({
    required this.isPlaying,
    required this.width,
    required this.height,
    required this.isDark,
  });

  final bool isPlaying;
  final double width;
  final double height;
  final bool isDark;

  @override
  State<_HorizontalTonearmWidget> createState() => _HorizontalTonearmWidgetState();
}

class _HorizontalTonearmWidgetState extends State<_HorizontalTonearmWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // 唱针臂角度动画：从抬起到放下
    _animation = Tween<double>(
      begin: -0.15, // 抬起角度
      end: 0.0, // 放下到唱片上
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    if (widget.isPlaying) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(_HorizontalTonearmWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Transform(
          alignment: Alignment.topRight, // 以右上角为轴心旋转
          transform: Matrix4.identity()..rotateZ(_animation.value),
          child: child,
        ),
      child: CustomPaint(
        size: Size(widget.width, widget.height),
        painter: _HorizontalTonearmPainter(isDark: widget.isDark),
      ),
    );
}

/// 水平唱针臂绘制器
class _HorizontalTonearmPainter extends CustomPainter {
  _HorizontalTonearmPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final pivotRadius = size.height * 0.35;
    final armWidth = size.height * 0.15;
    final headWidth = size.height * 0.2;
    final headLength = size.height * 0.25;

    // 转轴基座（右上角）
    final pivotCenter = Offset(size.width - pivotRadius * 0.8, pivotRadius * 0.8);
    final basePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.grey[500]!,
          Colors.grey[700]!,
          Colors.grey[800]!,
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: pivotCenter, radius: pivotRadius));
    canvas.drawCircle(pivotCenter, pivotRadius, basePaint);

    // 转轴高光
    final highlightPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.4),
          Colors.white.withValues(alpha: 0.1),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 1.0],
      ).createShader(Rect.fromCircle(
        center: pivotCenter + Offset(-pivotRadius * 0.2, -pivotRadius * 0.2),
        radius: pivotRadius * 0.5,
      ));
    canvas.drawCircle(
      pivotCenter + Offset(-pivotRadius * 0.2, -pivotRadius * 0.2),
      pivotRadius * 0.4,
      highlightPaint,
    );

    // 唱针臂（从转轴向左下角延伸）
    final armStartX = pivotCenter.dx - pivotRadius * 0.5;
    final armStartY = pivotCenter.dy + pivotRadius * 0.3;
    final armEndX = size.width * 0.15;
    final armEndY = size.height * 0.7;

    final armPath = Path();
    final armPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Colors.grey[600]!,
          Colors.grey[500]!,
          Colors.grey[700]!,
        ],
      ).createShader(Rect.fromPoints(
        Offset(armStartX, armStartY),
        Offset(armEndX, armEndY),
      ))
      ..strokeWidth = armWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    armPath..moveTo(armStartX, armStartY)
      ..quadraticBezierTo(
        armStartX * 0.5,
        (armStartY + armEndY) * 0.4,
        armEndX,
        armEndY,
      );
    canvas.drawPath(armPath, armPaint);

    // 臂高光
    final armHighlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = armWidth * 0.3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(armPath, armHighlightPaint);

    // 唱针头
    final headRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(armEndX, armEndY),
        width: headWidth,
        height: headLength,
      ),
      const Radius.circular(2),
    );
    final headPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.grey[600]!,
          Colors.grey[800]!,
        ],
      ).createShader(headRect.outerRect);
    canvas.drawRRect(headRect, headPaint);

    // 唱针尖
    final needlePaint = Paint()
      ..color = Colors.grey[400]!
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(armEndX, armEndY + headLength * 0.5),
      Offset(armEndX, armEndY + headLength * 0.5 + 3),
      needlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _HorizontalTonearmPainter oldDelegate) =>
      isDark != oldDelegate.isDark;
}

/// 网易云风格唱针臂组件
class _NeteaseTonearmWidget extends StatefulWidget {
  const _NeteaseTonearmWidget({
    required this.isPlaying,
    required this.armLength,
    required this.pivotSize,
    required this.recordRadius,
    required this.isDark,
  });

  final bool isPlaying;
  final double armLength;
  final double pivotSize;
  final double recordRadius;
  final bool isDark;

  @override
  State<_NeteaseTonearmWidget> createState() => _NeteaseTonearmWidgetState();
}

class _NeteaseTonearmWidgetState extends State<_NeteaseTonearmWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // 唱针臂角度动画：从抬起到落下
    // 停止时向右上方抬起（针头在唱片外），播放时落到唱片上
    _animation = Tween<double>(
      begin: -0.55, // 停止时抬起 ~-31度，针头在唱片外
      end: 0.0, // 播放时落到唱片上
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    if (widget.isPlaying) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(_NeteaseTonearmWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Transform(
          alignment: Alignment.topRight,
          transform: Matrix4.identity()..rotateZ(_animation.value),
          child: child,
        ),
      child: CustomPaint(
        size: Size(widget.armLength, widget.armLength),
        painter: _NeteaseTonearmPainter(
          pivotSize: widget.pivotSize,
          recordRadius: widget.recordRadius,
          isDark: widget.isDark,
        ),
      ),
    );
}

/// 网易云风格唱针臂绘制器
class _NeteaseTonearmPainter extends CustomPainter {
  _NeteaseTonearmPainter({
    required this.pivotSize,
    required this.recordRadius,
    required this.isDark,
  });

  final double pivotSize;
  final double recordRadius;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final pivotRadius = pivotSize / 2;
    // 转轴球在右上角
    final pivotCenter = Offset(size.width - pivotRadius, pivotRadius);
    
    // 唱针臂弯折设计：
    // 第一段：从转轴向左下延伸（主臂）
    // 第二段：在中间弯折，向下延伸（短臂+唱针头）
    
    final armStartX = pivotCenter.dx - pivotRadius * 0.5;
    final armStartY = pivotCenter.dy + pivotRadius * 0.3;
    
    // 弯折点（臂的中间）
    final bendX = size.width * 0.35;
    final bendY = size.height * 0.55;
    
    // 唱针头位置（弯折后向下）
    final armEndX = bendX - size.width * 0.08;
    final armEndY = size.height * 0.75;

    // 绘制主臂（从转轴到弯折点）
    final mainArmPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Colors.grey[400]!,
          Colors.grey[500]!,
        ],
      ).createShader(Rect.fromPoints(
        Offset(armStartX, armStartY),
        Offset(bendX, bendY),
      ))
      ..strokeWidth = size.width * 0.035
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final mainArmPath = Path()
      ..moveTo(armStartX, armStartY)
      ..lineTo(bendX, bendY);
    canvas.drawPath(mainArmPath, mainArmPaint);

    // 绘制短臂（从弯折点到唱针头）
    final shortArmPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.grey[500]!,
          Colors.grey[600]!,
        ],
      ).createShader(Rect.fromPoints(
        Offset(bendX, bendY),
        Offset(armEndX, armEndY),
      ))
      ..strokeWidth = size.width * 0.025
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final shortArmPath = Path()
      ..moveTo(bendX, bendY)
      ..lineTo(armEndX, armEndY);
    canvas.drawPath(shortArmPath, shortArmPaint);

    // 臂高光
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = size.width * 0.01
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(mainArmPath, highlightPaint);

    // 弯折处关节（小圆点）
    final jointPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.grey[400]!,
          Colors.grey[600]!,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(bendX, bendY),
        radius: size.width * 0.025,
      ));
    canvas.drawCircle(Offset(bendX, bendY), size.width * 0.02, jointPaint);

    // 转轴球 - 金属质感
    final pivotPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        colors: [
          Colors.grey[300]!,
          Colors.grey[500]!,
          Colors.grey[700]!,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: pivotCenter, radius: pivotRadius));
    canvas.drawCircle(pivotCenter, pivotRadius, pivotPaint);

    // 转轴球高光
    final pivotHighlight = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.5, -0.5),
        colors: [
          Colors.white.withValues(alpha: 0.5),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: pivotCenter, radius: pivotRadius));
    canvas.drawCircle(pivotCenter, pivotRadius * 0.6, pivotHighlight);

    // 唱针头（小方块）
    final headSize = size.width * 0.045;
    final headRect = Rect.fromCenter(
      center: Offset(armEndX, armEndY),
      width: headSize,
      height: headSize * 1.8,
    );
    final headPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.grey[500]!, Colors.grey[700]!],
      ).createShader(headRect);
    canvas.drawRect(headRect, headPaint);

    // 唱针尖
    final needlePaint = Paint()
      ..color = Colors.grey[400]!
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(armEndX, armEndY + headSize * 0.9),
      Offset(armEndX, armEndY + headSize * 0.9 + 4),
      needlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _NeteaseTonearmPainter oldDelegate) =>
      pivotSize != oldDelegate.pivotSize ||
      recordRadius != oldDelegate.recordRadius ||
      isDark != oldDelegate.isDark;
}

/// 中置唱针臂组件 - 转轴在上方中间，斜向唱片右侧
class _CenterTonearmWidget extends StatefulWidget {
  const _CenterTonearmWidget({
    required this.isPlaying,
    required this.armLength,
    required this.pivotSize,
    required this.isDark,
  });

  final bool isPlaying;
  final double armLength;
  final double pivotSize;
  final bool isDark;

  @override
  State<_CenterTonearmWidget> createState() => _CenterTonearmWidgetState();
}

class _CenterTonearmWidgetState extends State<_CenterTonearmWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // 唱针臂角度动画：
    // 停止时向右上偏移（负角度，逆时针），播放时落到唱片上
    _animation = Tween<double>(
      begin: -0.30, // 停止时向右上偏移约17度
      end: 0.0, // 播放时落到唱片上
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    ));

    if (widget.isPlaying) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(_CenterTonearmWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Transform(
          alignment: Alignment.topLeft, // 以左上角为轴心旋转（转轴位置）
          transform: Matrix4.identity()..rotateZ(_animation.value),
          child: child,
        ),
      child: CustomPaint(
        size: Size(widget.armLength, widget.armLength),
        painter: _CenterTonearmPainter(
          pivotSize: widget.pivotSize,
          isDark: widget.isDark,
        ),
      ),
    );
}

/// 弧形唱针臂绘制器 - 优美的弧线造型
class _CenterTonearmPainter extends CustomPainter {
  _CenterTonearmPainter({
    required this.pivotSize,
    required this.isDark,
  });

  final double pivotSize;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final pivotRadius = pivotSize / 2;
    // 转轴在左上角
    final pivotCenter = Offset(pivotRadius, pivotRadius);

    // 臂的参数
    final armWidth = size.width * 0.035;

    // 弧形臂的起点（从转轴出发）
    final armStartX = pivotCenter.dx;
    final armStartY = pivotCenter.dy + pivotRadius * 0.5;

    // 弧形臂的终点（唱片边缘）
    final armEndX = size.width * 0.75;
    final armEndY = size.height * 0.92;

    // 贝塞尔曲线控制点（创建优美的弧线）
    final controlX = size.width * 0.15;
    final controlY = size.height * 0.55;

    // 绘制弧形臂 - 使用二次贝塞尔曲线
    final armPath = Path()
      ..moveTo(armStartX, armStartY)
      ..quadraticBezierTo(controlX, controlY, armEndX, armEndY);

    // 臂的主体
    final armPaint = Paint()
      ..color = isDark ? Colors.grey[300]! : Colors.grey[400]!
      ..strokeWidth = armWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(armPath, armPaint);

    // 臂的高光（稍微偏移的细线）
    final highlightPath = Path()
      ..moveTo(armStartX - armWidth * 0.2, armStartY)
      ..quadraticBezierTo(
        controlX - armWidth * 0.2,
        controlY - armWidth * 0.1,
        armEndX - armWidth * 0.1,
        armEndY - armWidth * 0.1,
      );

    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = armWidth * 0.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(highlightPath, highlightPaint);

    // 转轴球 - 金属质感
    final pivotPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        colors: isDark
            ? [Colors.grey[200]!, Colors.grey[400]!, Colors.grey[600]!]
            : [Colors.grey[300]!, Colors.grey[500]!, Colors.grey[700]!],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: pivotCenter, radius: pivotRadius));
    canvas.drawCircle(pivotCenter, pivotRadius, pivotPaint);

    // 转轴球高光
    final pivotHighlight = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.5, -0.5),
        colors: [
          Colors.white.withValues(alpha: 0.7),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: pivotCenter, radius: pivotRadius));
    canvas.drawCircle(pivotCenter, pivotRadius * 0.4, pivotHighlight);

    // 计算曲线末端的切线方向（用于唱针头的角度）
    // 二次贝塞尔曲线在 t=1 处的切线方向
    final tangentX = armEndX - controlX;
    final tangentY = armEndY - controlY;
    final armAngle = math.atan2(tangentY, tangentX);

    // 唱针头
    final headWidth = armWidth * 2.2;
    final headHeight = armWidth * 3.5;

    canvas
      ..save()
      ..translate(armEndX, armEndY)
      ..rotate(armAngle + math.pi / 2); // 让头垂直于臂

    // 唱针头主体 - 圆角矩形
    final headRect = Rect.fromCenter(
      center: Offset(0, headHeight / 2),
      width: headWidth,
      height: headHeight,
    );
    final headPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [Colors.grey[300]!, Colors.grey[500]!]
            : [Colors.grey[400]!, Colors.grey[600]!],
      ).createShader(headRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(headRect, const Radius.circular(2)),
      headPaint,
    );

    // 唱针尖
    final needlePaint = Paint()
      ..color = isDark ? Colors.grey[300]! : Colors.grey[500]!
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        Offset(0, headHeight),
        Offset(0, headHeight + 3),
        needlePaint,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _CenterTonearmPainter oldDelegate) =>
      pivotSize != oldDelegate.pivotSize ||
      isDark != oldDelegate.isDark;
}
