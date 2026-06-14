import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/l10n/app_localizations.dart';
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
/// 检测到的真实状态只读呈现。
class CastPane extends ConsumerWidget {
  const CastPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
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
        SetHead(
          icon: Icons.cast_rounded,
          title: l.paneCastHeadTitle,
          subtitle: l.paneCastHeadSubtitle,
        ),

        // ===== 音频输出 =====
        SetSection(
          title: l.paneCastAudioSectionTitle,
          hint: l.paneCastAudioSectionHint,
          children: [
            SetRow(
              title: l.paneCastOutputDeviceTitle,
              desc: l.paneCastOutputDeviceDesc,
              trailing: audioLoading && audioCap == null
                  ? AppTag(l.paneCastDetecting)
                  : AppTag(_outputDeviceLabel(context, audioCap)),
            ),
            SetRow(
              title: l.paneCastDolbyTitle,
              desc: l.paneCastDolbyDesc,
              last: true,
              trailing: audioLoading && audioCap == null
                  ? AppTag(l.paneCastDetecting)
                  : AppTag(
                      (audioCap?.supportsDolby ?? false)
                          ? l.paneCastDolbyPassthrough
                          : l.paneCastDolbyUnsupported,
                      variant: (audioCap?.supportsDolby ?? false)
                          ? TagVariant.free
                          : TagVariant.limit,
                    ),
            ),
          ],
        ),

        // ===== 投屏 =====
        SetSection(
          title: l.paneCastCastingSectionTitle,
          children: [
            SetRow(
              title: l.paneCastMediaProxyTitle,
              desc: l.paneCastMediaProxyDesc,
              trailing: AppTag(l.paneCastMediaProxyTag),
            ),
            SetRow(
              title: 'DLNA / AirPlay',
              desc: castState.isCasting
                  ? l.paneCastDlnaCasting(
                      castState.session?.device.name ??
                          l.paneCastConnectedDevice,
                    )
                  : castState.isDiscovering
                      ? l.paneCastDlnaSearching
                      : l.paneCastDlnaIdleDesc,
              trailing: AppButton(
                label: castState.isDiscovering
                    ? l.paneCastSearchingShort
                    : l.paneCastSearchDevices,
                icon: Icons.wifi_tethering_rounded,
                dense: true,
                onPressed:
                    castState.isDiscovering ? null : castNotifier.startDiscovery,
              ),
            ),
            SetRow(
              title: l.paneCastStatusTitle,
              desc: l.paneCastStatusDesc,
              last: true,
              trailing: _CastStatus(castState: castState),
            ),
          ],
        ),

        // ===== 桌面歌词浮窗 =====
        SetSection(
          title: l.paneCastLyricSectionTitle,
          hint: lyricSupported ? null : l.paneCastLyricDesktopOnly,
          bottomMargin: false,
          children: [
            SetRow(
              title: l.paneCastLyricEnableTitle,
              desc: lyricSupported
                  ? l.paneCastLyricEnableDescShortcut
                  : l.paneCastLyricEnableDescUnsupported,
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
              title: l.paneCastLyricLayoutTitle,
              desc: l.paneCastLyricLayoutDesc,
              trailing: AppSegmented<bool>(
                value: lyric.showNextLine,
                onChanged: lyricSupported
                    ? (v) => lyricNotifier.updateSettings(
                          lyric.copyWith(showNextLine: v),
                        )
                    : (_) {},
                options: [
                  AppSegmentedOption(
                      value: false, label: l.paneCastLyricLayoutSingle),
                  AppSegmentedOption(
                      value: true, label: l.paneCastLyricLayoutDouble),
                ],
              ),
            ),
            SetRow(
              title: l.paneCastLyricTranslationTitle,
              desc: l.paneCastLyricTranslationDesc,
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
              title: l.paneCastLyricLockTitle,
              desc: l.paneCastLyricLockDesc,
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
              title: l.paneCastLyricAutoShowTitle,
              desc: l.paneCastLyricAutoShowDesc,
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
              title: l.paneCastLyricMinimizeTitle,
              desc: l.paneCastLyricMinimizeDesc,
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
  String _outputDeviceLabel(
    BuildContext context,
    AudioPassthroughCapability? cap,
  ) {
    final l = AppLocalizations.of(context);
    if (cap == null || !cap.isSupported) return l.paneCastOutputDeviceSystem;
    final name = cap.deviceName;
    if (name != null && name.isNotEmpty) return name;
    return switch (cap.outputDevice) {
      AudioOutputDevice.hdmi => 'HDMI',
      AudioOutputDevice.spdif => l.paneCastOutputDeviceSpdif,
      AudioOutputDevice.arc => 'HDMI ARC/eARC',
      AudioOutputDevice.bluetooth => l.paneCastOutputDeviceBluetooth,
      AudioOutputDevice.headphones => l.paneCastOutputDeviceHeadphones,
      AudioOutputDevice.speaker => l.paneCastOutputDeviceSpeaker,
      AudioOutputDevice.unknown => l.paneCastOutputDeviceSystem,
    };
  }
}

/// 投屏状态的只读指示：投屏中显示目标设备名 + 绿点，否则灰点 +「未投屏」。
class _CastStatus extends StatelessWidget {
  const _CastStatus({required this.castState});

  final CastState castState;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final casting = castState.isCasting;
    final label = casting
        ? (castState.session?.device.name ?? l.paneCastStatusConnected)
        : castState.isDiscovering
            ? l.paneCastStatusSearching
            : l.paneCastStatusIdle;
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
