import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';
import 'package:my_nas/features/book/presentation/pages/book_settings_page.dart';
import 'package:my_nas/features/book/presentation/pages/book_sources_page.dart';
import 'package:my_nas/features/book/presentation/providers/book_source_provider.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';
import 'package:my_nas/features/reading/presentation/providers/reader_settings_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';

/// 桌面「设置 · 阅读」详情 pane。
///
/// 对应设计稿 `settings_panes.jsx` 的 `PaneReading`：阅读器引擎、全局阅读偏好
/// 与在线书源（Legado 格式）列表。书源/图书设置的复杂管理沿用现有功能页
/// （[BookSourcesPage] / [BookSettingsPage]）。
class ReadingPane extends ConsumerWidget {
  const ReadingPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final settings = ref.watch(bookReaderSettingsProvider);
    final sourcesAsync = ref.watch(bookSourcesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.menu_book_outlined,
          title: '阅读',
          subtitle:
              '阅读器引擎、在线书源与全局阅读偏好。图书 / 漫画 / PDF 共享统一阅读进度（itemType 区分）。',
          actions: [
            AppButton(
              label: '导入书源',
              icon: Icons.add_rounded,
              onPressed: () => _openSources(context),
            ),
          ],
        ),

        // ---- 阅读器 ----
        SetSection(
          title: '阅读器',
          children: [
            SetRow(
              title: 'EPUB 引擎',
              desc: '原生（快、省内存）/ WebView（排版还原度高）',
              trailing: AppSegmented<EpubReaderEngine>(
                options: const [
                  AppSegmentedOption(
                    value: EpubReaderEngine.native,
                    label: 'EPUB 原生',
                  ),
                  AppSegmentedOption(
                    value: EpubReaderEngine.foliate,
                    label: 'WebView',
                  ),
                ],
                value: settings.epubEngine,
                onChanged: (v) => ref
                    .read(bookReaderSettingsProvider.notifier)
                    .setEpubEngine(v),
              ),
            ),
            SetRow(
              title: '保持屏幕常亮',
              desc: '阅读图书时不自动熄屏',
              trailing: AppSwitch(
                value: settings.keepScreenOn,
                onChanged: (v) => ref
                    .read(bookReaderSettingsProvider.notifier)
                    .setKeepScreenOn(value: v),
              ),
            ),
            SetRow(
              title: '显示阅读进度',
              desc: '在阅读器底部显示章节进度与百分比',
              trailing: AppSwitch(
                value: settings.showProgress,
                onChanged: (v) => ref
                    .read(bookReaderSettingsProvider.notifier)
                    .setShowProgress(value: v),
              ),
            ),
            SetRow(
              title: '全局阅读偏好',
              desc: '字号 / 字体 / 主题 / 翻页方式 — 新书自动套用',
              trailing: AppButton(
                label: '打开',
                icon: Icons.tune_rounded,
                dense: true,
                onPressed: () => _openBookSettings(context),
              ),
            ),
            SetRow(
              title: '阅读历史统计',
              desc: '阅读时长 / 完读率 / 日历热力图',
              last: true,
              trailing: const AppTag('即将推出', variant: TagVariant.plan),
            ),
          ],
        ),

        // ---- 在线书源 ----
        SetSection(
          title: '在线书源',
          hint: sourcesAsync.maybeWhen(
            data: (s) => 'Legado 格式 · ${s.length} 个',
            orElse: () => 'Legado 格式',
          ),
          children: _buildSourceRows(context, t, sourcesAsync),
        ),
      ],
    );
  }

  List<Widget> _buildSourceRows(
    BuildContext context,
    DesignTokens t,
    AsyncValue<List<BookSource>> sourcesAsync,
  ) {
    final preview = sourcesAsync.maybeWhen(
      data: (s) => s,
      orElse: () => const <BookSource>[],
    );

    final rows = <Widget>[];

    if (sourcesAsync.isLoading && preview.isEmpty) {
      rows.add(
        const SetRow(
          title: '加载中…',
          desc: '正在读取已配置的书源',
        ),
      );
    } else if (preview.isEmpty) {
      rows.add(
        const SetRow(
          title: '暂无书源',
          desc: '导入 Legado 格式书源后可在线搜索、阅读或加入书架',
        ),
      );
    } else {
      final shown = preview.take(4).toList();
      for (var i = 0; i < shown.length; i++) {
        final s = shown[i];
        final isLastRow = i == shown.length - 1 && preview.length <= 4;
        rows.add(
          SetRow(
            title: s.displayName,
            desc: '规则引擎：搜索 / 探索 / 正文 / 目录（CSS-XPath）',
            leading: _SourceIcon(t: t),
            last: isLastRow,
            trailing: AppTag(
              s.enabled ? '启用' : '停用',
              variant: s.enabled ? TagVariant.free : TagVariant.limit,
            ),
          ),
        );
      }
      if (preview.length > 4) {
        rows.add(
          SetRow(
            title: '查看全部 ${preview.length} 个书源',
            desc: '导入 / 编辑 / 启停 / 排序 / 在线搜索',
            last: true,
            trailing: AppButton(
              label: '管理',
              icon: Icons.tune_rounded,
              dense: true,
              onPressed: () => _openSources(context),
            ),
          ),
        );
      }
    }

    rows.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '书源支持导入 / 编辑 / 启停 / 搜索；在线结果可直接阅读或加入书架。',
                style: TextStyle(fontSize: 12, height: 1.4, color: t.text2),
              ),
            ),
            const SizedBox(width: 14),
            AppButton(
              label: '管理书源',
              icon: Icons.dns_rounded,
              dense: true,
              onPressed: () => _openSources(context),
            ),
          ],
        ),
      ),
    );

    return rows;
  }

  void _openSources(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const BookSourcesPage()),
      );

  void _openBookSettings(BuildContext context) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const BookSettingsPage()),
      );
}

/// 书源行左侧的小图标（对齐设计稿 `.conn-ic` 32×32）。
class _SourceIcon extends StatelessWidget {
  const _SourceIcon({required this.t});

  final DesignTokens t;

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: t.insetBg,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: t.hairline, width: 0.5),
        ),
        child: Icon(Icons.menu_book_outlined, size: 16, color: t.text2),
      );
}
