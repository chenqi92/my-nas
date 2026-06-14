import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/source_form_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';
import 'package:my_nas/shared/widgets/dialogs/source_wizard_dialog.dart';

/// 桌面端「数据源」骨架。
///
/// 视觉对齐设计稿 ops2.jsx (Sources)：source card grid + 状态点 + 库映射
/// chips + 「添加源」走 [SourceWizardDialog] 多步弹窗。
class SourcesDesktopPage extends ConsumerWidget {
  const SourcesDesktopPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final sourcesAsync = ref.watch(sourcesProvider);
    final connections = ref.watch(activeConnectionsProvider);
    final t = DesignTokens.of(context);

    return DesktopPageScaffold(
      title: l.sourcesPageTitle,
      subtitle: l.sourcesPageSubtitle,
      actions: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: FilledButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            barrierColor: Colors.black.withValues(alpha: 0.5),
            builder: (_) => const SourceWizardDialog(),
          ),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: Text(l.sourcesPageAddSource),
        ),
      ),
      body: sourcesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text(
          l.sourcesPageLoadError(e.toString()),
          style: TextStyle(color: t.err),
        ),
        data: (sources) {
          if (sources.isEmpty) {
            return DesktopComingSoon(
              icon: Icons.lan_outlined,
              message: l.sourcesPageEmptyHint,
            );
          }
          // 库映射来自 mediaLibraryConfig 派生：源 → 已映射的媒体类型集合，
          // 设计稿 s.libs 没有对应后端字段，故从既有 state 派生而非臆造。
          final libsConfig = ref.watch(mediaLibraryConfigProvider).valueOrNull;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sources.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 330,
              mainAxisExtent: 168,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemBuilder: (_, i) {
              final s = sources[i];
              return _SourceCard(
                source: s,
                conn: connections[s.id],
                libs: _libsForSource(libsConfig, s.id),
              );
            },
          );
        },
      ),
    );
  }

  /// 从媒体库配置派生某源已映射的媒体类型展示名（视频/音乐/…）。
  static List<String> _libsForSource(
    MediaLibraryConfig? config,
    String sourceId,
  ) {
    if (config == null) return const [];
    return [
      for (final type in MediaType.values)
        if (config.getPathsForType(type).any((p) => p.sourceId == sourceId))
          type.displayName,
    ];
  }
}

/// 单张数据源卡片。视觉对齐 ops2.jsx Sources 49-67。
class _SourceCard extends ConsumerWidget {
  const _SourceCard({
    required this.source,
    required this.conn,
    required this.libs,
  });

  final SourceEntity source;
  final SourceConnection? conn;
  final List<String> libs;

