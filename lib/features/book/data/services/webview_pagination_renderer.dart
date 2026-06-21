import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_content_processor.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';

/// 分页信息
class PaginationInfo {
  const PaginationInfo({
    required this.totalPages,
    required this.currentPage,
    required this.pageWidth,
    required this.pageHeight,
  });

  final int totalPages;
  final int currentPage;
  final double pageWidth;
  final double pageHeight;

  PaginationInfo copyWith({
    int? totalPages,
    int? currentPage,
    double? pageWidth,
    double? pageHeight,
  }) =>
      PaginationInfo(
        totalPages: totalPages ?? this.totalPages,
        currentPage: currentPage ?? this.currentPage,
        pageWidth: pageWidth ?? this.pageWidth,
        pageHeight: pageHeight ?? this.pageHeight,
      );
}

/// WebView 分页渲染器
/// 使用 CSS Multi-column 实现精确分页
class WebViewPaginationRenderer {
  WebViewPaginationRenderer({
    required this.settings,
    required this.onPaginationReady,
    required this.onPageChanged,
    required this.onChapterDetected,
    this.estimatedTotalPages,
    this.onLoadingStateChanged,
  });

  final BookReaderSettings settings;
  final ValueChanged<PaginationInfo> onPaginationReady;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<String> onChapterDetected;

  /// 估算的总页数（用于大文件快速显示）
  final int? estimatedTotalPages;

  /// 加载状态变化回调
  final ValueChanged<bool>? onLoadingStateChanged;

  InAppWebViewController? _controller;
  PaginationInfo? _paginationInfo;
  bool _isReady = false;
  // ignore: unused_field - 用于未来支持加载状态跟踪
  bool _isLoading = true;

  /// 是否已准备就绪
  bool get isReady => _isReady;

  /// 当前分页信息
  PaginationInfo? get paginationInfo => _paginationInfo;

