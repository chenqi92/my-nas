import 'package:flutter/material.dart';

/// TTS 高亮控制器
///
/// 根据 TTS 进度回调生成高亮 TextSpan。
/// 支持段落级和字符级高亮。
class TTSHighlightController extends ChangeNotifier {
  int _currentStart = 0;
  int _currentEnd = 0;
  String _currentWord = '';
  bool _enabled = true;

  int get currentStart => _currentStart;
  int get currentEnd => _currentEnd;
  String get currentWord => _currentWord;
  bool get enabled => _enabled;

  /// 更新 TTS 进度
  void onTTSProgress(int start, int end, String word) {
    if (_currentStart != start || _currentEnd != end) {
      _currentStart = start;
      _currentEnd = end;
      _currentWord = word;
      notifyListeners();
    }
  }

  /// 重置高亮
  void reset() {
    _currentStart = 0;
    _currentEnd = 0;
    _currentWord = '';
    notifyListeners();
  }

  /// 设置是否启用高亮
  void setEnabled(bool enabled) {
    if (_enabled != enabled) {
      _enabled = enabled;
      notifyListeners();
    }
  }

  /// 构建高亮文本
  ///
  /// [fullText] 完整文本
  /// [readStyle] 已读部分样式
  /// [highlightStyle] 当前朗读部分样式 (高亮)
  /// [unreadStyle] 未读部分样式
  TextSpan buildHighlightedText(
    String fullText, {
    TextStyle? readStyle,
    TextStyle? highlightStyle,
    TextStyle? unreadStyle,
  }) {
    if (!_enabled || _currentEnd <= 0 || _currentEnd > fullText.length) {
      return TextSpan(text: fullText, style: unreadStyle);
    }

    final safeStart = _currentStart.clamp(0, fullText.length);
    final safeEnd = _currentEnd.clamp(safeStart, fullText.length);

    return TextSpan(
      children: [
        // 已读部分
        if (safeStart > 0)
          TextSpan(
            text: fullText.substring(0, safeStart),
            style: readStyle,
          ),
        // 当前朗读部分 (高亮)
        TextSpan(
          text: fullText.substring(safeStart, safeEnd),
          style: highlightStyle,
        ),
        // 未读部分
        if (safeEnd < fullText.length)
          TextSpan(
            text: fullText.substring(safeEnd),
            style: unreadStyle,
          ),
      ],
    );
  }
}

/// 段落高亮样式生成器
class ParagraphHighlightBuilder {
  const ParagraphHighlightBuilder({
    required this.paragraphs,
    required this.currentParagraphIndex,
    required this.charStart,
    required this.charEnd,
    required this.theme,
    this.highlightEnabled = true,
  });

  final List<String> paragraphs;
  final int currentParagraphIndex;
  final int charStart;
  final int charEnd;
  final ThemeData theme;
  final bool highlightEnabled;

  /// 构建单个段落的 Widget
  Widget buildParagraph(int index, {double fontSize = 18.0}) {
    final text = paragraphs[index];
    final isCurrentParagraph = index == currentParagraphIndex;

    if (!highlightEnabled || !isCurrentParagraph) {
      // 非当前段落，普通显示
      return Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.8,
          color: isCurrentParagraph
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      );
    }

    // 当前段落，带高亮
    return RichText(
      text: _buildHighlightedSpan(text, fontSize),
    );
  }

  TextSpan _buildHighlightedSpan(String text, double fontSize) {
    if (charEnd <= 0 || charEnd > text.length) {
      return TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.8,
          color: theme.colorScheme.onSurface,
        ),
      );
    }

    final safeStart = charStart.clamp(0, text.length);
    final safeEnd = charEnd.clamp(safeStart, text.length);

    // 已读样式
    final readStyle = TextStyle(
      fontSize: fontSize,
      height: 1.8,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
    );

    // 高亮样式
    final highlightStyle = TextStyle(
      fontSize: fontSize,
      height: 1.8,
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
    );

    // 未读样式
    final unreadStyle = TextStyle(
      fontSize: fontSize,
      height: 1.8,
      color: theme.colorScheme.onSurface,
    );

    return TextSpan(
      children: [
        if (safeStart > 0)
          TextSpan(text: text.substring(0, safeStart), style: readStyle),
        TextSpan(
            text: text.substring(safeStart, safeEnd), style: highlightStyle),
        if (safeEnd < text.length)
          TextSpan(text: text.substring(safeEnd), style: unreadStyle),
      ],
    );
  }

  /// 构建段落背景装饰
  BoxDecoration? buildParagraphDecoration(int index) {
    if (!highlightEnabled || index != currentParagraphIndex) {
      return null;
    }

    return BoxDecoration(
      color: theme.colorScheme.primary.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(8),
    );
  }
}

/// 自动滚动控制器
class TTSAutoScrollController {
  ScrollController? _scrollController;
  final Map<int, GlobalKey> _paragraphKeys = {};

  /// 绑定滚动控制器
  void attachScrollController(ScrollController controller) {
    _scrollController = controller;
  }

  /// 注册段落 Key
  GlobalKey registerParagraph(int index) {
    _paragraphKeys[index] ??= GlobalKey();
    return _paragraphKeys[index]!;
  }

  /// 滚动到指定段落
  Future<void> scrollToParagraph(int index, {Duration? duration}) async {
    final key = _paragraphKeys[index];
    if (key == null || _scrollController == null) return;

    final context = key.currentContext;
    if (context == null) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // 获取段落位置
    final scrollableContext = _scrollController!.position.context.storageContext;
    final scrollableRenderObject = scrollableContext.findRenderObject();
    if (scrollableRenderObject == null) return;

    final offset = renderBox.localToGlobal(
      Offset.zero,
      ancestor: scrollableRenderObject,
    );

    // 计算滚动目标位置 (将段落滚动到视口中间)
    final viewportHeight = _scrollController!.position.viewportDimension;
    final targetOffset = _scrollController!.offset +
        offset.dy -
        viewportHeight / 3;

    final clampedOffset = targetOffset.clamp(
      _scrollController!.position.minScrollExtent,
      _scrollController!.position.maxScrollExtent,
    );

    await _scrollController!.animateTo(
      clampedOffset,
      duration: duration ?? const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// 释放资源
  void dispose() {
    _paragraphKeys.clear();
    _scrollController = null;
  }
}
