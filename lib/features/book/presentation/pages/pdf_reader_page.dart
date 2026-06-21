import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/core/widgets/keyboard_shortcuts.dart';
import 'package:my_nas/features/book/data/services/book_file_cache_service.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/providers/bottom_nav_visibility_provider.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';
import 'package:my_nas/shared/utils/form_l10n.dart';
import 'package:my_nas/shared/widgets/lottie_loading.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// PDF 阅读器状态
final pdfReaderProvider =
    StateNotifierProvider.family<PdfReaderNotifier, PdfReaderState, BookItem>(
      (ref, book) => PdfReaderNotifier(book, ref),
    );

sealed class PdfReaderState {}

class PdfReaderLoading extends PdfReaderState {
  PdfReaderLoading({String? message, this.progress = 0.0})
      : message = message ?? appL10n.pdfReaderLoadingMessage;
  final String message;
  final double progress; // 0.0 - 1.0
}

class PdfReaderLoaded extends PdfReaderState {
  PdfReaderLoaded({
    required this.documentRef,
    this.filePath,
    this.currentPage = 1,
    this.totalPages = 0,
    this.isDarkMode = false,
    this.isStreaming = false,
  });

  /// PDF 文档引用（用于流式加载）
  final PdfDocumentRef documentRef;

  /// 本地文件路径（如果有缓存）
  final String? filePath;
  final int currentPage;
  final int totalPages;
  final bool isDarkMode;

  /// 是否正在流式加载
  final bool isStreaming;

  PdfReaderLoaded copyWith({
    PdfDocumentRef? documentRef,
    String? filePath,
    int? currentPage,
    int? totalPages,
    bool? isDarkMode,
    bool? isStreaming,
  }) => PdfReaderLoaded(
      documentRef: documentRef ?? this.documentRef,
      filePath: filePath ?? this.filePath,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      isStreaming: isStreaming ?? this.isStreaming,
    );
}

class PdfReaderError extends PdfReaderState {
  PdfReaderError(this.message);
  final String message;
}

class PdfReaderNotifier extends StateNotifier<PdfReaderState> {
  PdfReaderNotifier(this.book, this._ref) : super(PdfReaderLoading()) {
    _loadPdf();
  }

  final BookItem book;
  final Ref _ref;
  final ReadingProgressService _progressService = ReadingProgressService();
  final BookFileCacheService _cacheService = BookFileCacheService();

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


