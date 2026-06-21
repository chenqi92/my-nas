import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/utils/form_l10n.dart';

/// 媒体模块设置状态
enum MediaSetupState {
  /// 没有配置任何源
  noSources,

  /// 有源但没连接
  notConnected,

  /// 已连接但没有配置媒体库路径
  noLibraryPaths,

  /// 已配置路径但源未连接
  pathsNotConnected,

  /// 一切就绪
  ready,
}

/// 媒体模块设置状态 Provider
final mediaSetupStateProvider =
    Provider.family<MediaSetupState, MediaType>((ref, mediaType) {
  final sourcesAsync = ref.watch(sourcesProvider);
  final connections = ref.watch(activeConnectionsProvider);
  final configAsync = ref.watch(mediaLibraryConfigProvider);

  final sources = sourcesAsync.valueOrNull ?? [];
  final config = configAsync.valueOrNull;

  // 1. 检查是否有源
  if (sources.isEmpty) {
    return MediaSetupState.noSources;
  }

  // 2. 检查是否有任何连接的源
  final hasConnectedSource = connections.values
      .any((conn) => conn.status == SourceStatus.connected);

  // 3. 检查是否有配置的媒体库路径
  final paths = config?.getEnabledPathsForType(mediaType) ?? [];

  if (paths.isEmpty) {
    // 没有配置路径
    if (hasConnectedSource) {
      return MediaSetupState.noLibraryPaths;
    } else {
      return MediaSetupState.notConnected;
    }
  }

  // 有配置的路径，检查这些路径对应的源是否已连接
  final connectedPaths = paths.where((path) {
    final conn = connections[path.sourceId];
    return conn?.status == SourceStatus.connected;
  }).toList();

  if (connectedPaths.isEmpty) {
    return MediaSetupState.pathsNotConnected;
  }

  return MediaSetupState.ready;
});

/// 智能媒体模块空状态组件
class MediaSetupWidget extends ConsumerWidget {
  const MediaSetupWidget({
    required this.mediaType, super.key,
    this.icon,
    this.emptyTitle,
    this.emptyMessage,
  });

  final MediaType mediaType;
  final IconData? icon;
  final String? emptyTitle;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mediaSetupStateProvider(mediaType));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildIcon(context, state, isDark),
            const SizedBox(height: 24),
            _buildTitle(context, state, isDark),
            const SizedBox(height: 12),
            _buildMessage(context, state, isDark),
            const SizedBox(height: 32),
            _buildAction(context, state),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(BuildContext context, MediaSetupState state, bool isDark) {
    final iconData = switch (state) {
      MediaSetupState.noSources => Icons.cloud_off_rounded,
      MediaSetupState.notConnected => Icons.cloud_off_rounded,
      MediaSetupState.noLibraryPaths => Icons.folder_open_rounded,
      MediaSetupState.pathsNotConnected => Icons.link_off_rounded,
      MediaSetupState.ready => icon ?? _getDefaultIcon(),
    };

    final color = switch (state) {
      MediaSetupState.noSources => AppColors.primary,
      MediaSetupState.notConnected => AppColors.warning,
      MediaSetupState.noLibraryPaths => AppColors.primary,
      MediaSetupState.pathsNotConnected => AppColors.warning,
      MediaSetupState.ready => AppColors.primary,
    };

    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(
        iconData,
        size: 40,
        color: color,
      ),
    );
  }

  Widget _buildTitle(BuildContext context, MediaSetupState state, bool isDark) {
    final l = context.l10n;
    final typeName = localizeFormText(context, mediaType.displayName);
    final title = switch (state) {
      MediaSetupState.noSources => l.mediaSetupTitleNoSources,
      MediaSetupState.notConnected => l.mediaSetupTitleNotConnected,
      MediaSetupState.noLibraryPaths => l.mediaSetupTitleNoLibraryPaths(typeName),
      MediaSetupState.pathsNotConnected => l.mediaSetupTitlePathsNotConnected,
      MediaSetupState.ready => emptyTitle ?? l.mediaSetupTitleReady(typeName),
    };

    return Text(
      title,
      style: context.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: isDark ? AppColors.darkOnSurface : null,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildMessage(
      BuildContext context, MediaSetupState state, bool isDark) {
    final l = context.l10n;
    final typeName = localizeFormText(context, mediaType.displayName);
    final message = switch (state) {
      MediaSetupState.noSources => l.mediaSetupMsgNoSources(typeName),
      MediaSetupState.notConnected => l.mediaSetupMsgNotConnected,
      MediaSetupState.noLibraryPaths => l.mediaSetupMsgNoLibraryPaths(typeName),
      MediaSetupState.pathsNotConnected => l.mediaSetupMsgPathsNotConnected,
      MediaSetupState.ready => emptyMessage ?? l.mediaSetupMsgReady(typeName),
    };

    return Text(
      message,
      style: context.textTheme.bodyMedium?.copyWith(
        color: isDark
            ? AppColors.darkOnSurfaceVariant
            : AppColors.lightOnSurfaceVariant,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildAction(BuildContext context, MediaSetupState state) {
    final (label, actionIcon, onTap) = switch (state) {
      MediaSetupState.noSources => (
          appL10n.mediaSetupActionAddConnection,
          Icons.add_rounded,
          () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
              )
        ),
      MediaSetupState.notConnected => (
          appL10n.mediaSetupActionGoConnect,
          Icons.link_rounded,
          () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
              )
        ),
      MediaSetupState.noLibraryPaths => (
          appL10n.mediaSetupActionSelectDirectory,
          Icons.folder_rounded,
          () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const MediaLibraryPage()),
              )
        ),
      MediaSetupState.pathsNotConnected => (
          appL10n.mediaSetupActionGoConnect,
          Icons.link_rounded,
          () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
              )
        ),
      MediaSetupState.ready => (null, null, null),
    };

    if (label == null) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(actionIcon, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getDefaultIcon() => switch (mediaType) {
      MediaType.video => Icons.movie_outlined,
      MediaType.music => Icons.library_music_outlined,
      MediaType.photo => Icons.photo_library_outlined,
      MediaType.comic => Icons.collections_outlined,
      MediaType.book => Icons.menu_book_outlined,
      MediaType.note => Icons.note_outlined,
    };
}
