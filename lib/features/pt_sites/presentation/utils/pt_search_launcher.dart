import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/pt_sites/presentation/pages/pt_site_detail_page.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';

/// 跳转到 PT 站搜索（带预填关键词）
///
/// 调用场景：从视频详情、相似/推荐卡片等位置带着片名快速发起 PT 资源搜索。
///
/// 行为：
/// - 当前没有任何 PT 站点 → 提示用户去添加
/// - 仅 1 个 PT 站 → 直接跳转到该站搜索页
/// - 多个 PT 站 → 弹底部 sheet 让用户选择
Future<void> launchPtSearchForMedia(
  BuildContext context,
  WidgetRef ref, {
  required String query,
}) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    context.showToast(context.l10n.ptSearchNoKeywordToast);
    return;
  }

  final allSources = ref.read(sourcesProvider).valueOrNull ?? const <SourceEntity>[];
  final ptSites = allSources
      .where((s) => s.type.category == SourceCategory.ptSites)
      .where((s) => s.type.isSupported)
      .toList();

  if (ptSites.isEmpty) {
    context.showToast(context.l10n.ptSearchNoSitesConfiguredToast);
    return;
  }

  SourceEntity? target;
  if (ptSites.length == 1) {
    target = ptSites.first;
  } else {
    target = await showAdaptiveModalSheet<SourceEntity>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.ptSearchSelectSiteDialogTitle(trimmed),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ...ptSites.map(
              (site) => ListTile(
                leading: Icon(site.type.icon, color: site.type.themeColor),
                title: Text(
                  site.name.isEmpty ? site.type.displayName : site.name,
                ),
                subtitle: Text(
                  site.host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(sheetContext, site),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  if (target == null || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PTSiteDetailPage(
        source: target!,
        initialQuery: trimmed,
      ),
    ),
  );
}
