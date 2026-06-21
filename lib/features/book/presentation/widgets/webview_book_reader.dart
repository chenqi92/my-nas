import 'dart:async';

import 'package:flutter/material.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_content_processor.dart';
import 'package:my_nas/features/book/data/services/chunked_content_provider.dart';
import 'package:my_nas/features/book/data/services/webview_pagination_renderer.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';

// 导出 PaginationInfo 以便其他文件使用
export 'package:my_nas/features/book/data/services/webview_pagination_renderer.dart'
    show PaginationInfo;

/// WebView 图书阅读器组件
/// 使用 CSS Multi-column 实现精确分页
/// 支持大文件分块加载和估算分页
class WebViewBookReader extends StatefulWidget {
  const WebViewBookReader({
    required this.htmlContent,
    required this.chapters,
    required this.settings,
    required this.onPaginationReady,
    required this.onPageChanged,
    required this.onChapterChanged,
    this.initialPage = 0,
    this.topBarHeight = 40.0,
    this.bottomBarHeight = 24.0,
    super.key,
  });

  /// HTML 内容
  final String htmlContent;

  /// 章节列表
  final List<BookChapter> chapters;

  /// 阅读设置
  final BookReaderSettings settings;

  /// 分页准备完成回调
  final ValueChanged<PaginationInfo> onPaginationReady;

  /// 页码变化回调
  final ValueChanged<int> onPageChanged;

  /// 章节变化回调
  final ValueChanged<String> onChapterChanged;

  /// 初始页码
  final int initialPage;

  /// 顶部固定栏高度
  final double topBarHeight;

  /// 底部状态栏高度
  final double bottomBarHeight;

  @override
  State<WebViewBookReader> createState() => WebViewBookReaderState();
}

class WebViewBookReaderState extends State<WebViewBookReader> {
  WebViewPaginationRenderer? _renderer;
  ChunkedContentProvider? _contentProvider;
  bool _isReady = false;
  bool _isLoading = true;
  PaginationInfo? _paginationInfo;

  /// 大文件阈值 (500KB)
  static const int _largeFileThreshold = 500000;

  /// 是否已准备就绪
  bool get isReady => _isReady;

  /// 当前分页信息
  PaginationInfo? get paginationInfo => _paginationInfo;

  /// 当前页码
  int get currentPage => _paginationInfo?.currentPage ?? 0;

  /// 总页数
  int get totalPages => _paginationInfo?.totalPages ?? 1;

  /// 阅读进度 (0.0 - 1.0)
  double get progress {
    if (_paginationInfo == null || _paginationInfo!.totalPages <= 1) return 0;
    return _paginationInfo!.currentPage / (_paginationInfo!.totalPages - 1);
  }

  @override
  void initState() {
    super.initState();
    _initializeContent();
  }

