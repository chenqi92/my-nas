import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/aria2/presentation/pages/aria2_detail_page.dart';
import 'package:my_nas/features/downloader/presentation/pages/downloader_list_page.dart';
import 'package:my_nas/features/downloader/presentation/providers/downloader_aggregate_provider.dart';
import 'package:my_nas/features/qbittorrent/presentation/pages/qbittorrent_detail_page.dart';
import 'package:my_nas/features/qbittorrent/presentation/providers/qbittorrent_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/transmission/presentation/pages/transmission_detail_page.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/providers/download_notify_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 桌面「设置 · 远程下载服务」详情 pane。
///
/// 设计稿 `settings_panes.jsx` 的 `PaneRemoteDl`：下载客户端列表（名称 / host /
/// 连接状态 / 偏好）+ 默认行为（全局限速 / 完成通知）。客户端列表接真实
/// [downloaderClientsProvider]；每行「偏好」打开对应客户端详情页；全局限速接
/// qBittorrent 真实接口。外壳负责滚动与 padding + maxWidth 居中。
class RemoteDlPane extends ConsumerWidget {
  const RemoteDlPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final clients = ref.watch(downloaderClientsProvider);

    // 全局限速仅 qBittorrent 客户端支持（API 提供 setGlobalSpeedLimits）。
    final qbSource = clients
        .where((c) => c.source.type == SourceType.qbittorrent)
        .map((c) => c.source)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.download_rounded,
          title: l.paneRemotedlTitle,
          subtitle: l.paneRemotedlSubtitle,
          actions: [
            AppButton(
              label: l.paneRemotedlAddDownloader,
              icon: Icons.add_rounded,
              variant: AppButtonVariant.primary,
              onPressed: () => _push(context, const DownloaderListPage()),
            ),
          ],
        ),
        SetSection(
          title: l.paneRemotedlClientsSection,
          hint: l.paneRemotedlClientsCount(clients.length),
          children: [
            if (clients.isEmpty)
              SetRow(
                title: l.paneRemotedlEmptyTitle,
                desc: l.paneRemotedlEmptyDesc,
                last: true,
                trailing: AppChip(
                  label: l.paneRemotedlAddChip,
                  icon: Icons.add_rounded,
                  onTap: () => _push(context, const DownloaderListPage()),
                ),
              )
            else ...[
              for (var i = 0; i < clients.length; i++)
                _ClientRow(
                  client: clients[i],
                  last: i == clients.length - 1 && clients.length == 1,
                ),
              if (clients.isNotEmpty)
                SetRow(
                  title: l.paneRemotedlManageTitle,
                  desc: l.paneRemotedlManageDesc,
                  last: true,
                  trailing: AppChip(
                    label: l.paneRemotedlManageChip,
                    icon: Icons.open_in_new_rounded,
                    onTap: () => _push(context, const DownloaderListPage()),
                  ),
                ),
            ],
          ],
        ),
        SetSection(
          title: l.paneRemotedlDefaultsSection,
          bottomMargin: false,
          children: [
            SetRow(
              title: l.paneRemotedlGlobalLimitTitle,
              desc: l.paneRemotedlGlobalLimitDesc,
              trailing: qbSource != null
                  ? AppChip(
                      label: l.paneRemotedlGlobalLimitSetChip,
                      icon: Icons.speed_rounded,
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            _GlobalLimitDialog(sourceId: qbSource.id),
                      ),
                    )
                  : AppTag(
                      l.paneRemotedlGlobalLimitManagedTag,
                      variant: TagVariant.limit,
                    ),
            ),
            SetRow(
              title: l.paneRemotedlNotifyTitle,
              desc: l.paneRemotedlNotifyDesc,
              last: true,
              trailing: AppSwitch(
                value: ref.watch(downloadNotifyProvider),
                onChanged: (v) => ref
                    .read(downloadNotifyProvider.notifier)
                    .setEnabled(enabled: v),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

/// 单个下载客户端行：图标 + 名称 + host + 连接状态点 + 「偏好」入口。
class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.client, required this.last});

  final DownloaderClient client;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final source = client.source;
    final host = '${source.host}:${source.port}';

    return SetRow(
      title: source.displayName,
      desc: host,
      last: last,
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: t.chipBgActive,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(source.type.icon, size: 16, color: t.accentBright),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusDot(client.connected ? DotStatus.ok : DotStatus.off),
          const SizedBox(width: 10),
          Text(
            client.connected
                ? l.paneRemotedlConnected
                : l.paneRemotedlDisconnected,
            style: TextStyle(fontSize: 12, color: t.text2),
          ),
          const SizedBox(width: 10),
          AppChip(
            label: l.paneRemotedlPreferenceChip,
            onTap: () => _openDetail(context, source),
          ),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, SourceEntity source) {
    final Widget page = switch (source.type) {
      SourceType.qbittorrent => QBittorrentDetailPage(source: source),
      SourceType.aria2 => Aria2DetailPage(source: source),
      SourceType.transmission => TransmissionDetailPage(source: source),
      _ => QBittorrentDetailPage(source: source),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

/// 全局限速对话框（qBittorrent）：单位 KB/s，0 表示不限速。
///
/// 复用 [qbittorrentActionsProvider].setGlobalSpeedLimits 与
/// [qbPreferencesProvider] 真实读写，与下载器任务台的同名控件一致。
class _GlobalLimitDialog extends ConsumerStatefulWidget {
  const _GlobalLimitDialog({required this.sourceId});

  final String sourceId;

  @override
  ConsumerState<_GlobalLimitDialog> createState() => _GlobalLimitDialogState();
}

class _GlobalLimitDialogState extends ConsumerState<_GlobalLimitDialog> {
  final _dl = TextEditingController();
  final _up = TextEditingController();
  bool _prefilled = false;
  bool _saving = false;

  @override
  void dispose() {
    _dl.dispose();
    _up.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final l = AppLocalizations.of(context);
    setState(() => _saving = true);
    final dl = (int.tryParse(_dl.text.trim()) ?? 0) * 1024;
    final up = (int.tryParse(_up.text.trim()) ?? 0) * 1024;
    try {
      await ref
          .read(qbittorrentActionsProvider(widget.sourceId))
          .setGlobalSpeedLimits(dlLimit: dl, upLimit: up);
      if (mounted) {
        Navigator.of(context).pop();
        context.showSuccessToast(l.paneRemotedlLimitUpdated);
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        context.showErrorToast(l.paneRemotedlLimitFailed(e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // 首次拿到偏好时按 KB/s 回填输入框。
    ref.watch(qbPreferencesProvider(widget.sourceId)).whenData((p) {
      if (!_prefilled && p != null) {
        _prefilled = true;
        _dl.text = (p.dlLimit / 1024).round().toString();
        _up.text = (p.upLimit / 1024).round().toString();
      }
    });
    return AlertDialog(
      title: Text(l.paneRemotedlGlobalLimitTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.paneRemotedlLimitHint, style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 14),
          TextField(
            controller: _dl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l.paneRemotedlLimitDlLabel,
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _up,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l.paneRemotedlLimitUpLabel,
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.paneRemotedlLimitCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _apply,
          child: Text(l.paneRemotedlLimitApply),
        ),
      ],
    );
  }
}
