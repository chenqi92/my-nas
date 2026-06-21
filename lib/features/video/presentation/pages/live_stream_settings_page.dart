import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/domain/entities/live_stream_models.dart';
import 'package:my_nas/features/video/presentation/providers/live_stream_provider.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 直播源设置页面
class LiveStreamSettingsPage extends ConsumerStatefulWidget {
  const LiveStreamSettingsPage({super.key});

  @override
  ConsumerState<LiveStreamSettingsPage> createState() =>
      _LiveStreamSettingsPageState();
}

class _LiveStreamSettingsPageState
    extends ConsumerState<LiveStreamSettingsPage>
    with ConsumerTabBarVisibilityMixin {
  bool _isReorderMode = false;

  @override
  void initState() {
    super.initState();
    hideTabBar();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(liveStreamSettingsProvider);
    final sources = settings.sortedSources;

    return Scaffold(
      appBar: AppBar(
        leading: const RoundedBackButton(),
        title: Text(context.l10n.liveStreamSourceManagementTitle),
        actions: [
          // 排序模式切换按钮
          if (sources.isNotEmpty)
            IconButton(
              icon: Icon(_isReorderMode ? Icons.done_rounded : Icons.reorder),
              onPressed: () {
                setState(() {
                  _isReorderMode = !_isReorderMode;
                });
              },
              tooltip: _isReorderMode ? context.l10n.liveStreamSortingFinish : context.l10n.liveStreamAdjustOrder,
            ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showAddSourceDialog(context),
            tooltip: context.l10n.liveStreamAddSource,
          ),
        ],
      ),
      body: sources.isEmpty
          ? _buildEmptyState(context)
          : _isReorderMode
              ? _buildReorderableList(sources, isDark)
              : _buildNormalList(sources, isDark),
    );
  }

  /// 构建普通列表（非排序模式）
  Widget _buildNormalList(List<LiveStreamSource> sources, bool isDark) =>
      ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sources.length,
        itemBuilder: (context, index) {
          final source = sources[index];
          return _SourceTile(
            key: ValueKey(source.id),
            source: source,
            index: index,
            isDark: isDark,
            isReorderMode: false,
            onToggle: (enabled) {
              ref
                  .read(liveStreamSettingsProvider.notifier)
                  .toggleEnabled(source.id, enabled: enabled);
            },
            onEdit: () => _showEditSourceDialog(context, source),
            onRefresh: () => _refreshSource(source.id),
            onDelete: () => _deleteSource(source),
          );
        },
      );

  /// 构建可排序列表（排序模式）
  Widget _buildReorderableList(List<LiveStreamSource> sources, bool isDark) =>
      ReorderableListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sources.length,
        onReorder: (oldIndex, newIndex) {
          ref
              .read(liveStreamSettingsProvider.notifier)
              .reorder(oldIndex, newIndex);
        },
        proxyDecorator: (child, index, animation) => AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final elevation = Tween<double>(begin: 0, end: 8).evaluate(animation);
            return Material(
              elevation: elevation,
              borderRadius: BorderRadius.circular(12),
              child: child,
            );
          },
          child: child,
        ),
        itemBuilder: (context, index) {
          final source = sources[index];
          return _SourceTile(
            key: ValueKey(source.id),
            source: source,
            index: index,
            isDark: isDark,
            isReorderMode: true,
            onToggle: (enabled) {
              ref
                  .read(liveStreamSettingsProvider.notifier)
                  .toggleEnabled(source.id, enabled: enabled);
            },
            onEdit: () => _showEditSourceDialog(context, source),
            onRefresh: () => _refreshSource(source.id),
            onDelete: () => _deleteSource(source),
          );
        },
      );

  Widget _buildEmptyState(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.satellite_alt_rounded,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.liveStreamEmptyTitle,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.liveStreamEmptyHint,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAddSourceDialog(context),
              icon: const Icon(Icons.add_rounded),
              label: Text(context.l10n.liveStreamAddSource),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
            ),
          ],
        ),
      );

  Future<void> _showAddSourceDialog(BuildContext context) async {
    final result = await showDialog<_SourceFormResult>(
      context: context,
      builder: (context) => _AddSourceDialog(
        notifier: ref.read(liveStreamSettingsProvider.notifier),
      ),
    );

    if (result != null && mounted) {
      context.showToast(context.l10n.liveStreamAddedToast(result.name));
    }
  }

  Future<void> _showEditSourceDialog(
    BuildContext context,
    LiveStreamSource source,
  ) async {
    final result = await showDialog<_SourceFormResult>(
      context: context,
      builder: (context) => _EditSourceDialog(
        source: source,
        notifier: ref.read(liveStreamSettingsProvider.notifier),
      ),
    );

    if (result != null && mounted) {
      context.showToast(context.l10n.liveStreamUpdatedToast(result.name));
    }
  }

  Future<void> _refreshSource(String sourceId) async {
    try {
      context.showToast(context.l10n.liveStreamRefreshingToast);
      final source = await ref
          .read(liveStreamSettingsProvider.notifier)
          .refreshSource(sourceId);
      if (mounted) {
        context.showToast(context.l10n.liveStreamRefreshedToast(source.channelCount));
      }
    } catch (e, st) {
      AppError.handleWithUI(context, e, st, context.l10n.liveStreamRefreshFailedError);
    }
  }

  Future<void> _deleteSource(LiveStreamSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.liveStreamDeleteSourceTitle),
        content: Text(context.l10n.liveStreamDeleteSourceConfirmation(source.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref
          .read(liveStreamSettingsProvider.notifier)
          .removeSource(source.id);
      if (mounted) {
        context.showToast(context.l10n.liveStreamDeletedToast(source.name));
      }
    }
  }
}

