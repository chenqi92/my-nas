import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/tts/edge_tts_voices.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Edge TTS 客户端
///
/// 通过 WebSocket 协议连接微软 Edge 语音合成服务。
/// 免费且无需 API Key。
class EdgeTTSClient {
  EdgeTTSClient._();
  static final EdgeTTSClient instance = EdgeTTSClient._();

  static const _wsUrl =
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';
  static const _trustedClientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';

  WebSocketChannel? _channel;
  final AudioPlayer _player = AudioPlayer();
  bool _isConnected = false;
  bool _isSpeaking = false;

  // 音频数据缓冲
  final List<int> _audioBuffer = [];
  Completer<void>? _speakCompleter;
  Future<void> _speakTail = Future<void>.value();
  final Set<String> _completingRequestIds = <String>{};
  Completer<void>? _playbackCancellation;
  int _speakGeneration = 0;
  int _connectionGeneration = 0;
  String? _activeRequestId;

  // 当前设置
  EdgeVoice _currentVoice = EdgeTTSVoices.defaultVoice;
  double _rate = 0.0; // -100 到 +100
  double _pitch = 0.0; // -50Hz 到 +50Hz
  double _volume = 0.0; // -100 到 +100

  // 回调
  void Function()? onStart;
  void Function()? onComplete;
  void Function(String error)? onError;

  EdgeVoice get currentVoice => _currentVoice;
  bool get isSpeaking => _isSpeaking;

  /// 连接到 Edge TTS 服务
  Future<void> connect() async {
    if (_isConnected) return;

    final connectionGeneration = ++_connectionGeneration;
    try {
      final connectionId = _generateConnectionId();
      final uri = Uri.parse(
        '$_wsUrl?TrustedClientToken=$_trustedClientToken&ConnectionId=$connectionId',
      );

      // 使用 IOWebSocketChannel 并添加必要的请求头模拟 Edge 浏览器
      final channel = IOWebSocketChannel.connect(
        uri,
        headers: {
          'Pragma': 'no-cache',
          'Cache-Control': 'no-cache',
          'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
          'Accept-Encoding': 'gzip, deflate, br',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0',
        },
      );
      _channel = channel;
      await channel.ready;

      if (!_isCurrentConnection(channel, connectionGeneration)) {
        await channel.sink.close();
        return;
      }

      _isConnected = true;
      logger.i('EdgeTTS: 已连接到服务');

      // 监听消息
      channel.stream.listen(
        (message) {
          if (_isCurrentConnection(channel, connectionGeneration)) {
            _handleMessage(message);
          }
        },
        onError: (Object error) {
          if (!_isCurrentConnection(channel, connectionGeneration)) return;
          logger.e('EdgeTTS WebSocket 错误', error);
          _failSpeak(error);
          _disconnect();
          _notifyError(error.toString());
        },
        onDone: () {
          if (!_isCurrentConnection(channel, connectionGeneration)) return;
          logger.d('EdgeTTS: 连接已关闭');
          if (_isSpeaking) {
            _failSpeak(
              StateError('EdgeTTS WebSocket closed before completion'),
            );
          }
          _disconnect();
        },
      );

      // 发送配置
      await _sendConfig();
    } catch (e, st) {
      logger.e('EdgeTTS: 连接失败', e, st);
      if (connectionGeneration == _connectionGeneration) {
        _disconnect();
      }
      rethrow;
    }
  }

  bool _isCurrentConnection(
    WebSocketChannel channel,
    int connectionGeneration,
  ) =>
      connectionGeneration == _connectionGeneration &&
      identical(_channel, channel);

  /// 断开连接
  void _disconnect() {
    final channel = _channel;
    _isConnected = false;
    _channel = null;
    _activeRequestId = null;
    _connectionGeneration++;
    channel?.sink.close();
  }

  /// 关闭客户端
  Future<void> dispose() async {
    await stop();
    _disconnect();
    await _player.dispose();
  }

