import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/core/widgets/keyboard_shortcuts.dart';
import 'package:my_nas/features/book/data/services/book_file_cache_service.dart';
import 'package:my_nas/features/book/data/services/mobi_parser_service.dart';
import 'package:my_nas/features/book/data/services/native_epub_paginator.dart';
import 'package:my_nas/features/book/data/services/native_epub_parser.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/features/reading/presentation/providers/reader_settings_provider.dart';
import 'package:my_nas/features/reading/presentation/widgets/page_flip_effect.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/providers/bottom_nav_visibility_provider.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';
import 'package:my_nas/shared/widgets/lottie_loading.dart';
import 'package:my_nas/shared/widgets/reader_settings_sheet.dart';
import 'package:my_nas/features/book/presentation/providers/tts_provider.dart';
import 'package:my_nas/features/book/presentation/widgets/floating_tts_control.dart';
import 'package:my_nas/features/book/data/services/tts/tts_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 原生电子书阅读器状态
sealed class NativeEbookReaderState {}

class NativeEbookLoading extends NativeEbookReaderState {
  NativeEbookLoading({this.message = '加载中...'});
  final String message;
}

class NativeEbookLoaded extends NativeEbookReaderState {
  NativeEbookLoaded({
    required this.book,
    required this.pages,
    required this.toc,
    required this.chapterPageRanges,
  });

  final ParsedEbook book;
  final List<EbookPage> pages;
  final List<TocItem> toc;
  final List<(int, int)> chapterPageRanges;
}

class NativeEbookError extends NativeEbookReaderState {
  NativeEbookError(this.message);
  final String message;
}

/// 原生电子书阅读器 Provider
final nativeEbookReaderProvider =
    StateNotifierProvider.family<NativeEbookReaderNotifier, NativeEbookReaderState, BookItem>(
  (ref, book) => NativeEbookReaderNotifier(book, ref),
);

class NativeEbookReaderNotifier extends StateNotifier<NativeEbookReaderState> {
  NativeEbookReaderNotifier(this.book, this._ref) : super(NativeEbookLoading()) {
    _loadBook();
  }

  final BookItem book;
  final Ref _ref;
  final BookFileCacheService _cacheService = BookFileCacheService();
  final NativeEpubParser _parser = NativeEpubParser.instance;
  final NativeEpubPaginator _paginator = NativeEpubPaginator.instance;

  Future<void> _loadBook() async {
    try {
      await _cacheService.init();

      state = NativeEbookLoading(message: '获取文件...');

      // 获取或下载文件
      File? epubFile = await _getOrDownloadFile();
      if (epubFile == null) {
        state = NativeEbookError('无法获取文件');
        return;
      }

      // 如果是 MOBI/AZW3，需要先转换为 EPUB
      if (book.format == BookFormat.mobi || book.format == BookFormat.azw3) {
        state = NativeEbookLoading(message: '转换格式...');
        final bytes = await epubFile.readAsBytes();
        final result = await MobiParserService().parse(bytes, book.name);
        if (result.epubPath != null) {
          epubFile = File(result.epubPath!);
        } else {
          state = NativeEbookError('转换失败');
          return;
        }
      }

      // 解析 EPUB
      state = NativeEbookLoading(message: '解析内容...');
      final parsedBook = await _parser.parse(epubFile);

      // 分页
      state = NativeEbookLoading(message: '分页中...');
      final htmlContents = parsedBook.chapters.map((c) => c.htmlContent).toList();

      // 使用默认视口大小进行分页（实际大小会在 build 时调整）
      const defaultViewport = Size(375, 667);
      const defaultStyle = TextStyle(fontSize: 18, height: 1.8);

      final result = await _paginator.paginate(
        htmlContents: htmlContents,
        viewportSize: defaultViewport,
        baseStyle: defaultStyle,
      );

      state = NativeEbookLoaded(
        book: parsedBook,
        pages: result.pages,
        toc: parsedBook.toc,
        chapterPageRanges: result.chapterPageRanges,
      );

      logger.i('NativeEbookReader: 加载完成 ${parsedBook.title}, ${result.totalPages} 页');
    } on Exception catch (e, st) {
      logger.e('NativeEbookReader: 加载失败', e, st);
      state = NativeEbookError('加载失败: $e');
    }
  }

