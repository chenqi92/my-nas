import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 分页后的页面
class EbookPage {
  EbookPage({
    required this.pageIndex,
    required this.chapterIndex,
    required this.htmlContent,
    required this.progress,
  });

  /// 页面索引（全局）
  final int pageIndex;

  /// 所属章节索引
  final int chapterIndex;

  /// 该页 HTML 内容
  final String htmlContent;

  /// 进度 (0.0 - 1.0)
  final double progress;

  /// 纯文本内容 (用于 TTS 朗读)
  String get textContent => htmlContent
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp('</p>|</div>|</h[1-6]>'), '\n\n')
        .replaceAll(RegExp('<[^>]+>'), '')
        .replaceAll(RegExp('&nbsp;'), ' ')
        .replaceAll(RegExp('&lt;'), '<')
        .replaceAll(RegExp('&gt;'), '>')
        .replaceAll(RegExp('&amp;'), '&')
        .replaceAll(RegExp('&quot;'), '"')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
}

/// 分页信息
class PaginationResult {
  PaginationResult({
    required this.pages,
    required this.totalPages,
    required this.chapterPageRanges,
  });

  /// 所有页面
  final List<EbookPage> pages;

  /// 总页数
  final int totalPages;

  /// 每个章节的页面范围 [startPage, endPage]
  final List<(int, int)> chapterPageRanges;
}

/// 原生 EPUB 分页器
///
/// 将 HTML 内容分页，计算每页显示的内容范围。
/// 使用文本测量来精确计算每页能容纳的内容。
class NativeEpubPaginator {
  NativeEpubPaginator._();
  static final NativeEpubPaginator instance = NativeEpubPaginator._();

  /// 对章节内容进行分页
  ///
  /// [htmlContents] - 每个章节的 HTML 内容列表
  /// [viewportSize] - 可用视口大小
  /// [baseStyle] - 基础文本样式
  /// [lineHeight] - 行高倍数
  Future<PaginationResult> paginate({
    required List<String> htmlContents,
    required Size viewportSize,
    required TextStyle baseStyle,
    double lineHeight = 1.5,
    double horizontalPadding = 24,
    double verticalPadding = 16,
  }) async {
    final stopwatch = Stopwatch()..start();

    final pages = <EbookPage>[];
    final chapterPageRanges = <(int, int)>[];

    // 计算可用内容区域
    final contentWidth = viewportSize.width - horizontalPadding * 2;
    final contentHeight = viewportSize.height - verticalPadding * 2;

    var globalPageIndex = 0;

    for (var chapterIndex = 0; chapterIndex < htmlContents.length; chapterIndex++) {
      final htmlContent = htmlContents[chapterIndex];
      final chapterStartPage = globalPageIndex;

      // 使用简化的分页策略：按段落分割
      final chapterPages = _paginateHtml(
        htmlContent: htmlContent,
        contentWidth: contentWidth,
        contentHeight: contentHeight,
        baseStyle: baseStyle,
        lineHeight: lineHeight,
      );

      for (var i = 0; i < chapterPages.length; i++) {
        pages.add(EbookPage(
          pageIndex: globalPageIndex,
          chapterIndex: chapterIndex,
          htmlContent: chapterPages[i],
          progress: (globalPageIndex + 1) / (chapterPages.length * htmlContents.length),
        ));
        globalPageIndex++;
      }

      chapterPageRanges.add((chapterStartPage, globalPageIndex - 1));
    }

    // 更新进度
    for (var i = 0; i < pages.length; i++) {
      pages[i] = EbookPage(
        pageIndex: pages[i].pageIndex,
        chapterIndex: pages[i].chapterIndex,
        htmlContent: pages[i].htmlContent,
        progress: (i + 1) / pages.length,
      );
    }

    stopwatch.stop();
    logger.i(
      'NativeEpubPaginator: 分页完成, '
      '${htmlContents.length} 章节, ${pages.length} 页, '
      '耗时 ${stopwatch.elapsedMilliseconds}ms',
    );

    return PaginationResult(
      pages: pages,
      totalPages: pages.length,
      chapterPageRanges: chapterPageRanges,
    );
  }

