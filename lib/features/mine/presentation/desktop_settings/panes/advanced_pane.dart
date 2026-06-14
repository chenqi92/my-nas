import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/network/host_mapping_entry.dart';
import 'package:my_nas/core/network/hosts_resolver_service.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_indexer.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_reindex_coordinator.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_settings.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/mine/presentation/pages/hosts_mapping_page.dart';
import 'package:my_nas/features/mine/presentation/pages/spotlight_settings_page.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';
import 'package:share_plus/share_plus.dart';

/// 桌面「设置 / 高级」详情 pane（设计稿 `settings_panes.jsx` PaneAdvanced）。
///
/// - Hosts 映射：直接读 [HostsResolverService]（单例 + changes 流），列出
///   域名 → IP，「管理」打开现有的 [HostsMappingPage]（增删改 / DoH 解析）。
/// - 系统集成：Spotlight 索引接真实 [spotlightEnabledProvider]（仅 macOS）；
///   Jump List 对应已有 [JumpListController]（Windows 任务栏，随播放历史自动
///   填充，无独立开关）；深度链接 `mynas://` 已注册并由 DeepLinkService 处理，
///   显示「已注册」。
/// - 诊断：诊断日志接真实 [AppLogger.logFilePath]（运行日志 app.log）——桌面端
///   行内提供「打开」「在文件夹中显示」「复制路径」，移动端走系统分享。
///
/// 外壳负责滚动与 38/32/38/96 padding + maxWidth 780 居中，这里只返回内容 Column。
class AdvancedPane extends ConsumerStatefulWidget {
  const AdvancedPane({super.key});

  @override
  ConsumerState<AdvancedPane> createState() => _AdvancedPaneState();
}

class _AdvancedPaneState extends ConsumerState<AdvancedPane> {
  late List<HostMappingEntry> _hosts;
  StreamSubscription<List<HostMappingEntry>>? _hostsSub;

  @override
  void initState() {
    super.initState();
    _hosts = HostsResolverService.instance.list();
    _hostsSub = HostsResolverService.instance.changes.listen((list) {
      if (mounted) setState(() => _hosts = list);
    });
  }

  @override
  void dispose() {
    _hostsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.terminal_rounded,
          title: '高级',
          subtitle: 'Hosts 映射、系统索引集成与诊断。',
          actions: [
            AppButton(
              label: '管理',
              icon: Icons.dns_rounded,
              onPressed: _openHostsPage,
            ),
          ],
        ),
        SetSection(
          title: 'Hosts 映射',
          hint: '域名 → IP · 绕过 DNS 污染',
          children: _hostRows(),
        ),
        SetSection(
          title: '系统集成',
          children: const [
            _SpotlightRow(),
            _JumpListRow(),
            _DeepLinkRow(last: true),
          ],
        ),
        const SetSection(
          title: '诊断',
          bottomMargin: false,
          children: [
            _DiagnosticLogRow(last: true),
          ],
        ),
      ],
    );

  List<Widget> _hostRows() {
    if (_hosts.isEmpty) {
      return [
        SetRow(
          leading: const _HostIcon(),
          title: '暂无映射',
          desc: '点「管理」手动添加，或用 DoH 自动解析常用域名',
          last: true,
          trailing: AppButton(
            label: '添加映射',
            icon: Icons.add_rounded,
            dense: true,
            onPressed: _openHostsPage,
          ),
        ),
      ];
    }
    return [
      for (var i = 0; i < _hosts.length; i++)
        _HostRow(
          entry: _hosts[i],
          last: i == _hosts.length - 1,
        ),
    ];
  }

  void _openHostsPage() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const HostsMappingPage()),
    );
  }
}

/// 单条 hosts 映射行：域名（等宽）→ IP（等宽灰）+ 来源 tag + 启用开关。
/// 开关直接写回 [HostsResolverService]；增删改走「管理」页。
class _HostRow extends StatelessWidget {
  const _HostRow({required this.entry, required this.last});

  final HostMappingEntry entry;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final sourceLabel = entry.source == HostMappingSource.doh ? 'DoH' : '手动';
    return SetRow(
      leading: const _HostIcon(),
      title: entry.host,
      desc: entry.ip,
      last: last,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTag(sourceLabel, variant: TagVariant.accent),
          const SizedBox(width: 10),
          AppSwitch(
            value: entry.enabled,
            onChanged: (enabled) => HostsResolverService.instance
                .toggle(entry.host, enabled: enabled),
          ),
        ],
      ),
    );
  }
}

class _HostIcon extends StatelessWidget {
  const _HostIcon();

  @override
  Widget build(BuildContext context) => Icon(
        Icons.language_rounded,
        size: 16,
        color: DesignTokens.of(context).text3,
      );
}

