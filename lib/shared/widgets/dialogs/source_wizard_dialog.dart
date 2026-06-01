import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';

/// 设计稿 ops2.jsx (AddSourceWizard)：4 步添加源向导。
///
/// 1) 选类型 — 21 种类型 grid（含【规划】项置灰）
/// 2) 连接信息 — 动态字段
/// 3) 测试连接 — spinner → 成功/失败
/// 4) 库映射 — path → 影视/音乐/照片/漫画/图书/不映射 segmented
///
/// 当前为骨架实现：完整连接表单 & 测试逻辑 复用现有 `source_form_page`
/// 接入（plan Group G）。本对话框先把 IA 与视觉敲定，从此处进入正式
/// `Navigator.push` 到现有的 SourceFormPage 完成详细配置。
class SourceWizardDialog extends StatefulWidget {
  const SourceWizardDialog({super.key});

  @override
  State<SourceWizardDialog> createState() => _SourceWizardDialogState();
}

class _SourceWizardDialogState extends State<SourceWizardDialog> {
  int _step = 0;
  String? _type;
  bool _testing = false;
  bool _tested = false;

  static const _steps = ['选择类型', '连接信息', '测试连接', '库映射'];

  static const _types = [
    ('Synology', Icons.dns_outlined, false),
    ('QNAP', Icons.dns_outlined, false),
    ('绿联 UGOS', Icons.dns_outlined, true),
    ('飞牛 fnOS', Icons.dns_outlined, true),
    ('SMB / CIFS', Icons.folder_shared_outlined, false),
    ('WebDAV', Icons.cloud_outlined, false),
    ('SFTP', Icons.terminal_rounded, false),
    ('FTP', Icons.terminal_rounded, false),
    ('NFS', Icons.folder_open_outlined, true),
    ('UPnP / DLNA', Icons.cast_rounded, false),
    ('S3 兼容', Icons.cloud_outlined, false),
    ('本地存储', Icons.folder_outlined, false),
    ('Jellyfin', Icons.movie_outlined, false),
    ('Emby', Icons.movie_outlined, false),
    ('Plex', Icons.movie_outlined, false),
    ('qBittorrent', Icons.download_rounded, false),
    ('aria2', Icons.download_rounded, false),
    ('Transmission', Icons.download_rounded, false),
    ('Trakt', Icons.track_changes_outlined, false),
    ('NAStool', Icons.auto_awesome_outlined, false),
    ('MoviePilot', Icons.auto_awesome_outlined, false),
    ('PT 站点', Icons.flag_circle_outlined, false),
    ('OpenSubtitles', Icons.subtitles_outlined, false),
  ];

  Future<void> _runTest() async {
    setState(() => _testing = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    setState(() {
      _testing = false;
      _tested = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: GlassPanel(
          strong: true,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(t: t, onClose: () => Navigator.of(context).pop()),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
                child: _Stepper(steps: _steps, current: _step, t: t),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
                  child: _stepBody(t),
                ),
              ),
              _Footer(
                t: t,
                onPrev: _step > 0
                    ? () => setState(() => _step--)
                    : null,
                onNext: _canNext() ? _next : null,
                nextLabel: _nextLabel(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepBody(DesignTokens t) {
    switch (_step) {
      case 0:
        return _TypeGrid(
          types: _types,
          selected: _type,
          onPick: (n) => setState(() => _type = n),
        );
      case 1:
        return _ConnectFormStub(t: t, type: _type);
      case 2:
        return _TestSpinner(
            t: t, testing: _testing, tested: _tested, onTest: _runTest);
      case 3:
        return _MappingStub(t: t);
      default:
        return const SizedBox.shrink();
    }
  }

  bool _canNext() {
    if (_step == 0) return _type != null;
    if (_step == 2 && !_tested) return true; // 允许跳过
    return true;
  }

  String _nextLabel() {
    if (_step == 3) return '完成并扫描';
    if (_step == 2 && !_tested) return '跳过';
    return '下一步';
  }

  void _next() {
    if (_step < 3) {
      setState(() => _step++);
    } else {
      Navigator.of(context).pop();
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.t, required this.onClose});
  final DesignTokens t;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.hairline)),
        ),
        child: Row(
          children: [
            Icon(Icons.lan_outlined, size: 17, color: t.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '添加数据源',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: t.text0,
                ),
              ),
            ),
            IconButton(
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, size: 16, color: t.text2),
            ),
          ],
        ),
      );
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.t,
    required this.onPrev,
    required this.onNext,
    required this.nextLabel,
  });
  final DesignTokens t;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final String nextLabel;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.hairline)),
        ),
        child: Row(
          children: [
            if (onPrev != null)
              TextButton(onPressed: onPrev, child: const Text('上一步')),
            const Spacer(),
            FilledButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.arrow_forward_rounded, size: 14),
              label: Text(nextLabel),
            ),
          ],
        ),
      );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.steps, required this.current, required this.t});
  final List<String> steps;
  final int current;
  final DesignTokens t;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          for (var i = 0; i < steps.length; i++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == current
                        ? t.accent
                        : i < current
                            ? t.chipBgActive
                            : t.insetBg,
                    border: Border.all(color: t.hairline),
                  ),
                  child: Center(
                    child: i < current
                        ? Icon(Icons.check_rounded,
                            size: 12, color: t.accentBright)
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: i == current
                                  ? t.accentContrast
                                  : t.text3,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  steps[i],
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: i == current ? t.text0 : t.text3,
                  ),
                ),
              ],
            ),
        ],
      );
}