  /// 对单个章节的 HTML 进行分页
  List<String> _paginateHtml({
    required String htmlContent,
    required double contentWidth,
    required double contentHeight,
    required TextStyle baseStyle,
    required double lineHeight,
  }) {
    // 提取段落
    final paragraphs = _extractParagraphs(htmlContent);

    if (paragraphs.isEmpty) {
      return [htmlContent];
    }

    final pages = <String>[];
    var currentPageParagraphs = <String>[];
    var currentHeight = 0.0;

    // 估算每行高度
    final lineHeightPx = baseStyle.fontSize! * lineHeight;

    for (final paragraph in paragraphs) {
      // 估算段落高度
      final paragraphHeight = _estimateParagraphHeight(
        paragraph: paragraph,
        contentWidth: contentWidth,
        baseStyle: baseStyle,
        lineHeightPx: lineHeightPx,
      );

      // 如果加入这个段落会超出页面高度
      if (currentHeight + paragraphHeight > contentHeight && currentPageParagraphs.isNotEmpty) {
        // 保存当前页
        pages.add(currentPageParagraphs.join('\n'));
        currentPageParagraphs = [];
        currentHeight = 0;
      }

      currentPageParagraphs.add(paragraph);
      currentHeight += paragraphHeight;
    }

    // 保存最后一页
    if (currentPageParagraphs.isNotEmpty) {
      pages.add(currentPageParagraphs.join('\n'));
    }

    return pages.isEmpty ? [htmlContent] : pages;
  }

  /// 从 HTML 中提取段落
  List<String> _extractParagraphs(String html) {
    final paragraphs = <String>[];

    // 匹配 <p>, <div>, <h1>-<h6> 等块级元素
    final blockPattern = RegExp(
      r'<(p|div|h[1-6]|li|blockquote|pre)[^>]*>[\s\S]*?</\1>',
      caseSensitive: false,
    );

    final matches = blockPattern.allMatches(html);

    if (matches.isEmpty) {
      // 没有块级元素，按换行分割
      final lines = html.split(RegExp(r'<br\s*/?>|\n'));
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          paragraphs.add('<p>$trimmed</p>');
        }
      }
    } else {
      for (final match in matches) {
        paragraphs.add(match.group(0) ?? '');
      }
    }

    return paragraphs;
  }

  /// 估算段落高度
  double _estimateParagraphHeight({
    required String paragraph,
    required double contentWidth,
    required TextStyle baseStyle,
    required double lineHeightPx,
  }) {
    // 移除 HTML 标签，获取纯文本
    final plainText = paragraph
        .replaceAll(RegExp('<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (plainText.isEmpty) {
      return lineHeightPx; // 空段落占一行
    }

    // 使用 TextPainter 测量文本
    final textPainter = TextPainter(
      text: TextSpan(text: plainText, style: baseStyle),
      textDirection: ui.TextDirection.ltr,
      maxLines: null,
    );

    textPainter.layout(maxWidth: contentWidth);

    // 计算行数
    final lineMetrics = textPainter.computeLineMetrics();
    final lineCount = lineMetrics.length;

    // 段落后加一些间距
    const paragraphSpacing = 8.0;

    return lineCount * lineHeightPx + paragraphSpacing;
  }

  /// 根据进度获取页面索引
  int getPageIndexFromProgress(double progress, int totalPages) {
    if (progress <= 0) return 0;
    if (progress >= 1) return totalPages - 1;
    return (progress * totalPages).floor().clamp(0, totalPages - 1);
  }

  /// 根据章节索引获取起始页面索引
  int getPageIndexFromChapter(
    int chapterIndex,
    List<(int, int)> chapterPageRanges,
  ) {
    if (chapterIndex < 0 || chapterIndex >= chapterPageRanges.length) {
      return 0;
    }
    return chapterPageRanges[chapterIndex].$1;
  }
}

/// HTML 内容渲染 Widget
///
/// 使用 flutter_widget_from_html_core 渲染 HTML 内容
class HtmlContentWidget extends StatelessWidget {
  const HtmlContentWidget({
    required this.html,
    this.textStyle,
    this.onTapUrl,
    this.imageProvider,
    super.key,
  });

  final String html;
  final TextStyle? textStyle;
  final void Function(String url)? onTapUrl;
  final ImageProvider? Function(String url)? imageProvider;

  @override
  Widget build(BuildContext context) => HtmlWidget(
      html,
      textStyle: textStyle,
      onTapUrl: onTapUrl != null
          ? (url) {
              onTapUrl!(url);
              return true;
            }
          : null,
      factoryBuilder: () => _CustomWidgetFactory(imageProvider: imageProvider),
    );
}

/// 自定义 Widget 工厂，用于处理图片等资源
class _CustomWidgetFactory extends WidgetFactory {
  _CustomWidgetFactory({this.imageProvider});

  final ImageProvider? Function(String url)? imageProvider;

  @override
  Widget? buildImageWidget(BuildTree meta, ImageSource src) {
    if (imageProvider != null && src.url.isNotEmpty) {
      final provider = imageProvider!(src.url);
      if (provider != null) {
        return Image(
          image: provider,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        );
      }
    }
    return super.buildImageWidget(meta, src);
  }
}
