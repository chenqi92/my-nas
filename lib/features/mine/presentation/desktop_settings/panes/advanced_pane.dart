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
import 'package:my_nas/l10n/app_localizations.dart';
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
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.terminal_rounded,
          title: l.paneAdvancedTitle,
          subtitle: l.paneAdvancedSubtitle,
          actions: [
            AppButton(
              label: l.paneAdvancedManageButton,
              icon: Icons.dns_rounded,
              onPressed: _openHostsPage,
            ),
          ],
        ),
        SetSection(
          title: l.paneAdvancedHostsTitle,
          hint: l.paneAdvancedHostsHint,
          children: _hostRows(),
        ),
        SetSection(
          title: l.paneAdvancedSystemIntegrationTitle,
          children: const [
            _SpotlightRow(),
            _JumpListRow(),
            _DeepLinkRow(last: true),
          ],
        ),
        SetSection(
          title: l.paneAdvancedDiagnosticsTitle,
          bottomMargin: false,
          children: const [
            _DiagnosticLogRow(last: true),
          ],
        ),
      ],
    );
  }

  List<Widget> _hostRows() {
    final l = AppLocalizations.of(context);
    if (_hosts.isEmpty) {
      return [
        SetRow(
          leading: const _HostIcon(),
          title: l.paneAdvancedNoMappingTitle,
          desc: l.paneAdvancedNoMappingDesc,
          last: true,
          trailing: AppButton(
            label: l.paneAdvancedAddMappingButton,
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
    final l = AppLocalizations.of(context);
    final sourceLabel =
        entry.source == HostMappingSource.doh ? 'DoH' : l.paneAdvancedSourceManual;
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
    final l = AppLocalizations.of(context);
    if (!Platform.isMacOS) {
      return SetRow(
        title: l.paneAdvancedSpotlightTitle,
        desc: l.paneAdvancedSpotlightDescNonMac,
        trailing: AppTag(l.paneAdvancedSpotlightTagMacOnly, variant: TagVariant.limit),
      );
    }
    final enabled = ref.watch(spotlightEnabledProvider);
    final rebuilding = ref.watch(SpotlightReindexCoordinator.progressProvider);
    return SetRow(
      title: l.paneAdvancedSpotlightTitle,
      desc: rebuilding
          ? l.paneAdvancedSpotlightDescRebuilding
          : l.paneAdvancedSpotlightDesc,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: l.paneAdvancedSpotlightSettingsButton,
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
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SetRow(
      title: l.paneAdvancedJumpListTitle,
      desc: l.paneAdvancedJumpListDesc,
      trailing: Platform.isWindows
          ? AppTag(l.paneAdvancedJumpListTagPlatform, variant: TagVariant.free)
          : AppTag(l.paneAdvancedJumpListTagWindowsOnly, variant: TagVariant.limit),
    );
  }
}

/// 深度链接行：`mynas://` 已在系统注册并由 DeepLinkService 处理（OAuth 回调等）。
class _DeepLinkRow extends StatelessWidget {
  const _DeepLinkRow({required this.last});

  final bool last;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SetRow(
      title: l.paneAdvancedDeepLinkTitle,
      desc: l.paneAdvancedDeepLinkDesc,
      last: last,
      trailing: Text(
        l.paneAdvancedDeepLinkRegistered,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: DesignTokens.of(context).text2,
        ),
      ),
    );
  }
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
    final l = AppLocalizations.of(context);
    final path = logger.logFilePath;
    final ready = path != null && path.isNotEmpty;
    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    return SetRow(
      title: l.paneAdvancedDiagnosticLogTitle,
      desc: ready
          ? l.paneAdvancedDiagnosticLogDescReady
          : l.paneAdvancedDiagnosticLogDescNotReady,
      last: last,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDesktop) ...[
            AppButton(
              label: l.paneAdvancedDiagnosticLogOpenButton,
              icon: Icons.description_rounded,
              dense: true,
              onPressed: ready ? () => _openFile(context, path) : null,
            ),
            const SizedBox(width: 8),
            AppButton(
              label: l.paneAdvancedDiagnosticLogRevealButton,
              icon: Icons.folder_open_rounded,
              dense: true,
              onPressed: ready ? () => _revealInFolder(context, path) : null,
            ),
            const SizedBox(width: 8),
            AppButton(
              label: l.paneAdvancedDiagnosticLogCopyPathButton,
              icon: Icons.copy_rounded,
              dense: true,
              onPressed: ready ? () => _copyPath(context, path) : null,
            ),
          ] else
            AppButton(
              label: l.paneAdvancedDiagnosticLogShareButton,
              icon: Icons.ios_share_rounded,
              dense: true,
              onPressed: ready ? () => _shareFile(context, path) : null,
            ),
        ],
      ),
    );
  }

  Future<void> _openFile(BuildContext context, String path) async {
    final l = AppLocalizations.of(context);
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
      messenger.showSnackBar(
        SnackBar(content: Text(l.paneAdvancedDiagnosticLogOpenFailed)),
      );
    }
  }

  Future<void> _revealInFolder(BuildContext context, String path) async {
    final l = AppLocalizations.of(context);
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
      messenger.showSnackBar(
        SnackBar(content: Text(l.paneAdvancedDiagnosticLogRevealFailed)),
      );
    }
  }

  Future<void> _copyPath(BuildContext context, String path) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: path));
    messenger.showSnackBar(
      SnackBar(content: Text(l.paneAdvancedDiagnosticLogPathCopied)),
    );
  }

  Future<void> _shareFile(BuildContext context, String path) async {
    final subject = AppLocalizations.of(context).paneAdvancedDiagnosticLogShareSubject;
    await AppError.guard(
      () => Share.shareXFiles([XFile(path)], subject: subject),
      action: 'AdvancedPane.shareLog',
    );
  }
}
