import 'dart:io';

import 'package:flutter/material.dart';
import 'package:my_nas/features/music/data/services/audio_effects_service.dart';
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

  String get _platformNote {
    if (Platform.isAndroid) return 'Android：使用系统 AudioEffect 硬件均衡器';
    if (Platform.isIOS) return 'iOS：当前播放引擎暂不支持 EQ（计划接入 AVAudioEngine）';
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return '桌面端：仅 media_kit 引擎生效（mpv af 滤镜）。如使用 just_audio 引擎，桌面 EQ 不可用';
    }
    return '当前平台暂不支持均衡器';
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
        title: const Text('均衡器'),
        actions: [
          IconButton(
            tooltip: '重置为平直',
            icon: const Icon(Icons.restart_alt),
            onPressed: _resetFlat,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('启用均衡器'),
            subtitle: Text(_platformNote),
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
              label: Text(p.name),
              selected: _state.presetId == p.id,
              onSelected: _state.enabled ? (_) => _applyPreset(p.id) : null,
            ),
          if (_state.presetId == 'custom')
            const ChoiceChip(label: Text('自定义'), selected: true),
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
