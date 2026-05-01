import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/network/http_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/core/widgets/keyboard_shortcuts.dart';
import 'package:my_nas/features/book/data/services/book_content_processor.dart';
import 'package:my_nas/features/book/data/services/book_file_cache_service.dart';
import 'package:my_nas/features/book/data/services/mobi_parser_service.dart';
import 'package:my_nas/features/book/data/services/progressive_pagination.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/book/presentation/pages/ebook_reader_page.dart';
import 'package:my_nas/features/book/presentation/widgets/webview_book_reader.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/features/reading/presentation/providers/reader_settings_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/providers/bottom_nav_visibility_provider.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';
import 'package:my_nas/shared/widgets/lottie_loading.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';
import 'package:my_nas/shared/widgets/reader_settings_sheet.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 阅读器状态
final txtReaderProvider =
    StateNotifierProvider.family<TxtReaderNotifier, TxtReaderState, BookItem>(
      (ref, book) => TxtReaderNotifier(book, ref),
    );

sealed class TxtReaderState {}

class TxtReaderLoading extends TxtReaderState {
  TxtReaderLoading({this.message = '加载中...'});

  final String message;
}

class TxtReaderLoaded extends TxtReaderState {
  TxtReaderLoaded({
    required this.content,
    this.htmlContent,
    this.scrollPosition = 0.0,
  });

  final String content;
  final String? htmlContent; // 原始 HTML 内容（用于 MOBI 等格式）
  final double scrollPosition;

  /// 是否有 HTML 内容可用
  bool get hasHtml => htmlContent != null && htmlContent!.isNotEmpty;

  TxtReaderLoaded copyWith({
    String? content,
    String? htmlContent,
    double? scrollPosition,
  }) => TxtReaderLoaded(
    content: content ?? this.content,
    htmlContent: htmlContent ?? this.htmlContent,
    scrollPosition: scrollPosition ?? this.scrollPosition,
  );
}

class TxtReaderError extends TxtReaderState {
  TxtReaderError(this.message);

  final String message;
}

/// MOBI/AZW3 转换为 EPUB 后需要重定向到 EPUB 阅读器
class TxtReaderRedirectToEpub extends TxtReaderState {
  TxtReaderRedirectToEpub(this.epubPath);

  final String epubPath;
}

class TxtReaderNotifier extends StateNotifier<TxtReaderState> {
  TxtReaderNotifier(this.book, this._ref) : super(TxtReaderLoading()) {
    loadBook();
  }

  final BookItem book;
  final Ref _ref;
  final ReadingProgressService _progressService = ReadingProgressService();
  final BookFileCacheService _cacheService = BookFileCacheService();

  /// 最大支持的文件大小 (50MB)
  static const int _maxFileSizeBytes = 50 * 1024 * 1024;

  /// 获取文件系统（如果有 sourceId）
  NasFileSystem? _getFileSystem() {
    if (book.sourceId == null) return null;
    final connections = _ref.read(activeConnectionsProvider);
    final connection = connections[book.sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      return null;
    }
    return connection.adapter.fileSystem;
  }

  Future<void> loadBook() async {
    state = TxtReaderLoading();

    try {
      // 检查文件大小
      if (book.size > _maxFileSizeBytes) {
        state = TxtReaderError(
          '文件过大 (${(book.size / 1024 / 1024).toStringAsFixed(1)} MB)\n'
          '最大支持 ${_maxFileSizeBytes ~/ 1024 ~/ 1024} MB 的文件\n\n'
          '建议使用 Calibre 将文件分割或转换为更小的格式',
        );
        return;
      }

      // 初始化缓存服务
      await _cacheService.init();

      String content;
      String? htmlContent;

      switch (book.format) {
        case BookFormat.txt:
          content = await _loadTxtBook();
        case BookFormat.epub:
          // EPUB/MOBI/AZW3 使用专门的 EbookReaderPage
          state = TxtReaderError('请使用电子书阅读器');
          return;
        case BookFormat.pdf:
          // PDF 使用专门的 PdfReaderPage
          state = TxtReaderError('请使用 PDF 阅读器');
          return;
        case BookFormat.mobi:
        case BookFormat.azw3:
          final result = await _loadMobiBook();
          // 检查是否转换为 EPUB
          if (result.epubPath != null) {
            state = TxtReaderRedirectToEpub(result.epubPath!);
            return;
          }
          content = result.content ?? '';
          htmlContent = result.htmlContent;
        case BookFormat.unknown:
          state = TxtReaderError('未知的电子书格式');
          return;
      }

      // 检查内容是否为空
      if (content.isEmpty && (htmlContent == null || htmlContent.isEmpty)) {
        state = TxtReaderError('文件内容为空或无法解析');
        return;
      }

      // 恢复阅读进度
      await _progressService.init();
      final itemId = _progressService.generateItemId(book.id, book.path);
      final progress = _progressService.getProgress(itemId);

      state = TxtReaderLoaded(
        content: content,
        htmlContent: htmlContent,
        scrollPosition: progress?.position ?? 0.0,
      );

      logger.i('图书加载完成: ${book.name}, 内容长度: ${content.length}, '
          'HTML: ${htmlContent?.length ?? 0}');
    } on Exception catch (e, st) {
      logger.e('加载图书失败', e, st);
      // 检查是否是内存相关错误
      final errorMsg = e.toString().toLowerCase();
      if (errorMsg.contains('memory') || errorMsg.contains('heap')) {
        state = TxtReaderError('内存不足，文件可能过大\n请尝试加载较小的文件');
      } else {
        state = TxtReaderError('加载失败: ${e.toString().replaceAll('Exception: ', '')}');
      }
    }
  }

  /// 从流中读取所有字节
  Future<Uint8List> _readStreamBytes(Stream<List<int>> stream) async {
    final chunks = <List<int>>[];
    await for (final chunk in stream) {
      chunks.add(chunk);
    }
    final totalLength = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final result = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }

  Future<String> _loadTxtBook() async {
    final uri = Uri.parse(book.url);
    List<int> bytes;

    // 优先使用流式加载（支持 SMB/WebDAV 等协议）
    final fileSystem = _getFileSystem();
    if (fileSystem != null) {
      state = TxtReaderLoading(message: '流式加载中...');
      final stream = await fileSystem.getFileStream(book.path);
      bytes = await _readStreamBytes(stream);
    } else if (uri.scheme == 'file') {
      // 本地文件
      final localFile = File(uri.toFilePath());
      if (!await localFile.exists()) {
        throw Exception('文件不存在');
      }
      bytes = await localFile.readAsBytes();
    } else if (uri.scheme == 'http' || uri.scheme == 'https') {
      // HTTP 远程文件
      final response = await InsecureHttpClient.get(uri);
      if (response.statusCode != 200) {
        throw Exception('加载失败: ${response.statusCode}');
      }
      bytes = response.bodyBytes;
    } else {
      throw Exception('不支持的协议: ${uri.scheme}');
    }

    // 尝试检测编码
    String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      // 尝试 GBK/GB2312
      content = _decodeGbk(bytes);
    }

    return content;
  }

  String _decodeGbk(List<int> bytes) => String.fromCharCodes(bytes);

  /// 加载 MOBI/AZW3 电子书
  Future<MobiParseResult> _loadMobiBook() async {
    Uint8List bytes;

    // 检查是否有缓存
    final cachedFile = await _cacheService.getCachedFile(
      book.sourceId,
      book.path,
    );

    if (cachedFile != null) {
      state = TxtReaderLoading(message: '使用缓存...');
      bytes = await cachedFile.readAsBytes();
      logger.i('MOBI 使用缓存: ${cachedFile.path}');
    } else {
      // 需要下载文件
      final uri = Uri.parse(book.url);

      final fileSystem = _getFileSystem();
      if (fileSystem != null) {
        state = TxtReaderLoading(message: '加载文件中...');
        final stream = await fileSystem.getFileStream(book.path);
        bytes = await _readStreamBytes(stream);
      } else if (uri.scheme == 'file') {
        final localFile = File(uri.toFilePath());
        if (!await localFile.exists()) {
          throw Exception('文件不存在');
        }
        bytes = await localFile.readAsBytes();
      } else if (uri.scheme == 'http' || uri.scheme == 'https') {
        state = TxtReaderLoading(message: '下载中...');
        final response = await InsecureHttpClient.get(uri);
        if (response.statusCode != 200) {
          throw Exception('加载失败: ${response.statusCode}');
        }
        bytes = response.bodyBytes;
      } else {
        throw Exception('不支持的协议: ${uri.scheme}');
      }

      // 保存到缓存
      state = TxtReaderLoading(message: '缓存文件...');
      await _cacheService.saveToCache(book.sourceId, book.path, bytes);
    }

    // 使用 MOBI 解析器
    state = TxtReaderLoading(message: '解析中...');
    final parser = MobiParserService();
    final fileName = path.basename(book.path);
    final result = await parser.parse(bytes, fileName);

    if (!result.success) {
      throw Exception(result.error ?? '解析失败');
    }

    return result;
  }

  void setScrollPosition(double position) {
    final current = state;
    if (current is TxtReaderLoaded) {
      state = current.copyWith(scrollPosition: position);
    }
  }

  /// 更新清理后的 HTML 内容
  void updateCleanedHtml(String cleanedHtml) {
    final current = state;
    if (current is TxtReaderLoaded) {
      state = current.copyWith(htmlContent: cleanedHtml);
    }
  }

  Future<void> saveProgress(double position, double maxPosition) async {
    final current = state;
    if (current is TxtReaderLoaded) {
      final itemId = _progressService.generateItemId(book.id, book.path);
      await _progressService.saveProgress(
        ReadingProgress(
          itemId: itemId,
          itemType: 'txt',
          position: position,
          totalPositions: maxPosition.toInt(),
          lastReadAt: DateTime.now(),
        ),
      );
    }
  }
}

