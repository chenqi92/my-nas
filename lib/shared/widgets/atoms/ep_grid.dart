import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';

/// 设计稿 `.ep-grid` / `.ep-cell` 原子：剧集进度方格网格。
///
/// 每集渲染为一个正方形方格，按状态着色：
/// - 缺集（默认）：[DesignTokens.insetBg] 底 + [DesignTokens.text3] 字 + 极细描边
/// - 已有 (`have`)：[DesignTokens.chipBgActive] 底 + [DesignTokens.accentBright]
///   字 + accent .3 描边
/// - 下载中 (`downloading`)：蓝底蓝字（对齐 app.css `.ep-cell.dl`）
///
/// 集号从 1 开始连续编号到 [total]；[have] 指已有集数（前 [have] 集标记为已有）。
/// [downloading] 为正在下载的集号集合（1-based），可选。
class EpisodeGrid extends StatelessWidget {
  const EpisodeGrid({
    required this.total,
    required this.have,
    this.downloading,
    super.key,
  });

  /// 总集数。
  final int total;

  /// 已有集数（前 [have] 集渲染为已有态）。
  final int have;

  /// 正在下载的集号集合（1-based）。为空 / null 时不渲染下载态。
  final Set<int>? downloading;

  /// 方格最小边长（对齐 css `minmax(38px,1fr)`）。
  static const double _minCell = 38;
  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();
    final dl = downloading;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 模拟 css `repeat(auto-fill, minmax(38px, 1fr))`：先求每行最多容纳几格，
        // 再把剩余宽度均分让方格撑满整行。
        var perRow = ((width + _gap) / (_minCell + _gap)).floor();
        if (perRow < 1) perRow = 1;
        if (perRow > total) perRow = total;
        final cell = (width - _gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (var n = 1; n <= total; n++)
              _EpisodeCell(
                number: n,
                size: cell,
                state: (dl != null && dl.contains(n))
                    ? _EpState.downloading
                    : (n <= have ? _EpState.have : _EpState.missing),
              ),
          ],
        );
      },
    );
  }
}

enum _EpState { missing, have, downloading }

class _EpisodeCell extends StatelessWidget {
  const _EpisodeCell({
    required this.number,
    required this.size,
    required this.state,
  });

  final int number;
  final double size;
  final _EpState state;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final (bg, fg, border) = switch (state) {
      _EpState.missing => (t.insetBg, t.text3, t.hairline),
      _EpState.have => (
          t.chipBgActive,
          t.accentBright,
          t.accent.withValues(alpha: 0.3),
        ),
      // app.css `.ep-cell.dl`：rgba(91,146,240,...) 底 / #7db1ff 字 / .4 边
      _EpState.downloading => (
          const Color(0x295B92F0),
          const Color(0xFF7DB1FF),
          const Color(0x665B92F0),
        ),
    };
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: border, width: 0.5),
        ),
        child: Center(
          child: Text(
            '$number',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
