import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:my_nas/core/errors/errors.dart';

/// 基于 shader 的真实卷页翻页效果
///
/// 用 `shaders/page_curl.frag` 做物理卷曲：折线角度随拖拽起点变化、圆柱卷曲
/// 半径、卷曲阴影、纸张背面着色。
///
/// **实现要点**：shader 需要两张纹理（当前页 / 目标页），而 Flutter 的
/// Widget 不能直接喂给 shader。这里让两页各自挂在 [RepaintBoundary] 下，
/// 用 `RenderRepaintBoundary.toImageSync()` 抓快照再交给 shader。
/// 抓拍只在一次翻页开始时做一次，拖拽过程中只更新 uniform，不重复抓拍。
///
/// **限制**：
/// - 仅水平翻页
/// - shader 加载失败时自动降级为透视变换，不影响可用性
class PageCurlView extends StatefulWidget {
  const PageCurlView({
    required this.currentPage,
    required this.nextPage,
    required this.progress,
    required this.direction,
    this.dragStartY = 0.5,
    this.backgroundColor = Colors.white,
    super.key,
  });

  /// 当前页内容（会被卷起）
  final Widget currentPage;

  /// 目标页内容（翻过去后露出）
  final Widget nextPage;

  /// 翻页进度 0.0（未开始）→ 1.0（完成）
  final double progress;

  /// 1.0 = 向左翻（下一页），-1.0 = 向右翻（上一页）
  final double direction;

  /// 拖动起始 Y 比例 0.0（顶）→ 1.0（底），决定折线倾斜角
  final double dragStartY;

  /// 卷曲区域外的填充色
  final Color backgroundColor;

  @override
  State<PageCurlView> createState() => _PageCurlViewState();
}

class _PageCurlViewState extends State<PageCurlView> {
  static ui.FragmentProgram? _cachedProgram;
  static bool _loadFailed = false;

  final GlobalKey _currentKey = GlobalKey();
  final GlobalKey _nextKey = GlobalKey();

  ui.FragmentShader? _shader;
  ui.Image? _currentImage;
  ui.Image? _nextImage;

  /// 是否已针对本次翻页抓过快照
  bool _captured = false;

  /// 静止态记录的可视尺寸，翻页时给离屏抓拍层用。
  /// 翻页过程中离屏层被 Positioned 压成 0×0，必须靠这个值撑开原尺寸，
  /// 否则抓到的图尺寸不对，shader 采样会错位。
  Size? _lastSize;

  @override
  void initState() {
    super.initState();
    _ensureShader();
  }

  Future<void> _ensureShader() async {
    if (_loadFailed) return;

    if (_cachedProgram == null) {
      // FragmentProgram.fromAsset 有内部缓存，但这里再存一层，
      // 避免每次进入翻页都走一次 await（会导致首帧降级闪烁）。
      final program = await AppError.guard(
        () => ui.FragmentProgram.fromAsset('shaders/page_curl.frag'),
        action: 'PageCurlView.loadShader',
      );
      if (program == null) {
        _loadFailed = true;
        if (mounted) setState(() {});
        return;
      }
      _cachedProgram = program;
    }

    if (!mounted) return;
    setState(() => _shader = _cachedProgram!.fragmentShader());
  }

