import 'package:flutter/material.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';

/// 桌面端「阅读」骨架。
///
/// 视觉对齐设计稿 media2.jsx (Reading)：全部 / 漫画 / 图书 / 笔记 chips +
/// 在线书源入口 + media-grid（漫画 ratio 3/4，图书 ratio 3/4）+ 笔记面板。
class ReadingDesktopPage extends StatefulWidget {
  const ReadingDesktopPage({super.key});

  @override
  State<ReadingDesktopPage> createState() => _ReadingDesktopPageState();
}

class _ReadingDesktopPageState extends State<ReadingDesktopPage> {
  String _tab = '全部';

  static const _tabs = ['全部', '漫画', '图书', '笔记'];

  @override
  Widget build(BuildContext context) {
    return DesktopPageScaffold(
      title: '阅读',
      subtitle: '漫画 · 图书 · 笔记 聚合 — 统一阅读进度（按类型区分，共享书签）',
      actions: Row(
        children: [
          for (final t in _tabs)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: AppChip(
                label: t,
                active: t == _tab,
                compact: true,
                onTap: () => setState(() => _tab = t),
              ),
            ),
          const SizedBox(width: 12),
          const AppChip(
            label: '在线书源',
            icon: Icons.language_rounded,
            compact: true,
          ),
        ],
      ),
      body: DesktopComingSoon(
        icon: _tab == '笔记'
            ? Icons.edit_note_rounded
            : _tab == '漫画'
                ? Icons.collections_bookmark_outlined
                : Icons.menu_book_outlined,
        message: switch (_tab) {
          '笔记' =>
            'Markdown 编辑 · 待办（- [ ]）解析 · 优先级 / 截止 / 逾期提示 · 多层目录树。',
          '漫画' => '映射「漫画」媒体库后，此处显示漫画书架（封面 + 续读进度）。',
          '图书' => '映射「图书」媒体库后，此处显示图书书架 + EPUB / PDF / TXT 入口。',
          _ => '聚合视图：漫画 + 图书 + 笔记 一并展示，按统一阅读进度排序。',
        },
      ),
    );
  }
}
