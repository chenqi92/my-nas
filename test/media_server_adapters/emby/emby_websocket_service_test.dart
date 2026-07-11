import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_nas/media_server_adapters/emby/emby_websocket_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _MockWebSocketChannel extends Mock implements WebSocketChannel {}

class _MockWebSocketSink extends Mock implements WebSocketSink {}

void main() {
  test('disconnect closes a channel that is still connecting', () async {
    final ready = Completer<void>();
    final channel = _MockWebSocketChannel();
    final sink = _MockWebSocketSink();
    when(() => channel.ready).thenAnswer((_) => ready.future);
    when(() => channel.sink).thenReturn(sink);
    when(sink.close).thenAnswer((_) async {});

    final service = EmbyWebSocketService(
      serverUrl: 'http://example.test',
      accessToken: 'token',
      connectionTimeout: const Duration(minutes: 1),
      channelFactory: (_) => channel,
    );

    final connect = service.connect();
    await Future<void>.delayed(Duration.zero);
    await service.disconnect();
    ready.complete();
    await connect;

    verify(sink.close).called(2);
    expect(service.isConnected, isFalse);
    service.dispose();
  });

  test('connection timeout closes the candidate channel', () async {
    final channel = _MockWebSocketChannel();
    final sink = _MockWebSocketSink();
    when(() => channel.ready).thenAnswer((_) => Completer<void>().future);
    when(() => channel.sink).thenReturn(sink);
    when(sink.close).thenAnswer((_) async {});

    final service = EmbyWebSocketService(
      serverUrl: 'http://example.test',
      accessToken: 'token',
      connectionTimeout: const Duration(milliseconds: 1),
      channelFactory: (_) => channel,
    );

    await service.connect();

    verify(sink.close).called(1);
    expect(service.isConnected, isFalse);
    await service.disconnect();
    service.dispose();
  });
}