  @override
  void didUpdateWidget(PageCurlView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 回到静止态时释放快照，下次翻页重新抓，避免内容更新后用到旧图
    if (widget.progress <= 0.0) {
      _releaseImages();
      _captured = false;
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    _releaseImages();
    super.dispose();
  }

  void _releaseImages() {
    _currentImage?.dispose();
    _nextImage?.dispose();
    _currentImage = null;
    _nextImage = null;
  }

  /// 从两个 RepaintBoundary 同步抓快照
  ///
  /// 用 toImageSync 而不是 toImage：后者返回 Future，在拖拽首帧拿不到图，
  /// 会看到一帧空白。toImageSync 走 GPU 侧同步路径，适合这种即时场景。
  void _captureIfNeeded() {
    if (_captured) return;

    final currentBoundary =
        _currentKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    final nextBoundary =
        _nextKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;

    if (currentBoundary == null || nextBoundary == null) return;
    // 布局未完成时抓拍会拿到空图
    if (!currentBoundary.hasSize || !nextBoundary.hasSize) return;

    try {
      final current = currentBoundary.toImageSync();
      final next = nextBoundary.toImageSync();
      _releaseImages();
      _currentImage = current;
      _nextImage = next;
      _captured = true;
    } on Exception catch (e, st) {
      // 抓拍失败不该中断阅读，降级到普通渲染即可
      AppError.ignore(e, st, 'PageCurlView 快照抓取失败，本次翻页降级');
    }
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;

    // 静止状态：直接显示当前页，不做任何额外开销。
    // 顺便记下可视尺寸，翻页时离屏抓拍层要靠它撑开布局。
    if (widget.progress <= 0.0) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          if (size.isFinite && size != _lastSize) {
            _lastSize = size;
          }
          return _buildLayers(showCurrent: true);
        },
      );
    }

    // shader 不可用：降级到透视变换
    if (shader == null) {
      return _buildFallback();
    }

    _captureIfNeeded();

    final current = _currentImage;
    final next = _nextImage;
    if (current == null || next == null) {
      // 快照还没就绪（布局未完成），先按降级方案渲染，下一帧会补上
      return _buildFallback();
    }

    return Stack(
      children: [
        // 两页的真实 widget 树必须持续挂载且真正参与绘制，否则
        // toImageSync 抓到空图。这里用 Offstage=false + 零尺寸裁剪的方式
        // 把它们移出可视区：既保留布局与绘制，又不干扰上层 shader 输出。
        //
        // 不能用 Opacity(0)：opacity 为 0 时 Flutter 会跳过子树绘制，
        // 抓拍结果是全透明图，shader 采样后整屏空白。
        Positioned(
          left: 0,
          top: 0,
          width: 0,
          height: 0,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            maxWidth: double.infinity,
            minHeight: 0,
            maxHeight: double.infinity,
            child: SizedBox(
              width: _lastSize?.width ?? 0,
              height: _lastSize?.height ?? 0,
              child: IgnorePointer(child: _buildLayers(showCurrent: true)),
            ),
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _PageCurlPainter(
                shader: shader,
                currentImage: current,
                nextImage: next,
                progress: widget.progress,
                direction: widget.direction,
                dragStartY: widget.dragStartY,
                backgroundColor: widget.backgroundColor,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ],
    );
  }

  /// 两页的真实 widget 树，各自包一层 RepaintBoundary 供抓拍
  Widget _buildLayers({required bool showCurrent}) => Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(key: _nextKey, child: widget.nextPage),
          ),
          if (showCurrent)
            Positioned.fill(
              child: RepaintBoundary(key: _currentKey, child: widget.currentPage),
            ),
        ],
      );

  /// shader 不可用时的降级：透视变换。
  /// 与改用 shader 之前的 simulation 行为一致，保证功能不退化。
  Widget _buildFallback() {
    final signed = widget.direction > 0 ? widget.progress : -widget.progress;
    final rotateY = signed.clamp(-1.0, 1.0) * 0.5;

    return Stack(
      children: [
        Positioned.fill(child: widget.nextPage),
        Positioned.fill(
          child: Transform(
            alignment:
                signed >= 0 ? Alignment.centerLeft : Alignment.centerRight,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(rotateY),
            child: widget.currentPage,
          ),
        ),
      ],
    );
  }
}

class _PageCurlPainter extends CustomPainter {
  const _PageCurlPainter({
    required this.shader,
    required this.currentImage,
    required this.nextImage,
    required this.progress,
    required this.direction,
    required this.dragStartY,
    required this.backgroundColor,
  });

  final ui.FragmentShader shader;
  final ui.Image currentImage;
  final ui.Image nextImage;
  final double progress;
  final double direction;
  final double dragStartY;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // uniform 顺序必须与 page_curl.frag 的声明顺序严格一致：
    // resolution(vec2) → progress → direction → dragStartY → backgroundColor(vec4)
    // sampler 单独用 setImageSampler，索引与 uniform sampler2D 的声明顺序一致。
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, progress.clamp(0.0, 1.0))
      ..setFloat(3, direction)
      ..setFloat(4, dragStartY.clamp(0.0, 1.0))
      ..setFloat(5, backgroundColor.r)
      ..setFloat(6, backgroundColor.g)
      ..setFloat(7, backgroundColor.b)
      ..setFloat(8, backgroundColor.a)
      ..setImageSampler(0, currentImage)
      ..setImageSampler(1, nextImage);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_PageCurlPainter old) =>
      progress != old.progress ||
      direction != old.direction ||
      dragStartY != old.dragStartY ||
      !identical(currentImage, old.currentImage) ||
      !identical(nextImage, old.nextImage) ||
      backgroundColor != old.backgroundColor;
}
