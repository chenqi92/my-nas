import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/core/widgets/keyboard_shortcuts.dart';
import 'package:my_nas/features/comic/data/services/archive_extract_service.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_list_page.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/features/reading/presentation/providers/reader_settings_provider.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/providers/bottom_nav_visibility_provider.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/reader_settings_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';
import 'package:path/path.dart' as path;
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 漫画页面项
class ComicPage {
  ComicPage({
    required this.index,
    this.url,
    this.bytes,
    this.fileName,
    this.filePath,
  });

  final int index;
  final String? url;
  final Uint8List? bytes;
  final String? fileName;
  /// 文件路径（用于流式加载）
  final String? filePath;

  bool get isLoaded => url != null || bytes != null || filePath != null;
}

/// 漫画阅读器状态
class ComicReaderState {
  ComicReaderState({
    required this.pages,
    required this.currentPage,
    this.isLoading = true,
    this.error,
    this.showControls = false,
    this.showSettings = false,
    this.isProgressRestored = false,
  });

  final List<ComicPage> pages;
  final int currentPage;
  final bool isLoading;
  final String? error;
  final bool showControls;
  final bool showSettings;
  final bool isProgressRestored; // 进度是否已恢复

  ComicReaderState copyWith({
    List<ComicPage>? pages,
    int? currentPage,
    bool? isLoading,
    String? error,
    bool? showControls,
    bool? showSettings,
    bool? isProgressRestored,
  }) =>
      ComicReaderState(
        pages: pages ?? this.pages,
        currentPage: currentPage ?? this.currentPage,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        showControls: showControls ?? this.showControls,
        showSettings: showSettings ?? this.showSettings,
        isProgressRestored: isProgressRestored ?? this.isProgressRestored,
      );
}

/// 漫画阅读器 Notifier
class ComicReaderNotifier extends StateNotifier<ComicReaderState> {
  ComicReaderNotifier(this._ref, this._comic)
      : super(ComicReaderState(
          pages: [],
          currentPage: 0,
        )) {
    _init();
  }

  final Ref _ref;
  final ComicItem _comic;
  final ReadingProgressService _progressService = ReadingProgressService();

  // 支持的图片格式
  static const _imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'];

  Future<void> _init() async {
    await _progressService.init();
    await _loadPages();
    await _restoreProgress();
  }

  Future<void> _loadPages() async {
    state = state.copyWith(isLoading: true);

    try {
      if (_comic.isArchive) {
        await _loadArchivePages();
      } else {
        await _loadFolderPages();
      }
    } on Exception catch (e) {
      logger.e('加载漫画页面失败', e);
      state = state.copyWith(isLoading: false, error: appL10n.comicReaderLoadFailedWithError(e));
    }
  }

  Future<void> _loadFolderPages() async {
    final connections = _ref.read(activeConnectionsProvider);
    final conn = connections[_comic.sourceId];
    if (conn == null) {
      state = state.copyWith(isLoading: false, error: appL10n.comicReaderConnectionUnavailable);
      return;
    }

    final fs = conn.adapter.fileSystem;
    final items = await fs.listDirectory(_comic.folderPath);

    final imageFiles = items.where((item) {
      if (item.isDirectory) return false;
      final ext = item.name.toLowerCase();
      return _imageExtensions.any(ext.endsWith);
    }).toList()

    ..sort((a, b) => a.name.compareTo(b.name));

    final pages = <ComicPage>[];
    for (var i = 0; i < imageFiles.length; i++) {
      final file = imageFiles[i];
      // 存储文件路径用于流式加载，而不是 URL
      // 因为 SMB/WebDAV 的 URL 格式 (smb://, webdav://) 无法被 Image.network 加载
      pages.add(ComicPage(
        index: i,
        filePath: file.path,
        fileName: file.name,
      ));
    }

    state = state.copyWith(pages: pages, isLoading: false);
  }

  Future<void> _loadArchivePages() async {
    final connections = _ref.read(activeConnectionsProvider);
    final conn = connections[_comic.sourceId];
    if (conn == null) {
      state = state.copyWith(isLoading: false, error: appL10n.comicReaderConnectionUnavailable);
      return;
    }

    final fs = conn.adapter.fileSystem;

    // 下载压缩包
    final stream = await fs.getFileStream(_comic.folderPath);
    final chunks = <List<int>>[];
    await for (final chunk in stream) {
      chunks.add(chunk);
    }
    final archiveBytes = Uint8List.fromList(chunks.expand((e) => e).toList());

    // 获取压缩类型
    final fileName = path.basename(_comic.folderPath);
    final archiveType = _getArchiveType(_comic.type);

    // 使用解压服务解压
    final extractService = ArchiveExtractService();
    final result = await extractService.extractImages(
      archiveBytes: archiveBytes,
      archiveType: archiveType,
      fileName: fileName,
    );

    if (!result.success) {
      state = state.copyWith(isLoading: false, error: result.error);
      return;
    }

    // 转换为 ComicPage
    final pages = <ComicPage>[];
    for (var i = 0; i < result.files.length; i++) {
      final file = result.files[i];
      pages.add(ComicPage(
        index: i,
        bytes: file.bytes,
        fileName: file.name,
      ));
    }

    state = state.copyWith(pages: pages, isLoading: false);
  }

