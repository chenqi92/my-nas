import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 树节点类型
enum NoteTreeNodeType { folder, file }

/// 树节点
class NoteTreeNode {
  NoteTreeNode({
    required this.name,
    required this.path,
    required this.type,
    required this.sourceId,
    this.children = const [],
    this.isExpanded = false,
    this.fileItem,
    this.url,
  });

  final String name;
  final String path;
  final NoteTreeNodeType type;
  final String sourceId;
  final List<NoteTreeNode> children;
  bool isExpanded;
  final FileItem? fileItem;
  final String? url;

  /// 是否是任务文件（文件名包含 _task）
  bool get isTaskFile =>
      type == NoteTreeNodeType.file &&
      name.toLowerCase().contains('_task');

  /// 显示名称（去除扩展名）
  String get displayName {
    if (type == NoteTreeNodeType.folder) return name;
    final dotIndex = name.lastIndexOf('.');
    return dotIndex > 0 ? name.substring(0, dotIndex) : name;
  }

  NoteTreeNode copyWith({
    String? name,
    String? path,
    NoteTreeNodeType? type,
    String? sourceId,
    List<NoteTreeNode>? children,
    bool? isExpanded,
    FileItem? fileItem,
    String? url,
  }) => NoteTreeNode(
      name: name ?? this.name,
      path: path ?? this.path,
      type: type ?? this.type,
      sourceId: sourceId ?? this.sourceId,
      children: children ?? this.children,
      isExpanded: isExpanded ?? this.isExpanded,
      fileItem: fileItem ?? this.fileItem,
      url: url ?? this.url,
    );
}

/// 笔记目录树组件
class NoteTreeWidget extends StatelessWidget {
  const NoteTreeWidget({
    required this.nodes,
    required this.selectedPath,
    required this.onNodeSelected,
    required this.onFolderToggle,
    required this.onFolderLoad,
    required this.isDark,
    this.onContextMenu,
    super.key,
  });

  final List<NoteTreeNode> nodes;
  final String? selectedPath;
  final void Function(NoteTreeNode node) onNodeSelected;
  final void Function(NoteTreeNode node) onFolderToggle;
  final void Function(NoteTreeNode node) onFolderLoad;
  final void Function(NoteTreeNode node)? onContextMenu;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return Center(
        child: Text(
          context.l10n.noteTreeEmptyMessage,
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey,
          ),
        ),
      );
    }

    return ListView(
      // 使用动态底部 padding 支持悬浮导航栏
      padding: EdgeInsets.only(top: 8, bottom: context.scrollBottomPadding),
      children: nodes.map((node) => _buildNode(context, node, 0)).toList(),
    );
  }

  Widget _buildNode(BuildContext context, NoteTreeNode node, int depth) {
    final isSelected = node.path == selectedPath;
    final isFolder = node.type == NoteTreeNodeType.folder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NoteTreeItem(
          node: node,
          depth: depth,
          isSelected: isSelected,
          isDark: isDark,
          onTap: () {
            if (isFolder) {
              // 如果是文件夹，切换展开状态
              onFolderToggle(node);
              // 如果之前没有加载过子节点，触发加载
              if (node.children.isEmpty && !node.isExpanded) {
                onFolderLoad(node);
              }
            } else {
              // 如果是文件，选中它
              onNodeSelected(node);
            }
          },
          onContextMenu: isFolder ? null : () => onContextMenu?.call(node),
        ),
        // 展开的子节点
        if (isFolder && node.isExpanded)
          ...node.children.map((child) => _buildNode(context, child, depth + 1)),
      ],
    );
  }
}

class _NoteTreeItem extends StatelessWidget {
  const _NoteTreeItem({
    required this.node,
    required this.depth,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
    this.onContextMenu,
  });

  final NoteTreeNode node;
  final int depth;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final isFolder = node.type == NoteTreeNodeType.folder;

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onLongPress: onContextMenu,
        onSecondaryTap: onContextMenu,
        child: InkWell(
          onTap: onTap,
          child: Container(
          height: 36,
          padding: EdgeInsets.only(left: 12 + depth * 16.0, right: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : AppColors.primary.withValues(alpha: 0.1))
                : null,
            border: isSelected
                ? Border(
                    left: BorderSide(
                      color: AppColors.primary,
                      width: 3,
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              // 展开/收起图标（仅文件夹）
              if (isFolder)
                Icon(
                  node.isExpanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  size: 18,
                  color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey,
                )
              else
                const SizedBox(width: 18),
              const SizedBox(width: 4),
              // 图标
              Icon(
                _getIcon(),
                size: 18,
                color: _getIconColor(),
              ),
              const SizedBox(width: 8),
              // 名称
              Expanded(
                child: Text(
                  node.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? AppColors.darkOnSurface : null),
                  ),
                ),
              ),
              // 任务文件标记
              if (node.isTaskFile)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    context.l10n.noteTreeTaskLabel,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
                ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  IconData _getIcon() {
    if (node.type == NoteTreeNodeType.folder) {
      return node.isExpanded ? Icons.folder_open_rounded : Icons.folder_rounded;
    }
    // 笔记文件图标
    if (node.isTaskFile) {
      return Icons.checklist_rounded;
    }
    return Icons.article_outlined;
  }

  Color _getIconColor() {
    if (node.type == NoteTreeNodeType.folder) {
      return Colors.amber.shade700;
    }
    if (node.isTaskFile) {
      return AppColors.warning;
    }
    return AppColors.primary;
  }
}
