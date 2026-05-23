import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/tts/edge_tts_client.dart';
import 'package:my_nas/features/book/data/services/tts/edge_tts_voices.dart';
import 'package:my_nas/features/book/data/services/tts/tts_settings.dart';
import 'package:my_nas/features/book/data/services/tts/tts_voice.dart';

/// TTS 播放状态
enum TTSPlayState {
  idle,
  playing,
  paused,
  completed,
}

/// TTS 进度信息
class TTSProgress {
  const TTSProgress({
    required this.text,
    required this.start,
    required this.end,
    required this.word,
  });

  final String text;
  final int start;
  final int end;
  final String word;
}

/// TTS 服务
///
/// 封装 flutter_tts，提供统一的 TTS 控制接口。
/// 支持本地 TTS 引擎，提供进度回调用于高亮同步。
class TTSService {
  TTSService._();

  static TTSService? _instance;
  static TTSService get instance => _instance ??= TTSService._();

  final FlutterTts _tts = FlutterTts();
  final EdgeTTSClient _edgeTts = EdgeTTSClient.instance;
  final TTSSettingsService _settingsService = TTSSettingsService();

  // 状态
  TTSPlayState _state = TTSPlayState.idle;
  TTSPlayState get state => _state;

  List<TTSVoice> _availableVoices = [];
  List<TTSVoice> get availableVoices => _availableVoices;

  TTSVoice? _currentVoice;
  TTSVoice? get currentVoice => _currentVoice;

  TTSSettings _settings = const TTSSettings();
  TTSSettings get settings => _settings;

  bool _isInitialized = false;

  // 回调
  final _stateController = StreamController<TTSPlayState>.broadcast();
  Stream<TTSPlayState> get stateStream => _stateController.stream;

  final _progressController = StreamController<TTSProgress>.broadcast();
  Stream<TTSProgress> get progressStream => _progressController.stream;

  final _completionController = StreamController<void>.broadcast();
  Stream<void> get completionStream => _completionController.stream;

  /// 初始化 TTS 服务
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // 初始化设置服务
      await _settingsService.init();
      _settings = _settingsService.getSettings();

      // 设置语言
      await _tts.setLanguage('zh-CN');

      // 应用设置
      await _applySetting();

      // 设置回调
      _tts.setStartHandler(() {
        _state = TTSPlayState.playing;
        _stateController.add(_state);
        logger.d('TTS: 开始朗读');
      });

      _tts.setCompletionHandler(() {
        _state = TTSPlayState.completed;
        _stateController.add(_state);
        _completionController.add(null);
        logger.d('TTS: 朗读完成');
      });

      _tts.setPauseHandler(() {
        _state = TTSPlayState.paused;
        _stateController.add(_state);
        logger.d('TTS: 已暂停');
      });

      _tts.setContinueHandler(() {
        _state = TTSPlayState.playing;
        _stateController.add(_state);
        logger.d('TTS: 继续朗读');
      });

      _tts.setCancelHandler(() {
        _state = TTSPlayState.idle;
        _stateController.add(_state);
        logger.d('TTS: 已取消');
      });

      _tts.setErrorHandler((msg) {
        logger.e('TTS 错误: $msg');
        _state = TTSPlayState.idle;
        _stateController.add(_state);
      });

      // 进度回调 - 关键，用于高亮同步
      _tts.setProgressHandler((text, start, end, word) {
        _progressController.add(TTSProgress(
          text: text,
          start: start,
          end: end,
          word: word,
        ));
      });

      // 获取可用音色
      await _loadVoices();

      // 恢复选中的音色
      if (_settings.selectedVoiceId != null) {
        final voice = _availableVoices.firstWhere(
          (v) => v.id == _settings.selectedVoiceId,
          orElse: () => VoicePresets.defaultChinese,
        );
        await setVoice(voice);
      }

