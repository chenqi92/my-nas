import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
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
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sources.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 360,
              mainAxisExtent: 138,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemBuilder: (_, i) {
              final s = sources[i];
              final conn = connections[s.id];
              final connected = conn?.status == SourceStatus.connected;
              return AppCard(
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
                          child: Icon(
                            Icons.dns_outlined,
                            color: t.accentBright,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                s.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: t.text0,
                                ),
                              ),
                              Text(
                                '${s.type.name} · ${s.host}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: t.text2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        StatusDot(
                          connected ? DotStatus.ok : DotStatus.off,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          connected ? '已连接' : '未连接',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: t.text1,
                          ),
                        ),
                        const Spacer(),
                        if (s.autoConnect)
                          const AppTag('自动', variant: TagVariant.accent),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
