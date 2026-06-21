import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/epub_image_extractor.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/shared/providers/bottom_nav_visibility_provider.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';
import 'package:my_nas/shared/widgets/lottie_loading.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// EPUB 漫画阅读方向
enum EpubComicReadingMode {
  leftToRight('从左到右'),
  rightToLeft('从右到左');

  const EpubComicReadingMode(this.label);
  final String label;
}

/// EPUB 漫画阅读器状态
class EpubComicReaderState {
  const EpubComicReaderState({
    this.pages = const [],
    this.currentPage = 0,
    this.isLoading = true,
    this.error,
    this.showControls = false,
    this.totalPages = 0,
    this.readingMode = EpubComicReadingMode.leftToRight,
  });

  final List<EpubImagePage> pages;
  final int currentPage;
  final bool isLoading;
  final String? error;
  final bool showControls;
  final int totalPages;
  final EpubComicReadingMode readingMode;

  EpubComicReaderState copyWith({
    List<EpubImagePage>? pages,
    int? currentPage,
    bool? isLoading,
    String? error,
    bool? showControls,
    int? totalPages,
    EpubComicReadingMode? readingMode,
  }) =>
      EpubComicReaderState(
        pages: pages ?? this.pages,
        currentPage: currentPage ?? this.currentPage,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        showControls: showControls ?? this.showControls,
        totalPages: totalPages ?? this.totalPages,
        readingMode: readingMode ?? this.readingMode,
      );
}

/// EPUB 漫画阅读器 Notifier
class EpubComicReaderNotifier extends StateNotifier<EpubComicReaderState> {
  EpubComicReaderNotifier(this._book, this._epubFile)
      : super(const EpubComicReaderState()) {
    _init();
  }

  final BookItem _book;
  final File _epubFile;
  final EpubImageExtractor _extractor = EpubImageExtractor.instance;
  final ReadingProgressService _progressService = ReadingProgressService();

  Future<void> _init() async {
    await _progressService.init();
    await _loadPages();
    await _restoreProgress();
  }

  Future<void> _loadPages() async {
    try {
      state = state.copyWith(isLoading: true);

      // 获取图片总数
      final totalPages = await _extractor.getImageCount(_epubFile);

      // 提取所有图片
      final pages = await _extractor.extractImages(_epubFile);

      state = state.copyWith(
        pages: pages,
        totalPages: totalPages,
        isLoading: false,
      );

      logger.i('EpubComicReader: 加载完成，共 $totalPages 页');
    } on Exception catch (e, st) {
      logger.e('EpubComicReader: 加载失败', e, st);
      state = state.copyWith(
        isLoading: false,
        error: '加载失败: $e',
      );
    }
  }

  Future<void> _restoreProgress() async {
    try {
      final sourceId = _book.sourceId ?? 'local';
      final itemId = _progressService.generateItemId(sourceId, _book.path);
      final progress = _progressService.getProgress(itemId);

      if (progress != null && progress.position > 0) {
        final page = progress.position.toInt().clamp(0, state.totalPages - 1);
        state = state.copyWith(currentPage: page);
        logger.d('EpubComicReader: 恢复进度到第 ${page + 1} 页');
      }
    } on Exception catch (e) {
      logger.w('EpubComicReader: 恢复进度失败: $e');
    }
  }

  void goToPage(int page) {
    if (page < 0 || page >= state.totalPages) return;
    state = state.copyWith(currentPage: page);
    _saveProgress();
  }

  void nextPage() {
    final delta = state.readingMode == EpubComicReadingMode.rightToLeft ? -1 : 1;
    goToPage(state.currentPage + delta);
  }

  void previousPage() {
    final delta = state.readingMode == EpubComicReadingMode.rightToLeft ? 1 : -1;
    goToPage(state.currentPage + delta);
  }

  void toggleControls() {
    state = state.copyWith(showControls: !state.showControls);
  }