/// 直播源列表项
class _SourceTile extends StatelessWidget {
  const _SourceTile({
    super.key,
    required this.source,
    required this.index,
    required this.isDark,
    required this.isReorderMode,
    required this.onToggle,
    required this.onEdit,
    required this.onRefresh,
    required this.onDelete,
  });

  final LiveStreamSource source;
  final int index;
  final bool isDark;
  final bool isReorderMode;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: isReorderMode
              ? ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle_rounded),
                )
              : Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: source.isEnabled
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : (isDark ? Colors.grey[800] : Colors.grey[200]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.satellite_alt_rounded,
                    size: 20,
                    color: source.isEnabled
                        ? AppColors.primary
                        : (isDark ? Colors.grey[600] : Colors.grey[400]),
                  ),
                ),
          title: Text(
            source.name,
            style: TextStyle(
              color: source.isEnabled ? null : Colors.grey,
            ),
          ),
          subtitle: Text(
            context.l10n.liveStreamChannelsCount(source.channelCount),
            style: TextStyle(
              color: source.isEnabled ? null : Colors.grey,
            ),
          ),
          trailing: isReorderMode
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: source.isEnabled,
                      onChanged: onToggle,
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: onRefresh,
                      tooltip: context.l10n.liveStreamRefreshChannelsTooltip,
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_rounded),
                      onPressed: onEdit,
                      tooltip: context.l10n.commonEdit,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_rounded),
                      onPressed: onDelete,
                      tooltip: context.l10n.commonDelete,
                      color: Colors.red,
                    ),
                  ],
                ),
        ),
      );
}

/// 表单结果
class _SourceFormResult {
  const _SourceFormResult({required this.name});
  final String name;
}

/// 添加直播源对话框
class _AddSourceDialog extends StatefulWidget {
  const _AddSourceDialog({required this.notifier});

  final LiveStreamSettingsNotifier notifier;

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  List<LiveChannel>? _previewChannels;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: Text(context.l10n.liveStreamAddSource),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.l10n.liveStreamSourceNameLabel,
                  hintText: context.l10n.liveStreamSourceNameHint,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: context.l10n.liveStreamPlaylistUrlLabel,
                  hintText: 'https://example.com/playlist.m3u',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                Center(
                  child: OutlinedButton.icon(
                    onPressed: _previewSource,
                    icon: const Icon(Icons.preview_rounded),
                    label: Text(context.l10n.liveStreamPreviewChannelsButton),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              if (_previewChannels != null) ...[
                const SizedBox(height: 16),
                Text(
                  context.l10n.liveStreamPreviewChannelsTitle(_previewChannels!.length),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceVariant
                        : AppColors.lightSurfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    itemCount: _previewChannels!.length.clamp(0, 20),
                    itemBuilder: (context, index) {
                      final channel = _previewChannels![index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          channel.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(channel.categoryDisplayName),
                      );
                    },
                  ),
                ),
                if (_previewChannels!.length > 20)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      context.l10n.liveStreamMoreChannelsHint(_previewChannels!.length - 20),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: _previewChannels != null && _nameController.text.isNotEmpty
              ? _save
              : null,
          child: Text(context.l10n.commonSave),
        ),
      ],
    );
  }

  Future<void> _previewSource() async {
    if (_urlController.text.isEmpty) {
      setState(() => _error = context.l10n.liveStreamUrlRequiredError);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final channels = await widget.notifier.previewChannels(
        _urlController.text.trim(),
      );
      setState(() {
        _previewChannels = channels;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = '解析失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);

    try {
      // addSource 返回添加后的源（含 id），直接使用它来更新频道
      final source = await widget.notifier.addSource(
        name: _nameController.text.trim(),
        playlistUrl: _urlController.text.trim(),
        autoRefresh: false, // 已经预览过，不需要再获取
      );

      // 手动设置频道（使用返回的源）
      await widget.notifier.updateSource(
        source.copyWith(channels: _previewChannels),
      );

      if (mounted) {
        Navigator.pop(
          context,
          _SourceFormResult(name: _nameController.text.trim()),
        );
      }
    } catch (e) {
      setState(() {
        _error = '保存失败: $e';
        _isLoading = false;
      });
    }
  }
}

/// 编辑直播源对话框
class _EditSourceDialog extends StatefulWidget {
  const _EditSourceDialog({
    required this.source,
    required this.notifier,
  });

  final LiveStreamSource source;
  final LiveStreamSettingsNotifier notifier;

  @override
  State<_EditSourceDialog> createState() => _EditSourceDialogState();
}

class _EditSourceDialogState extends State<_EditSourceDialog> {
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.source.name);
    _urlController = TextEditingController(text: widget.source.playlistUrl);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.l10n.liveStreamAddSource),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.l10n.liveStreamSourceNameLabel,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: context.l10n.liveStreamPlaylistUrlLabel,
                ),
                maxLines: 2,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.commonCancel),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            ElevatedButton(
              onPressed: _save,
              child: Text(context.l10n.commonSave),
            ),
        ],
      );

  Future<void> _save() async {
    if (_nameController.text.isEmpty) {
      setState(() => _error = context.l10n.liveStreamSourceNameRequiredError);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updatedSource = widget.source.copyWith(
        name: _nameController.text.trim(),
        playlistUrl: _urlController.text.trim(),
      );
      await widget.notifier.updateSource(updatedSource);

      if (mounted) {
        Navigator.pop(
          context,
          _SourceFormResult(name: _nameController.text.trim()),
        );
      }
    } catch (e) {
      setState(() {
        _error = '保存失败: $e';
        _isLoading = false;
      });
    }
  }
}