  /// 测试 / 重新连接当前源，并把结果以 SnackBar 反馈。
  Future<void> _reconnect(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(l.sourcesPageConnecting(source.name))),
    );
    final result =
        await ref.read(activeConnectionsProvider.notifier).reconnect(source.id);
    if (!context.mounted) return;
    final ok = result?.status == SourceStatus.connected;
    final need2fa = result?.status == SourceStatus.requires2FA;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? l.sourcesPageConnectSuccess(source.name)
                : need2fa
                    ? l.sourcesPageConnectNeeds2FA(source.name)
                    : l.sourcesPageConnectFailed(
                        source.name,
                        result?.errorMessage != null
                            ? l.sourcesPageErrorSuffix(result!.errorMessage!)
                            : '',
                      ),
          ),
        ),
      );
  }

  void _edit(BuildContext context) {
    SourceFormPage.openAdaptive<SourceEntity>(
      context,
      sourceType: source.type,
      existingSource: source,
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.sourcesPageDeleteTitle),
        content: Text(l.sourcesPageDeleteConfirm(source.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.sourcesPageCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.sourcesPageDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // 先解除库映射，再删源（源删除内部级联清理各库媒体数据）。
    await ref
        .read(mediaLibraryConfigProvider.notifier)
        .removePathsForSource(source.id);
    await ref.read(sourcesProvider.notifier).removeSource(source.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    // 未实现的源类型即「即将推出」，与设计稿 plan 态对齐。
    final isPlan = !source.type.isSupported;
    final status = conn?.status;
    final (dot, label, isErr) =
        _statusView(l, isPlan, status, conn?.errorMessage);

    final card = AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: t.insetBg,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(source.type.icon, size: 20, color: t.accentBright),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            source.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: t.text0,
                            ),
                          ),
                        ),
                        // 「需 2FA」从实时连接态派生（无静态 two_fa 字段）。
                        if (status == SourceStatus.requires2FA) ...[
                          const SizedBox(width: 7),
                          const AppTag('2FA', variant: TagVariant.accent),
                        ],
                      ],
                    ),
                    Text(
                      source.host.isEmpty
                          ? source.type.displayName
                          : '${source.type.displayName} · ${source.host}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: t.text2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isPlan)
                AppTag(l.sourcesPageComingSoon, variant: TagVariant.plan)
              else
                _SourceMenu(
                  color: t.text2,
                  onEdit: () => _edit(context),
                  onReconnect: () => _reconnect(context, ref),
                  onDelete: () => _confirmDelete(context, ref),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              StatusDot(dot),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isErr ? t.err : t.text1,
                  ),
                ),
              ),
              if (!isPlan)
                AppChip(
                  label: l.sourcesPageTestConnection,
                  compact: true,
                  onTap: () => _reconnect(context, ref),
                ),
            ],
          ),
          if (libs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final lib in libs) AppTag(l.sourcesPageLibraryTag(lib)),
              ],
            ),
          ],
        ],
      ),
    );

    // plan 卡整体降透明，呼应设计稿 opacity:.75。
    return isPlan ? Opacity(opacity: 0.75, child: card) : card;
  }

  /// 把（plan / 实时连接态）映射为「圆点 + 文案 + 是否错误色」。
  (DotStatus, String, bool) _statusView(
    AppLocalizations l,
    bool isPlan,
    SourceStatus? status,
    String? errorMessage,
  ) {
    if (isPlan) return (DotStatus.off, l.sourcesPageComingSoon, false);
    return switch (status) {
      SourceStatus.connected => (DotStatus.ok, l.sourcesPageStatusConnected, false),
      SourceStatus.requires2FA => (DotStatus.warn, l.sourcesPageStatusNeeds2FA, false),
      SourceStatus.connecting => (DotStatus.warn, l.sourcesPageStatusConnecting, false),
      SourceStatus.error =>
        (DotStatus.err, errorMessage ?? l.sourcesPageStatusError, true),
      SourceStatus.disconnected || null =>
        (DotStatus.off, l.sourcesPageStatusDisconnected, false),
    };
  }
}

/// 卡片右上角 30x30 的「更多」菜单按钮（对齐设计稿 .icon-btn dots）。
/// 提供 编辑 / 重新连接 / 删除（级联）三项操作。
class _SourceMenu extends StatelessWidget {
  const _SourceMenu({
    required this.color,
    required this.onEdit,
    required this.onReconnect,
    required this.onDelete,
  });

  final Color color;
  final VoidCallback onEdit;
  final VoidCallback onReconnect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      width: 30,
      height: 30,
      child: PopupMenuButton<String>(
        tooltip: l.sourcesPageMore,
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_horiz_rounded, size: 18, color: color),
        onSelected: (v) {
          switch (v) {
            case 'edit':
              onEdit();
            case 'reconnect':
              onReconnect();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'edit', child: Text(l.sourcesPageMenuEdit)),
          PopupMenuItem(
            value: 'reconnect',
            child: Text(l.sourcesPageMenuReconnect),
          ),
          PopupMenuItem(value: 'delete', child: Text(l.sourcesPageMenuDelete)),
        ],
      ),
    );
  }
}