class BookReaderPage extends ConsumerStatefulWidget {
  const BookReaderPage({required this.book, super.key});

  final BookItem book;

  @override
  ConsumerState<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends ConsumerState<BookReaderPage> {
  bool _showControls = false;
  bool _showToc = false;
  bool _showMoreMenu = false; // 更多菜单
  List<BookChapter> _chapters = [];
  String _currentChapterTitle = '';
  final ScrollController _scrollController = ScrollController();

  // 分页相关
  PageController? _pageController;
  List<String> _pages = []; // 分页后的内容 (用于旧模式)
  Map<int, int> _chapterPageMap = {}; // 章节索引 -> 页码映射
  int _currentPage = 0;
  int _totalPages = 1;
  bool _isPaginationReady = false;
  bool _isProcessing = false; // 内容处理中
  bool _isContentProcessed = false; // 内容是否已处理完成
  bool _isScrollPositionRestored = false; // 滚动位置是否已恢复

  // WebView 阅读器相关
  final GlobalKey<WebViewBookReaderState> _webViewReaderKey = GlobalKey();
  final bool _useWebViewRenderer = true; // 使用 WebView 渲染器 (更精确的分页)
  bool _webViewPaginationReady = false; // WebView 分页是否已准备就绪

  // 状态栏相关
  final Battery _battery = Battery();
  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.unknown;
  String _currentTime = '';
  Timer? _timeTimer;

  @override
  void initState() {
    super.initState();
    // 隐藏原生 Tab Bar（iOS 玻璃风格）
    NativeTabBarService.instance.setTabBarVisible(false);
    // 隐藏 Flutter 导航栏（经典风格）
    BottomNavVisibilityNotifier.instance?.hide();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initWakelock();
    _scrollController.addListener(_onScroll);
    _initStatusBar();
  }

  /// 初始化状态栏（电池和时间）
  Future<void> _initStatusBar() async {
    // 初始化时间
    _updateTime();
    // 每分钟更新一次时间
    _timeTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _updateTime(),
    );

    // 初始化电池信息
    // 注意：battery_plus 在某些 iOS 版本可能返回错误的类型（String 而不是 int）
    // 使用 catch Object 来捕获所有类型的错误（包括 TypeError）
    try {
      _batteryLevel = await _safeBatteryLevel();
      _batteryState = await _battery.batteryState;
      if (mounted) setState(() {});

      // 监听电池状态变化
      _battery.onBatteryStateChanged.listen((state) {
        if (mounted) {
          setState(() => _batteryState = state);
          _safeBatteryLevel().then((level) {
            if (mounted) setState(() => _batteryLevel = level);
          });
        }
      });
    // ignore: avoid_catches_without_on_clauses
    } catch (e, st) {
      // 某些平台可能不支持电池API，或者存在类型转换问题
      // 使用裸 catch 是因为需要捕获 TypeError（不是 Exception 的子类）
      logger.w('无法获取电池信息: $e $st');
    }
  }

  /// 安全获取电池电量，处理 iOS 平台可能的类型转换错误
  Future<int> _safeBatteryLevel() async {
    try {
      return await _battery.batteryLevel;
    // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      // battery_plus 在某些 iOS 版本可能返回 String 而不是 int
      // 导致 "type 'String' is not a subtype of type 'int?'" 错误
      // 使用裸 catch 是因为需要捕获 TypeError（不是 Exception 的子类）
      logger.w('获取电池电量时出现类型错误: $e');
      return -1; // 返回 -1 表示未知
    }
  }

  void _updateTime() {
    if (mounted) {
      setState(() {
        _currentTime = DateFormat('HH:mm').format(DateTime.now());
      });
    }
  }

  Future<void> _initWakelock() async {
    final settings = ref.read(bookReaderSettingsProvider);
    if (settings.keepScreenOn) {
      await WakelockPlus.enable();
    }
  }

  void _onScroll() {
    // 保存滚动位置
    if (_scrollController.hasClients) {
      final position = _scrollController.position.pixels;
      final maxPosition = _scrollController.position.maxScrollExtent;
      ref
          .read(txtReaderProvider(widget.book).notifier)
          .setScrollPosition(position);
      // 定期保存进度
      if (position % 500 < 10) {
        ref
            .read(txtReaderProvider(widget.book).notifier)
            .saveProgress(position, maxPosition);
      }
      // 更新当前章节标题
      _updateCurrentChapter(position, maxPosition);
    }
  }

  /// 根据滚动位置更新当前章节标题
  void _updateCurrentChapter(double position, double maxPosition) {
    if (_chapters.isEmpty || maxPosition <= 0) return;

    final state = ref.read(txtReaderProvider(widget.book));
    if (state is! TxtReaderLoaded || !state.hasHtml) return;

    final totalLength = state.htmlContent!.length.toDouble();

    // 找到当前位置对应的章节
    String? currentTitle;
    for (var i = _chapters.length - 1; i >= 0; i--) {
      final chapterPosition = _chapters[i].offset / totalLength * maxPosition;
      if (position >= chapterPosition - 50) {
        currentTitle = _chapters[i].title;
        break;
      }
    }

    if (currentTitle != null && currentTitle != _currentChapterTitle) {
      setState(() {
        _currentChapterTitle = currentTitle!;
      });
    }
  }

  /// 异步处理内容（提取章节、移除目录）
  Future<void> _processContentAsync(String htmlContent) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // 对于大文件，限制处理内容以提高性能
      // 超过 500KB 的内容只提取章节，不移除目录
      final shouldSimplify = htmlContent.length > 500000;

      if (shouldSimplify) {
        logger.i('大文件内容，使用简化处理模式');
        // 简化处理：只提取前100个章节，不处理目录
        final chapters = _extractChaptersSimple(htmlContent, maxChapters: 100);

        if (!mounted) return;

        setState(() {
          _chapters = chapters;
          _isProcessing = false;
          _isContentProcessed = true;
        });

        logger.i('简化处理完成: ${chapters.length} 个章节');
        return;
      }

