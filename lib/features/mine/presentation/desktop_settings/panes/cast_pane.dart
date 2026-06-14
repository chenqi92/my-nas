import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/music/presentation/providers/desktop_lyric_provider.dart';
import 'package:my_nas/features/video/presentation/providers/cast_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';

/// 桌面端「投屏与输出」设置 pane。
///
/// 对齐设计稿 `settings_panes.jsx` 的 `PaneCast`：音频输出 / 投屏（本地媒体代理、
/// DLNA · AirPlay、投屏状态）/ 桌面歌词浮窗三组。
///
/// 接真实状态：
/// - 桌面歌词浮窗 → [desktopLyricProvider]（启用 / 单双行 / 锁定穿透 / 自动显示）。
/// - DLNA · AirPlay 设备发现 → [castProvider]（搜索设备 / 当前会话状态）。
///
/// 暂无真实 provider 的项（音频输出设备、杜比全景声、本地代理开关、投屏状态显示）
/// 降级为只读 + 「即将推出」标签。
class CastPane extends ConsumerWidget {
  const CastPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricState = ref.watch(desktopLyricProvider);
    final lyricNotifier = ref.read(desktopLyricProvider.notifier);
    final lyricSupported = lyricNotifier.isSupported;
    final lyric = lyricState.settings;

    final castState = ref.watch(castProvider);
    final castNotifier = ref.read(castProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SetHead(
          icon: Icons.cast_rounded,
          title: '投屏与输出',
          subtitle: '音频输出、本地媒体代理、DLNA / AirPlay 投屏与桌面歌词浮窗。',
        ),

        // ===== 音频输出 =====
        SetSection(
          title: '音频输出',
          children: [
            SetRow(
              title: '输出设备',
              desc: '系统 / 蓝牙 / AirPlay / 外接 DAC',
              trailing: const AppTag('即将推出', variant: TagVariant.plan),
            ),
            SetRow(
              title: '杜比全景声',
              desc: '支持的输出设备上启用空间音频',
              last: true,
              trailing: const AppTag('即将推出', variant: TagVariant.plan),
            ),
          ],
        ),

        // ===== 投屏 =====
        SetSection(
          title: '投屏',
          children: [
            SetRow(
              title: '本地媒体代理 (shelf)',
              desc: '为 SMB 等非直链协议提供 HTTP 代理 — 投屏与 media_kit 播放的前提',
              trailing: const AppTag('随播放自动启用'),
            ),
            SetRow(
              title: 'DLNA / AirPlay',
              desc: castState.isCasting
                  ? '投屏中 · ${castState.session?.device.name ?? '已连接设备'}'
                  : castState.isDiscovering
                      ? '正在搜索设备…'
                      : '设备发现 · 远程控制（播放 / 暂停 / 音量 / 进度）',
              trailing: AppButton(
                label: castState.isDiscovering ? '搜索中…' : '搜索设备',
                icon: Icons.wifi_tethering_rounded,
                dense: true,
                onPressed:
                    castState.isDiscovering ? null : castNotifier.startDiscovery,
              ),
            ),
            SetRow(
              title: '投屏状态显示',
              desc: '在迷你 dock 与播放器显示当前投屏目标',
              last: true,
              trailing: const AppTag('即将推出', variant: TagVariant.plan),
            ),
          ],
        ),

        // ===== 桌面歌词浮窗 =====
        SetSection(
          title: '桌面歌词浮窗',
          hint: lyricSupported ? null : '仅桌面端',
          bottomMargin: false,
          children: [
            SetRow(
              title: '启用浮窗',
              desc: lyricSupported
                  ? '独立置顶窗口显示同步歌词 · 快捷键 ⌘/Ctrl + Shift + L'
                  : '独立置顶窗口显示同步歌词（仅 Windows / macOS）',
              trailing: AppSwitch(
                value: lyricState.isVisible,
                enabled: lyricSupported,
                onChanged: lyricSupported
                    ? (v) {
                        if (v) {
                          lyricNotifier.show();
                        } else {
                          lyricNotifier.hide();
                        }
                      }
                    : null,
              ),
            ),
            SetRow(
              title: '布局',
              desc: '单行仅当前句 · 双行附带下一句',
              trailing: AppSegmented<bool>(
                value: lyric.showNextLine,
                onChanged: lyricSupported
                    ? (v) => lyricNotifier.updateSettings(
                          lyric.copyWith(showNextLine: v),
                        )
                    : (_) {},
                options: const [
                  AppSegmentedOption(value: false, label: '单行'),
                  AppSegmentedOption(value: true, label: '双行'),
                ],
              ),
            ),
            SetRow(
              title: '锁定点击穿透',
              desc: '锁定后浮窗不拦截鼠标，仅显示',
              trailing: AppSwitch(
                value: lyric.lockPosition,
                enabled: lyricSupported,
                onChanged: lyricSupported
                    ? (v) => lyricNotifier.updateSettings(
                          lyric.copyWith(lockPosition: v),
                        )
                    : null,
              ),
            ),
            SetRow(
              title: '播放时自动显示',
              desc: '开始播放音乐时自动弹出浮窗',
              last: true,
              trailing: AppSwitch(
                value: lyric.showWhenPlaying,
                enabled: lyricSupported,
                onChanged: lyricSupported
                    ? (v) => lyricNotifier.updateSettings(
                          lyric.copyWith(showWhenPlaying: v),
                        )
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
