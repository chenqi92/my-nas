// ignore_for_file: unused_field

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/features/book/data/services/tts/tts_service.dart';
import 'package:my_nas/features/book/data/services/tts/tts_settings.dart';
import 'package:my_nas/features/book/data/services/tts/tts_voice.dart';

/// TTS 状态
class TTSState {
  const TTSState({
    this.playState = TTSPlayState.idle,
    this.currentParagraphIndex = 0,
    this.currentCharStart = 0,
    this.currentCharEnd = 0,
    this.currentWord = '',
    this.voices = const [],
    this.selectedVoice,
    this.settings = const TTSSettings(),
    this.isInitialized = false,
    this.error,
  });

  final TTSPlayState playState;
  final int currentParagraphIndex;
  final int currentCharStart;
  final int currentCharEnd;
  final String currentWord;
  final List<TTSVoice> voices;
  final TTSVoice? selectedVoice;
  final TTSSettings settings;
  final bool isInitialized;
  final String? error;

  bool get isPlaying => playState == TTSPlayState.playing;
  bool get isPaused => playState == TTSPlayState.paused;
  bool get isIdle => playState == TTSPlayState.idle;

  TTSState copyWith({
    TTSPlayState? playState,
    int? currentParagraphIndex,
    int? currentCharStart,
    int? currentCharEnd,
    String? currentWord,
    List<TTSVoice>? voices,
    TTSVoice? selectedVoice,
    TTSSettings? settings,
    bool? isInitialized,
    String? error,
  }) =>
      TTSState(
        playState: playState ?? this.playState,
        currentParagraphIndex:
            currentParagraphIndex ?? this.currentParagraphIndex,
        currentCharStart: currentCharStart ?? this.currentCharStart,
        currentCharEnd: currentCharEnd ?? this.currentCharEnd,
        currentWord: currentWord ?? this.currentWord,
        voices: voices ?? this.voices,
        selectedVoice: selectedVoice ?? this.selectedVoice,
        settings: settings ?? this.settings,
        isInitialized: isInitialized ?? this.isInitialized,
        error: error,
      );

  /// 清除高亮位置
  TTSState clearHighlight() => copyWith(
        currentCharStart: 0,
        currentCharEnd: 0,
        currentWord: '',
      );
}

/// TTS Provider
final ttsProvider = StateNotifierProvider<TTSNotifier, TTSState>((ref) {
  return TTSNotifier();
});

/// TTS 状态管理器
class TTSNotifier extends StateNotifier<TTSState> {
  TTSNotifier() : super(const TTSState());

  final TTSService _service = TTSService.instance;
  final TTSSettingsService _settingsService = TTSSettingsService();

  StreamSubscription<TTSPlayState>? _stateSubscription;
  StreamSubscription<TTSProgress>? _progressSubscription;
  StreamSubscription<void>? _completionSubscription;

  // 当前朗读的段落列表
  List<String> _paragraphs = [];
  int _currentParagraphIndex = 0;

  // 段落完成回调
  void Function()? _onParagraphComplete;
  void Function()? _onAllComplete;
  void Function(int paragraphIndex)? _onParagraphChanged;