  Future<void> _loadPdf() async {
    try {
      state = PdfReaderLoading();

      // 初始化服务
      await _cacheService.init();
      await _progressService.init();

      // 恢复阅读进度
      final itemId = _progressService.generateItemId(book.id, book.path);
      final progress = _progressService.getProgress(itemId);
      final startPage = progress?.position.toInt() ?? 1;

      // 检查是否有缓存
      final cachedFile = await _cacheService.getCachedFile(
        book.sourceId,
        book.path,
      );

      if (cachedFile != null) {
        // 使用缓存文件
        state = PdfReaderLoading(message: appL10n.pdfReaderUsingCache);
        logger.i('PDF 使用缓存: ${cachedFile.path}');
        await _loadFromFile(cachedFile, startPage);
        return;
      }

      // 尝试流式加载（直接从 URL）
      final fileSystem = _getFileSystem();
      if (fileSystem != null) {
        await _loadFromUrl(fileSystem, startPage);
        return;
      }

      // 本地文件
      final uri = Uri.parse(book.url);
      if (uri.scheme == 'file') {
        final localFile = File(uri.toFilePath());
        if (!await localFile.exists()) {
          state = PdfReaderError(appL10n.pdfReaderFileNotFound);
          return;
        }
        await _loadFromFile(localFile, startPage);
        return;
      }

      // HTTP URL（无文件系统）
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        await _loadFromHttpUrl(uri, startPage);
        return;
      }

      state = PdfReaderError(appL10n.pdfReaderUnsupportedProtocol(uri.scheme));
    } on Exception catch (e, stackTrace) {
      logger.e('加载 PDF 失败', e, stackTrace);
      state = PdfReaderError(appL10n.pdfReaderLoadFailedMessage(e));
    }
  }

  /// 从本地文件加载
  Future<void> _loadFromFile(File file, int startPage) async {
    state = PdfReaderLoading(message: appL10n.pdfReaderParsingMessage);
    final documentRef = PdfDocumentRefFile(file.path);

    try {
      final document = await _waitForDocument(documentRef);

      state = PdfReaderLoaded(
        documentRef: documentRef,
        filePath: file.path,
        currentPage: startPage.clamp(1, document.pages.length),
        totalPages: document.pages.length,
      );
      logger.i('PDF 加载完成（缓存）: ${book.name}, ${document.pages.length} 页');
    } on TimeoutException catch (e) {
      logger.e('PDF 解析超时', e);
      state = PdfReaderError(appL10n.pdfReaderParseTimeoutMessage);
    } on Exception catch (e) {
      logger.e('PDF 解析失败', e);
      state = PdfReaderError(appL10n.pdfReaderParseFailedMessage(e));
    }
  }

  /// 从 NAS 加载 PDF
  /// 策略：边下载边显示，先加载前几页让用户可以开始阅读
  Future<void> _loadFromUrl(NasFileSystem fileSystem, int startPage) async {
    state = PdfReaderLoading(message: appL10n.pdfReaderConnectingMessage);

    try {
      logger.i('PDF 开始加载: ${book.path}');
      final stopwatch = Stopwatch()..start();

      final stream = await fileSystem.getFileStream(book.path);

      // 使用分块策略：收集足够数据后立即尝试解析
      final chunks = <List<int>>[];
      var totalBytes = 0;
      var hasTriedEarlyLoad = false;
      PdfDocumentRef? documentRef;

      await for (final chunk in stream) {
        chunks.add(chunk);
        totalBytes += chunk.length;

        final sizeMB = (totalBytes / 1024 / 1024).toStringAsFixed(1);
        state = PdfReaderLoading(message: appL10n.pdfReaderLoadingSizeMb(sizeMB));

        // 当收集到至少 500KB 数据时，尝试早期解析（PDF 头部通常足够显示第一页）
        if (!hasTriedEarlyLoad && totalBytes > 512 * 1024) {
          hasTriedEarlyLoad = true;
          // 尝试用已有数据解析，不阻塞继续下载
          try {
            final partialBytes = _mergeChunks(chunks, totalBytes);
            final tempRef = PdfDocumentRefData(
              partialBytes,
              sourceName: '${book.name}_partial',
            );
            final tempListenable = tempRef.resolveListenable();
            // 非阻塞检查
            if (tempListenable.document != null) {
              documentRef = tempRef;
              final doc = tempListenable.document!;
              state = PdfReaderLoaded(
                documentRef: documentRef,
                currentPage: startPage.clamp(1, doc.pages.length),
                totalPages: doc.pages.length,
                isStreaming: true,
              );
              logger.i('PDF 早期加载成功: ${doc.pages.length} 页 (已下载 $sizeMB MB)');
            }
          } on Exception catch (_) {
            // 早期解析失败，继续下载
          }
        }
      }

      stopwatch.stop();
      logger.i('PDF 下载完成: $totalBytes 字节, 耗时 ${stopwatch.elapsedMilliseconds}ms');

      // 合并所有数据块
      final bytes = _mergeChunks(chunks, totalBytes);

      // 保存到缓存（后台执行，不阻塞）
      AppError.fireAndForget(
        _cacheService.saveToCache(book.sourceId, book.path, bytes),
        action: 'pdfReader.saveToCache',
      );

      // 如果还没有成功加载，使用完整数据
      if (documentRef == null || state is PdfReaderLoading) {
        state = PdfReaderLoading(message: appL10n.pdfReaderParsingMessage);
        documentRef = PdfDocumentRefData(bytes, sourceName: book.name);
        final document = await _waitForDocument(documentRef);

        state = PdfReaderLoaded(
          documentRef: documentRef,
          currentPage: startPage.clamp(1, document.pages.length),
          totalPages: document.pages.length,
        );
        logger.i('PDF 完整加载完成: ${book.name}, ${document.pages.length} 页');
      } else {
        // 已经早期加载成功，用完整数据替换以确保所有页面可用
        final fullRef = PdfDocumentRefData(bytes, sourceName: book.name);
        final fullDoc = await _waitForDocument(fullRef);
        final currentState = state;
        if (currentState is PdfReaderLoaded) {
          state = currentState.copyWith(
            documentRef: fullRef,
            totalPages: fullDoc.pages.length,
            isStreaming: false,
          );
        }
        logger.i('PDF 替换为完整文档: ${fullDoc.pages.length} 页');
      }
    } on Exception catch (e, stackTrace) {
      logger.e('PDF 加载失败', e, stackTrace);
      state = PdfReaderError(appL10n.pdfReaderLoadFailedMessage(e));
    }
  }

  /// 合并数据块
  Uint8List _mergeChunks(List<List<int>> chunks, int totalBytes) {
    final bytes = Uint8List(totalBytes);
    var offset = 0;
    for (final chunk in chunks) {
      bytes.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return bytes;
  }

  /// 从 HTTP URL 加载（无文件系统）
  Future<void> _loadFromHttpUrl(Uri uri, int startPage) async {
    state = PdfReaderLoading(message: appL10n.pdfReaderStreamingMessage);

    try {
      final documentRef = PdfDocumentRefUri(
        uri,
        preferRangeAccess: true,
      );

      final document = await _waitForDocument(documentRef);

      state = PdfReaderLoaded(
        documentRef: documentRef,
        currentPage: startPage.clamp(1, document.pages.length),
        totalPages: document.pages.length,
        isStreaming: true,
      );

      logger.i('PDF HTTP 加载完成: ${book.name}, ${document.pages.length} 页');
    } on TimeoutException catch (e) {
      logger.e('PDF HTTP 加载超时', e);
      state = PdfReaderError(appL10n.pdfReaderTimeoutMessage);
    } on Exception catch (e, stackTrace) {
      logger.e('PDF HTTP 加载失败', e, stackTrace);
      state = PdfReaderError(appL10n.pdfReaderLoadFailedMessage(e));
    }
  }

  /// 等待文档加载完成（带超时）
  Future<PdfDocument> _waitForDocument(PdfDocumentRef documentRef) async {
    final listenable = documentRef.resolveListenable();

    // 如果文档已加载，直接返回
    var document = listenable.document;
    if (document != null) return document;

    // 触发加载并等待完成
    await listenable.load().timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw TimeoutException(appL10n.pdfReaderParseTimeoutMessage);
      },
    );

    // 检查加载结果
    document = listenable.document;
    if (document != null) return document;

    // 检查是否有错误
    final error = listenable.error;
    if (error != null) {
      if (error is Exception || error is Error) {
        throw error;
      }
      throw Exception(appL10n.pdfReaderLoadFailedMessage(error));
    }

    throw StateError(appL10n.pdfReaderLoadErrorUnknown);
  }


  void setPage(int page) {
    final current = state;
    if (current is PdfReaderLoaded) {
      final newPage = page.clamp(1, current.totalPages);
      state = current.copyWith(currentPage: newPage);
      _saveProgress(newPage, current.totalPages);
    }
  }

  void toggleDarkMode() {
    final current = state;
    if (current is PdfReaderLoaded) {
      state = current.copyWith(isDarkMode: !current.isDarkMode);
    }
  }

  Future<void> _saveProgress(int page, int total) async {
    final itemId = _progressService.generateItemId(book.id, book.path);
    await _progressService.saveProgress(ReadingProgress(
      itemId: itemId,
      itemType: 'pdf',
      position: page.toDouble(),
      totalPositions: total,
      lastReadAt: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    // PdfDocumentRef 会自动管理文档的生命周期
    // 不需要手动 dispose
    super.dispose();
  }
}

class PdfReaderPage extends ConsumerStatefulWidget {
  const PdfReaderPage({required this.book, super.key});

  final BookItem book;

  @override
  ConsumerState<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends ConsumerState<PdfReaderPage> {
  bool _showControls = true;
  bool _showThumbnails = false;
  final PdfViewerController _controller = PdfViewerController();

  @override
  void initState() {
    super.initState();
    // 隐藏原生 Tab Bar（iOS 玻璃风格）
    NativeTabBarService.instance.setTabBarVisible(false);
    // 隐藏 Flutter 导航栏（经典风格）
    BottomNavVisibilityNotifier.instance?.hide();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initWakelock();
  }

  Future<void> _initWakelock() async {
    await WakelockPlus.enable();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    // 恢复导航栏可见性（通过 Provider 引用计数，由 MainScaffold 决定实际状态）
    BottomNavVisibilityNotifier.instance?.show();
    super.dispose();
  }

  /// 构建键盘快捷键映射
  Map<ShortcutKey, VoidCallback> _buildKeyboardShortcuts(PdfReaderLoaded state) => {
        // 导航
        CommonShortcuts.previous: () {
          if (state.currentPage > 1) {
            final newPage = state.currentPage - 1;
            _controller.goToPage(pageNumber: newPage);
            ref.read(pdfReaderProvider(widget.book).notifier).setPage(newPage);
          }
        },
        CommonShortcuts.next: () {
          if (state.currentPage < state.totalPages) {
            final newPage = state.currentPage + 1;
            _controller.goToPage(pageNumber: newPage);
            ref.read(pdfReaderProvider(widget.book).notifier).setPage(newPage);
          }
        },
        CommonShortcuts.previousPage: () {
          if (state.currentPage > 1) {
            final newPage = state.currentPage - 1;
            _controller.goToPage(pageNumber: newPage);
            ref.read(pdfReaderProvider(widget.book).notifier).setPage(newPage);
          }
        },
        CommonShortcuts.nextPage: () {
          if (state.currentPage < state.totalPages) {
            final newPage = state.currentPage + 1;
            _controller.goToPage(pageNumber: newPage);
            ref.read(pdfReaderProvider(widget.book).notifier).setPage(newPage);
          }
        },
        CommonShortcuts.first: () {
          _controller.goToPage(pageNumber: 1);
          ref.read(pdfReaderProvider(widget.book).notifier).setPage(1);
        },
        CommonShortcuts.last: () {
          _controller.goToPage(pageNumber: state.totalPages);
          ref.read(pdfReaderProvider(widget.book).notifier).setPage(state.totalPages);
        },

        // 控制栏切换
        CommonShortcuts.playPause: () => setState(() {
              _showControls = !_showControls;
              _showThumbnails = false;
            }),

        // 夜间模式
        CommonShortcuts.mute: () {
          ref.read(pdfReaderProvider(widget.book).notifier).toggleDarkMode();
        },

        // 缩放
        CommonShortcuts.zoomIn: _controller.zoomUp,
        CommonShortcuts.zoomOut: _controller.zoomDown,
        CommonShortcuts.zoomInCtrl: _controller.zoomUp,
        CommonShortcuts.zoomOutCtrl: _controller.zoomDown,

        // 退出
        CommonShortcuts.escape: () => Navigator.pop(context),
        CommonShortcuts.back: () => Navigator.pop(context),
      };

  /// 显示快捷键帮助
  void _showKeyboardHelp() {
    KeyboardShortcutsHelpDialog.show(
      context,
      title: context.l10n.pdfReaderKeyboardHelpTitle,
      shortcuts: [
        (key: '←', description: context.l10n.pdfReaderKeyboardPreviousPage),
        (key: '→', description: context.l10n.pdfReaderKeyboardNextPage),
        (key: 'Page Up', description: context.l10n.pdfReaderKeyboardPreviousPage),
        (key: 'Page Down', description: context.l10n.pdfReaderKeyboardNextPage),
        (key: 'Home', description: context.l10n.pdfReaderKeyboardFirstPage),
        (key: 'End', description: context.l10n.pdfReaderKeyboardLastPage),
        (key: 'Space', description: context.l10n.pdfReaderKeyboardToggleControls),
        (key: 'M', description: context.l10n.pdfReaderKeyboardToggleDarkMode),
        (key: '+/=', description: context.l10n.pdfReaderKeyboardZoomIn),
        (key: '-', description: context.l10n.pdfReaderKeyboardZoomOut),
        (key: 'Esc', description: context.l10n.pdfReaderKeyboardBack),
        (key: '?', description: context.l10n.pdfReaderKeyboardShowHelp),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pdfReaderProvider(widget.book));

    // 只有在加载完成时才提供键盘快捷键
    if (state is PdfReaderLoaded) {
      return KeyboardShortcuts(
        shortcuts: {
          ..._buildKeyboardShortcuts(state),
          CommonShortcuts.help: _showKeyboardHelp,
        },
        child: Scaffold(
          backgroundColor: Colors.grey.shade900,
          body: _buildReader(context, state),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      body: switch (state) {
        PdfReaderLoading(:final message) => LottieLoading.book(message: localizeFormText(context, message)),
        PdfReaderError(:final message) => _buildError(message),
        PdfReaderLoaded() => _buildReader(context, state),
      },
    );
  }

  Widget _buildError(String message) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
              label: Text(context.l10n.pdfReaderBackButton),
            ),
          ],
        ),
      ),
    );

  Widget _buildReader(BuildContext context, PdfReaderLoaded state) => Stack(
      children: [
        // PDF 内容（带固定顶栏）
        Column(
          children: [
            // 固定顶栏 - 避免摄像头遮挡内容
            _buildFixedHeader(state),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _showControls = !_showControls;
                  _showThumbnails = false;
                }),
                child: PdfViewer(
                  state.documentRef,
                  controller: _controller,
                  params: PdfViewerParams(
                    backgroundColor: state.isDarkMode ? Colors.black : Colors.grey.shade200,
                    pageDropShadow: BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(2, 2),
                    ),
                    // 性能优化参数
                    maxImageBytesCachedOnMemory: 150 * 1024 * 1024, // 150MB 缓存
                    horizontalCacheExtent: 2, // 预加载左右各2页
                    verticalCacheExtent: 2, // 预加载上下各2页
                    // 限制渲染分辨率以提高性能
                    getPageRenderingScale: (context, page, controller, estimatedScale) {
                      // 限制最大渲染尺寸为 4000 像素
                      final width = page.width * estimatedScale;
                      final height = page.height * estimatedScale;
                      if (width > 4000 || height > 4000) {
                        return min(4000 / page.width, 4000 / page.height);
                      }
                      return estimatedScale;
                    },
                    onPageChanged: (pageNumber) {
                      if (pageNumber != null) {
                        ref.read(pdfReaderProvider(widget.book).notifier).setPage(pageNumber);
                      }
                    },
                    // 初始页码
                    calculateInitialPageNumber: (_, controller) => state.currentPage,
                  ),
                ),
              ),
            ),
          ],
        ),

        // 流式加载指示器
        if (state.isStreaming)
          Positioned(
            top: MediaQuery.of(context).padding.top + 40, // 调整位置避开顶栏
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_download_rounded,
                    size: 14,
                    color: Colors.white70,
                  ),
                  SizedBox(width: 6),
                  Text(
                    context.l10n.pdfReaderStreaming,
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

        // 顶部控制栏
        if (_showControls)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(context, state),
          ),

        // 底部控制栏
        if (_showControls)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(context, state),
          ),

        // 缩略图面板
        if (_showThumbnails) _buildThumbnailPanel(context, state),
      ],
    );

  /// 构建固定顶栏，显示书名和页码
  Widget _buildFixedHeader(PdfReaderLoaded state) {
    final isDark = state.isDarkMode;
    final bgColor = isDark ? Colors.grey.shade900 : Colors.grey.shade100;
    final textColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
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
                widget.book.displayName,
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
              '${state.currentPage}/${state.totalPages}',
              style: TextStyle(
                color: textColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, PdfReaderLoaded state) => DecoratedBox(
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.book.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: () {
                  ref.read(pdfReaderProvider(widget.book).notifier).toggleDarkMode();
                },
                icon: Icon(
                  state.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  color: Colors.white,
                ),
                tooltip: state.isDarkMode ? context.l10n.pdfReaderLightMode : context.l10n.pdfReaderDarkMode,
              ),
              IconButton(
                onPressed: () => setState(() => _showThumbnails = !_showThumbnails),
                icon: const Icon(Icons.grid_view_rounded, color: Colors.white),
                tooltip: context.l10n.pdfReaderPageThumbnails,
              ),
            ],
          ),
        ),
      ),
    );

  Widget _buildBottomBar(BuildContext context, PdfReaderLoaded state) => DecoratedBox(
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
              // 页码指示器
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${state.currentPage} / ${state.totalPages}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '${((state.currentPage / state.totalPages) * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 页码滑块
              Row(
                children: [
                  IconButton(
                    onPressed: state.currentPage > 1
                        ? () {
                            final newPage = state.currentPage - 1;
                            _controller.goToPage(pageNumber: newPage);
                            ref.read(pdfReaderProvider(widget.book).notifier).setPage(newPage);
                          }
                        : null,
                    icon: Icon(
                      Icons.chevron_left_rounded,
                      color: state.currentPage > 1 ? Colors.white : Colors.white38,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: state.currentPage.toDouble(),
                      min: 1,
                      max: state.totalPages.toDouble(),
                      divisions: state.totalPages > 1 ? state.totalPages - 1 : null,
                      onChanged: (value) {
                        final page = value.toInt();
                        _controller.goToPage(pageNumber: page);
                        ref.read(pdfReaderProvider(widget.book).notifier).setPage(page);
                      },
                    ),
                  ),
                  IconButton(
                    onPressed: state.currentPage < state.totalPages
                        ? () {
                            final newPage = state.currentPage + 1;
                            _controller.goToPage(pageNumber: newPage);
                            ref.read(pdfReaderProvider(widget.book).notifier).setPage(newPage);
                          }
                        : null,
                    icon: Icon(
                      Icons.chevron_right_rounded,
                      color: state.currentPage < state.totalPages ? Colors.white : Colors.white38,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 功能按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildBottomButton(
                    icon: Icons.first_page_rounded,
                    label: context.l10n.pdfReaderFirstPage,
                    onTap: () {
                      _controller.goToPage(pageNumber: 1);
                      ref.read(pdfReaderProvider(widget.book).notifier).setPage(1);
                    },
                  ),
                  _buildBottomButton(
                    icon: Icons.zoom_out_rounded,
                    label: context.l10n.pdfReaderKeyboardZoomOut,
                    onTap: _controller.zoomDown,
                  ),
                  _buildBottomButton(
                    icon: Icons.zoom_in_rounded,
                    label: context.l10n.pdfReaderKeyboardZoomIn,
                    onTap: _controller.zoomUp,
                  ),
                  _buildBottomButton(
                    icon: Icons.last_page_rounded,
                    label: context.l10n.pdfReaderLastPage,
                    onTap: () {
                      _controller.goToPage(pageNumber: state.totalPages);
                      ref.read(pdfReaderProvider(widget.book).notifier).setPage(state.totalPages);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

  Widget _buildBottomButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );

  Widget _buildThumbnailPanel(BuildContext context, PdfReaderLoaded state) => Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.25,
        decoration: BoxDecoration(
          color: Colors.grey.shade900,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 10,
              offset: const Offset(-2, 0),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Text(
                      context.l10n.pdfReaderPagesPanel,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => setState(() => _showThumbnails = false),
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: state.totalPages,
                  itemBuilder: (context, index) {
                    final pageNumber = index + 1;
                    final isActive = pageNumber == state.currentPage;
                    return GestureDetector(
                      onTap: () {
                        _controller.goToPage(pageNumber: pageNumber);
                        ref.read(pdfReaderProvider(widget.book).notifier).setPage(pageNumber);
                        setState(() => _showThumbnails = false);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: isActive ? AppColors.primary : Colors.grey.shade800,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isActive ? AppColors.primary : Colors.grey.shade700,
                            width: isActive ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            context.l10n.pdfReaderPageNumber(pageNumber),
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.grey.shade400,
                              fontSize: 14,
                              fontWeight: isActive ? FontWeight.bold : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
}