  Future<File?> _getOrDownloadFile() async {
    // 检查缓存
    final cachedFile = await _cacheService.getCachedFile(book.sourceId, book.path);
    if (cachedFile != null && await cachedFile.exists()) {
      return cachedFile;
    }

    // 本地文件
    final uri = Uri.parse(book.url);
    if (uri.scheme == 'file') {
      final localFile = File(uri.toFilePath());
      if (await localFile.exists()) {
        return localFile;
      }
      return null;
    }

    // 从 NAS 下载
    final fileSystem = _getFileSystem();
    if (fileSystem != null) {
      state = NativeEbookLoading(message: '下载中...');
      final savedFile = await _cacheService.saveToCacheFromStream(
        book.sourceId,
        book.path,
        () => fileSystem.getFileStream(book.path),
      );
      return savedFile;
    }

    return null;
  }

  NasFileSystem? _getFileSystem() {
    if (book.sourceId == null) return null;
    final connections = _ref.read(activeConnectionsProvider);
    final connection = connections[book.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      return null;
    }
    return connection.adapter.fileSystem;
  }
}

/// 原生电子书阅读器页面
///
/// 使用纯 Flutter 渲染，无 WebView 依赖。
/// 特点：加载快、仿真翻页流畅、内存占用低
class NativeEbookReaderPage extends ConsumerStatefulWidget {
  const NativeEbookReaderPage({required this.book, super.key});

  final BookItem book;

  @override
  ConsumerState<NativeEbookReaderPage> createState() => _NativeEbookReaderPageState();
}

class _NativeEbookReaderPageState extends ConsumerState<NativeEbookReaderPage> {
  final PageController _pageController = PageController();
  final ReadingProgressService _progressService = ReadingProgressService();

  int _currentPage = 0;
  bool _showControls = false;
  bool _showToc = false;
  bool _showTTS = false;
  bool _userClosedTTS = false; // 用户手动关闭 TTS，防止自动重启