  /// 初始化
  Future<void> init() async {
    if (state.isInitialized) return;

    try {
      await _service.init();

      // 监听状态变化
      _stateSubscription = _service.stateStream.listen((playState) {
        state = state.copyWith(playState: playState);
      });

      // 监听进度变化
      _progressSubscription = _service.progressStream.listen((progress) {
        state = state.copyWith(
          currentCharStart: progress.start,
          currentCharEnd: progress.end,
          currentWord: progress.word,
        );
      });

      // 监听完成事件
      _completionSubscription = _service.completionStream.listen((_) {
        _onParagraphCompleted();
      });

      state = state.copyWith(
        isInitialized: true,
        voices: _service.availableVoices,
        selectedVoice: _service.currentVoice,
        settings: _service.settings,
      );
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'tts_init');
      state = state.copyWith(error: '初始化 TTS 失败: $e');
    }
  }

  /// 段落朗读完成处理
  void _onParagraphCompleted() {
    _onParagraphComplete?.call();

    // 检查是否还有下一段
    if (_currentParagraphIndex < _paragraphs.length - 1) {
      _currentParagraphIndex++;
      state = state.copyWith(
        currentParagraphIndex: _currentParagraphIndex,
      );
      state = state.clearHighlight();

      // 自动播放下一段
      if (state.settings.autoPlayNextChapter) {
        _speakCurrentParagraph();
      }
    } else {
      // 全部完成
      state = state.copyWith(playState: TTSPlayState.idle);
      state = state.clearHighlight();
      _onAllComplete?.call();
    }
  }

  /// 开始朗读段落列表
  Future<void> speakParagraphs(
    List<String> paragraphs, {
    int startIndex = 0,
    void Function()? onParagraphComplete,
    void Function()? onAllComplete,
    void Function(int paragraphIndex)? onParagraphChanged,
  }) async {
    if (!state.isInitialized) await init();

    _paragraphs = paragraphs;
    _currentParagraphIndex = startIndex.clamp(0, paragraphs.length - 1);
    _onParagraphComplete = onParagraphComplete;
    _onAllComplete = onAllComplete;
    _onParagraphChanged = onParagraphChanged;

    debugPrint('TTS speakParagraphs: 设置 ${paragraphs.length} 段, 起始索引 $_currentParagraphIndex');

    state = state.copyWith(
      currentParagraphIndex: _currentParagraphIndex,
    );
    state = state.clearHighlight();

    await _speakCurrentParagraph();
  }

  /// 朗读当前段落
  Future<void> _speakCurrentParagraph() async {
    if (_currentParagraphIndex >= _paragraphs.length) return;

    final text = _paragraphs[_currentParagraphIndex];
    if (text.trim().isEmpty) {
      // 跳过空段落
      _onParagraphCompleted();
      return;
    }

    await _service.speak(text);
  }

  /// 朗读单个文本
  Future<void> speak(String text) async {
    if (!state.isInitialized) await init();

    _paragraphs = [text];
    _currentParagraphIndex = 0;
    state = state.copyWith(currentParagraphIndex: 0);
    state = state.clearHighlight();

    await _service.speak(text);
  }

  /// 暂停
  Future<void> pause() async {
    await _service.pause();
  }

  /// 继续 (需要从断点重新播放)
  Future<void> resume() async {
    if (state.isPaused && _paragraphs.isNotEmpty) {
      await _speakCurrentParagraph();
    }
  }

  /// 停止
  Future<void> stop() async {
    await _service.stop();
    _paragraphs = [];
    _currentParagraphIndex = 0;
    state = state.copyWith(
      currentParagraphIndex: 0,
      playState: TTSPlayState.idle,
    );
    state = state.clearHighlight();
  }

  /// 上一段
  Future<void> previousParagraph() async {
    debugPrint('TTS previousParagraph: index=$_currentParagraphIndex, total=${_paragraphs.length}');
    if (_paragraphs.isEmpty) {
      debugPrint('TTS previousParagraph: _paragraphs is empty!');
      return;
    }
    if (_currentParagraphIndex > 0) {
      await _service.stop();
      _currentParagraphIndex--;
      state = state.copyWith(currentParagraphIndex: _currentParagraphIndex);
      state = state.clearHighlight();
      _onParagraphChanged?.call(_currentParagraphIndex);
      await _speakCurrentParagraph();
    } else {
      debugPrint('TTS previousParagraph: already at first paragraph');
    }
  }

  /// 下一段
  Future<void> nextParagraph() async {
    debugPrint('TTS nextParagraph: index=$_currentParagraphIndex, total=${_paragraphs.length}');
    if (_paragraphs.isEmpty) {
      debugPrint('TTS nextParagraph: _paragraphs is empty!');
      return;
    }
    if (_currentParagraphIndex < _paragraphs.length - 1) {
      await _service.stop();
      _currentParagraphIndex++;
      state = state.copyWith(currentParagraphIndex: _currentParagraphIndex);
      state = state.clearHighlight();
      _onParagraphChanged?.call(_currentParagraphIndex);
      await _speakCurrentParagraph();
    } else {
      debugPrint('TTS nextParagraph: already at last paragraph');
    }
  }

  /// 跳转到指定段落
  Future<void> goToParagraph(int index) async {
    if (index >= 0 && index < _paragraphs.length) {
      await _service.stop();
      _currentParagraphIndex = index;
      state = state.copyWith(currentParagraphIndex: _currentParagraphIndex);
      state = state.clearHighlight();
      await _speakCurrentParagraph();
    }
  }

  /// 设置音色（如果正在播放，会自动使用新音色重新朗读当前段落）
  Future<void> setVoice(TTSVoice voice) async {
    final wasPlaying = state.isPlaying;
    
    // 先停止当前朗读
    if (wasPlaying) {
      await _service.stop();
    }
    
    // 设置新音色
    await _service.setVoice(voice);
    state = state.copyWith(selectedVoice: voice);
    
    // 如果之前在播放，使用新音色重新朗读当前段落
    if (wasPlaying && _paragraphs.isNotEmpty) {
      await _speakCurrentParagraph();
    }
  }

  /// 设置 Edge TTS 音色
  Future<void> setEdgeVoice(String voiceId) async {
    final wasPlaying = state.isPlaying;
    
    if (wasPlaying) {
      await _service.stop();
    }
    
    final newSettings = state.settings.copyWith(selectedEdgeVoiceId: voiceId);
    state = state.copyWith(settings: newSettings);
    await _service.updateSettings(newSettings);
    
    // 如果之前在播放，使用新音色重新朗读当前段落
    if (wasPlaying && _paragraphs.isNotEmpty) {
      await _speakCurrentParagraph();
    }
  }

  /// 设置语速（如果正在播放，会自动重新朗读当前段落）
  Future<void> setSpeechRate(double rate) async {
    final wasPlaying = state.isPlaying;
    
    if (wasPlaying) {
      await _service.stop();
    }
    
    await _service.setSpeechRate(rate);
    state = state.copyWith(
      settings: state.settings.copyWith(speechRate: rate),
    );
    
    if (wasPlaying && _paragraphs.isNotEmpty) {
      await _speakCurrentParagraph();
    }
  }

  /// 设置音调（如果正在播放，会自动重新朗读当前段落）
  Future<void> setPitch(double pitch) async {
    final wasPlaying = state.isPlaying;
    
    if (wasPlaying) {
      await _service.stop();
    }
    
    await _service.setPitch(pitch);
    state = state.copyWith(
      settings: state.settings.copyWith(pitch: pitch),
    );
    
    if (wasPlaying && _paragraphs.isNotEmpty) {
      await _speakCurrentParagraph();
    }
  }

  /// 设置音量（如果正在播放，会自动重新朗读当前段落）
  Future<void> setVolume(double volume) async {
    final wasPlaying = state.isPlaying;
    
    if (wasPlaying) {
      await _service.stop();
    }
    
    await _service.setVolume(volume);
    state = state.copyWith(
      settings: state.settings.copyWith(volume: volume),
    );
    
    if (wasPlaying && _paragraphs.isNotEmpty) {
      await _speakCurrentParagraph();
    }
  }

  /// 设置引擎
  Future<void> setEngine(TTSEngine engine) async {
    final wasPlaying = state.isPlaying;
    
    if (wasPlaying) {
      await _service.stop();
    }
    
    final newSettings = state.settings.copyWith(engine: engine);
    state = state.copyWith(settings: newSettings);
    await _service.updateSettings(newSettings);
    
    // 如果之前在播放，使用新引擎重新朗读
    if (wasPlaying && _paragraphs.isNotEmpty) {
      await _speakCurrentParagraph();
    }
  }

  /// 更新设置
  Future<void> updateSettings(TTSSettings settings) async {
    await _service.updateSettings(settings);
    state = state.copyWith(settings: settings);
  }

  /// 试听音色
  Future<void> previewVoice(TTSVoice voice) async {
    await _service.previewVoice(voice);
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _progressSubscription?.cancel();
    _completionSubscription?.cancel();
    super.dispose();
  }
}
