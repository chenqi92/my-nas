import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';

/// 旋转封面组件 - 播放时唱片旋转动画
class RotatingCover extends StatefulWidget {
  const RotatingCover({
    required this.size,
    required this.isPlaying,
    this.coverData,
    this.coverUrl,
    this.showVinyl = true,
    this.rotationDuration = const Duration(seconds: 20),
    super.key,
  });

  final double size;
  final bool isPlaying;
  final List<int>? coverData;
  final String? coverUrl;
  final bool showVinyl;
  final Duration rotationDuration;

  @override
  State<RotatingCover> createState() => _RotatingCoverState();
}

class _RotatingCoverState extends State<RotatingCover>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: widget.rotationDuration,
    );
    if (widget.isPlaying) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(RotatingCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_rotationController.isAnimating) {
      _rotationController.repeat();
    } else if (!widget.isPlaying && _rotationController.isAnimating) {
      _rotationController.stop();
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _rotationController,
      builder: (context, child) => Transform.rotate(
          angle: _rotationController.value * 2 * math.pi,
          child: child,
        ),
      child: _buildCoverStack(),
    );

  Widget _buildCoverStack() {
    if (!widget.showVinyl) {
      return _buildCoverImage();
    }

    // 唱片效果：黑胶 + 封面
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 黑胶底盘
          _buildVinylDisc(),
          // 中心封面
          SizedBox(
            width: widget.size * 0.55,
            height: widget.size * 0.55,
            child: _buildCoverImage(),
          ),
        ],
      ),
    );
  }

  Widget _buildVinylDisc() => Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.grey[900]!,
            Colors.grey[850]!,
            Colors.grey[800]!,
            Colors.grey[900]!,
          ],
          stops: const [0.0, 0.3, 0.7, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _VinylGroovesPainter(),
      ),
    );

  Widget _buildCoverImage() {
    Widget coverImage;
    final coverData = widget.coverData;
    final coverUrl = widget.coverUrl;

    if (coverData != null && coverData.isNotEmpty) {
      coverImage = Image.memory(
        Uint8List.fromList(coverData),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildDefaultCover(),
      );
    } else if (coverUrl != null && coverUrl.isNotEmpty) {
      if (coverUrl.startsWith('file://')) {
        final filePath = coverUrl.substring(7);
        coverImage = Image.file(
          File(filePath),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildDefaultCover(),
        );
      } else {
        coverImage = Image.network(
          coverUrl,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildDefaultCover(),
        );
      }
    } else {
      coverImage = _buildDefaultCover();
    }

    return ClipOval(
      child: coverImage,
    );
  }

  Widget _buildDefaultCover() => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.secondary,
          ],
        ),
      ),
      child: const Icon(
        Icons.music_note_rounded,
        color: Colors.white,
        size: 32,
      ),
    );
}

/// 黑胶唱片纹路绘制器
class _VinylGroovesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.grey[700]!.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // 绘制唱片纹路
    for (var i = 0; i < 20; i++) {
      final radius = size.width * 0.3 + (size.width * 0.35 * i / 20);
      canvas.drawCircle(center, radius, paint);
    }

    // 中心孔高光
    final centerPaint = Paint()
      ..color = Colors.grey[600]!
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, size.width * 0.03, centerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 呼吸光晕容器 - 播放时有脉冲光晕效果
class GlowingContainer extends StatefulWidget {
  const GlowingContainer({
    required this.child,
    required this.isGlowing,
    this.glowColor,
    this.maxBlurRadius = 30,
    this.minBlurRadius = 15,
    this.maxSpreadRadius = 8,
    this.minSpreadRadius = 2,
    this.duration = const Duration(milliseconds: 2000),
    super.key,
  });

  final Widget child;
  final bool isGlowing;
  final Color? glowColor;
  final double maxBlurRadius;
  final double minBlurRadius;
  final double maxSpreadRadius;
  final double minSpreadRadius;
  final Duration duration;

  @override
  State<GlowingContainer> createState() => _GlowingContainerState();
}

class _GlowingContainerState extends State<GlowingContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );
    if (widget.isGlowing) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(GlowingContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isGlowing && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isGlowing && _pulseController.isAnimating) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isGlowing) {
      return widget.child;
    }

    final glowColor = widget.glowColor ?? AppColors.primary;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final pulseValue = _pulseAnimation.value;
        final blurRadius = widget.minBlurRadius +
            (widget.maxBlurRadius - widget.minBlurRadius) * pulseValue;
        final spreadRadius = widget.minSpreadRadius +
            (widget.maxSpreadRadius - widget.minSpreadRadius) * pulseValue;
        final opacity = 0.3 + 0.3 * pulseValue;

        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: glowColor.withValues(alpha: opacity),
                blurRadius: blurRadius,
                spreadRadius: spreadRadius,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 按压缩放组件 - 点击时有缩放弹性效果
class AnimatedPressable extends StatefulWidget {
  const AnimatedPressable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleDown = 0.95,
    this.duration = const Duration(milliseconds: 100),
    this.curve = Curves.easeOutCubic,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleDown;
  final Duration duration;
  final Curve curve;
  final bool enabled;

  @override
  State<AnimatedPressable> createState() => _AnimatedPressableState();
}

class _AnimatedPressableState extends State<AnimatedPressable>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scaleDown).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: widget.curve,
      ),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (!widget.enabled) return;
    _scaleController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    if (!widget.enabled) return;
    _scaleController.reverse();
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    if (!widget.enabled) return;
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onLongPress: widget.onLongPress,
      onSecondaryTap: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          ),
        child: widget.child,
      ),
    );
}

/// 毛玻璃卡片组件
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 16,
    this.blur = 10,
    this.isDark = false,
    this.onTap,
    super.key,
  });

  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsets padding;
  final double borderRadius;
  final double blur;
  final bool isDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.7),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.8),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.08),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      return AnimatedPressable(
        onTap: onTap,
        child: card,
      );
    }

    return card;
  }
}

/// 渐变胶囊按钮
class GradientChip extends StatelessWidget {
  const GradientChip({
    required this.label,
    required this.onTap,
    this.count,
    this.icon,
    this.gradientColors,
    this.height = 36,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final int? count;
  final IconData? icon;
  final List<Color>? gradientColors;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = gradientColors ?? [AppColors.primary, AppColors.secondary];

    return AnimatedPressable(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          boxShadow: [
            BoxShadow(
              color: colors[0].withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 滚动视差控制器 Mixin
mixin ScrollParallaxMixin<T extends StatefulWidget> on State<T> {
  ScrollController? _scrollController;
  double _scrollOffset = 0;

  ScrollController get scrollController =>
      _scrollController ??= ScrollController()..addListener(_onScroll);

  double get scrollOffset => _scrollOffset;

  /// 计算视差值 (0.0 ~ 1.0)
  double getParallaxProgress({
    double maxScroll = 100,
  }) => (_scrollOffset / maxScroll).clamp(0.0, 1.0);

  /// 根据滚动计算尺寸
  double lerpSize(double start, double end, {double maxScroll = 100}) {
    final progress = getParallaxProgress(maxScroll: maxScroll);
    return start + (end - start) * progress;
  }

  void _onScroll() {
    if (mounted) {
      setState(() {
        _scrollOffset = _scrollController!.offset;
      });
    }
  }

  @override
  void dispose() {
    _scrollController?.dispose();
    super.dispose();
  }
}