  /// 将 ComicType 转换为 ArchiveType
  ArchiveType _getArchiveType(ComicType type) => switch (type) {
        ComicType.cbz => ArchiveType.zip,
        ComicType.cbr => ArchiveType.rar,
        ComicType.cb7 => ArchiveType.sevenZip,
        ComicType.folder => ArchiveType.unknown,
      };

  Future<void> _restoreProgress() async {
    final itemId = _progressService.generateItemId(_comic.sourceId, _comic.folderPath);
    final progress = _progressService.getProgress(itemId);
    if (progress != null && state.pages.isNotEmpty) {
      final page = progress.position.toInt().clamp(0, state.pages.length - 1);
      state = state.copyWith(currentPage: page, isProgressRestored: true);
    } else {
      state = state.copyWith(isProgressRestored: true);
    }
  }

  void goToPage(int page) {
    if (page < 0 || page >= state.pages.length) return;
    state = state.copyWith(currentPage: page);
    _saveProgress();
  }

  void nextPage(ComicReadingMode readingMode) {
    if (readingMode == ComicReadingMode.doublePage) {
      goToPage(state.currentPage + 2);
    } else {
      goToPage(state.currentPage + 1);
    }
  }

  void previousPage(ComicReadingMode readingMode) {
    if (readingMode == ComicReadingMode.doublePage) {
      goToPage(state.currentPage - 2);
    } else {
      goToPage(state.currentPage - 1);
    }
  }

  void toggleControls() {
    state = state.copyWith(showControls: !state.showControls, showSettings: false);
  }

  void toggleSettings() {
    state = state.copyWith(showSettings: !state.showSettings);
  }

  void hideControls() {
    if (state.showControls) {
      state = state.copyWith(showControls: false, showSettings: false);
    }
  }

  Future<void> _saveProgress() async {
    final itemId = _progressService.generateItemId(_comic.sourceId, _comic.folderPath);
    await _progressService.saveProgress(
      ReadingProgress(
        itemId: itemId,
        itemType: 'comic',
        position: state.currentPage.toDouble(),
        totalPositions: state.pages.length,
        lastReadAt: DateTime.now(),
      ),
    );
  }
}

/// 漫画阅读器页面
class ComicReaderPage extends ConsumerStatefulWidget {
  const ComicReaderPage({required this.comic, super.key});

  final ComicItem comic;