  /// 构建 WebView Widget
  Widget buildWebView({
    required String htmlContent,
    required List<BookChapter> chapters,
    required double availableWidth,
    required double availableHeight,
  }) {
    final fullHtml = _buildPaginatedHtml(
      htmlContent,
      chapters,
      availableWidth,
      availableHeight,
    );

    return InAppWebView(
      initialData: InAppWebViewInitialData(
        data: fullHtml,
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
      initialSettings: InAppWebViewSettings(
        // 性能优化
        useShouldOverrideUrlLoading: false,
        mediaPlaybackRequiresUserGesture: true,
        allowsInlineMediaPlayback: false,
        javaScriptEnabled: true,
        // 禁用不需要的功能
        supportZoom: false,
        useWideViewPort: false,
        // 不透明背景 - 确保内容区域有正确的背景色
        transparentBackground: false,
        // 禁用滚动 (我们用 Flutter 控制)
        disableVerticalScroll: true,
        disableHorizontalScroll: true,
        // iOS 特定设置
        allowsBackForwardNavigationGestures: false,
        // Android 特定设置
        useHybridComposition: true,
        // Windows/macOS 设置
        isInspectable: kDebugMode,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        _setupJavaScriptHandlers(controller);
      },
      onLoadStop: (controller, url) async {
        // 页面加载完成后初始化分页
        await _initializePagination();
      },
      onConsoleMessage: (controller, message) {
        if (kDebugMode) {
          logger.d('WebView Console: ${message.message}');
        }
      },
    );
  }

  /// 设置 JavaScript 处理器
  void _setupJavaScriptHandlers(InAppWebViewController controller) {
    // 分页准备完成
    controller..addJavaScriptHandler(
      handlerName: 'onPaginationReady',
      callback: (args) {
        if (args.isNotEmpty) {
          final data = args[0] as Map<String, dynamic>;
          _paginationInfo = PaginationInfo(
            totalPages: data['totalPages'] as int,
            currentPage: 0,
            pageWidth: (data['pageWidth'] as num).toDouble(),
            pageHeight: (data['pageHeight'] as num).toDouble(),
          );
          _isReady = true;
          _isLoading = false;
          onLoadingStateChanged?.call(false);
          onPaginationReady(_paginationInfo!);
          logger.i('WebView 分页准备完成: ${_paginationInfo!.totalPages} 页');
        }
      },
    )

    // 页码变化

      ..addJavaScriptHandler(
        handlerName: 'onPageChanged',
        callback: (args) {
          if (args.isNotEmpty) {
            final page = args[0] as int;
            _paginationInfo = _paginationInfo?.copyWith(currentPage: page);
            onPageChanged(page);
          }
        },
      )
      // 章节检测
      ..addJavaScriptHandler(
        handlerName: 'onChapterDetected',
        callback: (args) {
          if (args.isNotEmpty) {
            final chapter = args[0] as String;
            onChapterDetected(chapter);
          }
        },
      );
  }

  /// 初始化分页
  Future<void> _initializePagination() async {
    if (_controller == null) return;

    try {
      await _controller!.evaluateJavascript(source: 'initPagination()');
    } on Exception catch (e) {
      logger.e('初始化分页失败', e);
    }
  }

  /// 跳转到指定页
  Future<void> goToPage(int pageIndex) async {
    if (_controller == null || !_isReady) return;
    if (_paginationInfo == null) return;

    final clampedPage = pageIndex.clamp(0, _paginationInfo!.totalPages - 1);

    try {
      await _controller!.evaluateJavascript(
        source: 'goToPage($clampedPage)',
      );
    } on Exception catch (e) {
      logger.e('跳转页面失败', e);
    }
  }

  /// 下一页
  Future<void> nextPage() async {
    if (_paginationInfo == null) return;
    await goToPage(_paginationInfo!.currentPage + 1);
  }

  /// 上一页
  Future<void> previousPage() async {
    if (_paginationInfo == null) return;
    await goToPage(_paginationInfo!.currentPage - 1);
  }

  /// 跳转到第一页
  Future<void> goToFirstPage() async {
    await goToPage(0);
  }

  /// 跳转到最后一页
  Future<void> goToLastPage() async {
    if (_paginationInfo == null) return;
    await goToPage(_paginationInfo!.totalPages - 1);
  }

  /// 跳转到指定进度 (0.0 - 1.0)
  Future<void> goToProgress(double progress) async {
    if (_paginationInfo == null) return;
    final page = (progress * (_paginationInfo!.totalPages - 1)).round();
    await goToPage(page);
  }

  /// 更新主题
  Future<void> updateTheme(BookReaderTheme theme) async {
    if (_controller == null) return;

    final css = _getThemeCss(theme);
    try {
      await _controller!.evaluateJavascript(
        source: 'updateTheme(`$css`)',
      );
    } on Exception catch (e) {
      logger.e('更新主题失败', e);
    }
  }

  /// 更新字体设置
  Future<void> updateFontSettings({
    double? fontSize,
    double? lineHeight,
    String? fontFamily,
  }) async {
    if (_controller == null) return;

    final updates = <String, dynamic>{};
    if (fontSize != null) updates['fontSize'] = fontSize;
    if (lineHeight != null) updates['lineHeight'] = lineHeight;
    if (fontFamily != null) updates['fontFamily'] = fontFamily;

    try {
      await _controller!.evaluateJavascript(
        source: 'updateFontSettings(${jsonEncode(updates)})',
      );
      // 字体变化后需要重新计算分页
      await _initializePagination();
    } on Exception catch (e) {
      logger.e('更新字体设置失败', e);
    }
  }

  /// 获取主题 CSS
  String _getThemeCss(BookReaderTheme theme) {
    final bg = _colorToHex(theme.backgroundColor);
    final fg = _colorToHex(theme.textColor);
    return '''
      body {
        background-color: $bg !important;
        color: $fg !important;
      }
      a { color: $fg !important; }
    ''';
  }

  /// Color 转 Hex
  String _colorToHex(Color color) {
    final r = color.r.toInt().toRadixString(16).padLeft(2, '0');
    final g = color.g.toInt().toRadixString(16).padLeft(2, '0');
    final b = color.b.toInt().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  /// 清理 HTML 内容：移除可能的外层 HTML 结构
  /// MOBI 解析出的内容可能包含完整的 HTML 文档结构，
  /// 直接嵌入会导致嵌套 HTML 文档，浏览器无法正确渲染
  String _sanitizeHtmlContent(String content) {
    var cleaned = content;
    
    // 移除 DOCTYPE
    cleaned = cleaned.replaceAll(
      RegExp('<!DOCTYPE[^>]*>', caseSensitive: false),
      '',
    );
    
    // 移除 html 标签
    cleaned = cleaned.replaceAll(
      RegExp('</?html[^>]*>', caseSensitive: false),
      '',
    );
    
    // 移除 head 及其内容
    cleaned = cleaned.replaceAll(
      RegExp('<head[^>]*>.*?</head>', caseSensitive: false, dotAll: true),
      '',
    );
    
    // 移除 body 标签（保留内容）
    cleaned = cleaned.replaceAll(
      RegExp('</?body[^>]*>', caseSensitive: false),
      '',
    );
    
    // 移除 meta 标签
    cleaned = cleaned.replaceAll(
      RegExp('<meta[^>]*/?>', caseSensitive: false),
      '',
    );
    
    // 移除 xml 声明
    cleaned = cleaned.replaceAll(
      RegExp(r'<\?xml[^>]*\?>', caseSensitive: false),
      '',
    );
    
    // 如果内容为空或只有空白，返回提示
    final trimmed = cleaned.trim();
    if (trimmed.isEmpty) {
      return '<p style="color: #999; text-align: center; padding: 20px;">${appL10n.webviewContentParsingFailed}</p>';
    }
    
    return trimmed;
  }

  /// 构建分页 HTML
  String _buildPaginatedHtml(
    String content,
    List<BookChapter> chapters,
    double width,
    double height,
  ) {
    // 清理内容，移除嵌套的 HTML 结构
    final sanitizedContent = _sanitizeHtmlContent(content);
    
    final theme = settings.theme;
    final bgColor = _colorToHex(theme.backgroundColor);
    final textColor = _colorToHex(theme.textColor);
    final fontSize = settings.fontSize;
    final lineHeight = settings.lineHeight;
    final fontFamily = settings.fontFamily ?? _getSystemFontStack();
    final horizontalPadding = settings.horizontalPadding;
    final verticalPadding = settings.verticalPadding;
    final paragraphSpacing = settings.paragraphSpacing;

    // 计算可用于内容的宽度和高度
    final contentWidth = width - horizontalPadding * 2;
    final contentHeight = height - verticalPadding * 2;

    // 章节数据 (用于检测当前章节)
    final chaptersJson = jsonEncode(
      chapters.map((c) => {'title': c.title, 'offset': c.offset}).toList(),
    );

    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=$width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
  <style>
    /* 重置样式 */
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      -webkit-tap-highlight-color: transparent;
      -webkit-touch-callout: none;
      -webkit-user-select: none;
      user-select: none;
    }

    html, body {
      width: ${width}px;
      height: ${height}px;
      overflow: hidden;
      background-color: $bgColor;
      margin: 0;
      padding: 0;
    }

    /* 内容容器 - CSS Multi-column 分页核心 */
    #content {
      /* 多列布局 */
      column-width: ${contentWidth}px;
      column-gap: ${horizontalPadding * 2}px;
      column-fill: auto;

      /* 尺寸 - 使用精确像素值 */
      width: ${width}px;
      height: ${contentHeight}px;
      max-height: ${contentHeight}px;

      /* 内边距 */
      padding: ${verticalPadding}px ${horizontalPadding}px;

      /* 排版 */
      font-family: $fontFamily;
      font-size: ${fontSize}px;
      line-height: $lineHeight;
      color: $textColor;
      text-align: justify;
      word-break: break-word;
      -webkit-hyphens: auto;
      hyphens: auto;

      /* 滚动控制 */
      overflow-x: hidden;
      overflow-y: hidden;

      /* 防止闪烁 */
      -webkit-font-smoothing: antialiased;
      -moz-osx-font-smoothing: grayscale;
    }

    /* 段落样式 */
    p {
      margin-bottom: ${paragraphSpacing}em;
      text-indent: 2em;
      break-inside: avoid;
      orphans: 2;
      widows: 2;
    }

    /* 标题样式 */
    h1, h2, h3, h4, h5, h6 {
      break-after: avoid;
      break-inside: avoid;
      margin-top: 1.2em;
      margin-bottom: 0.6em;
      text-indent: 0;
      font-weight: bold;
    }

    h1 { font-size: 1.6em; }
    h2 { font-size: 1.4em; }
    h3 { font-size: 1.2em; }
    h4, h5, h6 { font-size: 1.1em; }

    /* 链接样式 */
    a {
      color: $textColor;
      text-decoration: none;
    }

    /* 图片样式 */
    img {
      max-width: 100%;
      height: auto;
      break-inside: avoid;
      display: block;
      margin: 0.5em auto;
    }

    /* 引用样式 */
    blockquote {
      margin: 1em 0;
      padding-left: 1em;
      border-left: 3px solid ${textColor}40;
      font-style: italic;
      break-inside: avoid;
    }

    /* 代码样式 */
    pre, code {
      font-family: 'SF Mono', Consolas, 'Courier New', monospace;
      font-size: 0.9em;
      background: ${textColor}10;
      border-radius: 3px;
    }

    pre {
      padding: 0.5em;
      overflow-x: auto;
      break-inside: avoid;
    }

    code {
      padding: 0.1em 0.3em;
    }

    /* 列表样式 */
    ul, ol {
      margin: 0.5em 0;
      padding-left: 2em;
    }

    li {
      margin-bottom: 0.3em;
      break-inside: avoid;
    }

    /* 水平线 */
    hr {
      border: none;
      border-top: 1px solid ${textColor}30;
      margin: 1em 0;
    }

    /* 主题样式容器 */
    #theme-style {
      /* 动态注入的主题样式 */
    }
  </style>
<style id="theme-style"></style>
</head>
<body>
  <div id="content">$sanitizedContent</div>

