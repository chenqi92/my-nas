import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

/// 动画类型枚举
enum LottieAnimationType {
  /// 书籍翻页动画（阅读模块）
  book('assets/animations/book_loading.json'),

  /// 音乐波形动画（音乐模块）
  music('assets/animations/music_loading.json'),

  /// 视频播放动画（视频模块）
  video('assets/animations/video_loading.json'),

  /// 通用圆点动画（其他场景）
  dots('assets/animations/loading_dots.json');

  const LottieAnimationType(this.assetPath);
  final String assetPath;
}

/// Lottie 加载动画组件
///
/// 用于替代 CircularProgressIndicator，提供更美观的加载效果。
/// 支持不同模块使用不同的主题动画。
class LottieLoading extends StatelessWidget {
  const LottieLoading({
    super.key,
    this.type = LottieAnimationType.dots,
    this.message,
    this.size = 100,
    this.showMessage = true,
  });

  /// 便捷构造函数：书籍加载
  const LottieLoading.book({
    super.key,
    this.message,
    this.size = 100,
    this.showMessage = true,
  }) : type = LottieAnimationType.book;

  /// 便捷构造函数：音乐加载
  const LottieLoading.music({
    super.key,
    this.message,
    this.size = 100,
    this.showMessage = true,
  }) : type = LottieAnimationType.music;

  /// 便捷构造函数：视频加载
  const LottieLoading.video({
    super.key,
    this.message,
    this.size = 100,
    this.showMessage = true,
  }) : type = LottieAnimationType.video;

  /// 便捷构造函数：通用加载（圆点）
  const LottieLoading.dots({
    super.key,
    this.message,
    this.size = 80,
    this.showMessage = true,
  }) : type = LottieAnimationType.dots;

  /// 动画类型
  final LottieAnimationType type;

  /// 加载提示文本
  final String? message;

  /// 动画尺寸
  final double size;

  /// 是否显示消息文本
  final bool showMessage;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: Lottie.asset(
              type.assetPath,
              fit: BoxFit.contain,
              repeat: true,
              // 如果加载失败，显示一个简单的备用动画
              errorBuilder: (context, error, stackTrace) => _buildFallback(isDark),
            ),
          ),
          if (showMessage && message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : context.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  /// 备用加载动画（当Lottie加载失败时使用）
  Widget _buildFallback(bool isDark) => Center(
      child: SizedBox(
        width: size * 0.5,
        height: size * 0.5,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: isDark ? Colors.white70 : AppColors.primary,
        ),
      ),
    );
}

/// 迷你 Lottie 加载动画（用于小尺寸场景，如封面占位）
class MiniLottieLoading extends StatelessWidget {
  const MiniLottieLoading({
    super.key,
    this.type = LottieAnimationType.dots,
    this.size = 40,
  });

  final LottieAnimationType type;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
      width: size,
      height: size,
      child: Lottie.asset(
        type.assetPath,
        fit: BoxFit.contain,
        repeat: true,
        errorBuilder: (context, error, stackTrace) => Icon(
          _getIconForType(type),
          size: size * 0.6,
          color: Colors.grey.withValues(alpha: 0.5),
        ),
      ),
    );

  IconData _getIconForType(LottieAnimationType type) => switch (type) {
      LottieAnimationType.book => Icons.auto_stories_rounded,
      LottieAnimationType.music => Icons.music_note_rounded,
      LottieAnimationType.video => Icons.play_circle_rounded,
      LottieAnimationType.dots => Icons.more_horiz_rounded,
    };
}
