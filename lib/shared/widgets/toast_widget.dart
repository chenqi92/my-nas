import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/services/toast_service.dart';

/// 单个 Toast 消息组件
class ToastWidget extends StatelessWidget {
  const ToastWidget({
    required this.message,
    required this.onDismiss,
    this.position = ToastPosition.bottom,
    super.key,
  });

  /// Toast 消息数据
  final ToastMessage message;

  /// 关闭回调
  final VoidCallback onDismiss;

  /// 显示位置（影响样式）
  final ToastPosition position;

  /// 获取消息类型对应的图标
  IconData _getIcon() {
    switch (message.type) {
      case ToastType.success:
        return Icons.check_circle_rounded;
      case ToastType.info:
        return Icons.info_rounded;
      case ToastType.warning:
        return Icons.warning_rounded;
      case ToastType.error:
        return Icons.error_rounded;
    }
  }

  /// 获取消息类型对应的颜色
  Color _getColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (message.type) {
      case ToastType.success:
        return isDark ? AppColors.successLight : AppColors.success;
      case ToastType.info:
        return isDark ? AppColors.infoLight : AppColors.info;
      case ToastType.warning:
        return isDark ? AppColors.warningLight : AppColors.warning;
      case ToastType.error:
        return isDark ? AppColors.errorLight : AppColors.error;
    }
  }

  /// 获取背景颜色
  Color _getBackgroundColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = _getColor(context);

    if (isDark) {
      return baseColor.withValues(alpha: 0.15);
    } else {
      return baseColor.withValues(alpha: 0.1);
    }
  }

  /// 获取边框颜色
  Color _getBorderColor(BuildContext context) => _getColor(context).withValues(alpha: 0.3);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = _getColor(context);

    // 根据位置决定滑动方向
    final dismissDirection = switch (position) {
      ToastPosition.top => DismissDirection.up,
      ToastPosition.bottom => DismissDirection.down,
      ToastPosition.bottomRight => DismissDirection.horizontal,
    };

    return Dismissible(
      key: ValueKey(message.id),
      direction: message.dismissible ? dismissDirection : DismissDirection.none,
      onDismissed: (_) => onDismiss(),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: _getBackgroundColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _getBorderColor(context),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // 图标
                Icon(
                  _getIcon(),
                  color: color,
                  size: 22,
                ),
                const SizedBox(width: 12),

                // 消息内容
                Expanded(
                  child: Text(
                    message.message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // 操作按钮
                if (message.action != null && message.actionLabel != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      message.action?.call();
                      onDismiss();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: color,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      message.actionLabel!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],

                // 关闭按钮
                if (message.dismissible) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onDismiss,
                    child: Icon(
                      Icons.close_rounded,
                      color: isDark
                          ? Colors.white54
                          : Colors.black45,
                      size: 18,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Toast 动画包装器
class AnimatedToastWidget extends StatefulWidget {
  const AnimatedToastWidget({
    required this.message,
    required this.onDismiss,
    required this.position,
    super.key,
  });

  final ToastMessage message;
  final VoidCallback onDismiss;
  final ToastPosition position;

  @override
  State<AnimatedToastWidget> createState() => _AnimatedToastWidgetState();
}

class _AnimatedToastWidgetState extends State<AnimatedToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    // 根据位置决定滑动方向
    final slideBegin = switch (widget.position) {
      ToastPosition.top => const Offset(0, -1),
      ToastPosition.bottom => const Offset(0, 1),
      ToastPosition.bottomRight => const Offset(1, 0),
    };

    _slideAnimation = Tween<Offset>(
      begin: slideBegin,
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: ToastWidget(
          message: widget.message,
          onDismiss: widget.onDismiss,
          position: widget.position,
        ),
      ),
    );
}
