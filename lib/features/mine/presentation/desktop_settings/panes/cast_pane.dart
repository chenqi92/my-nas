import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/music/presentation/providers/desktop_lyric_provider.dart';
import 'package:my_nas/features/video/domain/entities/audio_capability.dart';
import 'package:my_nas/features/video/presentation/providers/cast_provider.dart';
import 'package:my_nas/features/video/presentation/providers/hdr_audio_settings_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 桌面端「投屏与输出」设置 pane。
///
/// 对齐设计稿 `settings_panes.jsx` 的 `PaneCast`：音频输出 / 投屏（本地媒体代理、
/// DLNA · AirPlay、投屏状态）/ 桌面歌词浮窗三组。
///
/// 接真实状态：
/// - 桌面歌词浮窗 → [desktopLyricProvider]（启用 / 单双行 / 翻译 / 锁定穿透 /
///   播放自动显示 / 最小化显示）。
/// - DLNA · AirPlay 设备发现 → [castProvider]（搜索设备 / 当前会话状态）。
/// - 音频输出能力（输出设备 / 杜比直通）→ [hdrAudioSettingsProvider] 检测到的只读能力。
///
/// 暂无可写设置的项（输出设备主动选择、杜比/空间音频开关、投屏状态显示开关）以
/// 检测到的真实状态只读呈现；确无任何状态的保留「即将推出」。
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

    final audioCap = ref.watch(
      hdrAudioSettingsProvider.select((s) => s.audioCapability),
    );
    final audioLoading = ref.watch(
      hdrAudioSettingsProvider.select((s) => s.isLoading),
    );

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
          hint: '检测自当前播放设备',
          children: [
            SetRow(
              title: '输出设备',
              desc: '系统 / 蓝牙 / AirPlay / 外接 DAC',
              trailing: audioLoading && audioCap == null
                  ? const AppTag('检测中')
                  : AppTag(_outputDeviceLabel(audioCap)),
            ),
            SetRow(
              title: '杜比全景声',
              desc: '支持的输出设备上启用空间音频',
              last: true,
              trailing: audioLoading && audioCap == null
                  ? const AppTag('检测中')
                  : AppTag(
                      (audioCap?.supportsDolby ?? false) ? '可直通' : '不支持',
                      variant: (audioCap?.supportsDolby ?? false)
                          ? TagVariant.free
                          : TagVariant.limit,
                    ),
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
              title: '投屏状态',
              desc: '当前投屏目标 · 在迷你 dock 与播放器同步显示',
              last: true,
              trailing: _CastStatus(castState: castState),
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
              title: '显示翻译',
              desc: '同时间轴的译文行一并显示',
              trailing: AppSwitch(
                value: lyric.showTranslation,
                enabled: lyricSupported,
                onChanged: lyricSupported
                    ? (v) => lyricNotifier.updateSettings(
                          lyric.copyWith(showTranslation: v),
                        )
                    : null,
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
            SetRow(
              title: '最小化主窗口时显示',
              desc: '主窗口最小化且正在播放时自动弹出浮窗',
              last: true,
              trailing: AppSwitch(
                value: lyric.showOnMinimize,
                enabled: lyricSupported,
                onChanged: lyricSupported
                    ? (v) => lyricNotifier.updateSettings(
                          lyric.copyWith(showOnMinimize: v),
                        )
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 把检测到的音频输出设备转成可读标签；未知 / 未检测时回退「系统默认」。
  String _outputDeviceLabel(AudioPassthroughCapability? cap) {
    if (cap == null || !cap.isSupported) return '系统默认';
    final name = cap.deviceName;
    if (name != null && name.isNotEmpty) return name;
    return switch (cap.outputDevice) {
      AudioOutputDevice.hdmi => 'HDMI',
      AudioOutputDevice.spdif => 'S/PDIF 光纤',
      AudioOutputDevice.arc => 'HDMI ARC/eARC',
      AudioOutputDevice.bluetooth => '蓝牙',
      AudioOutputDevice.headphones => '耳机',
      AudioOutputDevice.speaker => '内置扬声器',
      AudioOutputDevice.unknown => '系统默认',
    };
  }
}

/// 投屏状态的只读指示：投屏中显示目标设备名 + 绿点，否则灰点 +「未投屏」。
class _CastStatus extends StatelessWidget {
  const _CastStatus({required this.castState});

  final CastState castState;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final casting = castState.isCasting;
    final label = casting
        ? (castState.session?.device.name ?? '已连接')
        : castState.isDiscovering
            ? '搜索中'
            : '未投屏';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusDot(
          casting
              ? DotStatus.ok
              : castState.isDiscovering
                  ? DotStatus.accent
                  : DotStatus.off,
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: casting ? t.text0 : t.text2,
            ),
          ),
        ),
      ],
    );
  }
}