  void hideControls() {
    if (state.showControls) {
      state = state.copyWith(showControls: false);
    }
  }

  void setReadingMode(EpubComicReadingMode mode) {
    state = state.copyWith(readingMode: mode);
  }

  Future<void> _saveProgress() async {
    try {
      final sourceId = _book.sourceId ?? 'local';
      final itemId = _progressService.generateItemId(sourceId, _book.path);

      await _progressService.saveProgress(
        ReadingProgress(
          itemId: itemId,
          itemType: 'epub_comic',
          position: state.currentPage.toDouble(),
          totalPositions: state.totalPages,
          lastReadAt: DateTime.now(),
        ),
      );
    } on Exception catch (e) {
      logger.w('EpubComicReader: 保存进度失败: $e');
    }
  }
}

/// EPUB 漫画阅读器 Provider
final epubComicReaderProvider = StateNotifierProvider.autoDispose
    .family<EpubComicReaderNotifier, EpubComicReaderState, (BookItem, File)>(
  (ref, params) => EpubComicReaderNotifier(params.$1, params.$2),
);

/// EPUB 漫画阅读器页面
///
/// 使用 PhotoViewGallery 渲染 EPUB 中的图片
/// 适用于漫画类型的 EPUB 文件
class EpubComicReaderPage extends ConsumerStatefulWidget {
  const EpubComicReaderPage({
    required this.book,
    required this.epubFile,
    super.key,
  });

  final BookItem book;
  final File epubFile;

  @override
  ConsumerState<EpubComicReaderPage> createState() => _EpubComicReaderPageState();
}

class _EpubComicReaderPageState extends ConsumerState<EpubComicReaderPage> {
  late PageController _pageController;
  bool _isPageControllerReady = false;

  @override
  void initState() {
    super.initState();
    // 隐藏原生 Tab Bar（iOS 玻璃风格）
    NativeTabBarService.instance.setTabBarVisible(false);
    // 隐藏 Flutter 导航栏（经典风格）
    BottomNavVisibilityNotifier.instance?.hide();
    _pageController = PageController();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initWakelock();
  }