      // 在 Isolate 中处理内容，添加超时
      final result = await BookContentProcessor.processContent(htmlContent)
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          logger.w('内容处理超时，使用简化模式');
          // 超时时返回简化结果
          return ContentProcessResult(
            cleanedHtml: htmlContent,
            chapters: _extractChaptersSimple(htmlContent, maxChapters: 50),
          );
        },
      );

      if (!mounted) return;

      // 更新清理后的 HTML 内容
      ref
          .read(txtReaderProvider(widget.book).notifier)
          .updateCleanedHtml(result.cleanedHtml);

      setState(() {
        _chapters = result.chapters;
        _isProcessing = false;
        _isContentProcessed = true;
      });

      logger.i(
        '内容处理完成: ${result.chapters.length} 个章节, '
        '${result.removedTocSection ? "已移除目录页" : "无目录页"}',
      );
    } on Exception catch (e) {
      logger.e('内容处理失败', e);
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _isContentProcessed = true; // 即使失败也标记为已处理，避免重复
      });
    }
  }

  /// 简化的章节提取（用于大文件）
  List<BookChapter> _extractChaptersSimple(String content, {int maxChapters = 100}) {
    final chapters = <BookChapter>[];
    final pattern = RegExp(r'<h([1-3])[^>]*>([^<]{1,100})</h\1>', caseSensitive: false);

    for (final match in pattern.allMatches(content)) {
      if (chapters.length >= maxChapters) break;

      final level = int.tryParse(match.group(1) ?? '1') ?? 1;
      var title = match.group(2)?.trim() ?? '';

      // 移除内部 HTML 标签
      title = title.replaceAll(RegExp('<[^>]*>'), '').trim();

      if (title.isNotEmpty && title.length < 80) {
        chapters.add(BookChapter(
          title: title,
          offset: match.start,
          level: level,
        ));
      }
    }

    return chapters;
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _pageController?.dispose();
    _timeTimer?.cancel();
    // 恢复导航栏可见性（通过 Provider 引用计数，由 MainScaffold 决定实际状态）
    BottomNavVisibilityNotifier.instance?.show();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (!_showControls) {
        _showToc = false;
        _showMoreMenu = false;
      }
    });
  }

  /// 快速切换夜间模式
  void _toggleNightMode() {
    final settings = ref.read(bookReaderSettingsProvider);
    final currentTheme = settings.theme;

    // 在浅色和深色主题之间切换
    final newTheme = currentTheme == BookReaderTheme.light ||
            currentTheme == BookReaderTheme.sepia ||
            currentTheme == BookReaderTheme.green
        ? BookReaderTheme.dark
        : BookReaderTheme.light;

    ref.read(bookReaderSettingsProvider.notifier).setTheme(newTheme);
  }

  /// 跳转到章节
  void _jumpToChapter(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= _chapters.length) return;

    final chapter = _chapters[chapterIndex];
    final state = ref.read(txtReaderProvider(widget.book));
    final settings = ref.read(bookReaderSettingsProvider);

    // 判断是否使用分页模式（非连续滚动模式时使用分页）
    final usePageMode =
        state is TxtReaderLoaded &&
        state.hasHtml &&
        settings.pageTurnMode != BookPageTurnMode.slide;

    // 判断是否使用 WebView 渲染器
    final useWebView = _useWebViewRenderer &&
        state is TxtReaderLoaded &&
        state.hasHtml &&
        usePageMode;

    if (useWebView && _webViewPaginationReady && _totalPages > 0) {
      // WebView 分页模式：根据章节偏移量计算目标页码
      final totalLength = state.htmlContent!.length.toDouble();
      final progress = chapter.offset / totalLength;
      final targetPage = (progress * (_totalPages - 1)).round().clamp(0, _totalPages - 1);

      _webViewReaderKey.currentState?.goToPage(targetPage);

      setState(() {
        _currentPage = targetPage;
        _currentChapterTitle = chapter.title;
        _showToc = false;
      });
    } else if (usePageMode && _isPaginationReady && _pages.isNotEmpty) {
      // 传统分页模式：使用章节页码映射
      final targetPage = _chapterPageMap[chapterIndex] ?? 0;

      _pageController?.animateToPage(
        targetPage.clamp(0, _pages.length - 1),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );

      setState(() {
        _currentPage = targetPage;
        _currentChapterTitle = chapter.title;
        _showToc = false;
      });
    } else {
      // 滚动模式
      if (!_scrollController.hasClients) return;

      final maxScroll = _scrollController.position.maxScrollExtent;
      if (state is TxtReaderLoaded && state.hasHtml) {
        final totalLength = state.htmlContent!.length.toDouble();
        final targetPosition = (chapter.offset / totalLength * maxScroll).clamp(
          0.0,
          maxScroll,
        );

        _scrollController.animateTo(
          targetPosition,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }

      setState(() {
        _showToc = false;
      });
    }
  }

  /// 获取当前章节索引
  int _getCurrentChapterIndex() {
    if (_chapters.isEmpty) return 0;
    
    // 根据当前章节标题查找索引
    if (_currentChapterTitle.isNotEmpty) {
      for (var i = 0; i < _chapters.length; i++) {
        if (_chapters[i].title == _currentChapterTitle) {
          return i;
        }
      }
    }
    
    // 如果没有匹配的章节标题，根据当前页面位置估算
    final state = ref.read(txtReaderProvider(widget.book));
    final settings = ref.read(bookReaderSettingsProvider);
    
    final usePageMode = state is TxtReaderLoaded &&
        state.hasHtml &&
        settings.pageTurnMode != BookPageTurnMode.slide;
    final useWebView = _useWebViewRenderer &&
        state is TxtReaderLoaded &&
        state.hasHtml &&
        usePageMode;
    
    double progress = 0;
    if (useWebView && _totalPages > 0) {
      progress = _currentPage / _totalPages;
    } else if (usePageMode && _pages.isNotEmpty) {
      progress = _currentPage / _pages.length;
    } else if (_scrollController.hasClients && 
               _scrollController.position.maxScrollExtent > 0) {
      progress = _scrollController.position.pixels / 
                 _scrollController.position.maxScrollExtent;
    }
    
    // 根据进度找到对应的章节
    if (state is TxtReaderLoaded && state.hasHtml) {
      final totalLength = state.htmlContent!.length.toDouble();
      final currentOffset = progress * totalLength;
      
      for (var i = _chapters.length - 1; i >= 0; i--) {
        if (_chapters[i].offset <= currentOffset) {
          return i;
        }
      }
    }
    
    return 0;
  }

  void _showSettingsSheet() {
    showReaderSettingsSheet(
      context,
      title: '阅读设置',
      icon: Icons.auto_stories_rounded,
      iconColor: AppColors.info,
      contentBuilder: (context) => Consumer(
        builder: (context, ref, _) {
          final settings = ref.watch(bookReaderSettingsProvider);
          return _buildSettingsContent(settings);
        },
      ),
    );
  }

  /// 当前阅读位置（百分比 0..1，无法获取时为 0）
  double _currentReadPosition() {
    if (_pageController != null && _pageController!.hasClients) {
      final page = _pageController!.page ?? _currentPage.toDouble();
      final total = _pages.isNotEmpty ? _pages.length : (_totalPages > 0 ? _totalPages : 1);
      return total > 0 ? (page / total).clamp(0.0, 1.0) : 0.0;
    }
    if (_scrollController.hasClients) {
      final max = _scrollController.position.maxScrollExtent;
      if (max <= 0) return 0;
      return (_scrollController.position.pixels / max).clamp(0.0, 1.0);
    }
    return 0;
  }

  /// 跳转到书签位置
  Future<void> _jumpToBookmarkPosition(double position) async {
    if (_pageController != null && _pageController!.hasClients && _pages.isNotEmpty) {
      final target = (position * _pages.length).round().clamp(0, _pages.length - 1);
      await _pageController!.animateToPage(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }
    if (_scrollController.hasClients) {
      final max = _scrollController.position.maxScrollExtent;
      if (max <= 0) return;
      _scrollController.animateTo(
        (position * max).clamp(0.0, max),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// 显示书签管理 sheet
  Future<void> _showBookmarksSheet() async {
    final itemId = ReadingProgressService().generateItemId(
      widget.book.sourceId ?? 'local',
      widget.book.path,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final bookmarks = ReadingProgressService().getBookmarks(itemId)
            ..sort((a, b) => (b.createdAt ?? DateTime(0))
                .compareTo(a.createdAt ?? DateTime(0)));

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            builder: (_, scrollController) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.bookmark_rounded),
                      const SizedBox(width: 8),
                      const Text(
                        '书签',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('添加当前位置'),
                        onPressed: () async {
                          final position = _currentReadPosition();
                          final title = _currentChapterTitle.isNotEmpty
                              ? _currentChapterTitle
                              : '位置 ${(position * 100).toStringAsFixed(1)}%';
                          final bookmark = Bookmark(
                            id: DateTime.now().microsecondsSinceEpoch.toString(),
                            itemId: itemId,
                            title: title,
                            position: position,
                            createdAt: DateTime.now(),
                          );
                          try {
                            await ReadingProgressService().addBookmark(bookmark);
                            setSheetState(() {});
                            if (sheetContext.mounted) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                const SnackBar(
                                  content: Text('已添加书签'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            }
                          } catch (e, st) {
                            AppError.handle(e, st, 'bookReader.addBookmark');
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: bookmarks.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              '暂无书签\n点击右上角"添加当前位置"创建第一个书签',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: bookmarks.length,
                          itemBuilder: (_, index) {
                            final bm = bookmarks[index];
                            return Dismissible(
                              key: ValueKey(bm.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                color: Colors.redAccent,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: const Icon(Icons.delete, color: Colors.white),
                              ),
                              onDismissed: (_) async {
                                try {
                                  await ReadingProgressService()
                                      .deleteBookmark(itemId, bm.id);
                                  setSheetState(() {});
                                } catch (e, st) {
                                  AppError.handle(e, st, 'bookReader.deleteBookmark');
                                }
                              },
                              child: ListTile(
                                leading: const Icon(Icons.bookmark_rounded),
                                title: Text(
                                  bm.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${(bm.position * 100).toStringAsFixed(1)}%'
                                  '${bm.createdAt != null ? ' · ${DateFormat('MM-dd HH:mm').format(bm.createdAt!)}' : ''}',
                                ),
                                onTap: () async {
                                  Navigator.pop(sheetContext);
                                  await _jumpToBookmarkPosition(bm.position);
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 构建键盘快捷键映射
  Map<ShortcutKey, VoidCallback> _buildKeyboardShortcuts(
    BookReaderSettings settings,
    TxtReaderState readerState,
  ) {
    final usePageMode = settings.pageTurnMode != BookPageTurnMode.slide;
    // 判断是否使用 WebView 渲染（需要有 HTML 内容且使用 WebView 渲染器）
    final hasHtml = readerState is TxtReaderLoaded && readerState.hasHtml;
    final useWebView = _useWebViewRenderer && hasHtml && usePageMode;

    return {
      // 导航
      CommonShortcuts.previous: () => _handlePreviousPage(
            usePageMode: usePageMode,
            useWebView: useWebView,
          ),
      CommonShortcuts.next: () => _handleNextPage(
            usePageMode: usePageMode,
            useWebView: useWebView,
          ),
      CommonShortcuts.previousPage: () => _handlePreviousPage(
            usePageMode: usePageMode,
            useWebView: useWebView,
          ),
      CommonShortcuts.nextPage: () => _handleNextPage(
            usePageMode: usePageMode,
            useWebView: useWebView,
          ),
      CommonShortcuts.first: () {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      },
      CommonShortcuts.last: () {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      },

      // 控制栏切换
      CommonShortcuts.playPause: _toggleControls,
      CommonShortcuts.toggleControls: _toggleControls,

      // 夜间模式
      CommonShortcuts.mute: _toggleNightMode,

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
      title: '阅读快捷键',
      shortcuts: [
        (key: '←', description: '上一页'),
        (key: '→', description: '下一页'),
        (key: 'Page Up', description: '上一页'),
        (key: 'Page Down', description: '下一页'),
        (key: 'Home', description: '跳到开头'),
        (key: 'End', description: '跳到结尾'),
        (key: 'Space', description: '显示/隐藏控制栏'),
        (key: 'M', description: '切换夜间模式'),
        (key: ',', description: '打开设置'),
        (key: 'Esc', description: '返回'),
        (key: '?', description: '显示此帮助'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(txtReaderProvider(widget.book));
    final settings = ref.watch(bookReaderSettingsProvider);

    return KeyboardShortcuts(
      shortcuts: {
        ..._buildKeyboardShortcuts(settings, state),
        CommonShortcuts.help: _showKeyboardHelp,
      },
      child: Scaffold(
        backgroundColor: settings.theme.backgroundColor,
        body: switch (state) {
          TxtReaderLoading(:final message) => LottieLoading.book(message: message),
          TxtReaderError(:final message) => AppErrorWidget(
              message: message,
              onRetry: () =>
                  ref.read(txtReaderProvider(widget.book).notifier).loadBook(),
            ),
          TxtReaderRedirectToEpub(:final epubPath) => _buildEpubRedirect(epubPath),
          TxtReaderLoaded() => _buildReader(context, state, settings),
        },
      ),
    );
  }

  /// MOBI/AZW3 重定向到电子书阅读器
  /// 注：EbookReaderPage 使用 FoliateViewer，可直接读取 MOBI/AZW3，无需转换
  Widget _buildEpubRedirect(String epubPath) {
    // 自动跳转到电子书阅读器
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 替换当前页面为电子书阅读器
      // EbookReaderPage 使用原始书籍路径，可直接读取 MOBI/AZW3
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (context) => EbookReaderPage(book: widget.book),
        ),
      );
    });

    return const LottieLoading.book(
      message: '正在打开电子书阅读器...',
    );
  }

  Widget _buildReader(
    BuildContext context,
    TxtReaderLoaded state,
    BookReaderSettings settings,
  ) {
    final theme = settings.theme;

    // 首次加载时处理内容（提取章节、移除目录）
    if (state.hasHtml && !_isContentProcessed && !_isProcessing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _processContentAsync(state.htmlContent!);
      });
    }

    // 对于 MOBI/AZW3 等长文档，使用分页模式以提高性能
    final usePageMode =
        state.hasHtml && settings.pageTurnMode != BookPageTurnMode.slide;

    // 判断是否使用 WebView 渲染器
    final useWebView = _useWebViewRenderer && state.hasHtml && usePageMode;

    // 初始化分页（如果需要且尚未完成）- 仅在非 WebView 模式下使用传统分页
    // 需要等内容处理完成后再分页，因为分页依赖清理后的 HTML
    if (usePageMode &&
        !useWebView &&
        !_isPaginationReady &&
        state.hasHtml &&
        _isContentProcessed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _paginateContentAsync(state.htmlContent!, settings);
      });
    }

    return Stack(
      children: [
        // 阅读内容
        ColoredBox(
          color: theme.backgroundColor,
          child: SafeArea(
            child: Column(
              children: [
                // 固定顶栏 - 避免摄像头遮挡内容
                _buildFixedHeader(theme, settings),
                Expanded(
                  child: useWebView
                      ? _buildWebViewContent(state, settings)
                      : (usePageMode
                          ? _buildPagedContent(state, settings)
                          : _buildScrollContent(state, settings)),
                ),
                // 底部状态栏（进度、电池、时间）
                if (settings.showProgress)
                  _buildBottomStatusBar(theme, settings, usePageMode || useWebView, state),
              ],
            ),
          ),
        ),

        // 点击交互区域（始终显示，根据 tapToTurn 设置决定是否翻页）
        _buildTapZones(settings),

        // 顶部控制栏
        if (_showControls)
          Positioned(top: 0, left: 0, right: 0, child: _buildTopBar(context)),

        // 底部控制栏
        if (_showControls)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(context, settings),
          ),

        // 目录抽屉
        if (_showToc) _buildTocDrawer(context, settings),

        // 更多菜单面板
        if (_showMoreMenu) _buildMoreMenuPanel(context, settings),
      ],
    );
  }

  /// 滚动模式内容
  Widget _buildScrollContent(
    TxtReaderLoaded state,
    BookReaderSettings settings,
  ) {
    // 在第一帧渲染后恢复滚动位置
    if (!_isScrollPositionRestored && state.scrollPosition > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreScrollPosition(state.scrollPosition);
      });
    }

    return SingleChildScrollView(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: settings.horizontalPadding,
        vertical: settings.verticalPadding,
      ),
      child: _buildContent(state, settings),
    );
  }

  /// WebView 分页模式内容 - 使用 CSS Multi-column 实现精确分页
  Widget _buildWebViewContent(
    TxtReaderLoaded state,
    BookReaderSettings settings,
  ) {
    // 检查是否有有效的 HTML 内容
    if (!state.hasHtml) {
      // 没有 HTML 内容，回退到纯文本模式
      return _buildScrollContent(
        TxtReaderLoaded(
          content: state.content,
          scrollPosition: state.scrollPosition,
        ),
        settings,
      );
    }

    // 记录内容信息用于调试（不阻塞渲染）
    if (kDebugMode) {
      final htmlLength = state.htmlContent?.length ?? 0;
      logger.d('WebView 内容: $htmlLength 字符');
    }

    // 内容处理中时显示加载提示（仅在非 WebView 模式下阻塞）
    // WebView 模式可以直接渲染原始内容，不需要等待处理完成
    // 注：这个加载阻塞仅用于传统分页模式，因为传统分页需要清理后的 HTML
    // WebView 使用 CSS multi-column 分页，可以处理原始 HTML
    /*
    if (!_isContentProcessed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: settings.theme.textColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '正在处理内容...',
              style: TextStyle(
                color: settings.theme.textColor.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            // 添加跳过按钮，允许用户直接查看内容
            TextButton(
              onPressed: () {
                setState(() {
                  _isContentProcessed = true;
                });
              },
              child: Text(
                '跳过处理',
                style: TextStyle(
                  color: settings.theme.textColor.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      );
    }
    */

    // 计算顶部和底部栏的高度
    const topBarHeight = 40.0; // _buildFixedHeader 的大致高度
    const bottomBarHeight = 24.0; // _buildBottomStatusBar 的大致高度

    // 调试信息：显示内容长度
    final contentLength = state.htmlContent?.length ?? 0;
    logger.i('WebView 内容长度: $contentLength 字符');

    return Stack(
      children: [
        WebViewBookReader(
          key: _webViewReaderKey,
          htmlContent: state.htmlContent!,
          chapters: _chapters,
          settings: settings,
          initialPage: _currentPage,
          topBarHeight: topBarHeight,
          bottomBarHeight: bottomBarHeight,
          onPaginationReady: (info) {
            if (!mounted) return;
            setState(() {
              _webViewPaginationReady = true;
              _totalPages = info.totalPages;
              _currentPage = info.currentPage;
            });
            // 恢复阅读进度
            _restoreWebViewPageProgress();
          },
          onPageChanged: (page) {
            if (!mounted) return;
            setState(() {
              _currentPage = page;
            });
            // 保存进度
            _savePageProgress(page);
          },
          onChapterChanged: (chapter) {
            if (!mounted) return;
            if (chapter != _currentChapterTitle) {
              setState(() {
                _currentChapterTitle = chapter;
              });
            }
          },
        ),
      ],
    );
  }

  /// 恢复 WebView 分页进度
  void _restoreWebViewPageProgress() {
    final itemId = ReadingProgressService().generateItemId(
      widget.book.sourceId ?? 'local',
      widget.book.path,
    );
    final progress = ReadingProgressService().getProgress(itemId);
    if (progress != null && _totalPages > 1) {
      final targetPage = progress.position.toInt().clamp(0, _totalPages - 1);
      if (targetPage > 0) {
        // 延迟跳转，确保 WebView 已准备就绪
        Future.delayed(const Duration(milliseconds: 200), () {
          _webViewReaderKey.currentState?.goToPage(targetPage);
        });
      }
    }
  }

  /// 恢复滚动位置
  void _restoreScrollPosition(double savedPosition) {
    if (_isScrollPositionRestored) return;
    _isScrollPositionRestored = true;

    // 等待内容完全渲染后再恢复
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll <= 0) return;

      // savedPosition 是百分比位置 (0-1)，需要转换为实际像素
      final targetPosition = (savedPosition * maxScroll).clamp(0.0, maxScroll);

      _scrollController.jumpTo(targetPosition);
      logger.d('恢复滚动位置: $savedPosition -> $targetPosition px');
    });
  }

  /// 分页模式内容 - 用于 MOBI/AZW3 等长文档，提高性能
  Widget _buildPagedContent(
    TxtReaderLoaded state,
    BookReaderSettings settings,
  ) {
    // 如果分页尚未完成，显示加载中
    if (!_isPaginationReady || _pages.isEmpty) {
      return LottieLoading.book(
        message: '正在分页...',
      );
    }

    _pageController ??= PageController(initialPage: _currentPage);

    // 根据翻页模式选择不同的翻页效果
    final pageMode = settings.pageTurnMode;

    // 无动画模式 - 使用 physics: NeverScrollableScrollPhysics() 但仍响应按钮
    if (pageMode == BookPageTurnMode.none) {
      return PageView.builder(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _pages.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) => _buildPageItem(index, settings),
      );
    }

    // 滑动/仿真/覆盖模式 - 使用自定义动画
    return PageView.builder(
      controller: _pageController,
      itemCount: _pages.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) => AnimatedBuilder(
        animation: _pageController!,
        builder: (context, child) {
          // 计算当前页面的位置偏移
          double pageOffset = 0;
          if (_pageController!.position.haveDimensions) {
            pageOffset = _pageController!.page! - index;
          }

          // 根据翻页模式应用不同的变换
          return _buildAnimatedPage(
            index: index,
            settings: settings,
            pageOffset: pageOffset,
            pageMode: pageMode,
          );
        },
      ),
    );
  }

  /// 页面切换回调
  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
      // 更新当前章节标题
      _updateChapterFromPage(page);
    });
    // 保存进度
    _savePageProgress(page);
  }

  /// 构建页面内容项
  Widget _buildPageItem(int index, BookReaderSettings settings) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: settings.horizontalPadding,
          vertical: settings.verticalPadding,
        ),
        // 使用 SingleChildScrollView 确保内容超出时可以滚动
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: _buildPageContent(_pages[index], settings),
        ),
      );

  /// 构建带动画的页面
  Widget _buildAnimatedPage({
    required int index,
    required BookReaderSettings settings,
    required double pageOffset,
    required BookPageTurnMode pageMode,
  }) {
    final theme = settings.theme;
    final pageWidget = _buildPageItem(index, settings);

    switch (pageMode) {
      case BookPageTurnMode.scroll:
        // 翻页模式 - 标准的水平滑动
        return pageWidget;

      case BookPageTurnMode.simulation:
        // 仿真翻页 - 模拟翻书效果（通过透视变换）
        final rotateY = pageOffset.clamp(-1.0, 1.0) * 0.5;
        return Transform(
          alignment: pageOffset >= 0 ? Alignment.centerLeft : Alignment.centerRight,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001) // 透视效果
            ..rotateY(rotateY),
          child: pageWidget,
        );

      case BookPageTurnMode.cover:
        // 覆盖翻页 - 新页面覆盖旧页面
        if (pageOffset <= 0) {
          // 当前页或下一页
          return Transform.translate(
            offset: Offset(
              pageOffset * MediaQuery.of(context).size.width,
              0,
            ),
            child: pageWidget,
          );
        } else {
          // 上一页 - 保持不动，被覆盖
          return ColoredBox(
            color: theme.backgroundColor,
            child: pageWidget,
          );
        }

      case BookPageTurnMode.slide:
      case BookPageTurnMode.none:
        // 滚动模式和无动画模式不应该到达这里（非分页模式）
        return pageWidget;
    }
  }

  /// 构建单页内容
  Widget _buildPageContent(String pageHtml, BookReaderSettings settings) {
    final theme = settings.theme;
    return Html(
      data: pageHtml,
      style: _buildHtmlStyles(settings, theme),
      onCssParseError: (css, messages) {
        // 忽略 CSS 解析错误，返回 null 使用默认样式
        logger.d('CSS 解析错误: $css');
        return null;
      },
    );
  }

  /// 渐进式分页（使用新的分页算法）
  Future<void> _paginateContentAsync(
    String htmlContent,
    BookReaderSettings settings,
  ) async {
    if (_isPaginationReady) return;

    try {
      logger.i('开始渐进式分页...');

      // 第一阶段: 快速估算分页
      final quickResult = await ProgressivePagination.quickPaginate(
        htmlContent: htmlContent,
        chapters: _chapters,
        context: context,
        settings: settings,
      );

      if (!mounted) return;

      // 立即显示快速分页结果
      setState(() {
        _pages = quickResult.pages;
        _chapterPageMap = quickResult.chapterPageMap;
        _isPaginationReady = true;
        // 恢复之前的页码进度
        _restorePageProgress();
      });

      logger.i('快速分页完成: ${quickResult.pages.length} 页');

      // 第二阶段(可选): 后台优化分页
      // 注释掉以提高性能,如需要可取消注释
      /*
      logger.i('开始后台优化分页...');
      final refinedResult = await ProgressivePagination.refinePagination(
        initialResult: quickResult,
        context: context,
        settings: settings,
        onProgress: (progress) {
          logger.d('优化进度: ${(progress * 100).toStringAsFixed(0)}%');
        },
      );

      if (!mounted) return;

      setState(() {
        _pages = refinedResult.pages;
        _chapterPageMap = refinedResult.chapterPageMap;
        // 保持当前页码位置
        _currentPage = _currentPage.clamp(0, _pages.length - 1);
      });

      logger.i('分页优化完成: ${quickResult.pages.length} -> ${refinedResult.pages.length} 页');
      */
    } on Exception catch (e, st) {
      logger.e('分页失败', e, st);
      // 失败时使用整个内容作为单页
      setState(() {
        _pages = [htmlContent];
        _isPaginationReady = true;
      });
    }
  }

  /// 保存分页进度
  Future<void> _savePageProgress(int page) async {
    final state = ref.read(txtReaderProvider(widget.book));
    if (state is! TxtReaderLoaded) return;

    final itemId = ReadingProgressService().generateItemId(
      widget.book.sourceId ?? 'local',
      widget.book.path,
    );
    await ReadingProgressService().saveProgress(
      ReadingProgress(
        itemId: itemId,
        itemType: 'txt',
        position: page.toDouble(),
        totalPositions: _pages.length,
        lastReadAt: DateTime.now(),
      ),
    );
  }

  /// 恢复分页进度
  void _restorePageProgress() {
    final itemId = ReadingProgressService().generateItemId(
      widget.book.sourceId ?? 'local',
      widget.book.path,
    );
    final progress = ReadingProgressService().getProgress(itemId);
    if (progress != null && _pages.isNotEmpty) {
      _currentPage = progress.position.toInt().clamp(0, _pages.length - 1);
      _pageController?.jumpToPage(_currentPage);
    }
  }

  /// 从页码更新当前章节
  void _updateChapterFromPage(int page) {
    if (_chapters.isEmpty || _pages.isEmpty) return;

    // 计算当前进度百分比
    final progress = page / _pages.length;

    // 找到对应的章节
    String? title;
    for (var i = _chapters.length - 1; i >= 0; i--) {
      if (_chapters[i].offset <= progress) {
        title = _chapters[i].title;
        break;
      }
    }

    if (title != null && title != _currentChapterTitle) {
      setState(() {
        _currentChapterTitle = title!;
      });
    }
  }

  /// 获取分页进度文本
  String _getPageProgressText() {
    // WebView 分页模式
    if (_webViewPaginationReady && _totalPages > 0) {
      return '${_currentPage + 1} / $_totalPages';
    }
    // 传统分页模式
    if (_pages.isEmpty) return '';
    return '${_currentPage + 1} / ${_pages.length}';
  }

  /// 构建底部状态栏（进度、电池、时间）
  Widget _buildBottomStatusBar(
    BookReaderTheme theme,
    BookReaderSettings settings,
    bool usePageMode,
    TxtReaderLoaded state,
  ) {
    final textStyle = TextStyle(
      color: theme.textColor.withValues(alpha: 0.5),
      fontSize: 10,
    );

    return Container(
      padding: EdgeInsets.only(
        top: 2,
        bottom: 8,
        left: settings.horizontalPadding,
        right: settings.horizontalPadding,
      ),
      color: theme.backgroundColor,
      child: Row(
        children: [
          // 进度
          Text(
            usePageMode ? _getPageProgressText() : _getProgressText(state),
            style: textStyle,
          ),
          const Spacer(),
          // 电池图标和电量
          _buildBatteryIndicator(theme),
          const SizedBox(width: 6),
          // 时间
          Text(_currentTime, style: textStyle),
        ],
      ),
    );
  }

  /// 构建电池指示器
  Widget _buildBatteryIndicator(BookReaderTheme theme) {
    final color = theme.textColor.withValues(alpha: 0.5);
    final isCharging = _batteryState == BatteryState.charging;

    // 根据电量选择图标
    IconData batteryIcon;
    if (isCharging) {
      batteryIcon = Icons.battery_charging_full_rounded;
    } else if (_batteryLevel >= 90) {
      batteryIcon = Icons.battery_full_rounded;
    } else if (_batteryLevel >= 70) {
      batteryIcon = Icons.battery_6_bar_rounded;
    } else if (_batteryLevel >= 50) {
      batteryIcon = Icons.battery_5_bar_rounded;
    } else if (_batteryLevel >= 30) {
      batteryIcon = Icons.battery_3_bar_rounded;
    } else if (_batteryLevel >= 15) {
      batteryIcon = Icons.battery_2_bar_rounded;
    } else {
      batteryIcon = Icons.battery_1_bar_rounded;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(batteryIcon, size: 12, color: color),
        const SizedBox(width: 2),
        Text('$_batteryLevel%', style: TextStyle(color: color, fontSize: 10)),
      ],
    );
  }

  /// 构建固定顶栏，显示返回按钮和书名（左对齐）
  Widget _buildFixedHeader(BookReaderTheme theme, BookReaderSettings settings) {
    // 显示当前章节标题，如果没有则显示书名
    final displayTitle = _currentChapterTitle.isNotEmpty
        ? _currentChapterTitle
        : widget.book.displayName;

    return Container(
      padding: EdgeInsets.only(
        left: 4,
        right: settings.horizontalPadding,
        top: 4,
        bottom: 4,
      ),
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: theme.textColor.withValues(alpha: 0.1),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // 返回按钮
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.arrow_back_ios_rounded,
                size: 18,
                color: theme.textColor.withValues(alpha: 0.6),
              ),
            ),
          ),
          // 书名（左对齐）
          Expanded(
            child: Text(
              displayTitle,
              style: TextStyle(
                color: theme.textColor.withValues(alpha: 0.6),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建目录抽屉
  Widget _buildTocDrawer(BuildContext context, BookReaderSettings settings) {
    final theme = settings.theme;
    final isDark =
        theme == BookReaderTheme.dark || theme == BookReaderTheme.black;

    return Positioned(
      top: 0,
      bottom: 0,
      left: 0,
      child: GestureDetector(
        onTap: () {}, // 防止点击穿透
        child: Container(
          width: MediaQuery.of(context).size.width * 0.75,
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade200,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '目录',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                        onPressed: () => setState(() => _showToc = false),
                      ),
                    ],
                  ),
                ),
                // 章节列表
                Expanded(
                  child: _chapters.isEmpty
                      ? Center(
                          child: Text(
                            '暂无目录',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.grey[500]
                                  : Colors.grey[600],
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _chapters.length,
                          itemBuilder: (context, index) {
                            final chapter = _chapters[index];
                            return ListTile(
                              title: Text(
                                chapter.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              onTap: () => _jumpToChapter(index),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(TxtReaderLoaded state, BookReaderSettings settings) {
    // 如果有 HTML 内容，使用 flutter_html 渲染
    if (state.hasHtml) {
      return _buildHtmlContent(state.htmlContent!, settings);
    }

    // 否则使用纯文本渲染
    return _buildTextContent(state.content, settings);
  }

  /// 使用 flutter_html 渲染 HTML 内容
  Widget _buildHtmlContent(String htmlContent, BookReaderSettings settings) {
    final theme = settings.theme;

    // 调试: 输出当前字体设置
    logger.d('渲染HTML内容 - 字体: ${settings.fontFamily ?? "系统默认"}, '
        '字号: ${settings.fontSize}, 行高: ${settings.lineHeight}');

    // 额外的颜色值清理（防止 flutter_html 解析崩溃）
    final cleanedHtml = _sanitizeHtmlColors(htmlContent);

    // 构建 HTML 样式
    final style = {
      'body': Style(
        fontSize: FontSize(settings.fontSize),
        lineHeight: LineHeight(settings.lineHeight),
        color: theme.textColor,
        fontFamily: settings.fontFamily,
        margin: Margins.zero,
        padding: HtmlPaddings.zero,
      ),
      'p': Style(
        margin: Margins.only(bottom: settings.paragraphSpacing * 16),
        textAlign: TextAlign.justify,
      ),
      'h1': Style(
        fontSize: FontSize(settings.fontSize * 1.5),
        fontWeight: FontWeight.bold,
        margin: Margins.only(top: 24, bottom: 16),
      ),
      'h2': Style(
        fontSize: FontSize(settings.fontSize * 1.3),
        fontWeight: FontWeight.bold,
        margin: Margins.only(top: 20, bottom: 12),
      ),
      'h3': Style(
        fontSize: FontSize(settings.fontSize * 1.15),
        fontWeight: FontWeight.bold,
        margin: Margins.only(top: 16, bottom: 8),
      ),
      'h4': Style(
        fontSize: FontSize(settings.fontSize * 1.05),
        fontWeight: FontWeight.bold,
        margin: Margins.only(top: 12, bottom: 6),
      ),
      'h5': Style(
        fontSize: FontSize(settings.fontSize),
        fontWeight: FontWeight.bold,
        margin: Margins.only(top: 8, bottom: 4),
      ),
      'h6': Style(
        fontSize: FontSize(settings.fontSize * 0.9),
        fontWeight: FontWeight.bold,
        margin: Margins.only(top: 8, bottom: 4),
      ),
      'blockquote': Style(
        margin: Margins.symmetric(vertical: 12, horizontal: 16),
        padding: HtmlPaddings.only(left: 12),
        border: Border(
          left: BorderSide(
            color: theme.textColor.withValues(alpha: 0.3),
            width: 3,
          ),
        ),
        fontStyle: FontStyle.italic,
      ),
      'a': Style(color: Colors.blue, textDecoration: TextDecoration.underline),
      'img': Style(
        display: Display.none, // 隐藏图片，避免加载问题
      ),
      'ul': Style(
        margin: Margins.only(bottom: 12),
        padding: HtmlPaddings.only(left: 20),
      ),
      'ol': Style(
        margin: Margins.only(bottom: 12),
        padding: HtmlPaddings.only(left: 20),
      ),
      'li': Style(margin: Margins.only(bottom: 4)),
      'pre': Style(
        backgroundColor: theme.textColor.withValues(alpha: 0.05),
        padding: HtmlPaddings.all(12),
        margin: Margins.symmetric(vertical: 8),
      ),
      'code': Style(
        backgroundColor: theme.textColor.withValues(alpha: 0.05),
        fontFamily: 'monospace',
        fontSize: FontSize(settings.fontSize * 0.9),
      ),
    };

    // 使用 Builder 包装以捕获可能的渲染错误
    return Builder(
      builder: (context) {
        try {
          return Html(
            data: cleanedHtml,
            style: style,
            onLinkTap: (url, attributes, element) {
              if (url != null) {
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              }
            },
            onCssParseError: (css, messages) {
              // 忽略 CSS 解析错误，返回 null 使用默认样式
              logger.d('CSS 解析错误: $css');
              return null;
            },
          );
        } on FormatException catch (e) {
          logger.e('HTML 渲染格式错误', e);
          // 回退到纯文本渲染
          return _buildTextContent(
            cleanedHtml.replaceAll(RegExp('<[^>]*>'), ''),
            settings,
          );
        }
      },
    );
  }

  /// 清理 HTML 中的无效颜色值（防止 flutter_html 崩溃）
  String _sanitizeHtmlColors(String html) {
    if (!html.contains('color')) return html;

    var result = html;

    // 移除控制字符
    result = result.replaceAll(
      RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'),
      '',
    );

    // 替换所有 0x 开头的颜色值为安全的黑色
    result = result.replaceAll(
      // ignore: unnecessary_raw_strings - 保持正则表达式一致风格
      RegExp(r'0x[0-9a-fA-F]{1,8}', caseSensitive: false),
      '#000000',
    );

    // 移除不完整或无效的颜色声明
    result = result.replaceAllMapped(
      // ignore: unnecessary_raw_strings - 保持正则表达式清晰易读
      RegExp(r'''color\s*[:=]\s*["']?[^#\w][^;"'>]*["']?''', caseSensitive: false),
      (match) => '',
    );

    return result;
  }

  /// 构建 HTML 样式（复用于分页和滚动模式）
  Map<String, Style> _buildHtmlStyles(
    BookReaderSettings settings,
    BookReaderTheme theme,
  ) {
    // 调试: 确保分页模式下也正确应用字体
    logger.d('构建HTML样式 - 字体: ${settings.fontFamily ?? "系统默认"}');

    return {
      'body': Style(
        fontSize: FontSize(settings.fontSize),
        lineHeight: LineHeight(settings.lineHeight),
        color: theme.textColor,
        fontFamily: settings.fontFamily,
        margin: Margins.zero,
        padding: HtmlPaddings.zero,
      ),
    'p': Style(
      margin: Margins.only(bottom: settings.paragraphSpacing * 16),
      textAlign: TextAlign.justify,
    ),
    'h1': Style(
      fontSize: FontSize(settings.fontSize * 1.5),
      fontWeight: FontWeight.bold,
      margin: Margins.only(top: 24, bottom: 16),
    ),
    'h2': Style(
      fontSize: FontSize(settings.fontSize * 1.3),
      fontWeight: FontWeight.bold,
      margin: Margins.only(top: 20, bottom: 12),
    ),
    'h3': Style(
      fontSize: FontSize(settings.fontSize * 1.15),
      fontWeight: FontWeight.bold,
      margin: Margins.only(top: 16, bottom: 8),
    ),
    'h4': Style(
      fontSize: FontSize(settings.fontSize * 1.05),
      fontWeight: FontWeight.bold,
      margin: Margins.only(top: 12, bottom: 6),
    ),
    'h5': Style(
      fontSize: FontSize(settings.fontSize),
      fontWeight: FontWeight.bold,
      margin: Margins.only(top: 8, bottom: 4),
    ),
    'h6': Style(
      fontSize: FontSize(settings.fontSize * 0.9),
      fontWeight: FontWeight.bold,
      margin: Margins.only(top: 8, bottom: 4),
    ),
    'blockquote': Style(
      margin: Margins.symmetric(vertical: 12, horizontal: 16),
      padding: HtmlPaddings.only(left: 12),
      border: Border(
        left: BorderSide(
          color: theme.textColor.withValues(alpha: 0.3),
          width: 3,
        ),
      ),
      fontStyle: FontStyle.italic,
    ),
    'a': Style(color: Colors.blue, textDecoration: TextDecoration.underline),
    'img': Style(
      display: Display.none, // 隐藏图片，避免加载问题
    ),
    'ul': Style(
      margin: Margins.only(bottom: 12),
      padding: HtmlPaddings.only(left: 20),
    ),
    'ol': Style(
      margin: Margins.only(bottom: 12),
      padding: HtmlPaddings.only(left: 20),
    ),
    'li': Style(margin: Margins.only(bottom: 4)),
    'pre': Style(
      backgroundColor: theme.textColor.withValues(alpha: 0.05),
      padding: HtmlPaddings.all(12),
      margin: Margins.symmetric(vertical: 8),
    ),
    'code': Style(
      backgroundColor: theme.textColor.withValues(alpha: 0.05),
      fontFamily: 'monospace',
      fontSize: FontSize(settings.fontSize * 0.9),
    ),
  };
}

  /// 使用纯文本渲染
  Widget _buildTextContent(String content, BookReaderSettings settings) {
    final theme = settings.theme;

    // 智能段落检测
    final paragraphs = _splitIntoParagraphs(content);
    final children = <Widget>[];

    for (var i = 0; i < paragraphs.length; i++) {
      if (paragraphs[i].trim().isEmpty) continue;
      children.add(
        Padding(
          padding: EdgeInsets.only(
            bottom: i < paragraphs.length - 1
                ? settings.paragraphSpacing * 16
                : 0,
          ),
          child: SelectableText(
            paragraphs[i].trim(),
            style: TextStyle(
              fontSize: settings.fontSize,
              height: settings.lineHeight,
              color: theme.textColor,
              fontFamily: settings.fontFamily,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// 智能段落分割
  /// 支持多种段落格式：
  /// 1. 双换行分隔 (\n\n)
  /// 2. 中文段落缩进（以全角空格或两个空格开头）
  /// 3. 单换行但下一行有缩进
  List<String> _splitIntoParagraphs(String content) {
    // 首先尝试按双换行分割
    final doubleNewlineParagraphs = content.split(RegExp(r'\n\s*\n'));
    if (doubleNewlineParagraphs.length > 10) {
      // 如果有足够多的双换行段落，使用这种方式
      return doubleNewlineParagraphs;
    }

    // 否则尝试智能分割
    final lines = content.split('\n');
    final paragraphs = <String>[];
    final currentParagraph = StringBuffer();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmedLine = line.trim();

      if (trimmedLine.isEmpty) {
        // 空行表示段落结束
        if (currentParagraph.isNotEmpty) {
          paragraphs.add(currentParagraph.toString().trim());
          currentParagraph.clear();
        }
        continue;
      }

      // 检测是否是新段落的开始
      final isNewParagraph = _isNewParagraphStart(line, trimmedLine);

      if (isNewParagraph && currentParagraph.isNotEmpty) {
        // 保存当前段落，开始新段落
        paragraphs.add(currentParagraph.toString().trim());
        currentParagraph.clear();
      }

      if (currentParagraph.isNotEmpty) {
        currentParagraph.write(' ');
      }
      currentParagraph.write(trimmedLine);
    }

    // 添加最后一个段落
    if (currentParagraph.isNotEmpty) {
      paragraphs.add(currentParagraph.toString().trim());
    }

    return paragraphs.isEmpty ? [content] : paragraphs;
  }

  /// 检测是否是新段落的开始
  bool _isNewParagraphStart(String line, String trimmedLine) {
    // 1. 以全角空格开头（中文段落缩进）
    if (line.startsWith('\u3000') || line.startsWith('　')) {
      return true;
    }

    // 2. 以两个或更多空格开头
    if (line.startsWith('  ')) {
      return true;
    }

    // 3. 以章节标题开头（第X章、Chapter X 等）
    if (RegExp(
      r'^(第[一二三四五六七八九十百千万\d]+[章节回篇卷集部]|Chapter\s*\d+|CHAPTER\s*\d+)',
      caseSensitive: false,
    ).hasMatch(trimmedLine)) {
      return true;
    }

    // 4. 以数字序号开头（1. 2. 等）
    if (RegExp(r'^\d+[.、．]\s').hasMatch(trimmedLine)) {
      return true;
    }

    return false;
  }

  String _getProgressText(TxtReaderLoaded? state) {
    if (!_scrollController.hasClients) return '0%';
    final position = _scrollController.position.pixels;
    final maxPosition = _scrollController.position.maxScrollExtent;
    if (maxPosition <= 0) return '0%';
    final progress = (position / maxPosition * 100).clamp(0, 100);
    return '${progress.toStringAsFixed(0)}%';
  }

  Widget _buildTapZones(BookReaderSettings settings) => Positioned.fill(
      // 三区域交互:
      // - 左侧 25%: 上一页
      // - 中间 50%: 切换控制栏
      // - 右侧 25%: 下一页
      child: GestureDetector(
        onTapUp: (details) {
          final screenWidth = MediaQuery.of(context).size.width;
          final tapX = details.localPosition.dx;
          final ratio = tapX / screenWidth;

          final state = ref.read(txtReaderProvider(widget.book));
          final usePageMode = state is TxtReaderLoaded &&
              state.hasHtml &&
              settings.pageTurnMode != BookPageTurnMode.slide;
          final useWebView = _useWebViewRenderer &&
              state is TxtReaderLoaded &&
              state.hasHtml &&
              usePageMode;

          if (ratio < 0.25) {
            // 左侧区域 - 上一页
            _handlePreviousPage(usePageMode: usePageMode, useWebView: useWebView);
          } else if (ratio > 0.75) {
            // 右侧区域 - 下一页
            _handleNextPage(usePageMode: usePageMode, useWebView: useWebView);
          } else {
            // 中间区域 - 切换控制栏
            _toggleControls();
          }
        },
        behavior: HitTestBehavior.translucent,
        child: Container(),
      ),
    );

  /// 处理上一页操作
  void _handlePreviousPage({
    required bool usePageMode,
    required bool useWebView,
  }) {
    if (useWebView) {
      // WebView 分页模式
      _webViewReaderKey.currentState?.previousPage();
    } else if (usePageMode) {
      // 传统分页模式
      if (_pageController != null && _currentPage > 0) {
        _pageController!.previousPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } else {
      // 滚动模式
      if (_scrollController.hasClients) {
        final screenHeight = MediaQuery.of(context).size.height;
        _scrollController.animateTo(
          (_scrollController.offset - screenHeight * 0.8).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  /// 处理下一页操作
  void _handleNextPage({
    required bool usePageMode,
    required bool useWebView,
  }) {
    if (useWebView) {
      // WebView 分页模式
      _webViewReaderKey.currentState?.nextPage();
    } else if (usePageMode) {
      // 传统分页模式
      if (_pageController != null && _currentPage < _pages.length - 1) {
        _pageController!.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } else {
      // 滚动模式
      if (_scrollController.hasClients) {
        final screenHeight = MediaQuery.of(context).size.height;
        _scrollController.animateTo(
          (_scrollController.offset + screenHeight * 0.8).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  /// 构建底部操作按钮
  Widget _buildBottomActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool enabled = true,
  }) {
    final isEnabled = enabled && onPressed != null;
    return InkWell(
      onTap: isEnabled ? onPressed : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isEnabled ? Colors.white : Colors.white38,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isEnabled ? Colors.white : Colors.white38,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0.9),
          Colors.black.withValues(alpha: 0.6),
          Colors.transparent,
        ],
        stops: const [0.0, 0.7, 1.0],
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
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              tooltip: '返回',
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
            // 目录按钮
            IconButton(
              icon: const Icon(Icons.list, color: Colors.white),
              onPressed: _chapters.isNotEmpty
                  ? () => setState(() => _showToc = !_showToc)
                  : null,
              tooltip: '目录',
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildBottomBar(BuildContext context, BookReaderSettings settings) {
    final state = ref.read(txtReaderProvider(widget.book));
    final usePageMode =
        state is TxtReaderLoaded &&
        state.hasHtml &&
        settings.pageTurnMode != BookPageTurnMode.slide;
    final useWebView = _useWebViewRenderer &&
        state is TxtReaderLoaded &&
        state.hasHtml &&
        usePageMode;

    // 获取当前模式的总页数
    final effectiveTotalPages = useWebView ? _totalPages : _pages.length;
    final maxPageIndex = (effectiveTotalPages - 1).clamp(0, double.maxFinite.toInt());

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.9),
            Colors.black.withValues(alpha: 0.6),
            Colors.transparent,
          ],
          stops: const [0.0, 0.7, 1.0],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 进度条 - 槽式设计
              Row(
                children: [
                  // 上一章按钮
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                    onPressed: _chapters.isNotEmpty ? () => _jumpToChapter(_getCurrentChapterIndex() - 1) : null,
                    tooltip: '上一章',
                    iconSize: 28,
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 6,
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                        thumbColor: AppColors.primary,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                          elevation: 2,
                        ),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                        trackShape: const RoundedRectSliderTrackShape(),
                      ),
                      child: Slider(
                        value: (usePageMode || useWebView)
                            ? _currentPage.toDouble().clamp(0, maxPageIndex.toDouble())
                            : (_scrollController.hasClients
                                  ? (_scrollController.position.pixels /
                                            _scrollController
                                                .position
                                                .maxScrollExtent)
                                        .clamp(0.0, 1.0)
                                  : 0.0),
                        max: (usePageMode || useWebView)
                            ? maxPageIndex.toDouble().clamp(1, double.infinity)
                            : 1.0,
                        onChanged: (value) {
                          if (useWebView) {
                            // WebView 分页模式
                            final page = value.round().clamp(0, maxPageIndex);
                            _webViewReaderKey.currentState?.goToPage(page);
                            setState(() => _currentPage = page);
                          } else if (usePageMode && _pages.isNotEmpty) {
                            // 传统分页模式
                            final page = value.round().clamp(0, _pages.length - 1);
                            _pageController?.jumpToPage(page);
                            setState(() => _currentPage = page);
                          } else if (_scrollController.hasClients) {
                            // 滚动模式
                            final target =
                                value *
                                _scrollController.position.maxScrollExtent;
                            _scrollController.jumpTo(target);
                          }
                        },
                      ),
                    ),
                  ),
                  // 下一章按钮
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                    onPressed: _chapters.isNotEmpty ? () => _jumpToChapter(_getCurrentChapterIndex() + 1) : null,
                    tooltip: '下一章',
                    iconSize: 28,
                  ),
                ],
              ),
              // 功能按钮 - 重新设计为更实用的功能
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 目录
                  _buildBottomActionButton(
                    icon: Icons.list_rounded,
                    label: '目录',
                    enabled: _chapters.isNotEmpty,
                    onPressed: _chapters.isNotEmpty
                        ? () => setState(() {
                              _showToc = !_showToc;
                              _showMoreMenu = false;
                            })
                        : null,
                  ),
                  // 夜间模式切换
                  _buildBottomActionButton(
                    icon: settings.theme == BookReaderTheme.dark ||
                            settings.theme == BookReaderTheme.black
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    label: settings.theme == BookReaderTheme.dark ||
                            settings.theme == BookReaderTheme.black
                        ? '日间'
                        : '夜间',
                    onPressed: _toggleNightMode,
                  ),
                  // 阅读设置
                  _buildBottomActionButton(
                    icon: Icons.settings_rounded,
                    label: '设置',
                    onPressed: _showSettingsSheet,
                  ),
                  // 书签
                  _buildBottomActionButton(
                    icon: Icons.bookmark_outline_rounded,
                    label: '书签',
                    onPressed: _showBookmarksSheet,
                  ),
                  // 更多菜单
                  _buildBottomActionButton(
                    icon: Icons.more_horiz_rounded,
                    label: '更多',
                    onPressed: () => setState(() {
                      _showMoreMenu = !_showMoreMenu;
                      _showToc = false;
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsContent(BookReaderSettings settings) {
    final settingsNotifier = ref.read(bookReaderSettingsProvider.notifier);

    // 翻页方式选项
    const pageTurnModes = [
      (icon: Icons.swap_vert_rounded, label: '滚动'),
      (icon: Icons.swipe_rounded, label: '滑动'),
      (icon: Icons.auto_stories_rounded, label: '仿真'),
      (icon: Icons.layers_rounded, label: '覆盖'),
      (icon: Icons.article_rounded, label: '无动画'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 翻页方式
        const SettingSectionTitle(title: '翻页方式'),
        SettingPageTurnModePicker(
          modes: pageTurnModes,
          selectedIndex: settings.pageTurnMode.index,
          onSelect: (index) {
            settingsNotifier.setPageTurnMode(BookPageTurnMode.values[index]);
            // 重置分页状态 (传统模式和 WebView 模式)
            setState(() {
              // 传统分页
              _isPaginationReady = false;
              _pages = [];
              _pageController?.dispose();
              _pageController = null;
              // WebView 分页
              _webViewPaginationReady = false;
              _totalPages = 1;
              _currentPage = 0;
            });
          },
        ),
        const SizedBox(height: 24),

        // 字体选择 - 横向滑动
        SettingSectionTitle(
          title: '字体',
          trailing: AvailableFonts.getDisplayName(settings.fontFamily),
        ),
        SettingFontPicker(
          selectedFont: settings.fontFamily,
          onSelect: settingsNotifier.setFontFamily,
        ),
        const SizedBox(height: 24),

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

        // 段落间距
        SettingSliderRow(
          label: '段落间距',
          value: settings.paragraphSpacing,
          max: 3,
          divisions: 15,
          onChanged: settingsNotifier.setParagraphSpacing,
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

        // 主题
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

  /// 构建更多菜单面板
  Widget _buildMoreMenuPanel(BuildContext context, BookReaderSettings settings) {
    final isDark = settings.theme == BookReaderTheme.dark ||
        settings.theme == BookReaderTheme.black;

    final state = ref.read(txtReaderProvider(widget.book));
    final usePageMode = state is TxtReaderLoaded &&
        state.hasHtml &&
        settings.pageTurnMode != BookPageTurnMode.slide;
    final useWebView = _useWebViewRenderer &&
        state is TxtReaderLoaded &&
        state.hasHtml &&
        usePageMode;

    return Positioned(
      bottom: 140, // 在底部控制栏上方
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '更多功能',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: isDark ? Colors.white70 : Colors.black54,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _showMoreMenu = false),
                ),
              ],
            ),
            const Divider(),
            // 功能列表
            _buildMoreMenuItem(
              icon: Icons.first_page_rounded,
              label: '跳转到开头',
              isDark: isDark,
              onTap: () {
                if (useWebView) {
                  // WebView 分页模式
                  _webViewReaderKey.currentState?.goToFirstPage();
                  setState(() {
                    _currentPage = 0;
                    _showMoreMenu = false;
                  });
                } else if (usePageMode && _pageController != null) {
                  // 传统分页模式
                  _pageController!.jumpToPage(0);
                  setState(() {
                    _currentPage = 0;
                    _showMoreMenu = false;
                  });
                } else if (_scrollController.hasClients) {
                  // 滚动模式
                  _scrollController.jumpTo(0);
                  setState(() => _showMoreMenu = false);
                }
              },
            ),
            _buildMoreMenuItem(
              icon: Icons.last_page_rounded,
              label: '跳转到结尾',
              isDark: isDark,
              onTap: () {
                if (useWebView) {
                  // WebView 分页模式
                  _webViewReaderKey.currentState?.goToLastPage();
                  setState(() {
                    _currentPage = _totalPages - 1;
                    _showMoreMenu = false;
                  });
                } else if (usePageMode && _pageController != null && _pages.isNotEmpty) {
                  // 传统分页模式
                  _pageController!.jumpToPage(_pages.length - 1);
                  setState(() {
                    _currentPage = _pages.length - 1;
                    _showMoreMenu = false;
                  });
                } else if (_scrollController.hasClients) {
                  // 滚动模式
                  _scrollController.jumpTo(
                    _scrollController.position.maxScrollExtent,
                  );
                  setState(() => _showMoreMenu = false);
                }
              },
            ),
            _buildMoreMenuItem(
              icon: Icons.info_outline_rounded,
              label: '图书信息',
              isDark: isDark,
              onTap: () {
                setState(() => _showMoreMenu = false);
                _showBookInfo();
              },
            ),
            _buildMoreMenuItem(
              icon: Icons.refresh_rounded,
              label: '刷新内容',
              isDark: isDark,
              onTap: () {
                setState(() => _showMoreMenu = false);
                // 重新加载图书 - 通过重新初始化 notifier
                ref.invalidate(txtReaderProvider(widget.book));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('正在重新加载...'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 构建更多菜单项
  Widget _buildMoreMenuItem({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDark ? Colors.white70 : Colors.black54,
              size: 22,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );

  /// 显示图书信息
  void _showBookInfo() {
    final state = ref.read(txtReaderProvider(widget.book));
    final settings = ref.read(bookReaderSettingsProvider);
    final isDark = settings.theme == BookReaderTheme.dark ||
        settings.theme == BookReaderTheme.black;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: Text(
          '图书信息',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('书名', widget.book.displayName, isDark),
            _buildInfoRow(
              '格式',
              widget.book.path.split('.').last.toUpperCase(),
              isDark,
            ),
            _buildInfoRow(
              '大小',
              '${(widget.book.size / 1024 / 1024).toStringAsFixed(2)} MB',
              isDark,
            ),
            if (state is TxtReaderLoaded)
              _buildInfoRow(
                '字符数',
                NumberFormat('#,###').format(state.content.length),
                isDark,
              ),
            if (_chapters.isNotEmpty)
              _buildInfoRow('章节数', '${_chapters.length}', isDark),
            // 显示总页数 - 支持 WebView 和传统分页模式
            if (_webViewPaginationReady && _totalPages > 0)
              _buildInfoRow('总页数', '$_totalPages', isDark)
            else if (_pages.isNotEmpty)
              _buildInfoRow('总页数', '${_pages.length}', isDark),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '关闭',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建信息行
  Widget _buildInfoRow(String label, String value, bool isDark) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              '$label:',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
}