      _isInitialized = true;
      logger.i('TTS: 初始化完成, 可用音色: ${_availableVoices.length}');
    } on Exception catch (e, st) {
      logger.e('TTS: 初始化失败', e, st);
      rethrow;
    }
  }

  /// 加载可用音色
  Future<void> _loadVoices() async {
    try {
      final voices = await _tts.getVoices as List<dynamic>?;
      if (voices == null) {
        _availableVoices = [VoicePresets.defaultChinese];
        return;
      }

      final voiceList = voices
          .cast<Map<dynamic, dynamic>>()
          .where((v) {
            final locale = v['locale'] as String? ?? '';
            // 只保留中文音色
            return locale.startsWith('zh') ||
                locale.startsWith('cmn') ||
                locale.contains('CN') ||
                locale.contains('TW') ||
                locale.contains('HK');
          })
          .map(TTSVoice.fromSystemVoice)
          .toList();

      // 去重：按 ID 去重（同一音色可能被系统重复返回）
      final seenIds = <String>{};
      _availableVoices = voiceList.where((voice) {
        if (seenIds.contains(voice.id)) return false;
        seenIds.add(voice.id);
        return true;
      }).toList();

      // 确保至少有一个默认音色
      if (_availableVoices.isEmpty) {
        _availableVoices = [VoicePresets.defaultChinese];
      }

      // 按性别排序
      _availableVoices.sort((a, b) => a.gender.index.compareTo(b.gender.index));
      
      logger.d('TTS: 加载 ${_availableVoices.length} 个中文音色');
    } on Exception catch (e) {
      logger.w('TTS: 加载音色失败', e);
      _availableVoices = [VoicePresets.defaultChinese];
    }
  }

  /// 应用当前设置
  Future<void> _applySetting() async {
    // iOS TTS 语速范围是 0.0-1.0，其中 0.5 是正常速度
    // Android TTS 语速范围是 0.5-2.0，其中 1.0 是正常速度
    // 我们使用用户设置值 (0.5-2.0)，需要对 iOS 进行转换
    final rate = Platform.isIOS
        ? _convertRateForIOS(_settings.speechRate)
        : _settings.speechRate;
    await _tts.setSpeechRate(rate);
    await _tts.setPitch(_settings.pitch);
    await _tts.setVolume(_settings.volume);

    // iOS 特定配置
    if (Platform.isIOS) {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.ambient,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
    }

    // Android 特定配置
    if (Platform.isAndroid) {
      await _tts.setQueueMode(1); // 1 = QUEUE_ADD
    }
  }

  /// 开始朗读
  Future<void> speak(String text) async {
    if (!_isInitialized) await init();

    if (text.trim().isEmpty) {
      logger.w('TTS: 文本为空，跳过朗读');
      return;
    }

    // 调试日志 - 使用 print 确保输出到控制台
    // ignore: avoid_print
    print('🔊 TTS.speak: engine=${_settings.engine.name}, edgeVoiceId=${_settings.selectedEdgeVoiceId}');

    // 根据引擎设置选择 TTS 方式
    if (_settings.engine == TTSEngine.edge) {
      // ignore: avoid_print
      print('🔊 TTS: 使用 Edge TTS 朗读');
      await _speakWithEdgeTTS(text);
    } else {
      // ignore: avoid_print
      print('🔊 TTS: 使用系统 TTS 朗读');
      await _tts.speak(text);
    }
  }

  /// 使用 Edge TTS 朗读
  Future<void> _speakWithEdgeTTS(String text) async {
    // ignore: avoid_print
    print('🔊 _speakWithEdgeTTS: 开始, voiceId=${_settings.selectedEdgeVoiceId}');
    try {
      // 设置 Edge TTS 音色
      if (_settings.selectedEdgeVoiceId != null) {
        final voice = EdgeTTSVoices.getVoiceById(_settings.selectedEdgeVoiceId!);
        if (voice != null) {
          _edgeTts.setVoice(voice);
          // ignore: avoid_print
          print('🔊 _speakWithEdgeTTS: 设置音色 ${voice.name}');
        }
      } else {
        _edgeTts.setVoice(EdgeTTSVoices.defaultVoice);
        // ignore: avoid_print
        print('🔊 _speakWithEdgeTTS: 使用默认音色');
      }

      // 设置语速/音调/音量 (转换为 Edge TTS 范围)
      _edgeTts.setRate(_settings.speechRate - 1.0); // 0.5-2.0 -> -0.5-1.0
      _edgeTts.setPitch(_settings.pitch - 1.0); // 0.5-2.0 -> -0.5-1.0
      _edgeTts.setVolume(_settings.volume);

      // 设置回调
      _edgeTts.onStart = () {
        _state = TTSPlayState.playing;
        _stateController.add(_state);
        // ignore: avoid_print
        print('🔊 EdgeTTS: onStart 回调');
      };

      _edgeTts.onComplete = () {
        _state = TTSPlayState.completed;
        _stateController.add(_state);
        _completionController.add(null);
        // ignore: avoid_print
        print('🔊 EdgeTTS: onComplete 回调');
      };

      _edgeTts.onError = (error) {
        // ignore: avoid_print
        print('🔊 EdgeTTS: onError 回调 - $error');
        // 降级到系统 TTS
        _tts.speak(text);
      };

      // ignore: avoid_print
      print('🔊 _speakWithEdgeTTS: 调用 _edgeTts.speak()');
      await _edgeTts.speak(text);
      // ignore: avoid_print
      print('🔊 _speakWithEdgeTTS: _edgeTts.speak() 完成');
    } catch (e, st) {
      // 捕获所有错误，包括 Error 和 Exception
      // ignore: avoid_print
      print('🔊 _speakWithEdgeTTS: 捕获错误 - $e');
      print('🔊 Stack trace: $st');
      // 网络错误时降级到系统 TTS
      await _tts.speak(text);
    }
  }

  /// 暂停
  Future<void> pause() async {
    await _tts.pause();
  }

  /// 继续
  Future<void> resume() async {
    // flutter_tts 没有 resume，只能重新播放
    // 这里我们使用平台特定的方法
    if (Platform.isIOS) {
      // iOS 支持 pause/continue
      await _tts.speak(''); // 触发 continue
    }
    // Android 需要重新播放，由调用方处理
  }

  /// 停止
  Future<void> stop() async {
    // 停止两种引擎
    await _tts.stop();
    await _edgeTts.stop();
    _state = TTSPlayState.idle;
    _stateController.add(_state);
  }

  /// 设置音色
  Future<void> setVoice(TTSVoice voice) async {
    try {
      await _tts.setVoice(voice.toFlutterTtsVoice());
      _currentVoice = voice;

      // 保存选择
      _settings = _settings.copyWith(selectedVoiceId: voice.id);
      await _settingsService.saveSettings(_settings);

      logger.d('TTS: 设置音色为 ${voice.displayName}');
    } on Exception catch (e) {
      logger.w('TTS: 设置音色失败', e);
    }
  }

  /// 设置语速
  Future<void> setSpeechRate(double rate) async {
    final clampedRate = rate.clamp(0.5, 2.0);
    // iOS 需要转换为 0-1 范围
    final platformRate = Platform.isIOS
        ? _convertRateForIOS(clampedRate)
        : clampedRate;
    await _tts.setSpeechRate(platformRate);
    _settings = _settings.copyWith(speechRate: clampedRate);
    await _settingsService.saveSettings(_settings);
  }

  /// 将用户设置的语速 (0.5-2.0) 转换为 iOS 语速 (0.0-1.0)
  /// 用户设置 1.0 = iOS 0.5 (正常速度)
  /// 用户设置 0.5 = iOS 0.25 (慢速)
  /// 用户设置 2.0 = iOS 1.0 (快速)
  double _convertRateForIOS(double userRate) {
    // 线性映射: userRate 0.5->0.25, 1.0->0.5, 2.0->1.0
    // 公式: (userRate - 0.5) / 1.5 * 0.75 + 0.25
    return ((userRate - 0.5) / 1.5 * 0.75 + 0.25).clamp(0.0, 1.0);
  }

  /// 设置音调
  Future<void> setPitch(double pitch) async {
    final clampedPitch = pitch.clamp(0.5, 2.0);
    await _tts.setPitch(clampedPitch);
    _settings = _settings.copyWith(pitch: clampedPitch);
    await _settingsService.saveSettings(_settings);
  }

  /// 设置音量
  Future<void> setVolume(double volume) async {
    final clampedVolume = volume.clamp(0.0, 1.0);
    await _tts.setVolume(clampedVolume);
    _settings = _settings.copyWith(volume: clampedVolume);
    await _settingsService.saveSettings(_settings);
  }

  /// 更新设置
  Future<void> updateSettings(TTSSettings settings) async {
    // ignore: avoid_print
    print('🔊 TTSService.updateSettings: engine=${settings.engine.name}, edgeVoiceId=${settings.selectedEdgeVoiceId}');
    _settings = settings;
    await _applySetting();
    await _settingsService.saveSettings(settings);
  }

  /// 试听音色
  Future<void> previewVoice(TTSVoice voice) async {
    final previousVoice = _currentVoice;
    await _tts.setVoice(voice.toFlutterTtsVoice());
    await _tts.speak('你好，这是${voice.displayName}的试听效果。');

    // 恢复之前的音色
    if (previousVoice != null) {
      await Future<void>.delayed(const Duration(seconds: 3));
      await _tts.setVoice(previousVoice.toFlutterTtsVoice());
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    await stop();
    await _stateController.close();
    await _progressController.close();
    await _completionController.close();
    _isInitialized = false;
    _instance = null;
  }
}