/// Spotlight 索引行：仅 macOS 接 [spotlightEnabledProvider]，其它平台只读「仅 macOS」。
class _SpotlightRow extends ConsumerWidget {
  const _SpotlightRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Platform.isMacOS) {
      return const SetRow(
        title: 'Spotlight 索引',
        desc: '把媒体库索引进 macOS Spotlight — 仅 macOS',
        trailing: AppTag('仅 macOS', variant: TagVariant.limit),
      );
    }
    final enabled = ref.watch(spotlightEnabledProvider);
    final rebuilding = ref.watch(SpotlightReindexCoordinator.progressProvider);
    return SetRow(
      title: 'Spotlight 索引',
      desc: rebuilding
          ? '正在重建系统索引…'
          : '把视频 / 音乐 / 书籍 / 漫画 / 笔记标题索引进 macOS Spotlight',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: '设置',
            dense: true,
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const SpotlightSettingsPage(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          AppSwitch(
            value: enabled,
            enabled: !rebuilding,
            onChanged: (v) => _toggle(ref, value: v),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(WidgetRef ref, {required bool value}) async {
    await ref.read(spotlightEnabledProvider.notifier).setEnabled(value);
    if (value) {
      await ref.read(spotlightReindexCoordinatorProvider).rebuildAll();
    } else {
      await ref.read(spotlightIndexerProvider).clearAll();
      ref.read(SpotlightReindexCoordinator.lastReportProvider.notifier).state =
          null;
    }
  }
}

/// Jump List / 跳转列表行：对应 [JumpListController]，仅 Windows 任务栏可用。
class _JumpListRow extends StatelessWidget {
  const _JumpListRow();

  @override
  Widget build(BuildContext context) => SetRow(
        title: 'Jump List / 跳转列表',
        desc: 'Windows 任务栏快捷项 — 随平台启用',
        trailing: Platform.isWindows
            ? const AppTag('随平台启用', variant: TagVariant.free)
            : const AppTag('仅 Windows', variant: TagVariant.limit),
      );
}

/// 深度链接行：`mynas://` 已在系统注册并由 DeepLinkService 处理（OAuth 回调等）。
class _DeepLinkRow extends StatelessWidget {
  const _DeepLinkRow({required this.last});

  final bool last;

  @override
  Widget build(BuildContext context) => SetRow(
      title: '深度链接',
      desc: 'mynas:// — OAuth 回调走系统浏览器',
      last: last,
      trailing: Text(
        '已注册',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: DesignTokens.of(context).text2,
        ),
      ),
    );
}

/// 诊断日志行：接真实 [AppLogger.logFilePath]（运行日志 `app.log`）。
///
/// - 桌面端（macOS / Windows / Linux）：用系统命令直接打开日志文件、在文件
///   管理器中定位、复制路径，方便排错时取证。
/// - 移动端：用 [Share] 把日志文件分享出去。
/// 日志未就绪（启动早期 / 初始化失败）时禁用按钮并提示。
class _DiagnosticLogRow extends StatelessWidget {
  const _DiagnosticLogRow({required this.last});

  final bool last;

  @override
  Widget build(BuildContext context) {
    final path = logger.logFilePath;
    final ready = path != null && path.isNotEmpty;
    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    return SetRow(
      title: '诊断日志',
      desc: ready ? '运行日志 app.log · 排错取证' : '日志尚未就绪',
      last: last,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDesktop) ...[
            AppButton(
              label: '打开',
              icon: Icons.description_rounded,
              dense: true,
              onPressed: ready ? () => _openFile(context, path) : null,
            ),
            const SizedBox(width: 8),
            AppButton(
              label: '在文件夹中显示',
              icon: Icons.folder_open_rounded,
              dense: true,
              onPressed: ready ? () => _revealInFolder(context, path) : null,
            ),
            const SizedBox(width: 8),
            AppButton(
              label: '复制路径',
              icon: Icons.copy_rounded,
              dense: true,
              onPressed: ready ? () => _copyPath(context, path) : null,
            ),
          ] else
            AppButton(
              label: '分享日志',
              icon: Icons.ios_share_rounded,
              dense: true,
              onPressed: ready ? () => _shareFile(path) : null,
            ),
        ],
      ),
    );
  }

  Future<void> _openFile(BuildContext context, String path) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isWindows) {
        await Process.run('notepad', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      }
    } on Object catch (e, st) {
      AppError.ignore(e, st, 'AdvancedPane.openLog');
      messenger.showSnackBar(const SnackBar(content: Text('打开日志失败')));
    }
  }

  Future<void> _revealInFolder(BuildContext context, String path) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [File(path).parent.path]);
      }
    } on Object catch (e, st) {
      AppError.ignore(e, st, 'AdvancedPane.revealLog');
      messenger.showSnackBar(const SnackBar(content: Text('定位日志失败')));
    }
  }

  Future<void> _copyPath(BuildContext context, String path) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: path));
    messenger.showSnackBar(const SnackBar(content: Text('日志路径已复制')));
  }

  Future<void> _shareFile(String path) async {
    await AppError.guard(
      () => Share.shareXFiles([XFile(path)], subject: 'MyNAS 诊断日志'),
      action: 'AdvancedPane.shareLog',
    );
  }
}
