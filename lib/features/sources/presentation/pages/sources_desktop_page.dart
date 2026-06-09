import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
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
    final sourcesAsync = ref.watch(sourcesProvider);
    final connections = ref.watch(activeConnectionsProvider);
    final t = DesignTokens.of(context);

    return DesktopPageScaffold(
      title: '数据源',
      subtitle: '添加源 → 媒体库目录映射 → 扫描 → 库。删除源将级联删除其媒体与映射。',
      actions: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: FilledButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            barrierColor: Colors.black.withValues(alpha: 0.5),
            builder: (_) => const SourceWizardDialog(),
          ),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('添加源'),
        ),
      ),
      body: sourcesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text(
          '加载源失败：$e',
          style: TextStyle(color: t.err),
        ),
        data: (sources) {
          if (sources.isEmpty) {
            return const DesktopComingSoon(
              icon: Icons.lan_outlined,
              message: '点击右上「添加源」连接你的第一个 NAS / 媒体服务器 / 下载器。\n'
                  '支持 Synology、QNAP、SMB、WebDAV、SFTP、FTP、UPnP、'
                  'Jellyfin / Emby / Plex、aria2 / qBittorrent / Transmission、'
                  'Trakt、NAStool / MoviePilot 等 20+ 种。',
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
class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.conn,
    required this.libs,
  });

  final SourceEntity source;
  final SourceConnection? conn;
  final List<String> libs;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    // 未实现的源类型即「即将推出」，与设计稿 plan 态对齐。
    final isPlan = !source.type.isSupported;
    final status = conn?.status;
    final (dot, label, isErr) = _statusView(isPlan, status, conn?.errorMessage);

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
                const AppTag('即将推出', variant: TagVariant.plan)
              else
                _MenuButton(color: t.text2),
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
                const AppChip(label: '测试连接', compact: true),
            ],
          ),
          if (libs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final l in libs) AppTag('$l库'),
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
    bool isPlan,
    SourceStatus? status,
    String? errorMessage,
  ) {
    if (isPlan) return (DotStatus.off, '即将推出', false);
    return switch (status) {
      SourceStatus.connected => (DotStatus.ok, '已连接', false),
      SourceStatus.requires2FA => (DotStatus.warn, '需 2FA', false),
      SourceStatus.connecting => (DotStatus.warn, '连接中', false),
      SourceStatus.error => (DotStatus.err, errorMessage ?? '错误', true),
      SourceStatus.disconnected || null => (DotStatus.off, '未连接', false),
    };
  }
}

/// 卡片右上角 30x30 的「更多」菜单按钮（对齐设计稿 .icon-btn dots）。
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 30,
        height: 30,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
            onTap: () {},
            child: Icon(Icons.more_horiz_rounded, size: 18, color: color),
          ),
        ),
      );
}