  Future<void> _initWakelock() async {
    await WakelockPlus.enable();
  }

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    // 恢复导航栏可见性（通过 Provider 引用计数，由 MainScaffold 决定实际状态）
    BottomNavVisibilityNotifier.instance?.show();
    super.dispose();
  }

  void _updatePageController(int currentPage) {
    if (!_isPageControllerReady && _pageController.hasClients) {
      _isPageControllerReady = true;
      if (currentPage > 0) {
        _pageController.jumpToPage(currentPage);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final params = (widget.book, widget.epubFile);
    final state = ref.watch(epubComicReaderProvider(params));
    final notifier = ref.read(epubComicReaderProvider(params).notifier);

    // 更新 PageController
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePageController(state.currentPage);
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowLeft): notifier.previousPage,
          const SingleActivator(LogicalKeyboardKey.arrowRight): notifier.nextPage,
          const SingleActivator(LogicalKeyboardKey.arrowUp): notifier.previousPage,
          const SingleActivator(LogicalKeyboardKey.arrowDown): notifier.nextPage,
          const SingleActivator(LogicalKeyboardKey.pageUp): notifier.previousPage,
          const SingleActivator(LogicalKeyboardKey.pageDown): notifier.nextPage,
          const SingleActivator(LogicalKeyboardKey.space): notifier.nextPage,
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
        },
        child: Focus(
          autofocus: true,
          child: state.isLoading
              ? LottieLoading.book(message: context.l10n.bookEpubComicReaderLoading)
              : state.error != null
                  ? _buildErrorView(state.error!)
                  : Stack(
                      children: [
                        // 漫画内容
                        _buildGallery(state, notifier),
                        // 控制栏
                        if (state.showControls) ...[
                          _buildTopBar(context, state, notifier),
                          _buildBottomBar(context, state, notifier),
                        ],
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildErrorView(String error) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              error,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.commonBack),
            ),
          ],
        ),
      );

  Widget _buildGallery(
    EpubComicReaderState state,
    EpubComicReaderNotifier notifier,
  ) {
    final isRtl = state.readingMode == EpubComicReadingMode.rightToLeft;

    return GestureDetector(
      onTap: notifier.toggleControls,
      child: PhotoViewGallery.builder(
        pageController: _pageController,
        itemCount: state.pages.length,
        reverse: isRtl,
        builder: (context, index) {
          final page = state.pages[index];
          return PhotoViewGalleryPageOptions(
            imageProvider: MemoryImage(page.data),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3,
            initialScale: PhotoViewComputedScale.contained,
            heroAttributes: PhotoViewHeroAttributes(tag: 'page_$index'),
          );
        },
        scrollPhysics: const BouncingScrollPhysics(),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        loadingBuilder: (context, event) => Center(
          child: Icon(
            Icons.auto_stories_rounded,
            size: 32,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
        onPageChanged: (index) {
          notifier.goToPage(isRtl ? state.pages.length - 1 - index : index);
        },
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    EpubComicReaderState state,
    EpubComicReaderNotifier notifier,
  ) =>
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: DecoratedBox(
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
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    widget.book.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 阅读方向切换
                IconButton(
                  icon: Icon(
                    state.readingMode == EpubComicReadingMode.rightToLeft
                        ? Icons.format_textdirection_r_to_l
                        : Icons.format_textdirection_l_to_r,
                    color: Colors.white,
                  ),
                  tooltip: state.readingMode == EpubComicReadingMode.rightToLeft
                      ? context.l10n.bookEpubComicReadingModeRtl
                      : context.l10n.bookEpubComicReadingModeLtr,
                  onPressed: () {
                    notifier.setReadingMode(
                      state.readingMode == EpubComicReadingMode.rightToLeft
                          ? EpubComicReadingMode.leftToRight
                          : EpubComicReadingMode.rightToLeft,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildBottomBar(
    BuildContext context,
    EpubComicReaderState state,
    EpubComicReaderNotifier notifier,
  ) =>
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: DecoratedBox(
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 进度条
                  Row(
                    children: [
                      Text(
                        '${state.currentPage + 1}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Expanded(
                        child: Slider(
                          value: state.currentPage.toDouble(),
                          min: 0,
                          max: (state.totalPages - 1).toDouble().clamp(0, double.infinity),
                          onChanged: (value) {
                            notifier.goToPage(value.toInt());
                            _pageController.jumpToPage(value.toInt());
                          },
                          activeColor: AppColors.primary,
                          inactiveColor: Colors.white24,
                        ),
                      ),
                      Text(
                        '${state.totalPages}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  // 控制按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.first_page, color: Colors.white),
                        onPressed: () {
                          notifier.goToPage(0);
                          _pageController.jumpToPage(0);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_left, color: Colors.white, size: 32),
                        onPressed: () {
                          notifier.previousPage();
                          final targetPage = state.readingMode == EpubComicReadingMode.rightToLeft
                              ? state.currentPage + 1
                              : state.currentPage - 1;
                          if (targetPage >= 0 && targetPage < state.totalPages) {
                            _pageController.animateToPage(
                              targetPage,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, color: Colors.white, size: 32),
                        onPressed: () {
                          notifier.nextPage();
                          final targetPage = state.readingMode == EpubComicReadingMode.rightToLeft
                              ? state.currentPage - 1
                              : state.currentPage + 1;
                          if (targetPage >= 0 && targetPage < state.totalPages) {
                            _pageController.animateToPage(
                              targetPage,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.last_page, color: Colors.white),
                        onPressed: () {
                          final lastPage = state.totalPages - 1;
                          notifier.goToPage(lastPage);
                          _pageController.jumpToPage(lastPage);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
