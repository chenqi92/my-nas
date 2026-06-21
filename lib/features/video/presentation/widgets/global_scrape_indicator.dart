import 'dart:async';

import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/data/services/video_scanner_service.dart';

/// 全局刮削状态指示器
///
/// 用于在应用任何页面显示刮削进度，即使用户离开了媒体库页面
class GlobalScrapeIndicator extends StatefulWidget {
  const GlobalScrapeIndicator({super.key});

  @override
  State<GlobalScrapeIndicator> createState() => _GlobalScrapeIndicatorState();
}

class _GlobalScrapeIndicatorState extends State<GlobalScrapeIndicator>
    with SingleTickerProviderStateMixin {
  // 进度更新节流：最小间隔 200ms
  static const _throttleMs = 200;
  DateTime _lastUpdate = DateTime.now();

  StreamSubscription<ScrapeStats>? _subscription;
  ScrapeStats? _stats;
  bool _isVisible = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    _subscription = VideoScannerService().scrapeStatsStream.listen((stats) {
      if (!mounted) return;

      // 完成状态强制更新，进行中状态节流
      final isTerminal = stats.isAllDone;
      final now = DateTime.now();
      if (!isTerminal && now.difference(_lastUpdate).inMilliseconds < _throttleMs) {
        return;
      }
      _lastUpdate = now;

      setState(() {
        _stats = stats;
        final shouldShow = !stats.isAllDone && stats.total > 0;

        if (shouldShow && !_isVisible) {
          _isVisible = true;
          _animationController.forward();
        } else if (!shouldShow && _isVisible) {
          _animationController.reverse().then((_) {
            if (mounted) {
              setState(() => _isVisible = false);
            }
          });
        }
      });
    });

    // 初始检查刮削状态
    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    if (VideoScannerService().isScraping) {
      final stats = await VideoScannerService().getScrapeStats();
      if (mounted && !stats.isAllDone) {
        setState(() {
          _stats = stats;
          _isVisible = true;
          _animationController.forward();
        });
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isVisible || _stats == null) {
      return const SizedBox.shrink();
    }

    final stats = _stats!;
    final progress = stats.progress;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '正在刮削视频元数据...',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                Text(
                  '${stats.processed}/${stats.total}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                minHeight: 4,
              ),
            ),
            if (stats.failed > 0) ...[
              const SizedBox(height: 4),
              Text(
                context.l10n.videoScrapeIndicatorStats(stats.completed, stats.failed),
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 紧凑版刮削指示器（用于 AppBar）
class CompactScrapeIndicator extends StatefulWidget {
  const CompactScrapeIndicator({super.key});

  @override
  State<CompactScrapeIndicator> createState() => _CompactScrapeIndicatorState();
}

class _CompactScrapeIndicatorState extends State<CompactScrapeIndicator> {
  // 进度更新节流：最小间隔 200ms
  static const _throttleMs = 200;
  DateTime _lastUpdate = DateTime.now();

  StreamSubscription<ScrapeStats>? _subscription;
  ScrapeStats? _stats;
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();

    _subscription = VideoScannerService().scrapeStatsStream.listen((stats) {
      if (!mounted) return;

      // 完成状态强制更新，进行中状态节流
      final isTerminal = stats.isAllDone;
      final now = DateTime.now();
      if (!isTerminal && now.difference(_lastUpdate).inMilliseconds < _throttleMs) {
        return;
      }
      _lastUpdate = now;

      setState(() => _stats = stats);
    });

    _checkInitialState();
  }

  Future<void> _checkInitialState() async {
    if (VideoScannerService().isScraping) {
      final stats = await VideoScannerService().getScrapeStats();
      if (mounted) {
        setState(() => _stats = stats);
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _toggleDetails() => setState(() => _showDetails = !_showDetails);

  @override
  Widget build(BuildContext context) {
    if (_stats == null || _stats!.isAllDone) {
      return const SizedBox.shrink();
    }

    final stats = _stats!;
    final progress = stats.progress;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: _toggleDetails,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: _showDetails
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
            : EdgeInsets.zero,
        decoration: _showDetails
            ? BoxDecoration(
                color: isDark
                    ? Colors.grey[800]!.withValues(alpha: 0.9)
                    : Colors.grey[200]!.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
              )
            : null,
        child: _showDetails
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 2.5,
                      backgroundColor: Colors.grey.withValues(alpha: 0.3),
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${stats.processed}/${stats.total}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              )
            : SizedBox(
                width: 32,
                height: 32,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 2.5,
                        backgroundColor: Colors.grey.withValues(alpha: 0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                    Text(
                      '${(progress * 100).toInt()}',
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
