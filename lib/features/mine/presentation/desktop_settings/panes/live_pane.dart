import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/domain/entities/live_stream_models.dart';
import 'package:my_nas/features/video/presentation/pages/live_stream_settings_page.dart';
import 'package:my_nas/features/video/presentation/providers/live_stream_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 设置 · 直播源（设计稿 `settings_panes.jsx` PaneLive）。
///
/// IPTV / M3U / HLS 直播源管理：列出真实直播源（名称 / 频道数 / 更新时间），
/// 行内提供预览、刷新；添加 / 编辑 / 排序统一打开现有的
/// [LiveStreamSettingsPage]，保留完整功能。
class LivePane extends ConsumerWidget {
  const LivePane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final settings = ref.watch(liveStreamSettingsProvider);
    final sources = settings.sortedSources;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.live_tv_outlined,
          title: '直播源',
          subtitle: 'IPTV / M3U / HLS 直播源管理。添加、编辑、排序、刷新与频道预览。',
          actions: [
            AppButton(
              label: '添加直播源',
              icon: Icons.add_rounded,
              variant: AppButtonVariant.primary,
              onPressed: () => _openManager(context),
            ),
          ],
        ),
        SetSection(
          title: '直播源',
          hint: sources.isEmpty
              ? 'M3U / HLS'
              : '${sources.length} 个 · M3U / HLS',
          children: sources.isEmpty
              ? [
                  SetRow(
                    leading: _SourceIcon(enabled: false),
                    title: '暂无直播源',
                    desc: '添加 M3U / HLS 播放列表开始观看直播',
                    last: true,
                    trailing: AppButton(
                      label: '添加',
                      icon: Icons.add_rounded,
                      dense: true,
                      onPressed: () => _openManager(context),
                    ),
                  ),
                ]
              : [
                  for (var i = 0; i < sources.length; i++)
                    SetRow(
                      leading: _SourceIcon(enabled: sources[i].isEnabled),
                      title: sources[i].name,
                      desc:
                          '${sources[i].channelCount} 频道 · 更新于 ${_formatUpdated(sources[i].updatedAt)}',
                      last: i == sources.length - 1,
                      trailing: _SourceActions(source: sources[i]),
                    ),
                ],
        ),
        SetSection(
          title: '管理',
          children: [
            SetRow(
              leading: Icon(Icons.tune_rounded, size: 18, color: t.text2),
              title: '编辑 / 排序 / 删除',
              desc: '打开直播源管理页，添加或调整 M3U 播放列表',
              last: true,
              trailing: AppButton(
                label: '打开管理页',
                icon: Icons.open_in_new_rounded,
                dense: true,
                onPressed: () => _openManager(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static void _openManager(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LiveStreamSettingsPage(),
      ),
    );
  }

  static String _formatUpdated(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(day).inDays;
    final hm = DateFormat('HH:mm').format(dt);
    if (diffDays == 0) return '今天 $hm';
    if (diffDays == 1) return '昨天 $hm';
    if (diffDays < 7) return '$diffDays 天前';
    return DateFormat('MM-dd').format(dt);
  }
}

/// 行首的源图标：随启用态切换强调 / 灰显。
class _SourceIcon extends StatelessWidget {
  const _SourceIcon({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: enabled ? t.chipBgActive : t.insetBg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(
        Icons.cast_rounded,
        size: 16,
        color: enabled ? t.accentBright : t.text3,
      ),
    );
  }
}

/// 行尾动作：状态点 + 预览 chip + 刷新（真实读写）。
class _SourceActions extends ConsumerStatefulWidget {
  const _SourceActions({required this.source});

  final LiveStreamSource source;

  @override
  ConsumerState<_SourceActions> createState() => _SourceActionsState();
}

class _SourceActionsState extends ConsumerState<_SourceActions> {
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusDot(
          widget.source.isEnabled ? DotStatus.ok : DotStatus.off,
          size: 7,
        ),
        const SizedBox(width: 10),
        AppChip(
          label: '预览',
          icon: Icons.visibility_outlined,
          compact: true,
          onTap: () => LivePane._openManager(context),
        ),
        const SizedBox(width: 6),
        _IconAction(
          icon: Icons.refresh_rounded,
          busy: _refreshing,
          tooltip: '刷新频道',
          onTap: _refreshing ? null : _refresh,
        ),
        const SizedBox(width: 2),
        _IconAction(
          icon: Icons.drag_indicator_rounded,
          tooltip: '排序 / 管理',
          color: t.text3,
          onTap: () => LivePane._openManager(context),
        ),
      ],
    );
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final source = await ref
          .read(liveStreamSettingsProvider.notifier)
          .refreshSource(widget.source.id);
      if (mounted) {
        context.showToast('已刷新: ${source.channelCount} 个频道');
      }
    } catch (e, st) {
      if (mounted) {
        AppError.handleWithUI(context, e, st, '刷新失败');
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }
}

/// 设计稿 `.icon-btn`：30x30 圆角图标按钮，hover 显 chipBg。
class _IconAction extends StatefulWidget {
  const _IconAction({
    required this.icon,
    this.onTap,
    this.busy = false,
    this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool busy;
  final String? tooltip;
  final Color? color;

  @override
  State<_IconAction> createState() => _IconActionState();
}

class _IconActionState extends State<_IconAction> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final disabled = widget.onTap == null;
    final fg = widget.color ?? t.text2;

    var child = widget.busy
        ? SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : Icon(widget.icon, size: 16, color: fg);

    child = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: DesignTokens.ease,
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _hovering && !disabled ? t.chipBg : Colors.transparent,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      ),
      child: child,
    );

    final tooltip = widget.tooltip;
    if (tooltip != null) {
      child = Tooltip(message: tooltip, child: child);
    }

    return Opacity(
      opacity: disabled && !widget.busy ? 0.5 : 1,
      child: MouseRegion(
        cursor: disabled ? MouseCursor.defer : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: child,
        ),
      ),
    );
  }
}
