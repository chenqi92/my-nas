import 'package:flutter/material.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/presentation/pages/service_sources_page.dart';

/// 媒体管理列表页面
class MediaManagementListPage extends StatelessWidget {
  const MediaManagementListPage({super.key});

  @override
  Widget build(BuildContext context) => ServiceSourcesPage(
        title: '媒体管理',
        category: SourceCategory.mediaManagement,
        emptyIcon: Icons.construction_rounded,
        emptyTitle: context.l10n.mediaManagementEmptyTitle,
        emptySubtitle: context.l10n.mediaManagementEmptySubtitle,
      );
}
