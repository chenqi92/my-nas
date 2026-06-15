import 'dart:async';

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

    try {
      final connectionId = _generateConnectionId();
      final uri = Uri.parse(
        '$_wsUrl?TrustedClientToken=$_trustedClientToken&ConnectionId=$connectionId',
      );

      // 使用 IOWebSocketChannel 并添加必要的请求头模拟 Edge 浏览器
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: {
          'Pragma': 'no-cache',
          'Cache-Control': 'no-cache',
          'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
          'Accept-Encoding': 'gzip, deflate, br',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0',
        },
      );
      await _channel!.ready;

      _isConnected = true;
      logger.i('EdgeTTS: 已连接到服务');

      // 监听消息
      _channel!.stream.listen(
        _handleMessage,
        onError: (Object error) {
          logger.e('EdgeTTS WebSocket 错误', error);
          onError?.call(error.toString());
          _disconnect();
        },
        onDone: () {
          logger.d('EdgeTTS: 连接已关闭');
          _disconnect();
        },
      );

      // 发送配置
      await _sendConfig();
    } on Exception catch (e, st) {
      logger.e('EdgeTTS: 连接失败', e, st);
      _isConnected = false;
      rethrow;
    }
  }


  /// 断开连接
  void _disconnect() {
    _isConnected = false;
    _channel?.sink.close();
    _channel = null;
  }

  /// 关闭客户端
  Future<void> dispose() async {
    await stop();
    _disconnect();
    await _player.dispose();
  }

  /// 朗读文本
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;

    // 确保已连接
    if (!_isConnected) {
      await connect();
    }

    _isSpeaking = true;
    _audioBuffer.clear();
    _speakCompleter = Completer<void>();
    onStart?.call();

    try {
      // 发送 SSML 请求
      final ssml = _buildSSML(text);
      final requestId = _generateRequestId();

      // ignore: leading_newlines_in_multiline_strings 协议帧首行不能有前导换行
      final message = '''X-RequestId:$requestId\r
Content-Type:application/ssml+xml\r
Path:ssml\r
\r
$ssml''';

      _channel!.sink.add(message);
      logger.d('EdgeTTS: 发送请求, 文本长度: ${text.length}');

      // 等待完成
      await _speakCompleter!.future;
    } on Exception catch (e, st) {
      logger.e('EdgeTTS: 朗读失败', e, st);
      _isSpeaking = false;
      rethrow;
    }
  }

  /// 停止朗读
  Future<void> stop() async {
    _isSpeaking = false;
    _audioBuffer.clear();
    _speakCompleter?.complete();
    await _player.stop();
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
      // 文本消息
      if (message.contains('Path:turn.start')) {
        logger.d('EdgeTTS: 开始合成');
      } else if (message.contains('Path:turn.end')) {
        logger.d('EdgeTTS: 合成完成');
        _onAudioComplete();
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

    // 提取音频数据
    final audioData = data.sublist(headerLength + 2);
    _audioBuffer.addAll(audioData);
  }

  /// 音频合成完成
  Future<void> _onAudioComplete() async {
    if (_audioBuffer.isEmpty) {
      _isSpeaking = false;
      _speakCompleter?.complete();
      onComplete?.call();
      return;
    }

    try {
      // 将音频数据保存到临时文件
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/edge_tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
      await tempFile.writeAsBytes(_audioBuffer);

      // 播放音频
      await _player.setFilePath(tempFile.path);
      await _player.play();

      // 等待播放完成
      await _player.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );

      // 清理临时文件
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } on Exception catch (e, st) {
      logger.e('EdgeTTS: 播放失败', e, st);
    }

    _isSpeaking = false;
    _audioBuffer.clear();
    _speakCompleter?.complete();
    onComplete?.call();
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
    final pitchStr = _pitch >= 0 ? '+${_pitch.toInt()}Hz' : '${_pitch.toInt()}Hz';
    final volumeStr = _volume >= 0 ? '+${_volume.toInt()}%' : '${_volume.toInt()}%';

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
