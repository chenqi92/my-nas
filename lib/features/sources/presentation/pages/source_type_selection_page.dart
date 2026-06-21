import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/source_form_page.dart';
import 'package:my_nas/shared/utils/form_l10n.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 源类型选择页面
///
/// 以分组列表形式展示所有可用的源类型，
/// 用户点击后进入对应的表单页面进行配置
class SourceTypeSelectionPage extends ConsumerWidget {
  const SourceTypeSelectionPage({
    super.key,
    this.allowedCategories,
  });

  /// 允许显示的分类列表
  /// 如果为 null，则显示所有分类
  final List<SourceCategory>? allowedCategories;

  /// 检查分类是否应该显示
  bool _shouldShowCategory(SourceCategory category) =>
      allowedCategories == null || allowedCategories!.contains(category);

  /// 检查是否有存储类分类
  bool get _hasStorageCategories =>
      allowedCategories == null ||
      allowedCategories!.any((c) => c.isStorageCategory);

  /// 检查是否有服务类分类
  bool get _hasServiceCategories =>
      allowedCategories == null ||
      allowedCategories!.any((c) => !c.isStorageCategory);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 根据允许的分类动态生成标题
    final title = allowedCategories == null
        ? context.l10n.sourceTypeSelectionAddConnection
        : _hasStorageCategories && !_hasServiceCategories
            ? context.l10n.sourceTypeSelectionAddConnection
            : !_hasStorageCategories && _hasServiceCategories
                ? context.l10n.sourceTypeSelectionAddService
                : context.l10n.sourceTypeSelectionAddConnection;

    return Scaffold(
      appBar: AppBar(
        leading: const RoundedBackButton(),
        title: Text(title),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          // 存储类源
          if (_hasStorageCategories) ...[
            _buildSectionHeader(context, '存储类源'),
            if (_shouldShowCategory(SourceCategory.nasDevices))
              _buildCategorySection(
                context,
                SourceCategory.nasDevices,
                SourceType.byCategory(SourceCategory.nasDevices),
              ),
            if (_shouldShowCategory(SourceCategory.genericProtocols))
              _buildCategorySection(
                context,
                SourceCategory.genericProtocols,
                SourceType.byCategory(SourceCategory.genericProtocols),
              ),
            // 本地存储：仅在桌面端显示（iOS/Android 沙盒无价值）
            if (_shouldShowCategory(SourceCategory.localStorage) &&
                !kIsWeb &&
                (Platform.isWindows || Platform.isMacOS || Platform.isLinux))
              _buildCategorySection(
                context,
                SourceCategory.localStorage,
                SourceType.byCategory(SourceCategory.localStorage),
              ),
            // 移动端媒体：不在连接源页面显示，仅通过媒体库添加
            // 用户在媒体库页面点击"添加本机"时会自动创建对应源
            if (_shouldShowCategory(SourceCategory.mediaServers))
              _buildCategorySection(
                context,
                SourceCategory.mediaServers,
                SourceType.byCategory(SourceCategory.mediaServers),
              ),
            const SizedBox(height: 16),
          ],

          // 服务类源
          if (_hasServiceCategories) ...[
            _buildSectionHeader(context, '服务类源'),
            if (_shouldShowCategory(SourceCategory.downloadTools))
              _buildCategorySection(
                context,
                SourceCategory.downloadTools,
                SourceType.byCategory(SourceCategory.downloadTools),
              ),
            if (_shouldShowCategory(SourceCategory.mediaTracking))
              _buildCategorySection(
                context,
                SourceCategory.mediaTracking,
                SourceType.byCategory(SourceCategory.mediaTracking),
              ),
            if (_shouldShowCategory(SourceCategory.mediaManagement))
              _buildCategorySection(
                context,
                SourceCategory.mediaManagement,
                SourceType.byCategory(SourceCategory.mediaManagement),
              ),
            if (_shouldShowCategory(SourceCategory.ptSites))
              _buildCategorySection(
                context,
                SourceCategory.ptSites,
                SourceType.byCategory(SourceCategory.ptSites),
              ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// 构建分组标题
  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 构建分类区块
  Widget _buildCategorySection(
    BuildContext context,
    SourceCategory category,
    List<SourceType> types,
  ) {
    if (types.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (int i = 0; i < types.length; i++) ...[
              _buildSourceTypeTile(context, types[i]),
              if (i < types.length - 1)
                Divider(
                  height: 1,
                  indent: 56,
                  endIndent: 0,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建源类型列表项
  Widget _buildSourceTypeTile(BuildContext context, SourceType type) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSupported = type.isSupported;

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSupported
              ? colorScheme.primaryContainer.withValues(alpha: 0.5)
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          type.icon,
          color: isSupported
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          size: 22,
        ),
      ),
      title: Row(
        children: [
          Text(
            localizeFormText(context, type.displayName),
            style: TextStyle(
              color: isSupported ? null : colorScheme.onSurfaceVariant,
            ),
          ),
          if (!isSupported) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                context.l10n.sourceTypeSelectionComingSoon,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        localizeFormText(context, type.description),
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: isSupported
            ? colorScheme.onSurfaceVariant
            : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
      ),
      enabled: isSupported,
      onTap: isSupported
          ? () => SourceFormPage.openAdaptive<void>(
                context,
                sourceType: type,
                popTwice: true,
              )
          : null,
    );
  }
}
