import 'package:flutter/material.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/presentation/pages/service_sources_page.dart';

/// PT 站点列表页面
///
/// 用于管理 PT 站点连接（馒头等）
class PTSitesListPage extends StatelessWidget {
  const PTSitesListPage({super.key});

  @override
  Widget build(BuildContext context) => ServiceSourcesPage(
    title: context.l10n.ptSitesListTitle,
    category: SourceCategory.ptSites,
    emptyIcon: Icons.rss_feed_rounded,
    emptyTitle: context.l10n.ptSitesListEmptyTitle,
    emptySubtitle: context.l10n.ptSitesListEmptySubtitle,
  );
}