  /// 朗读文本
  Future<void> speak(String text) {
    if (text.trim().isEmpty) return Future<void>.value();

    final speakGeneration = _speakGeneration;
    final operation = _speakTail.then((_) async {
      if (speakGeneration != _speakGeneration) return;
      await _speakOnce(text, speakGeneration);
    });
    _speakTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _speakOnce(String text, int speakGeneration) async {
    if (speakGeneration != _speakGeneration) return;

    // 确保已连接
    if (!_isConnected) {
      await connect();
    }
    if (speakGeneration != _speakGeneration) return;

    _isSpeaking = true;
    _audioBuffer.clear();
    final completer = Completer<void>();
    _speakCompleter = completer;
    _notifyStart();

    final requestId = _generateRequestId();
    _activeRequestId = requestId;
    try {
      // 发送 SSML 请求
      final ssml = _buildSSML(text);

      // ignore: leading_newlines_in_multiline_strings 协议帧首行不能有前导换行
      final message = '''X-RequestId:$requestId\r
Content-Type:application/ssml+xml\r
Path:ssml\r
\r
$ssml''';

      final channel = _channel;
      if (channel == null || !_isConnected) {
        throw Exception('EdgeTTS WebSocket is not connected');
      }
      channel.sink.add(message);
      logger.d('EdgeTTS: 发送请求, 文本长度: ${text.length}');

      // 等待完成
      await completer.future;
    } catch (e, st) {
      logger.e('EdgeTTS: 朗读失败', e, st);
      if (_activeRequestId == requestId) {
        _failSpeak(e, st);
      }
      rethrow;
    } finally {
      if (identical(_speakCompleter, completer)) {
        _speakCompleter = null;
      }
    }
  }

  /// 停止朗读
  Future<void> stop() async {
    _speakGeneration++;
    _isSpeaking = false;
    _activeRequestId = null;
    _audioBuffer.clear();
    _cancelPlaybackWait();
    _completeSpeak();
    // 关闭当前连接，确保已取消请求的迟到消息不会污染下一次朗读。
    _disconnect();
    await _player.stop();
  }

  void _completeSpeak() {
    final completer = _speakCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void _failSpeak(Object error, [StackTrace? stackTrace]) {
    _isSpeaking = false;
    _activeRequestId = null;
    _audioBuffer.clear();
    _cancelPlaybackWait();
    final completer = _speakCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }

  void _cancelPlaybackWait() {
    final cancellation = _playbackCancellation;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
  }

  void _notifyStart() {
    try {
      onStart?.call();
    } catch (e, st) {
      logger.w('EdgeTTS: onStart 回调失败', e, st);
    }
  }

  void _notifyComplete() {
    try {
      onComplete?.call();
    } catch (e, st) {
      logger.w('EdgeTTS: onComplete 回调失败', e, st);
    }
  }

  void _notifyError(String error) {
    try {
      onError?.call(error);
    } catch (e, st) {
      logger.w('EdgeTTS: onError 回调失败', e, st);
    }
  }

  /// 设置音色
  void setVoice(EdgeVoice voice) {
    _currentVoice = voice;
  }

  /// 设置语速 (0.0 = 正常, -1.0 = 最慢, 1.0 = 最快)
  void setRate(double rate) {
    // 转换为 -100 到 +100 范围
    _rate = (rate * 100).clamp(-100, 100);
  }

  /// 设置音调 (0.0 = 正常, -1.0 = 最低, 1.0 = 最高)
  void setPitch(double pitch) {
    // 转换为 -50Hz 到 +50Hz 范围
    _pitch = (pitch * 50).clamp(-50, 50);
  }

  /// 设置音量 (0.0 = 静音, 1.0 = 最大)
  void setVolume(double volume) {
    // 转换为 -100 到 0 范围 (Edge TTS 音量)
    _volume = ((volume - 1) * 100).clamp(-100, 0);
  }

  /// 处理 WebSocket 消息
  void _handleMessage(dynamic message) {
    if (message is String) {
      final messageRequestId = _extractRequestId(message);
      if (!_matchesActiveRequest(messageRequestId)) return;

      // 文本消息
      if (message.contains('Path:turn.start')) {
        logger.d('EdgeTTS: 开始合成');
      } else if (message.contains('Path:turn.end')) {
        logger.d('EdgeTTS: 合成完成');
        final requestId = messageRequestId ?? _activeRequestId;
        if (requestId != null) {
          unawaited(_onAudioComplete(requestId));
        }
      }
    } else if (message is List<int>) {
      // 二进制消息（音频数据）
      _handleAudioData(Uint8List.fromList(message));
    }
  }

  /// 处理音频数据
  void _handleAudioData(Uint8List data) {
    // Edge TTS 返回的数据格式:
    // 前两个字节是头部长度，后面是音频数据
    if (data.length < 2) return;

    final headerLength = (data[0] << 8) | data[1];
    if (data.length <= headerLength + 2) return;

    final header = utf8.decode(
      data.sublist(2, headerLength + 2),
      allowMalformed: true,
    );
    if (!_matchesActiveRequest(_extractRequestId(header))) return;

    // 提取音频数据
    final audioData = data.sublist(headerLength + 2);
    _audioBuffer.addAll(audioData);
  }

  String? _extractRequestId(String headers) {
    for (final line in headers.split(RegExp(r'\r?\n'))) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      if (line.substring(0, separator).trim().toLowerCase() == 'x-requestid') {
        final value = line.substring(separator + 1).trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  bool _matchesActiveRequest(String? requestId) {
    final activeRequestId = _activeRequestId;
    if (!_isSpeaking || activeRequestId == null) return false;
    return requestId == null || requestId == activeRequestId;
  }

  /// 音频合成完成
  Future<void> _onAudioComplete(String requestId) async {
    if (!_matchesActiveRequest(requestId) ||
        !_completingRequestIds.add(requestId)) {
      return;
    }

    File? tempFile;
    final playbackCancellation = Completer<void>();
    _playbackCancellation = playbackCancellation;
    try {
      final audioData = Uint8List.fromList(_audioBuffer);
      if (audioData.isNotEmpty) {
        // 将当前请求的音频快照保存到临时文件，避免后续请求修改缓冲区。
        final tempDir = Directory.systemTemp;
        tempFile = File(
          '${tempDir.path}/edge_tts_${DateTime.now().microsecondsSinceEpoch}.mp3',
        );
        await tempFile.writeAsBytes(audioData);
        if (!_matchesActiveRequest(requestId)) return;

        // 播放音频
        await _player.setFilePath(tempFile.path);
        if (!_matchesActiveRequest(requestId)) return;
        await _player.play();
        if (!_matchesActiveRequest(requestId)) return;

        // 等待播放完成。Future.any 不会取消败方 Future，因此这里显式管理
        // playerStateStream 订阅，stop() 取消时也能立即释放监听。
        final playbackCompleted = Completer<void>();
        final playbackSubscription = _player.playerStateStream.listen(
          (state) {
            if (state.processingState == ProcessingState.completed &&
                !playbackCompleted.isCompleted) {
              playbackCompleted.complete();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!playbackCompleted.isCompleted) {
              playbackCompleted.completeError(error, stackTrace);
            }
          },
        );
        try {
          await Future.any<void>([
            playbackCompleted.future,
            playbackCancellation.future,
          ]);
        } finally {
          await playbackSubscription.cancel();
        }
        if (playbackCancellation.isCompleted) return;
        if (!_matchesActiveRequest(requestId)) return;
      }
    } catch (e, st) {
      logger.e('EdgeTTS: 播放失败', e, st);
      if (_matchesActiveRequest(requestId)) {
        _failSpeak(e, st);
        _notifyError(e.toString());
      }
    } finally {
      _completingRequestIds.remove(requestId);
      if (identical(_playbackCancellation, playbackCancellation)) {
        _playbackCancellation = null;
      }
      if (tempFile != null) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } on Exception catch (e) {
          logger.w('EdgeTTS: 清理临时音频失败: $e');
        }
      }
    }

    if (!_matchesActiveRequest(requestId)) return;
    _isSpeaking = false;
    _activeRequestId = null;
    _audioBuffer.clear();
    _completeSpeak();
    _notifyComplete();
  }

  /// 发送配置
  Future<void> _sendConfig() async {
    const config = '''
Content-Type:application/json; charset=utf-8\r
Path:speech.config\r
\r
{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}''';

    _channel!.sink.add(config);
  }

  /// 构建 SSML
  String _buildSSML(String text) {
    final rateStr = _rate >= 0 ? '+${_rate.toInt()}%' : '${_rate.toInt()}%';
    final pitchStr = _pitch >= 0
        ? '+${_pitch.toInt()}Hz'
        : '${_pitch.toInt()}Hz';
    final volumeStr = _volume >= 0
        ? '+${_volume.toInt()}%'
        : '${_volume.toInt()}%';

    // 转义 XML 特殊字符
    final escapedText = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');

    // ignore: leading_newlines_in_multiline_strings SSML 内容不应有前导换行
    return '''<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="${_currentVoice.locale}">
  <voice name="${_currentVoice.id}">
    <prosody rate="$rateStr" pitch="$pitchStr" volume="$volumeStr">
      $escapedText
    </prosody>
  </voice>
</speak>''';
  }

  /// 生成连接 ID
  String _generateConnectionId() {
    final random = Random();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 生成请求 ID
  String _generateRequestId() {
    final random = Random();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