class _TypeGrid extends StatelessWidget {
  const _TypeGrid({
    required this.types,
    required this.selected,
    required this.onPick,
  });

  final List<(String, IconData, bool)> types;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: types.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        mainAxisExtent: 92,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (_, i) {
        final (name, icon, plan) = types[i];
        return Opacity(
          opacity: plan ? 0.55 : 1,
          child: AppCard(
            onTap: plan ? null : () => onPick(name),
            selected: name == selected,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: t.insetBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: t.accentBright, size: 19),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: t.text0,
                      ),
                    ),
                  ],
                ),
                if (plan)
                  const Positioned(
                    top: -2,
                    right: -2,
                    child: AppTag('规划', variant: TagVariant.plan),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConnectFormStub extends StatelessWidget {
  const _ConnectFormStub({required this.t, required this.type});
  final DesignTokens t;
  final String? type;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: t.insetBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${type ?? '该类型'} 连接信息',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: t.text0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '完整的字段（主机 / 端口 / 用户名 / 密码 / 自动连接 / 记住设备 / '
              '信任自签证书）将复用现有 `SourceFormPage`。点击「下一步」试连，'
              '或从「数据源」页对应卡片直接进入既有表单。',
              style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.6),
            ),
          ],
        ),
      );
}

class _TestSpinner extends StatelessWidget {
  const _TestSpinner({
    required this.t,
    required this.testing,
    required this.tested,
    required this.onTest,
  });

  final DesignTokens t;
  final bool testing;
  final bool tested;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final color = tested
        ? t.ok
        : testing
            ? t.accentBright
            : t.accent;
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: tested
                ? t.ok.withValues(alpha: 0.12)
                : t.insetBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(
            tested
                ? Icons.check_rounded
                : testing
                    ? Icons.sync_rounded
                    : Icons.link_rounded,
            size: 36,
            color: color,
          ),
        ),
        const SizedBox(height: 20),
        if (!tested) ...[
          Text(
            testing ? '正在测试连接…' : '准备测试连接',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: t.text0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            testing
                ? '登录 · 列目录 · 取版本 · 验证凭据'
                : '将验证登录、目录列举与版本信息。凭据安全存储；失败将静默降级。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
          ),
          const SizedBox(height: 18),
          if (!testing)
            FilledButton.icon(
              onPressed: onTest,
              icon: const Icon(Icons.link_rounded, size: 14),
              label: const Text('开始测试'),
            ),
        ] else ...[
          Text(
            '连接成功',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: t.ok,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '版本与共享列表读取完成 · 凭据已安全存储',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: t.text2),
          ),
        ],
      ],
    );
  }
}

class _MappingStub extends StatelessWidget {
  const _MappingStub({required this.t});
  final DesignTokens t;

  @override
  Widget build(BuildContext context) {
    final samples = const [
      ('/video', '影视', Icons.movie_outlined),
      ('/music', '音乐', Icons.library_music_outlined),
      ('/photo', '照片', Icons.photo_library_outlined),
      ('/comic', '漫画', Icons.collections_bookmark_outlined),
      ('/ebook', '图书', Icons.menu_book_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '把源里的文件夹标记为媒体库（SRC-30）。映射后将供扫描 / 搜索 / 播放使用。',
          style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
        ),
        const SizedBox(height: 14),
        for (final (path, lib, icon) in samples)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 16, color: t.text2),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    path,
                    style: TextStyle(
                      fontSize: 13,
                      color: t.text0,
                      fontFamily: 'SF Mono',
                      fontFamilyFallback: const ['Menlo'],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: t.chipBgActive,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 13, color: t.accentBright),
                      const SizedBox(width: 6),
                      Text(
                        '$lib 库',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: t.text0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
