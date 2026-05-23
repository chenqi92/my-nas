import 'package:flutter/material.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';

/// 在线书籍页面内容组件
///
/// 渲染单页的纯文本内容，使用 BookReaderSettings 中的样式设置。
class OnlinePageContent extends StatelessWidget {
  const OnlinePageContent({
    required this.content,
    required this.settings,
    this.chapterTitle,
    super.key,
  });

  /// 页面文本内容
  final String content;

  /// 阅读设置
  final BookReaderSettings settings;

  /// 章节标题（可选，显示在页面顶部）
  final String? chapterTitle;

  @override
  Widget build(BuildContext context) => Container(
      color: settings.theme.backgroundColor,
      padding: EdgeInsets.symmetric(
        horizontal: settings.horizontalPadding,
        vertical: settings.verticalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 章节标题（如有）
          if (chapterTitle != null) ...[
            Text(
              chapterTitle!,
              style: TextStyle(
                fontSize: settings.fontSize + 4,
                fontWeight: FontWeight.bold,
                color: settings.theme.textColor,
                fontFamily: settings.fontFamily,
                height: settings.lineHeight,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: settings.lineHeight * 8),
          ],
          // 正文内容
          Expanded(
            child: Text(
              content,
              style: TextStyle(
                fontSize: settings.fontSize,
                height: settings.lineHeight,
                color: settings.theme.textColor,
                fontFamily: settings.fontFamily,
              ),
              textAlign: TextAlign.justify,
            ),
          ),
        ],
      ),
    );
}

/// 简化版页面内容（不带章节标题，纯内容渲染）
class SimplePageContent extends StatelessWidget {
  const SimplePageContent({
    required this.content,
    required this.settings,
    super.key,
  });

  final String content;
  final BookReaderSettings settings;

  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.symmetric(
        horizontal: settings.horizontalPadding,
        vertical: settings.verticalPadding,
      ),
      child: Text(
        content,
        style: TextStyle(
          fontSize: settings.fontSize,
          height: settings.lineHeight,
          color: settings.theme.textColor,
          fontFamily: settings.fontFamily,
        ),
        textAlign: TextAlign.justify,
      ),
    );
}
