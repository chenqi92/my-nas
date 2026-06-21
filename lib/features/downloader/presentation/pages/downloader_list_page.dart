import 'package:flutter/material.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/presentation/pages/service_sources_page.dart';

/// 下载器列表页面
class DownloaderListPage extends StatelessWidget {
  const DownloaderListPage({super.key});

  @override
  Widget build(BuildContext context) => ServiceSourcesPage(
        title: context.l10n.downloaderListPageTitle,
        category: SourceCategory.downloadTools,
        emptyIcon: Icons.download_rounded,
        emptyTitle: context.l10n.downloaderListPageEmptyTitle,
        emptySubtitle: context.l10n.downloaderListPageEmptySubtitle,
      );
}
