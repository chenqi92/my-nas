import 'dart:io';

import 'package:flutter/material.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/data/services/audio_effects_service.dart';
import 'package:my_nas/shared/utils/form_l10n.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 均衡器与音效设置页
///
/// - 顶部开关 + 预设切换
/// - 10 段垂直 slider（-12dB ~ +12dB）
/// - 当前平台支持情况说明
class AudioEffectsPage extends StatefulWidget {
  const AudioEffectsPage({super.key});

  @override
  State<AudioEffectsPage> createState() => _AudioEffectsPageState();
}

class _AudioEffectsPageState extends State<AudioEffectsPage> {
  late EqualizerState _state;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await AudioEffectsService.instance.init();
    if (!mounted) return;
    setState(() {
      _state = AudioEffectsService.instance.state;
      _ready = true;
    });
  }

  Future<void> _toggleEnabled(bool v) async {
    await AudioEffectsService.instance.setEnabled(enabled: v);
    if (!mounted) return;
    setState(() => _state = AudioEffectsService.instance.state);
  }

  Future<void> _applyPreset(String id) async {
    await AudioEffectsService.instance.applyPreset(id);
    if (!mounted) return;
    setState(() => _state = AudioEffectsService.instance.state);
  }

  Future<void> _setBand(int index, double value) async {
    await AudioEffectsService.instance.setBandGain(index, value);
    if (!mounted) return;
    setState(() => _state = AudioEffectsService.instance.state);
  }

  Future<void> _resetFlat() async {
    await AudioEffectsService.instance.resetFlat();
    if (!mounted) return;
    setState(() => _state = AudioEffectsService.instance.state);
  }

  String _platformNote(BuildContext context) {
    if (Platform.isAndroid) return context.l10n.musicEffectsPlatformNoteAndroid;
    if (Platform.isIOS) return context.l10n.musicEffectsPlatformNoteIos;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return context.l10n.musicEffectsPlatformNoteDesktop;
    }
    return context.l10n.musicEffectsPlatformNoteUnsupported;
  }

  String _formatBandLabel(int hz) {
    if (hz >= 1000) return '${hz ~/ 1000}k';
    return '$hz';
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        leading: const RoundedBackButton(),
        title: Text(context.l10n.musicEffectsPageTitle),
        actions: [
          IconButton(
            tooltip: context.l10n.musicEffectsResetToFlat,
            icon: const Icon(Icons.restart_alt),
            onPressed: _resetFlat,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: Text(context.l10n.musicEffectsEnableTitle),
            subtitle: Text(_platformNote(context)),
            value: _state.enabled,
            onChanged: _toggleEnabled,
          ),
          const SizedBox(height: 8),
          _buildPresetChips(context),
          const SizedBox(height: 16),
          _buildEqSliders(context),
        ],
      ),
    );
  }

  Widget _buildPresetChips(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in kEqPresets)
            ChoiceChip(
              label: Text(localizeFormText(context, p.name)),
              selected: _state.presetId == p.id,
              onSelected: _state.enabled ? (_) => _applyPreset(p.id) : null,
            ),
          if (_state.presetId == 'custom')
            ChoiceChip(label: Text(context.l10n.musicEffectsCustomPreset), selected: true),
        ],
      );

  Widget _buildEqSliders(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 280,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < kEqBands.length; i++)
            Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: 18,
                    child: Text(
                      _state.gains[i].toStringAsFixed(1),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  Expanded(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Slider(
                        value: _state.gains[i].clamp(kEqMinGain, kEqMaxGain),
                        min: kEqMinGain,
                        max: kEqMaxGain,
                        divisions: 48,
                        onChanged: _state.enabled
                            ? (v) => _setBand(i, v)
                            : null,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 18,
                    child: Text(
                      _formatBandLabel(kEqBands[i]),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
