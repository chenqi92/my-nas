import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/platform_capabilities.dart';
import 'package:my_nas/shared/widgets/app_bottom_sheet.dart';

/// 上下文菜单项
class ContextMenuItem<T> {
  const ContextMenuItem({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.isDestructive = false,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final T? value;
  final VoidCallback? onTap;
  final bool isDestructive;
  final Color? iconColor;
}

/// 上下文菜单区域
///
/// 自动根据平台适配触发方式：
/// - 移动端：长按触发底部弹窗菜单
/// - 桌面端：右键触发弹出菜单
class ContextMenuRegion<T> extends StatelessWidget {
  const ContextMenuRegion({
    required this.child,
    required this.menuItems,
    super.key,
    this.onSelected,
    this.title,
    this.enabled = true,
  });

  /// 子组件
  final Widget child;

  /// 菜单项列表
  final List<ContextMenuItem<T>> menuItems;

  /// 选中菜单项时的回调
  final ValueChanged<T>? onSelected;

  /// 菜单标题（仅用于移动端底部弹窗）
  final String? title;

  /// 是否启用上下文菜单
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled || menuItems.isEmpty) return child;

    return PlatformCapabilities.isDesktop
        ? _buildDesktopMenu(context)
        : _buildMobileMenu(context);
  }

  /// 构建桌面端菜单（右键触发）
  Widget _buildDesktopMenu(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showDesktopMenu(context, details.globalPosition, isDark);
      },
      child: child,
    );
  }

  /// 构建移动端菜单（长按触发）
  Widget _buildMobileMenu(BuildContext context) => GestureDetector(
      onLongPress: () => _showMobileMenu(context),
      child: child,
    );

  /// 显示桌面端弹出菜单
  Future<void> _showDesktopMenu(
    BuildContext context,
    Offset position,
    bool isDark,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final result = await showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: isDark ? AppColors.darkSurface : null,
      items: menuItems.map((item) => _buildPopupMenuItem(item, isDark)).toList(),
    );

    if (result != null) {
      final selectedItem = menuItems.firstWhere(
        (item) => item.value == result,
        orElse: () => menuItems.first,
      );
      selectedItem.onTap?.call();
      onSelected?.call(result);
    }
  }

  /// 构建 PopupMenuItem
  PopupMenuItem<T> _buildPopupMenuItem(ContextMenuItem<T> item, bool isDark) {
    final effectiveColor = item.isDestructive
        ? AppColors.error
        : (item.iconColor ??
            (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface));

    return PopupMenuItem<T>(
      value: item.value,
      child: Row(
        children: [
          Icon(
            item.icon,
            size: 20,
            color: effectiveColor,
          ),
          const SizedBox(width: 12),
          Text(
            item.label,
            style: TextStyle(
              color: item.isDestructive ? AppColors.error : null,
            ),
          ),
        ],
      ),
    );
  }

  /// 显示移动端底部弹窗菜单
  Future<void> _showMobileMenu(BuildContext context) async {
    final result = await showOptionsBottomSheet<T>(
      context: context,
      title: title,
      options: menuItems
          .map(
            (item) => OptionItem<T>(
              icon: item.icon,
              title: item.label,
              value: item.value,
              onTap: item.onTap,
              isDestructive: item.isDestructive,
              iconColor: item.iconColor,
            ),
          )
          .toList(),
    );

    if (result != null) {
      final selectedItem = menuItems.firstWhere(
        (item) => item.value == result,
        orElse: () => menuItems.first,
      );
      selectedItem.onTap?.call();
      onSelected?.call(result);
    }
  }
}

/// 媒体文件操作类型
enum MediaFileAction {
  /// 从媒体库移除（只删除缓存和数据库记录）
  removeFromLibrary,

  /// 从源删除（同时删除源文件）
  deleteFromSource,

  /// 添加到收藏
  addToFavorites,

  /// 从收藏移除
  removeFromFavorites,

  /// 分享
  share,

  /// 查看详情
  viewDetails,

  /// 下载
  download,
}

