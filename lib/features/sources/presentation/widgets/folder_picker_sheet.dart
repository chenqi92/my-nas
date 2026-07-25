import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

class FolderPickerSheet extends StatefulWidget {
  const FolderPickerSheet({
    required this.sources,
    required this.connections,
    required this.onSelect,
    super.key,
  });

  final List<SourceEntity> sources;
  final Map<String, SourceConnection> connections;
  final void Function(String sourceId, String path, String? name) onSelect;

  @override
  State<FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends State<FolderPickerSheet> {
  SourceEntity? _selectedSource;
  String _currentPath = '/';
  List<FileItem> _items = [];
  bool _isLoading = false;
  String? _errorMessage;
  final List<String> _pathHistory = ['/'];

  @override
  void initState() {
    super.initState();
    if (widget.sources.isNotEmpty) {
      _selectedSource = widget.sources.first;
      _loadDirectory();
    }
  }

  NasFileSystem? get _fileSystem {
    if (_selectedSource == null) return null;
    return widget.connections[_selectedSource!.id]?.adapter.fileSystem;
  }

  Future<void> _loadDirectory() async {
    final fs = _fileSystem;
    if (fs == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await fs.listDirectory(_currentPath);
      setState(() {
        _items = items.where((f) => f.isDirectory).toList();
        _items.sort((a, b) => a.name.compareTo(b.name));
      });
    } on Exception catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _navigateTo(String path) {
    _pathHistory.add(path);
    setState(() => _currentPath = path);
    _loadDirectory();
  }

  void _navigateBack() {
    if (_pathHistory.length > 1) {
      _pathHistory.removeLast();
      setState(() => _currentPath = _pathHistory.last);
      _loadDirectory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // 拖动条
            const SheetDragHandle(bottomPadding: 0),

            // 标题栏
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    context.l10n.folderPickerSelectTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),

            // 源选择器
            if (widget.sources.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<SourceEntity>(
                  key: ValueKey(_selectedSource?.id),
                  initialValue: _selectedSource,
                  decoration: InputDecoration(
                    labelText: context.l10n.folderPickerSelectSource,
                    prefixIcon: const Icon(Icons.storage),
                  ),
                  items: widget.sources
                      .map(
                        (source) => DropdownMenuItem(
                          value: source,
                          child: Text(source.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (source) {
                    setState(() {
                      _selectedSource = source;
                      _currentPath = '/';
                      _pathHistory
                        ..clear()
                        ..add('/');
                    });
                    _loadDirectory();
                  },
                ),
              ),

            const SizedBox(height: 8),

            // 路径导航
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _pathHistory.length > 1 ? _navigateBack : null,
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: context.l10n.folderPickerBackToParent,
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _currentPath,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {
                      widget.onSelect(
                        _selectedSource!.id,
                        _currentPath,
                        _currentPath.split('/').last,
                      );
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: Text(context.l10n.folderPickerSelect),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // 目录列表
            Expanded(child: _buildContent(scrollController)),

            // 底部安全区域
            SizedBox(height: bottomPadding > 0 ? bottomPadding : 16),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ScrollController scrollController) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_errorMessage!),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadDirectory,
              child: Text(context.l10n.folderPickerRetry),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_off_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.folderPickerEmptyDirectory,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return ListTile(
          leading: const Icon(Icons.folder_rounded),
          title: Text(item.name),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _navigateTo(item.path),
        );
      },
    );
  }
}