  <script>
    // 章节数据
    const chapters = $chaptersJson;

    // 分页状态
    let totalPages = 1;
    let currentPage = 0;
    let pageWidth = $width;
    let isAnimating = false;
    let isReady = false;

    // 获取内容元素
    function getContent() {
      return document.getElementById('content');
    }

    // 计算总页数
    function calculateTotalPages() {
      const content = getContent();
      if (!content) return 1;

      // 强制重新布局以获取准确的 scrollWidth
      content.offsetHeight;

      // 使用 scrollWidth 计算总页数
      const scrollWidth = content.scrollWidth;
      const visibleWidth = pageWidth;

      // 确保至少有1页，并且计算正确
      const pages = Math.max(1, Math.ceil(scrollWidth / visibleWidth));

      console.log('分页计算: scrollWidth=' + scrollWidth + ', pageWidth=' + visibleWidth + ', totalPages=' + pages);

      return pages;
    }

    // 初始化分页
    function initPagination() {
      const content = getContent();
      if (!content) {
        console.error('无法找到内容元素');
        return;
      }

      // 检查内容是否为空
      if (!content.innerHTML || content.innerHTML.trim() === '') {
        console.error('内容为空');
        return;
      }

      pageWidth = $width;

      // 等待一帧确保布局完成
      requestAnimationFrame(() => {
        totalPages = calculateTotalPages();
        currentPage = 0;
        isReady = true;

        // 确保在第一页
        goToPage(0, false);

        // 通知 Flutter
        if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
          window.flutter_inappwebview.callHandler('onPaginationReady', {
            totalPages: totalPages,
            currentPage: currentPage,
            pageWidth: pageWidth,
            pageHeight: $height
          });
        }

        console.log('分页初始化完成: totalPages=' + totalPages);
      });
    }

    // 跳转到指定页
    function goToPage(page, animate = true) {
      if (isAnimating) return;

      const content = getContent();
      if (!content) return;

      // 限制页码范围
      page = Math.max(0, Math.min(page, totalPages - 1));

      if (page === currentPage && animate) return;

      currentPage = page;
      const targetX = page * pageWidth;

      if (animate) {
        isAnimating = true;
        content.style.transition = 'transform 0.3s ease-out';
        content.style.transform = 'translateX(-' + targetX + 'px)';

        setTimeout(() => {
          content.style.transition = '';
          isAnimating = false;
        }, 300);
      } else {
        content.style.transform = 'translateX(-' + targetX + 'px)';
      }

      // 通知 Flutter
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('onPageChanged', currentPage);
      }

      // 检测当前章节
      detectCurrentChapter();
    }

    // 下一页
    function nextPage() {
      if (currentPage < totalPages - 1) {
        goToPage(currentPage + 1);
      }
    }

    // 上一页
    function prevPage() {
      if (currentPage > 0) {
        goToPage(currentPage - 1);
      }
    }

    // 检测当前章节
    function detectCurrentChapter() {
      if (chapters.length === 0) return;

      // 估算当前位置对应的内容偏移
      const content = getContent();
      if (!content) return;

      const progress = totalPages > 1 ? currentPage / (totalPages - 1) : 0;
      const estimatedOffset = Math.floor(progress * content.textContent.length);

      // 找到对应的章节
      let currentChapter = chapters[0]?.title || '';
      for (const chapter of chapters) {
        if (chapter.offset <= estimatedOffset) {
          currentChapter = chapter.title;
        } else {
          break;
        }
      }

      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('onChapterDetected', currentChapter);
      }
    }

    // 更新主题
    function updateTheme(css) {
      const style = document.getElementById('theme-style');
      if (style) {
        style.textContent = css;
      }
    }

    // 更新字体设置
    function updateFontSettings(settings) {
      const content = getContent();
      if (!content) return;

      if (settings.fontSize) {
        content.style.fontSize = settings.fontSize + 'px';
      }
      if (settings.lineHeight) {
        content.style.lineHeight = settings.lineHeight;
      }
      if (settings.fontFamily) {
        content.style.fontFamily = settings.fontFamily;
      }
    }

    // 监听窗口大小变化
    window.addEventListener('resize', () => {
      // 延迟处理,避免频繁触发
      clearTimeout(window.resizeTimer);
      window.resizeTimer = setTimeout(() => {
        const oldPage = currentPage;
        const oldProgress = totalPages > 1 ? currentPage / (totalPages - 1) : 0;

        initPagination();

        // 尝试保持阅读进度
        if (isReady) {
          const newPage = Math.round(oldProgress * (totalPages - 1));
          goToPage(newPage, false);
        }
      }, 200);
    });

    // 页面加载完成后初始化
    document.addEventListener('DOMContentLoaded', () => {
      console.log('DOM 加载完成，准备初始化分页');
      // 等待内容渲染完成 - 使用多次 requestAnimationFrame 确保布局稳定
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          requestAnimationFrame(() => {
            initPagination();
          });
        });
      });
    });
  </script>
</body>
</html>
''';
  }

  /// 获取系统字体栈
  String _getSystemFontStack() {
    if (Platform.isIOS || Platform.isMacOS) {
      return '-apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", sans-serif';
    } else if (Platform.isWindows) {
      return '"Microsoft YaHei", "SimHei", "SimSun", sans-serif';
    } else if (Platform.isAndroid) {
      return '"Noto Sans SC", "Roboto", sans-serif';
    } else {
      return '"Noto Sans SC", sans-serif';
    }
  }

  /// 销毁渲染器
  void dispose() {
    _controller = null;
    _paginationInfo = null;
    _isReady = false;
  }
}
