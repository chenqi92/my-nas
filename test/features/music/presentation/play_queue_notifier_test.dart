import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';

/// localhost fixture：播放队列增删/下一首插入/重排，支撑播放恢复相关队列行为。
/// ≠真实 NAS。
void main() {
  MusicItem track(String id) => MusicItem(
        id: id,
        name: '$id.mp3',
        path: '/fixture/$id.mp3',
        url: 'file:///fixture/$id.mp3',
        title: id,
      );

  group('PlayQueueNotifier', () {
    test('setQueue / clear', () {
      final q = PlayQueueNotifier()..setQueue([track('a'), track('b')]);
      expect(q.state.map((e) => e.id), ['a', 'b']);
      q.clear();
      expect(q.state, isEmpty);
    });

    test('addToQueue 追加到末尾', () {
      final q = PlayQueueNotifier()
        ..setQueue([track('a')])
        ..addToQueue(track('b'));
      expect(q.state.map((e) => e.id), ['a', 'b']);
    });

    test('addNext 在当前曲后插入（play_next）', () {
      final q = PlayQueueNotifier()
        ..setQueue([track('a'), track('c')])
        ..addNext(track('b'), 0);
      expect(q.state.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('addNext 空队列时直接设为唯一曲目', () {
      final q = PlayQueueNotifier()..addNext(track('solo'), 0);
      expect(q.state.map((e) => e.id), ['solo']);
    });

    test('removeFromQueue 忽略越界，合法索引删除', () {
      final q = PlayQueueNotifier()..setQueue([track('a'), track('b'), track('c')]);
      q.removeFromQueue(99);
      expect(q.state.length, 3);
      q.removeFromQueue(1);
      expect(q.state.map((e) => e.id), ['a', 'c']);
    });

    test('reorder 交换位置', () {
      final q = PlayQueueNotifier()
        ..setQueue([track('a'), track('b'), track('c')])
        ..reorder(0, 2);
      expect(q.state.map((e) => e.id), ['b', 'c', 'a']);
    });

    test('MusicItem.lastPosition 保留恢复位点', () {
      final item = track('x').copyWith(
        lastPosition: const Duration(seconds: 42),
      );
      expect(item.lastPosition, const Duration(seconds: 42));
    });
  });
}