  @override
  ConsumerState<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends ConsumerState<ComicReaderPage> {
  late final StateNotifierProvider<ComicReaderNotifier, ComicReaderState> _provider;
  PageController? _pageController;
  ScrollController? _scrollController;
  int? _lastInitializedPage; // 记录 PageController 初始化的页码
  bool _hasJumpedToRestoredPage = false; // 是否已跳转到恢复的页面

  @override
  void initState() {
    super.initState();
    // 隐藏原生 Tab Bar（iOS 玻璃风格）
    NativeTabBarService.instance.setTabBarVisible(false);
    // 隐藏 Flutter 导航栏（经典风格）
    BottomNavVisibilityNotifier.instance?.hide();
    _provider = StateNotifierProvider<ComicReaderNotifier, ComicReaderState>(
      (ref) => ComicReaderNotifier(ref, widget.comic),
    );

    // 进入全屏模式
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initWakelock();
  }

  Future<void> _initWakelock() async {
    final settings = ref.read(comicReaderSettingsProvider);
    if (settings.keepScreenOn) {
      await WakelockPlus.enable();
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    _scrollController?.dispose();
    WakelockPlus.disable();
    // 退出全屏模式
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // 恢复导航栏可见性（通过 Provider 引用计数，由 MainScaffold 决定实际状态）
    BottomNavVisibilityNotifier.instance?.show();
    super.dispose();
  }

  /// 显示页面列表抽屉
  void _showPageListDrawer(BuildContext context, ComicReaderState state) {
    final settings = ref.read(comicReaderSettingsProvider);
    final isDarkBg = settings.backgroundColor == ComicBackgroundColor.black ||
        settings.backgroundColor == ComicBackgroundColor.darkGray ||
        settings.backgroundColor == ComicBackgroundColor.gray;

    showAdaptiveModalSheet<void>(
      context: context,
      backgroundColor: isDarkBg ? const Color(0xFF1A1A1A) : Colors.white,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // 拖拽指示器
            const SheetDragHandle(topPadding: 8, bottomPadding: 8),
            // 标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    context.l10n.comicReaderPageListTitle,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDarkBg ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${state.currentPage + 1}/${state.pages.length}',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkBg ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 页面网格
            Expanded(
              child: GridView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 0.7,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: state.pages.length,
                itemBuilder: (context, index) {
                  final isCurrentPage = index == state.currentPage;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      ref.read(_provider.notifier).goToPage(index);
                      _pageController?.jumpToPage(
                        settings.readingMode == ComicReadingMode.doublePage
                            ? index ~/ 2
                            : index,
                      );
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isCurrentPage
                              ? AppColors.primary
                              : (isDarkBg ? Colors.grey.shade700 : Colors.grey.shade300),
                          width: isCurrentPage ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Stack(
                        children: [
                          // 页面缩略图占位符
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.image_outlined,
                                  color: isDarkBg ? Colors.grey.shade600 : Colors.grey.shade400,
                                  size: 24,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isCurrentPage ? FontWeight.bold : FontWeight.normal,
                                    color: isCurrentPage
                                        ? AppColors.primary
                                        : (isDarkBg ? Colors.grey.shade400 : Colors.grey.shade600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 当前页标记
                          if (isCurrentPage)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  size: 10,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsSheet() {
    showReaderSettingsSheet(
      context,
      title: context.l10n.comicReaderSettingsTitle,
      icon: Icons.menu_book_rounded,
      iconColor: AppColors.secondary,
      contentBuilder: (context) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(comicReaderSettingsProvider);
          return _buildSettingsContent(settings);
        },
      ),
    );
  }

  /// 构建键盘快捷键映射
  Map<ShortcutKey, VoidCallback> _buildKeyboardShortcuts(
    ComicReaderState state,
    ComicReaderNotifier notifier,
    ComicReaderSettings settings,
  ) {
    final isRtl = settings.readingDirection == ComicReadingDirection.rtl;

    // 上一页操作
    void goToPrevious() {
      if (_pageController != null && _pageController!.hasClients) {
        _pageController!.previousPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else if (_scrollController != null && _scrollController!.hasClients) {
        final offset = (_scrollController!.offset -
                MediaQuery.of(context).size.height * 0.8)
            .clamp(0.0, _scrollController!.position.maxScrollExtent);
        _scrollController!.animateTo(
          offset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }

    // 下一页操作
    void goToNext() {
      if (_pageController != null && _pageController!.hasClients) {
        _pageController!.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else if (_scrollController != null && _scrollController!.hasClients) {
        final offset = (_scrollController!.offset +
                MediaQuery.of(context).size.height * 0.8)
            .clamp(0.0, _scrollController!.position.maxScrollExtent);
        _scrollController!.animateTo(
          offset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }

    return {
      // 导航（考虑阅读方向）
      CommonShortcuts.previous: isRtl ? goToNext : goToPrevious,
      CommonShortcuts.next: isRtl ? goToPrevious : goToNext,
      CommonShortcuts.previousPage: isRtl ? goToNext : goToPrevious,
      CommonShortcuts.nextPage: isRtl ? goToPrevious : goToNext,
      CommonShortcuts.first: () {
        notifier.goToPage(0);
        _pageController?.jumpToPage(0);
      },
      CommonShortcuts.last: () {
        final lastPage = state.pages.length - 1;
        notifier.goToPage(lastPage);
        _pageController?.jumpToPage(
          settings.readingMode == ComicReadingMode.doublePage
              ? lastPage ~/ 2
              : lastPage,
        );
      },

      // 控制栏切换
      CommonShortcuts.playPause: notifier.toggleControls,
      CommonShortcuts.toggleControls: notifier.toggleControls,

      // 设置
      CommonShortcuts.settings: _showSettingsSheet,

      // 退出
      CommonShortcuts.escape: () => Navigator.pop(context),
      CommonShortcuts.back: () => Navigator.pop(context),
    };
  }

  /// 显示快捷键帮助
  void _showKeyboardHelp() {
    KeyboardShortcutsHelpDialog.show(
      context,
      title: context.l10n.comicReaderKeyboardHelpTitle,
      shortcuts: [
        (key: '←', description: context.l10n.comicReaderPreviousPage),
        (key: '→', description: context.l10n.comicReaderNextPage),
        (key: 'Page Up', description: context.l10n.comicReaderPreviousPage),
        (key: 'Page Down', description: context.l10n.comicReaderNextPage),
        (key: 'Home', description: context.l10n.comicReaderFirstPage),
        (key: 'End', description: context.l10n.comicReaderLastPage),
        (key: 'Space', description: context.l10n.comicReaderToggleControls),
        (key: ',', description: context.l10n.comicReaderOpenSettings),
        (key: 'Esc', description: context.l10n.comicReaderBack),
        (key: '?', description: context.l10n.comicReaderShowHelp),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_provider);
    final notifier = ref.read(_provider.notifier);
    final settings = ref.watch(comicReaderSettingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return KeyboardShortcuts(
      shortcuts: {
        ..._buildKeyboardShortcuts(state, notifier, settings),
        CommonShortcuts.help: _showKeyboardHelp,
      },
      child: Scaffold(
        backgroundColor: settings.backgroundColor.color,
        body: Stack(
          children: [
            // 主内容（带固定顶栏）
            Column(
              children: [
                // 固定顶栏 - 避免摄像头遮挡内容
                _buildFixedHeader(state, settings),
                Expanded(
                  child: _buildMainContent(state, notifier, settings),
                ),
              ],
            ),

            // 点击翻页区域
            if (settings.tapToTurn && !state.isLoading && state.pages.isNotEmpty)
              _buildTapZones(state, notifier, settings),

            // 控制栏
            if (state.showControls) ...[
              // 顶部栏
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopBar(context, state, settings, isDark),
              ),
              // 底部栏
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomBar(context, state, notifier, settings, isDark),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建固定顶栏，显示漫画名和页码
  Widget _buildFixedHeader(ComicReaderState state, ComicReaderSettings settings) {
    final bgColor = settings.backgroundColor.color;
    // 根据背景颜色选择文字颜色
    final isDarkBg = settings.backgroundColor == ComicBackgroundColor.black ||
        settings.backgroundColor == ComicBackgroundColor.darkGray ||
        settings.backgroundColor == ComicBackgroundColor.gray;
    final textColor = isDarkBg ? Colors.grey.shade400 : Colors.grey.shade600;
    final borderColor = isDarkBg ? Colors.grey.shade800 : Colors.grey.shade300;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: borderColor,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.comic.folderName,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (state.pages.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                '${state.currentPage + 1}/${state.pages.length}',
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建主内容区域
  Widget _buildMainContent(
    ComicReaderState state,
    ComicReaderNotifier notifier,
    ComicReaderSettings settings,
  ) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              state.error!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.comicReaderBack),
            ),
          ],
        ),
      );
    }

    if (state.pages.isEmpty) {
      return Center(
        child: Text(
          context.l10n.comicReaderNoImagesFound,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    return _buildReader(state, notifier, settings);
  }

  Widget _buildTapZones(
    ComicReaderState state,
    ComicReaderNotifier notifier,
    ComicReaderSettings settings,
  ) {
    final isRtl = settings.readingDirection == ComicReadingDirection.rtl;

    // 翻页逻辑：只更新 PageController，由 onPageChanged 回调更新 notifier 状态
    void goToPrevious() {
      if (_pageController != null && _pageController!.hasClients) {
        _pageController!.previousPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else if (_scrollController != null && _scrollController!.hasClients) {
        // webtoon 模式：向上滚动一屏
        final offset = (_scrollController!.offset -
                MediaQuery.of(context).size.height * 0.8)
            .clamp(0.0, _scrollController!.position.maxScrollExtent);
        _scrollController!.animateTo(
          offset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }

    void goToNext() {
      if (_pageController != null && _pageController!.hasClients) {
        _pageController!.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else if (_scrollController != null && _scrollController!.hasClients) {
        // webtoon 模式：向下滚动一屏
        final offset = (_scrollController!.offset +
                MediaQuery.of(context).size.height * 0.8)
            .clamp(0.0, _scrollController!.position.maxScrollExtent);
        _scrollController!.animateTo(
          offset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }

    // 使用 translucent 行为让滑动手势可以穿透到 PageView
    // 只响应点击（tap）事件，不会拦截滑动手势
    return Positioned.fill(
      child: Row(
        children: [
          // 左侧区域 - 点击翻页
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (isRtl) {
                  goToNext();
                } else {
                  goToPrevious();
                }
              },
              // translucent 允许手势穿透，但仍然响应点击
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),
          ),
          // 中间区域 - 显示/隐藏控制栏
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: notifier.toggleControls,
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),
          ),
          // 右侧区域 - 点击翻页
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (isRtl) {
                  goToPrevious();
                } else {
                  goToNext();
                }
              },
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReader(
    ComicReaderState state,
    ComicReaderNotifier notifier,
    ComicReaderSettings settings,
  ) {
    switch (settings.readingMode) {
      case ComicReadingMode.singlePage:
        return _buildSinglePageReader(state, notifier, settings);
      case ComicReadingMode.doublePage:
        return _buildDoublePageReader(state, notifier, settings);
      case ComicReadingMode.webtoon:
        return _buildWebtoonReader(state, notifier, settings);
    }
  }

  Widget _buildSinglePageReader(
    ComicReaderState state,
    ComicReaderNotifier notifier,
    ComicReaderSettings settings,
  ) {
    // 初始化 PageController
    if (_pageController == null) {
      _pageController = PageController(initialPage: state.currentPage);
      _lastInitializedPage = state.currentPage;
    }

    // 进度恢复后，跳转到正确的页面
    if (state.isProgressRestored &&
        !_hasJumpedToRestoredPage &&
        _lastInitializedPage != state.currentPage) {
      _hasJumpedToRestoredPage = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController?.hasClients ?? false) {
          _pageController!.jumpToPage(state.currentPage);
        }
      });
    }

    final isRtl = settings.readingDirection == ComicReadingDirection.rtl;

    // 检查是否有需要流式加载的页面（文件夹类型漫画）
    final hasStreamPages = state.pages.any((p) => p.bytes == null && p.filePath != null);

    if (hasStreamPages) {
      // 使用 PageView + PhotoView 组合，支持流式加载
      return PageView.builder(
        controller: _pageController,
        itemCount: state.pages.length,
        reverse: isRtl,
        onPageChanged: (index) {
          notifier.goToPage(index);
        },
        itemBuilder: (context, index) {
          final page = state.pages[index];
          return _buildSinglePageWithZoom(page, settings, index);
        },
      );
    }

    // 使用 PhotoViewGallery（适用于内存图片和网络图片）
    return PhotoViewGallery.builder(
      pageController: _pageController,
      itemCount: state.pages.length,
      reverse: isRtl,
      builder: (context, index) {
        final page = state.pages[index];
        return PhotoViewGalleryPageOptions(
          imageProvider: _getImageProvider(page),
          minScale: _getMinScale(settings.scaleMode),
          maxScale: PhotoViewComputedScale.covered * 3,
          initialScale: _getInitialScale(settings.scaleMode),
          heroAttributes: PhotoViewHeroAttributes(tag: 'comic_page_$index'),
        );
      },
      onPageChanged: (index) {
        notifier.goToPage(index);
      },
      scrollPhysics: const BouncingScrollPhysics(),
      backgroundDecoration: BoxDecoration(color: settings.backgroundColor.color),
      loadingBuilder: (context, event) => const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      ),
    );
  }

  /// 构建支持缩放的单页（用于流式加载的图片）
  Widget _buildSinglePageWithZoom(
    ComicPage page,
    ComicReaderSettings settings,
    int index,
  ) {
    // 优先使用内存中的字节数据
    if (page.bytes != null) {
      return PhotoView(
        imageProvider: MemoryImage(page.bytes!),
        minScale: _getMinScale(settings.scaleMode),
        maxScale: PhotoViewComputedScale.covered * 3,
        initialScale: _getInitialScale(settings.scaleMode),
        backgroundDecoration: BoxDecoration(color: settings.backgroundColor.color),
        heroAttributes: PhotoViewHeroAttributes(tag: 'comic_page_$index'),
        loadingBuilder: (context, event) => _buildLoadingPlaceholder(),
        errorBuilder: (context, error, stackTrace) => _buildErrorPlaceholder(),
      );
    }

    // 使用文件路径流式加载（文件夹类型漫画）
    if (page.filePath != null) {
      final fs = _getFileSystem();
      if (fs != null) {
        return StreamImage(
          path: page.filePath,
          fileSystem: fs,
          fit: BoxFit.contain,
          placeholder: _buildLoadingPlaceholder(),
          errorWidget: _buildErrorPlaceholder(),
          cacheKey: '${widget.comic.sourceId}_${page.filePath}',
          enableZoom: true,
          minScale: _getMinScale(settings.scaleMode),
          maxScale: PhotoViewComputedScale.covered * 3,
          initialScale: _getInitialScale(settings.scaleMode),
          backgroundColor: settings.backgroundColor.color,
        );
      }
    }

    // 使用 URL 加载
    if (page.url != null) {
      final url = page.url!;
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return PhotoView(
          imageProvider: NetworkImage(url),
          minScale: _getMinScale(settings.scaleMode),
          maxScale: PhotoViewComputedScale.covered * 3,
          initialScale: _getInitialScale(settings.scaleMode),
          backgroundDecoration: BoxDecoration(color: settings.backgroundColor.color),
          heroAttributes: PhotoViewHeroAttributes(tag: 'comic_page_$index'),
          loadingBuilder: (context, event) => _buildLoadingPlaceholder(),
          errorBuilder: (context, error, stackTrace) => _buildErrorPlaceholder(),
        );
      }
    }

    return _buildErrorPlaceholder();
  }

  PhotoViewComputedScale _getMinScale(ComicScaleMode mode) => switch (mode) {
        ComicScaleMode.fitWidth => PhotoViewComputedScale.contained,
        ComicScaleMode.fitHeight => PhotoViewComputedScale.contained,
        ComicScaleMode.fitScreen => PhotoViewComputedScale.contained,
        ComicScaleMode.original => PhotoViewComputedScale.contained,
      };

  PhotoViewComputedScale _getInitialScale(ComicScaleMode mode) => switch (mode) {
        ComicScaleMode.fitWidth => PhotoViewComputedScale.contained,
        ComicScaleMode.fitHeight => PhotoViewComputedScale.contained,
        ComicScaleMode.fitScreen => PhotoViewComputedScale.contained,
        ComicScaleMode.original => PhotoViewComputedScale.covered,
      };

  Widget _buildDoublePageReader(
    ComicReaderState state,
    ComicReaderNotifier notifier,
    ComicReaderSettings settings,
  ) {
    // 双页模式：左右两页并排显示
    final totalDoublePages = (state.pages.length + 1) ~/ 2;
    final currentDoublePage = state.currentPage ~/ 2;
    final isRtl = settings.readingDirection == ComicReadingDirection.rtl;

    // 初始化 PageController
    if (_pageController == null) {
      _pageController = PageController(initialPage: currentDoublePage);
      _lastInitializedPage = state.currentPage;
    }

    // 进度恢复后，跳转到正确的页面
    if (state.isProgressRestored &&
        !_hasJumpedToRestoredPage &&
        _lastInitializedPage != state.currentPage) {
      _hasJumpedToRestoredPage = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController?.hasClients ?? false) {
          _pageController!.jumpToPage(currentDoublePage);
        }
      });
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: totalDoublePages,
      reverse: isRtl,
      onPageChanged: (index) {
        notifier.goToPage(index * 2);
      },
      itemBuilder: (context, index) {
        final leftIndex = index * 2;
        final rightIndex = leftIndex + 1;

        // RTL 模式下交换左右页
        final firstIndex = isRtl ? rightIndex : leftIndex;
        final secondIndex = isRtl ? leftIndex : rightIndex;

        return Row(
          children: [
            Expanded(
              child: firstIndex < state.pages.length && firstIndex >= 0
                  ? _buildPageImage(state.pages[firstIndex], settings)
                  : const SizedBox(),
            ),
            Expanded(
              child: secondIndex < state.pages.length && secondIndex >= 0
                  ? _buildPageImage(state.pages[secondIndex], settings)
                  : const SizedBox(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWebtoonReader(
    ComicReaderState state,
    ComicReaderNotifier notifier,
    ComicReaderSettings settings,
  ) {
    _scrollController ??= ScrollController();

    return ListView.builder(
      controller: _scrollController,
      itemCount: state.pages.length,
      itemBuilder: (context, index) {
        final page = state.pages[index];
        return Padding(
          padding: EdgeInsets.only(bottom: settings.webtoonPageGap),
          child: _buildPageImage(page, settings, fit: BoxFit.fitWidth),
        );
      },
    );
  }

  /// 获取当前漫画对应的文件系统
  NasFileSystem? _getFileSystem() {
    final connections = ref.read(activeConnectionsProvider);
    final conn = connections[widget.comic.sourceId];
    return conn?.adapter.fileSystem;
  }

  Widget _buildPageImage(
    ComicPage page,
    ComicReaderSettings settings, {
    BoxFit fit = BoxFit.contain,
  }) {
    // 优先使用内存中的字节数据（压缩包解压后的图片）
    if (page.bytes != null) {
      return Image.memory(
        page.bytes!,
        fit: fit,
        errorBuilder: (_, _, _) => _buildErrorPlaceholder(),
      );
    }

    // 使用文件路径流式加载（文件夹类型漫画）
    if (page.filePath != null) {
      final fs = _getFileSystem();
      if (fs != null) {
        return StreamImage(
          path: page.filePath,
          fileSystem: fs,
          fit: fit,
          placeholder: _buildLoadingPlaceholder(),
          errorWidget: _buildErrorPlaceholder(),
          cacheKey: '${widget.comic.sourceId}_${page.filePath}',
        );
      }
    }

    // 使用 URL 加载（仅适用于 HTTP/HTTPS URL）
    if (page.url != null) {
      final url = page.url!;
      // 检查是否是有效的 HTTP URL
      if (url.startsWith('http://') || url.startsWith('https://')) {
        return Image.network(
          url,
          fit: fit,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return _buildLoadingPlaceholder();
          },
          errorBuilder: (_, _, _) => _buildErrorPlaceholder(),
        );
      }
      // 对于非 HTTP URL（如 smb://, webdav://），尝试使用流式加载
      final fs = _getFileSystem();
      if (fs != null && page.filePath != null) {
        return StreamImage(
          path: page.filePath,
          fileSystem: fs,
          fit: fit,
          placeholder: _buildLoadingPlaceholder(),
          errorWidget: _buildErrorPlaceholder(),
          cacheKey: '${widget.comic.sourceId}_${page.filePath}',
        );
      }
    }

    return _buildErrorPlaceholder();
  }

  Widget _buildLoadingPlaceholder() => const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );

  Widget _buildErrorPlaceholder() => const Center(
        child: Icon(Icons.broken_image, size: 48, color: Colors.white24),
      );

  ImageProvider _getImageProvider(ComicPage page) {
    if (page.bytes != null) {
      return MemoryImage(page.bytes!);
    } else if (page.url != null) {
      return NetworkImage(page.url!);
    }
    return const AssetImage('assets/images/placeholder.png');
  }

  Widget _buildTopBar(
    BuildContext context,
    ComicReaderState state,
    ComicReaderSettings settings,
    bool isDark,
  ) =>
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    widget.comic.folderName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 目录按钮（显示页面列表）
                IconButton(
                  icon: const Icon(Icons.list, color: Colors.white),
                  onPressed: state.pages.isNotEmpty
                      ? () => _showPageListDrawer(context, state)
                      : null,
                  tooltip: context.l10n.comicReaderPageListTooltip,
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildBottomBar(
    BuildContext context,
    ComicReaderState state,
    ComicReaderNotifier notifier,
    ComicReaderSettings settings,
    bool isDark,
  ) {
    final isRtl = settings.readingDirection == ComicReadingDirection.rtl;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 页码滑块
              Row(
                children: [
                  Text(
                    '${state.currentPage + 1}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Expanded(
                    child: Slider(
                      value: state.currentPage.toDouble(),
                      max: (state.pages.length - 1).toDouble(),
                      onChanged: (value) {
                        notifier.goToPage(value.round());
                        _pageController?.jumpToPage(
                          settings.readingMode == ComicReadingMode.doublePage
                              ? value.round() ~/ 2
                              : value.round(),
                        );
                      },
                      activeColor: AppColors.primary,
                      inactiveColor: Colors.white24,
                    ),
                  ),
                  Text(
                    '${state.pages.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              // 翻页按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      isRtl ? Icons.skip_next_rounded : Icons.skip_previous_rounded,
                      color: Colors.white,
                    ),
                    onPressed: state.currentPage > 0
                        ? () {
                            if (_pageController != null && _pageController!.hasClients) {
                              _pageController!.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              );
                            }
                          }
                        : null,
                    tooltip: context.l10n.comicReaderPreviousPage,
                  ),
                  IconButton(
                    icon: const Icon(Icons.first_page, color: Colors.white),
                    onPressed: () {
                      notifier.goToPage(0);
                      _pageController?.jumpToPage(0);
                    },
                    tooltip: context.l10n.comicReaderFirstPage,
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, color: Colors.white),
                    onPressed: _showSettingsSheet,
                    tooltip: context.l10n.comicReaderSettings,
                  ),
                  IconButton(
                    icon: const Icon(Icons.last_page, color: Colors.white),
                    onPressed: () {
                      final lastPage = state.pages.length - 1;
                      notifier.goToPage(lastPage);
                      _pageController?.jumpToPage(
                        settings.readingMode == ComicReadingMode.doublePage
                            ? lastPage ~/ 2
                            : lastPage,
                      );
                    },
                    tooltip: context.l10n.comicReaderLastPage,
                  ),
                  IconButton(
                    icon: Icon(
                      isRtl ? Icons.skip_previous_rounded : Icons.skip_next_rounded,
                      color: Colors.white,
                    ),
                    onPressed: state.currentPage < state.pages.length - 1
                        ? () {
                            if (_pageController != null && _pageController!.hasClients) {
                              _pageController!.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              );
                            }
                          }
                        : null,
                    tooltip: context.l10n.comicReaderNextPage,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsContent(ComicReaderSettings settings) {
    final settingsNotifier = ref.read(comicReaderSettingsProvider.notifier);

    // 阅读模式选项
    final readingModes = [
      (icon: Icons.crop_portrait, label: context.l10n.comicReaderSinglePage),
      (icon: Icons.menu_book, label: context.l10n.comicReaderDoublePage),
      (icon: Icons.view_day, label: context.l10n.comicReaderWebtoon),
    ];

    // 阅读方向选项
    final readingDirections = [
      (icon: Icons.arrow_forward, label: context.l10n.comicReaderLeftToRight),
      (icon: Icons.arrow_back_rounded, label: context.l10n.comicReaderRightToLeft),
    ];

    // 缩放模式选项
    final scaleModes = [
      (icon: Icons.width_normal, label: context.l10n.comicReaderFitWidth),
      (icon: Icons.height, label: context.l10n.comicReaderFitHeight),
      (icon: Icons.fit_screen, label: context.l10n.comicReaderFitScreen),
      (icon: Icons.crop_original, label: context.l10n.comicReaderOriginalSize),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 阅读模式 - 横向滑动
        SettingSectionTitle(title: context.l10n.comicReaderReadingMode),
        SettingPageTurnModePicker(
          modes: readingModes,
          selectedIndex: settings.readingMode.index,
          onSelect: (index) {
            settingsNotifier.setReadingMode(ComicReadingMode.values[index]);
            _resetControllers();
          },
        ),
        const SizedBox(height: 24),

        // 阅读方向 - 横向滑动
        SettingSectionTitle(title: context.l10n.comicReaderReadingDirection),
        SettingPageTurnModePicker(
          modes: readingDirections,
          selectedIndex: settings.readingDirection.index,
          onSelect: (index) => settingsNotifier.setReadingDirection(ComicReadingDirection.values[index]),
        ),
        const SizedBox(height: 24),

        // 缩放模式 - 横向滑动
        SettingSectionTitle(title: context.l10n.comicReaderScaleMode),
        SettingPageTurnModePicker(
          modes: scaleModes,
          selectedIndex: settings.scaleMode.index,
          onSelect: (index) => settingsNotifier.setScaleMode(ComicScaleMode.values[index]),
        ),
        const SizedBox(height: 24),

        // 背景颜色
        SettingSectionTitle(title: context.l10n.comicReaderBackgroundColor),
        SettingColorPicker(
          colors: ComicBackgroundColor.values.map((c) => c.color).toList(),
          selectedIndex: ComicBackgroundColor.values.indexOf(settings.backgroundColor),
          onSelect: (index) => settingsNotifier.setBackgroundColor(ComicBackgroundColor.values[index]),
        ),
        const SizedBox(height: 24),

        // 长条模式页间距
        if (settings.readingMode == ComicReadingMode.webtoon) ...[
          SettingSliderRow(
            label: context.l10n.comicReaderWebtoonPageGapLabel,
            value: settings.webtoonPageGap,
            max: 50,
            divisions: 10,
            valueLabel: '${settings.webtoonPageGap.toInt()}',
            onChanged: settingsNotifier.setWebtoonPageGap,
          ),
          const SizedBox(height: 16),
        ],

        // 开关选项
        SettingSectionTitle(title: context.l10n.comicReaderOtherSettings),
        SettingSwitchRow(
          title: context.l10n.comicReaderShowPageNumber,
          value: settings.showPageNumber,
          onChanged: (value) => settingsNotifier.setShowPageNumber(value: value),
        ),
        SettingSwitchRow(
          title: context.l10n.comicReaderKeepScreenOn,
          value: settings.keepScreenOn,
          onChanged: (value) async {
            settingsNotifier.setKeepScreenOn(value: value);
            if (value) {
              await WakelockPlus.enable();
            } else {
              await WakelockPlus.disable();
            }
          },
        ),
        SettingSwitchRow(
          title: context.l10n.comicReaderTapToTurn,
          subtitle: context.l10n.comicReaderTapToTurnDescription,
          value: settings.tapToTurn,
          onChanged: (value) => settingsNotifier.setTapToTurn(value: value),
        ),
      ],
    );
  }

  void _resetControllers() {
    _pageController?.dispose();
    _pageController = null;
    _scrollController?.dispose();
    _scrollController = null;
  }
}
