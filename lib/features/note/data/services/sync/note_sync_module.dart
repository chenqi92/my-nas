import 'package:my_nas/core/sync/syncable_module.dart';
import 'package:my_nas/features/note/data/services/note_state_service.dart';

/// 同步笔记交互状态：每条笔记的最后打开时间、阅读位置、书签。
///
/// 笔记内容本身保存在 NAS 上（文件系统），不会被上传到云同步通道。
/// 这里只同步元数据 + 书签 + 阅读位置。
///
/// 合并策略：
/// - 标量字段（modifiedAt、scrollOffset）：取 updatedAt 较新的一方；
///   远端缺失时回落到本地，反之亦然
/// - lastOpenedAt：取两端较新者（不需要 updatedAt 比较，单调时间）
/// - bookmarks：按 (line, createdAt) 指纹做并集
class NoteSyncModule implements SyncableModule {
  NoteSyncModule();

  final NoteStateService _service = NoteStateService();

  @override
  String get key => 'note_states';

  @override
  String get displayName => '笔记 - 阅读状态与书签';

  @override
  Future<DateTime?> getLocalUpdatedAt() async {
    await _service.init();
    final list = _service.getAllStates();
    DateTime? maxAt;
    for (final s in list) {
      if (maxAt == null || s.updatedAt.isAfter(maxAt)) maxAt = s.updatedAt;
    }
    return maxAt;
  }

  @override
  Future<Map<String, dynamic>> exportData() async {
    await _service.init();
    final list = _service.getAllStates();
    return {
      'version': 1,
      'states': list.map((s) => s.toMap()).toList(),
    };
  }

  @override
  Future<void> importData(Map<String, dynamic> data) async {
    await _service.init();
    final list = (data['states'] as List?) ?? const [];
    for (final raw in list) {
      if (raw is! Map) continue;
      try {
        final remote = NoteState.fromMap(raw);
        final local = _service.getState(remote.notePath);
        if (local == null) {
          await _service.saveState(remote);
          continue;
        }
        await _service.saveState(_merge(local, remote));
      } on Exception catch (_) {
        continue;
      }
    }
  }

  NoteState _merge(NoteState local, NoteState remote) {
    final dedup = <String, NoteBookmark>{};
    for (final b in local.bookmarks) {
      dedup[b.fingerprint] = b;
    }
    for (final b in remote.bookmarks) {
      dedup[b.fingerprint] = b;
    }
    final bookmarks = dedup.values.toList()
      ..sort((a, b) => a.line.compareTo(b.line));

    final useRemote = remote.updatedAt.isAfter(local.updatedAt);
    final winner = useRemote ? remote : local;
    final loser = useRemote ? local : remote;

    final lastOpenedAt = remote.lastOpenedAt.isAfter(local.lastOpenedAt)
        ? remote.lastOpenedAt
        : local.lastOpenedAt;

    return NoteState(
      notePath: winner.notePath,
      modifiedAt: winner.modifiedAt ?? loser.modifiedAt,
      scrollOffset: winner.scrollOffset ?? loser.scrollOffset,
      lastOpenedAt: lastOpenedAt,
      bookmarks: bookmarks,
      updatedAt: winner.updatedAt,
    );
  }
}
