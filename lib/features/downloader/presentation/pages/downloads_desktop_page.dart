import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';
import 'package:my_nas/shared/widgets/dialogs/add_download_dialog.dart';

/// 桌面端「下载器」骨架。
///
/// 视觉对齐设计稿 ops.jsx (Downloads)：客户端 chips + 状态 chips + 偏好
/// panel + dense-table。aria2 / qBittorrent / Transmission 三客户端的
/// 真实任务列表接入沿用各自 provider（见 plan Group E）。
class DownloadsDesktopPage extends StatefulWidget {
  const DownloadsDesktopPage({super.key});

  @override
  State<DownloadsDesktopPage> createState() => _DownloadsDesktopPageState();
}

class _DownloadsDesktopPageState extends State<DownloadsDesktopPage> {
  String _client = '全部';
  String _filter = '全部';

  static const _clients = ['全部', 'qBittorrent', 'aria2', 'Transmission'];
  static const _filters = ['全部', '下载中', '做种', '已暂停', '已完成'];

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return DesktopPageScaffold(
      title: '下载器',
      subtitle: 'qBittorrent · aria2 · Transmission — 跨客户端统一任务台',
      maxWidth: 1500,
      actions: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: FilledButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            barrierColor: Colors.black.withValues(alpha: 0.5),
            builder: (_) => const AddDownloadDialog(),
          ),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('新建任务'),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final c in _clients)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AppChip(
                    label: c,
                    active: c == _client,
                    icon: c == '全部'
                        ? null
                        : Icons.circle,
                    compact: true,
                    onTap: () => setState(() => _client = c),
                    trailing: c == '全部' ? null : const StatusDot(DotStatus.off),
                  ),
                ),
              const Spacer(),
              for (final f in _filters)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: AppChip(
                    label: f,
                    active: f == _filter,
                    compact: true,
                    onTap: () => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 42),
            decoration: BoxDecoration(
              color: t.panelBg,
              border: Border.all(color: t.panelBorder),
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.download_outlined, size: 40, color: t.text3),
                  const SizedBox(height: 12),
                  Text(
                    '尚未连接下载客户端',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.text1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '到「数据源」添加 qBittorrent / aria2 / Transmission 之后，'
                    '所有任务会聚合到这里（含 PT 一键发送）。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: t.text2,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
