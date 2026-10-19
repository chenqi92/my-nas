import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/presentation/providers/playback_settings_provider.dart';

String playbackOrientationLabel(
  BuildContext context,
  PlaybackOrientation value,
) => switch (value) {
  PlaybackOrientation.auto => context.l10n.videoOrientationAuto,
  PlaybackOrientation.video => context.l10n.videoOrientationVideo,
  PlaybackOrientation.portrait => context.l10n.videoOrientationPortrait,
  PlaybackOrientation.reversePortrait =>
    context.l10n.videoOrientationReversePortrait,
  PlaybackOrientation.landscape => context.l10n.videoOrientationLandscape,
  PlaybackOrientation.reverseLandscape =>
    context.l10n.videoOrientationReverseLandscape,
};

class PlaybackOrientationMenu extends ConsumerWidget {
  const PlaybackOrientationMenu({super.key, this.iconColor});

  final Color? iconColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(playbackSettingsProvider);
    final notifier = ref.read(playbackSettingsProvider.notifier);
    return PopupMenuButton<PlaybackOrientation>(
      tooltip: context.l10n.videoOrientation,
      icon: Icon(Icons.arrow_drop_down, color: iconColor),
      onSelected: notifier.setOrientation,
      itemBuilder: (context) => PlaybackOrientation.values
          .map(
            (value) => CheckedPopupMenuItem(
              value: value,
              checked: settings.orientation == value,
              child: Text(playbackOrientationLabel(context, value)),
            ),
          )
          .toList(),
    );
  }
}