  void _initializeContent() {
    final contentLength = widget.htmlContent.length;
    final isLargeFile = contentLength > _largeFileThreshold;

    logger.i(
      'WebViewBookReader: 初始化 - '
      '内容长度: $contentLength, '
      '大文件: $isLargeFile',
    );

    // 对于大文件，创建分块提供者
    if (isLargeFile) {
      _contentProvider = ChunkedContentProvider(
        fullContent: widget.htmlContent,
        chapters: widget.chapters,
      );
    }

    _initRenderer();

    // 对于大文件，先使用估算值快速响应
    if (isLargeFile && _contentProvider != null) {
      // 延迟一帧后发送估算的分页信息，让 UI 有时间显示加载状态
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _sendEstimatedPagination();
      });
    }
  }

  /// 发送估算的分页信息
  void _sendEstimatedPagination() {
    if (_contentProvider == null) return;

    final estimatedInfo = PaginationInfo(
      totalPages: _contentProvider!.estimatedTotalPages,
      currentPage: 0,
      pageWidth: MediaQuery.of(context).size.width,
      pageHeight: MediaQuery.of(context).size.height,
    );

    // 先通知外部估算值（用于显示进度条等）
    logger.i('WebViewBookReader: 发送估算分页 - ${estimatedInfo.totalPages} 页');
    widget.onPaginationReady(estimatedInfo);
  }

  @override
  void didUpdateWidget(WebViewBookReader oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 设置变化时更新渲染器
    if (oldWidget.settings.theme != widget.settings.theme) {
      _renderer?.updateTheme(widget.settings.theme);
    }

    if (oldWidget.settings.fontSize != widget.settings.fontSize ||
        oldWidget.settings.lineHeight != widget.settings.lineHeight ||
        oldWidget.settings.fontFamily != widget.settings.fontFamily) {
      _renderer?.updateFontSettings(
        fontSize: widget.settings.fontSize,
        lineHeight: widget.settings.lineHeight,
        fontFamily: widget.settings.fontFamily,
      );
    }
  }

  void _initRenderer() {
    _renderer = WebViewPaginationRenderer(
      settings: widget.settings,
      onPaginationReady: _onPaginationReady,
      onPageChanged: _onPageChanged,
      onChapterDetected: widget.onChapterChanged,
      estimatedTotalPages: _contentProvider?.estimatedTotalPages,
      onLoadingStateChanged: _onLoadingStateChanged,
    );
  }

  void _onLoadingStateChanged(bool isLoading) {
    if (!mounted) return;
    setState(() {
      _isLoading = isLoading;
    });
  }

  void _onPaginationReady(PaginationInfo info) {
    // 检查 widget 是否仍然 mounted，避免在 dispose 后调用 setState
    if (!mounted) return;

    setState(() {
      _isReady = true;
      _isLoading = false;
      _paginationInfo = info;
    });

    widget.onPaginationReady(info);

    // 跳转到初始页
    if (widget.initialPage > 0) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          goToPage(widget.initialPage);
        }
      });
    }

    logger.i('WebView 阅读器准备完成: ${info.totalPages} 页');
  }

  void _onPageChanged(int page) {
    // 检查 widget 是否仍然 mounted，避免在 dispose 后调用 setState
    if (!mounted) return;

    setState(() {
      _paginationInfo = _paginationInfo?.copyWith(currentPage: page);
    });

    widget.onPageChanged(page);
  }

  /// 跳转到指定页
  Future<void> goToPage(int page) async {
    await _renderer?.goToPage(page);
  }

  /// 下一页
  Future<void> nextPage() async {
    await _renderer?.nextPage();
  }

  /// 上一页
  Future<void> previousPage() async {
    await _renderer?.previousPage();
  }

  /// 跳转到第一页
  Future<void> goToFirstPage() async {
    await _renderer?.goToFirstPage();
  }

  /// 跳转到最后一页
  Future<void> goToLastPage() async {
    await _renderer?.goToLastPage();
  }

  /// 跳转到指定进度 (0.0 - 1.0)
  Future<void> goToProgress(double progress) async {
    await _renderer?.goToProgress(progress);
  }

  @override
  Widget build(BuildContext context) {
    if (_renderer == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 计算可用的内容区域
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight -
            widget.topBarHeight -
            widget.bottomBarHeight;

        return Stack(
          children: [
            // WebView 内容
            _renderer!.buildWebView(
              htmlContent: widget.htmlContent,
              chapters: widget.chapters,
              availableWidth: availableWidth,
              availableHeight: availableHeight,
            ),

            // 加载指示器覆盖层
            if (_isLoading)
              Positioned.fill(
                child: ColoredBox(
                  color: widget.settings.theme.backgroundColor,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: widget.settings.theme.textColor
                              .withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          context.l10n.bookReaderLoadingContent,
                          style: TextStyle(
                            color: widget.settings.theme.textColor
                                .withValues(alpha: 0.5),
                            fontSize: 14,
                          ),
                        ),
                        if (_contentProvider != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            context.l10n.bookReaderEstimatedPages(_contentProvider!.estimatedTotalPages),
                            style: TextStyle(
                              color: widget.settings.theme.textColor
                                  .withValues(alpha: 0.3),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _renderer?.dispose();
    super.dispose();
  }
}