  // 进度保存防抖
  Timer? _saveProgressTimer;
  static const _saveProgressDebounce = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    // 隐藏原生 Tab Bar（iOS 玻璃风格）
    NativeTabBarService.instance.setTabBarVisible(false);
    // 隐藏 Flutter 导航栏（经典风格）
    BottomNavVisibilityNotifier.instance?.hide();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initWakelock();
    _loadProgress();
  }

  Future<void> _initWakelock() async {
    final settings = ref.read(bookReaderSettingsProvider);
    if (settings.keepScreenOn) {
      await WakelockPlus.enable();
    }
  }

  Future<void> _loadProgress() async {
    await _progressService.init();
    final itemId = _progressService.generateItemId(
      widget.book.sourceId ?? 'local',
      widget.book.path,
    );
    final progress = _progressService.getProgress(itemId);
    if (progress != null && progress.position > 0) {
      final state = ref.read(nativeEbookReaderProvider(widget.book));
      if (state is NativeEbookLoaded) {
        final pageIndex = _paginator.getPageIndexFromProgress(
          progress.position,
          state.pages.length,
        );
        setState(() => _currentPage = pageIndex);
        _pageController.jumpToPage(pageIndex);
      }
    }
  }

  NativeEpubPaginator get _paginator => NativeEpubPaginator.instance;

  // 缓存最后的阅读状态用于 dispose 时保存
  NativeEbookLoaded? _lastLoadedState;

  @override
  void dispose() {
    _saveProgressTimer?.cancel();
    // 使用缓存的状态保存进度，避免 ref.read() 错误
    _saveProgressImmediatelyWithState(_lastLoadedState);
    // 停止 TTS 播放 - 使用直接服务调用确保可靠停止
    TTSService.instance.stop();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    // 恢复导航栏可见性（通过 Provider 引用计数，由 MainScaffold 决定实际状态）
    BottomNavVisibilityNotifier.instance?.show();
    _pageController.dispose();
    super.dispose();
  }

  void _saveProgressDebounced() {
    _saveProgressTimer?.cancel();
    _saveProgressTimer = Timer(_saveProgressDebounce, _saveProgressImmediately);
  }

  Future<void> _saveProgressImmediately() async {
    if (!mounted) return;
    final state = ref.read(nativeEbookReaderProvider(widget.book));
    if (state is! NativeEbookLoaded) return;
    _lastLoadedState = state; // 缓存状态
    await _saveProgressImmediatelyWithState(state);
  }

  Future<void> _saveProgressImmediatelyWithState(NativeEbookLoaded? state) async {
    if (state == null) return;

    final itemId = _progressService.generateItemId(
      widget.book.sourceId ?? 'local',
      widget.book.path,
    );

    final progress = state.pages.isNotEmpty
        ? (_currentPage + 1) / state.pages.length
        : 0.0;

    await _progressService.saveProgress(
      ReadingProgress(
        itemId: itemId,
        itemType: 'epub_native',
        position: progress,
        totalPositions: state.pages.length,
        lastReadAt: DateTime.now(),
      ),
    );
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (!_showControls) {
        _showToc = false;
        // Keep TTS visible if playing
        final ttsState = ref.read(ttsProvider);
        if (!ttsState.isPlaying && !ttsState.isPaused) {
          _showTTS = false;
        }
      }
    });
  }

  /// 开始朗读当前页面
  Future<void> _startTTS() async {
    final state = ref.read(nativeEbookReaderProvider(widget.book));
    if (state is! NativeEbookLoaded) return;

    final ttsNotifier = ref.read(ttsProvider.notifier);
    await ttsNotifier.init();

    // 获取当前页面的文本内容
    final currentPageContent = state.pages[_currentPage].textContent;
    if (currentPageContent.isEmpty) return;

    // 按段落分割
    final paragraphs = currentPageContent
        .split(RegExp(r'\n\n+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();

    // 用户开始 TTS，清除用户关闭标志
    _userClosedTTS = false;
    setState(() => _showTTS = true);

    await ttsNotifier.speakParagraphs(
      paragraphs,
      onParagraphChanged: (paragraphIndex) {
        // TTS 段落变化时的回调（可用于滚动到对应位置）
        debugPrint('TTS: 当前段落 $paragraphIndex');
      },
      onAllComplete: () {
        // 朗读完成，检查是否自动播放下一页
        final settings = ref.read(ttsProvider).settings;
        // 如果用户已手动关闭，不自动播放下一页
        if (!_userClosedTTS && settings.autoPlayNextChapter && _currentPage < state.pages.length - 1) {
          _goToPage(_currentPage + 1);
          Future.delayed(const Duration(milliseconds: 300), _startTTS);
        }
      },
    );
  }

  void _goToPage(int page) {
    final state = ref.read(nativeEbookReaderProvider(widget.book));
    if (state is! NativeEbookLoaded) return;

    final targetPage = page.clamp(0, state.pages.length - 1);
    _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _goToChapter(int chapterIndex) {
    final state = ref.read(nativeEbookReaderProvider(widget.book));
    if (state is! NativeEbookLoaded) return;

    final pageIndex = _paginator.getPageIndexFromChapter(
      chapterIndex,
      state.chapterPageRanges,
    );
    _goToPage(pageIndex);
    setState(() => _showToc = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nativeEbookReaderProvider(widget.book));
    final settings = ref.watch(bookReaderSettingsProvider);

    return KeyboardShortcuts(
      shortcuts: _buildKeyboardShortcuts(settings),
      child: Scaffold(
        backgroundColor: settings.theme.backgroundColor,
        body: switch (state) {
          NativeEbookLoading(:final message) => LottieLoading.book(message: message),
          NativeEbookError(:final message) => _buildError(message),
          NativeEbookLoaded() => _buildReader(state, settings),
        },
      ),
    );
  }

  Map<ShortcutKey, VoidCallback> _buildKeyboardShortcuts(BookReaderSettings settings) {
    return {
      CommonShortcuts.previous: () => _goToPage(_currentPage - 1),
      CommonShortcuts.next: () => _goToPage(_currentPage + 1),
      CommonShortcuts.previousPage: () => _goToPage(_currentPage - 1),
      CommonShortcuts.nextPage: () => _goToPage(_currentPage + 1),
      CommonShortcuts.first: () => _goToPage(0),
      CommonShortcuts.playPause: _toggleControls,
      CommonShortcuts.toggleControls: _toggleControls,
      CommonShortcuts.escape: () => Navigator.pop(context),
      CommonShortcuts.back: () => Navigator.pop(context),
    };
  }

  Widget _buildError(String message) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      );

  Widget _buildReader(NativeEbookLoaded state, BookReaderSettings settings) {
    final useFlutterFlip = settings.pageTurnMode == BookPageTurnMode.simulation ||
        settings.pageTurnMode == BookPageTurnMode.cover;

    // 构建 PageView 内容
    Widget pageView = PageView.builder(
      controller: _pageController,
      // 当使用 PageFlipEffect 时，禁用 PageView 的滑动（翻页由 PageFlipEffect 处理）
      physics: useFlutterFlip ? const NeverScrollableScrollPhysics() : null,
      itemCount: state.pages.length,
      onPageChanged: (page) {
        setState(() => _currentPage = page);
        _saveProgressDebounced();
      },
      itemBuilder: (context, index) {
        final page = state.pages[index];
        return _buildPageContent(page, settings);
      },
    );

    // 如果不使用 Flutter 翻页效果，用 GestureDetector 处理点击
    if (!useFlutterFlip) {
      pageView = GestureDetector(
        onTap: _toggleControls,
        child: pageView,
      );
    }

    Widget readerContent = ColoredBox(
      color: settings.theme.backgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            // 固定顶栏 - 显示书名
            _buildFixedHeader(state, settings),
            // 阅读器内容
            Expanded(child: pageView),
            // 固定底栏 - 显示进度
            if (settings.showProgress) _buildFixedFooter(state, settings),
          ],
        ),
      ),
    );

    // 如果使用 Flutter 翻页效果
    if (useFlutterFlip) {
      readerContent = PageFlipEffect(
        mode: settings.pageTurnMode == BookPageTurnMode.simulation
            ? PageFlipMode.simulation
            : PageFlipMode.cover,
        backgroundColor: settings.theme.backgroundColor,
        onNextPage: () async {
          if (_currentPage < state.pages.length - 1) {
            _goToPage(_currentPage + 1);
          }
        },
        onPrevPage: () async {
          if (_currentPage > 0) {
            _goToPage(_currentPage - 1);
          }
        },
        onTap: (details) => _toggleControls(),
        child: readerContent,
      );
    }

    return Stack(
      children: [
        readerContent,
        // 控制栏
        if (_showControls) ...[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(state, settings),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(state, settings),
          ),
        ],
        // 目录抽屉
        if (_showToc) _buildTocDrawer(state, settings),
        // TTS 浮动控制栏（新设计，不遮挡内容）
        if (_showTTS)
          FloatingTTSControl(
            onClose: () {
              _userClosedTTS = true; // 标记用户手动关闭
              setState(() => _showTTS = false);
            },
            backgroundColor: settings.theme.backgroundColor,
          ),
      ],
    );
  }

  Widget _buildPageContent(EbookPage page, BookReaderSettings settings) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: settings.horizontalPadding),
      child: HtmlContentWidget(
        html: page.htmlContent,
        textStyle: TextStyle(
          fontSize: settings.fontSize,
          height: settings.lineHeight,
          color: settings.theme.textColor,
          fontFamily: settings.fontFamily,
        ),
        imageProvider: (url) {
          final imageData = NativeEpubParser.instance.getImage(url);
          if (imageData != null) {
            return MemoryImage(imageData);
          }
          return null;
        },
      ),
    );
  }

  Widget _buildFixedHeader(NativeEbookLoaded state, BookReaderSettings settings) {
    final isDark = settings.theme == BookReaderTheme.dark ||
        settings.theme == BookReaderTheme.black;
    final textColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              state.book.title,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_currentPage + 1}/${state.pages.length}',
            style: TextStyle(color: textColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFixedFooter(NativeEbookLoaded state, BookReaderSettings settings) {
    final isDark = settings.theme == BookReaderTheme.dark ||
        settings.theme == BookReaderTheme.black;
    final textColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final progress = state.pages.isNotEmpty
        ? ((_currentPage + 1) / state.pages.length * 100).toStringAsFixed(1)
        : '0.0';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '第 ${_currentPage + 1} 页',
            style: TextStyle(color: textColor, fontSize: 11),
          ),
          Text(
            '$progress%',
            style: TextStyle(color: textColor, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(NativeEbookLoaded state, BookReaderSettings settings) {
    return DecoratedBox(
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
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.book.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(NativeEbookLoaded state, BookReaderSettings settings) {
    final isDark = settings.theme == BookReaderTheme.dark ||
        settings.theme == BookReaderTheme.black;
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
              // 进度条
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white24,
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: _currentPage.toDouble(),
                  min: 0,
                  max: (state.pages.length - 1).toDouble().clamp(0, double.infinity),
                  onChanged: (value) => _goToPage(value.round()),
                ),
              ),
              // 页码
              Text(
                '${_currentPage + 1} / ${state.pages.length}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 12),
              // 控制按钮 - 与 Foliate 布局一致
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _BottomBarButton(
                    icon: Icons.menu_book_rounded,
                    label: '目录',
                    isDark: isDark,
                    onPressed: () => setState(() => _showToc = !_showToc),
                  ),
                  _BottomBarButton(
                    icon: Icons.headphones_rounded,
                    label: '朗读',
                    isDark: isDark,
                    onPressed: _startTTS,
                  ),
                  _BottomBarButton(
                    icon: isDark ? Icons.light_mode : Icons.dark_mode,
                    label: isDark ? '日间' : '夜间',
                    isDark: isDark,
                    onPressed: () {
                      final notifier = ref.read(bookReaderSettingsProvider.notifier);
                      final newTheme = isDark
                          ? BookReaderTheme.light
                          : BookReaderTheme.dark;
                      notifier.setTheme(newTheme);
                    },
                  ),
                  _BottomBarButton(
                    icon: Icons.settings_rounded,
                    label: '设置',
                    isDark: isDark,
                    onPressed: _showSettingsSheet,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTocDrawer(NativeEbookLoaded state, BookReaderSettings settings) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showToc = false),
        child: Container(
          color: Colors.black54,
          child: Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () {}, // 阻止点击传递
              child: Container(
                width: MediaQuery.of(context).size.width * 0.75,
                height: double.infinity,
                color: settings.theme.backgroundColor,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 标题
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.menu_book_rounded,
                              color: settings.theme.textColor,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '目录',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: settings.theme.textColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(color: settings.theme.textColor.withValues(alpha: 0.2)),
                      // 目录列表
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: state.toc.length,
                          itemBuilder: (context, index) {
                            final item = state.toc[index];
                            return _buildTocItem(item, index, settings);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTocItem(TocItem item, int index, BookReaderSettings settings) {
    return InkWell(
      onTap: () => _goToChapter(index),
      child: Padding(
        padding: EdgeInsets.only(
          left: 16.0 + item.depth * 16.0,
          right: 16,
          top: 12,
          bottom: 12,
        ),
        child: Text(
          item.title,
          style: TextStyle(
            fontSize: 14,
            color: settings.theme.textColor,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  void _showSettingsSheet() {
    showReaderSettingsSheet(
      context,
      title: '阅读设置',
      icon: Icons.settings_rounded,
      contentBuilder: (context) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(bookReaderSettingsProvider);
          return _buildSettingsContent(settings);
        },
      ),
    );
  }

  Widget _buildSettingsContent(BookReaderSettings settings) {
    final settingsNotifier = ref.read(bookReaderSettingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 字体大小
        SettingSliderRow(
          label: '字体大小',
          value: settings.fontSize,
          min: 12,
          max: 36,
          divisions: 12,
          valueLabel: '${settings.fontSize.toInt()}',
          onChanged: settingsNotifier.setFontSize,
        ),
        const SizedBox(height: 16),

        // 行高
        SettingSliderRow(
          label: '行高',
          value: settings.lineHeight,
          min: 1,
          max: 3,
          divisions: 20,
          onChanged: settingsNotifier.setLineHeight,
        ),
        const SizedBox(height: 16),

        // 页边距
        SettingSliderRow(
          label: '页边距',
          value: settings.horizontalPadding,
          min: 8,
          max: 64,
          divisions: 14,
          valueLabel: '${settings.horizontalPadding.toInt()}',
          onChanged: settingsNotifier.setHorizontalPadding,
        ),
        const SizedBox(height: 24),

        // 阅读主题
        const SettingSectionTitle(title: '阅读主题'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: BookReaderTheme.values
                .map(
                  (theme) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _buildThemeOption(
                      theme: theme,
                      isSelected: settings.theme == theme,
                      onTap: () => settingsNotifier.setTheme(theme),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 24),

        // 其他设置
        const SettingSectionTitle(title: '其他设置'),
        SettingSwitchRow(
          title: '屏幕常亮',
          value: settings.keepScreenOn,
          onChanged: (value) {
            settingsNotifier.setKeepScreenOn(value: value);
            if (value) {
              WakelockPlus.enable();
            } else {
              WakelockPlus.disable();
            }
          },
        ),
        SettingSwitchRow(
          title: '显示进度',
          value: settings.showProgress,
          onChanged: (value) => settingsNotifier.setShowProgress(value: value),
        ),
      ],
    );
  }

  Widget _buildThemeOption({
    required BookReaderTheme theme,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.backgroundColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? Colors.grey.shade600 : Colors.grey.shade300),
                width: isSelected ? 3 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                'Aa',
                style: TextStyle(
                  color: theme.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            theme.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? Colors.white70 : Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部控制栏按钮（与 Foliate 阅读器一致）
class _BottomBarButton extends StatelessWidget {
  const _BottomBarButton({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = Colors.white;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
