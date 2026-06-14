import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/network/host_mapping_entry.dart';
import 'package:my_nas/core/network/hosts_resolver_service.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_indexer.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_reindex_coordinator.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_settings.dart';
import 'package:my_nas/features/mine/presentation/pages/hosts_mapping_page.dart';
import 'package:my_nas/features/mine/presentation/pages/spotlight_settings_page.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';

/// 桌面「设置 / 高级」详情 pane（设计稿 `settings_panes.jsx` PaneAdvanced）。
///
/// - Hosts 映射：直接读 [HostsResolverService]（单例 + changes 流），列出
///   域名 → IP，「管理」打开现有的 [HostsMappingPage]（增删改 / DoH 解析）。
/// - 系统集成：Spotlight 索引接真实 [spotlightEnabledProvider]（仅 macOS）；
///   系统托盘 / Jump List 为平台相关的只读状态（对应已有平台服务，无独立设置开关）；
///   深度链接 `mynas://` 已注册并由 DeepLinkService 处理，显示「已注册」。
/// - 诊断：诊断日志导出尚未实现，降级为「即将推出」。
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
            _SystemTrayRow(),
            _JumpListRow(),
            _DeepLinkRow(last: true),
          ],
        ),
        SetSection(
          title: '诊断',
          bottomMargin: false,
          children: const [
            SetRow(
              title: '诊断日志',
              desc: '导出运行日志用于排错',
              last: true,
              trailing: AppTag('即将推出', variant: TagVariant.plan),
            ),
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

/// Spotlight 索引行：仅 macOS 接 [spotlightEnabledProvider]，其它平台只读「即将推出」。
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

/// 系统托盘行：对应已有平台托盘能力（Windows / Linux），随平台启用，无独立开关。
class _SystemTrayRow extends StatelessWidget {
  const _SystemTrayRow();

  @override
  Widget build(BuildContext context) {
    final supported = Platform.isWindows || Platform.isLinux;
    return SetRow(
      title: '系统托盘',
      desc: '最小化到托盘（Windows / Linux）',
      trailing: supported
          ? const AppTag('随平台启用', variant: TagVariant.free)
          : const AppTag('仅桌面端', variant: TagVariant.limit),
    );
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
