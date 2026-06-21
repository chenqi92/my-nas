import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/book/data/services/tts/edge_tts_voices.dart';
import 'package:my_nas/features/book/data/services/tts/tts_settings.dart';
import 'package:my_nas/features/book/data/services/tts/tts_voice.dart';
import 'package:my_nas/features/book/presentation/providers/tts_provider.dart';
import 'package:my_nas/shared/utils/form_l10n.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// 音色选择器
class TTSVoiceSelector extends ConsumerStatefulWidget {
  const TTSVoiceSelector({super.key});

  @override
  ConsumerState<TTSVoiceSelector> createState() => _TTSVoiceSelectorState();
}

class _TTSVoiceSelectorState extends ConsumerState<TTSVoiceSelector> {
  VoiceGender? _filterGender;

  @override
  Widget build(BuildContext context) {
    final ttsState = ref.watch(ttsProvider);
    final ttsNotifier = ref.read(ttsProvider.notifier);
    final theme = Theme.of(context);
    final settings = ttsState.settings;
    final isEdgeEngine = settings.engine == TTSEngine.edge;

    // 根据引擎选择音色列表
    List<TTSVoice> allVoices;
    String? selectedVoiceId;
    
    if (isEdgeEngine) {
      // Edge TTS 音色
      allVoices = EdgeTTSVoices.chineseVoices.map((v) => v.toTTSVoice()).toList();
      selectedVoiceId = settings.selectedEdgeVoiceId;
    } else {
      // 系统 TTS 音色
      allVoices = ttsState.voices;
      selectedVoiceId = settings.selectedVoiceId;
    }

    // 过滤音色
    var filteredVoices = allVoices;
    if (_filterGender != null) {
      filteredVoices = allVoices.where((v) => v.gender == _filterGender).toList();
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // 拖动指示器
          const SheetDragHandle(bottomPadding: 0),

          // 标题
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.record_voice_over,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.bookTTSVoiceSelectorTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.bookTTSVoiceSelectorDone),
                ),
              ],
            ),
          ),

          // 性别筛选
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildFilterChip(
                  label: context.l10n.bookTTSVoiceFilterAll,
                  isSelected: _filterGender == null,
                  onSelected: () => setState(() => _filterGender = null),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: context.l10n.bookTTSVoiceFilterMale,
                  isSelected: _filterGender == VoiceGender.male,
                  onSelected: () =>
                      setState(() => _filterGender = VoiceGender.male),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: context.l10n.bookTTSVoiceFilterFemale,
                  isSelected: _filterGender == VoiceGender.female,
                  onSelected: () =>
                      setState(() => _filterGender = VoiceGender.female),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 音色列表
          Expanded(
            child: filteredVoices.isEmpty
                ? Center(
                    child: Text(
                      context.l10n.bookTTSVoiceEmpty,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredVoices.length,
                    itemBuilder: (context, index) {
                      final voice = filteredVoices[index];
                      final isSelected = voice.id == selectedVoiceId;

                      return _buildVoiceTile(
                        context,
                        voice: voice,
                        isSelected: isSelected,
                        onTap: () {
                          if (isEdgeEngine) {
                            ttsNotifier.setEdgeVoice(voice.id);
                          } else {
                            ttsNotifier.setVoice(voice);
                          }
                        },
                        onPreview: () => ttsNotifier.previewVoice(voice),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    final theme = Theme.of(context);
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: theme.colorScheme.primaryContainer,
      checkmarkColor: theme.colorScheme.primary,
    );
  }

  Widget _buildVoiceTile(
    BuildContext context, {
    required TTSVoice voice,
    required bool isSelected,
    required VoidCallback onTap,
    required VoidCallback onPreview,
  }) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(
              VoicePresets.getVoiceIcon(voice.gender),
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ),
        title: Text(
          localizeFormText(context, voice.displayName),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: isSelected ? FontWeight.w600 : null,
          ),
        ),
        subtitle: Text(
          localizeFormText(context, voice.gender.label),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 试听按钮
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              onPressed: onPreview,
              tooltip: context.l10n.bookTTSVoicePreviewTooltip,
            ),
            // 选中标记
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: theme.colorScheme.primary,
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