/// 显示媒体文件上下文菜单的便捷方法
///
/// 用于视频、音乐、照片、图书、漫画等媒体文件的上下文菜单
Future<MediaFileAction?> showMediaFileContextMenu({
  required BuildContext context,
  required String fileName,
  bool showRemoveFromLibrary = true,
  bool showDeleteFromSource = true,
  bool showAddToFavorites = false,
  bool isFavorite = false,
  bool showShare = false,
  bool showDownload = false,
  bool showViewDetails = false,
  List<ContextMenuItem<MediaFileAction>>? additionalItems,
}) async {
  final items = <ContextMenuItem<MediaFileAction>>[];

  if (showViewDetails) {
    items.add(
      ContextMenuItem(
        icon: Icons.info_outline_rounded,
        label: context.l10n.mediaFileContextMenuViewDetails,
        value: MediaFileAction.viewDetails,
      ),
    );
  }

  if (showDownload) {
    items.add(
      ContextMenuItem(
        icon: Icons.download_rounded,
        label: context.l10n.mediaFileContextMenuDownload,
        value: MediaFileAction.download,
      ),
    );
  }

  if (showShare) {
    items.add(
      ContextMenuItem(
        icon: Icons.share_rounded,
        label: context.l10n.mediaFileContextMenuShare,
        value: MediaFileAction.share,
      ),
    );
  }

  if (showAddToFavorites) {
    items.add(
      ContextMenuItem(
        icon: isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        label: isFavorite ? context.l10n.mediaFileContextMenuRemoveFromFavorites : context.l10n.mediaFileContextMenuAddToFavorites,
        value: isFavorite
            ? MediaFileAction.removeFromFavorites
            : MediaFileAction.addToFavorites,
        iconColor: isFavorite ? AppColors.error : null,
      ),
    );
  }

  if (additionalItems != null) {
    items.addAll(additionalItems);
  }

  if (showRemoveFromLibrary) {
    items.add(
      ContextMenuItem(
        icon: Icons.visibility_off_rounded,
        label: context.l10n.mediaFileContextMenuRemoveFromLibrary,
        value: MediaFileAction.removeFromLibrary,
      ),
    );
  }

  if (showDeleteFromSource) {
    items.add(
      ContextMenuItem(
        icon: Icons.delete_forever_rounded,
        label: context.l10n.mediaFileContextMenuDeleteSourceFile,
        value: MediaFileAction.deleteFromSource,
        isDestructive: true,
      ),
    );
  }

  if (PlatformCapabilities.isDesktop) {
    // 桌面端直接返回选中的值（菜单已在调用前显示）
    return _showDesktopContextMenu<MediaFileAction>(
      context: context,
      items: items,
    );
  } else {
    // 移动端显示底部弹窗
    return showOptionsBottomSheet<MediaFileAction>(
      context: context,
      title: fileName,
      options: items
          .map(
            (item) => OptionItem<MediaFileAction>(
              icon: item.icon,
              title: item.label,
              value: item.value,
              isDestructive: item.isDestructive,
              iconColor: item.iconColor,
            ),
          )
          .toList(),
    );
  }
}

/// 显示桌面端上下文菜单
Future<T?> _showDesktopContextMenu<T>({
  required BuildContext context,
  required List<ContextMenuItem<T>> items,
}) async {
  final box = context.findRenderObject()! as RenderBox;
  final position = box.localToGlobal(
    Offset(box.size.width / 2, box.size.height / 2),
  );

  final isDark = Theme.of(context).brightness == Brightness.dark;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return null;

  return showMenu<T>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      overlay.size.width - position.dx,
      overlay.size.height - position.dy,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    color: isDark ? AppColors.darkSurface : null,
    items: items
        .map(
          (item) => PopupMenuItem<T>(
            value: item.value,
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 20,
                  color: item.isDestructive
                      ? AppColors.error
                      : (item.iconColor ??
                          (isDark
                              ? AppColors.darkOnSurface
                              : AppColors.lightOnSurface)),
                ),
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: TextStyle(
                    color: item.isDestructive ? AppColors.error : null,
                  ),
                ),
              ],
            ),
          ),
        )
        .toList(),
  );
}

/// 显示删除确认对话框
///
/// [title] 对话框标题
/// [content] 对话框内容
/// [confirmText] 确认按钮文字
/// [isDestructive] 是否为危险操作（影响确认按钮颜色）
Future<bool> showDeleteConfirmDialog({
  required BuildContext context,
  required String title,
  required String content,
  String confirmText = '',
  bool isDestructive = true,
}) async {
  final resolvedConfirmText = confirmText.isEmpty ? context.l10n.commonDelete : confirmText;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;

      return AlertDialog(
        title: Text(title),
        content: Text(content),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: isDark ? AppColors.darkSurface : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              context.l10n.commonCancel,
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : null,
              ),
            ),
          ),
          FilledButton(
            style: isDestructive
                ? FilledButton.styleFrom(backgroundColor: AppColors.error)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(resolvedConfirmText),
          ),
        ],
      );
    },
  );

  return result ?? false;
}
