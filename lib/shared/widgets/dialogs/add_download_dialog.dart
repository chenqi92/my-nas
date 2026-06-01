import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 设计稿 dialogs.jsx 中 AddDownload：新建下载任务弹窗。
///
/// 4 字段：URI/磁力 textarea + 客户端选择 + 分类 + 保存位置 + 暂停 switch。
/// 提交动作目前不接 aria2/qBittorrent/Transmission 客户端 API（plan Group E
/// 完成 downloads_desktop 数据接线时一并接）。
class AddDownloadDialog extends StatefulWidget {
  const AddDownloadDialog({this.prefill, super.key});

  /// 从 PT 详情等场景预填一组磁力链接。
  final String? prefill;

  @override
  State<AddDownloadDialog> createState() => _AddDownloadDialogState();
}

class _AddDownloadDialogState extends State<AddDownloadDialog> {
  late final TextEditingController _uri =
      TextEditingController(text: widget.prefill ?? '');
  String _client = 'qBittorrent';
  String _category = '电影';
  bool _paused = false;

  static const _clients = ['qBittorrent', 'aria2', 'Transmission'];
  static const _categories = ['电影', '剧集', '动画', '音乐', '其他'];

  @override
  void dispose() {
    _uri.dispose();
    super.dispose();
  }

  int get _linkCount =>
      _uri.text.split('\n').where((e) => e.trim().isNotEmpty).length;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: GlassPanel(
          strong: true,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(t: t, onClose: () => Navigator.of(context).pop()),
              Flexible(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Label('链接 · 磁力 · 种子', t: t),
                      const SizedBox(height: 7),
                      TextField(
                        controller: _uri,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: '粘贴 HTTP 直链、magnet: 磁力链接（每行一个）',
                          hintStyle: TextStyle(color: t.text3, fontSize: 12.5),
                          filled: true,
                          fillColor: t.insetBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: t.hairline),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: t.hairline),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                BorderSide(color: t.accent, width: 1.5),
                          ),
                          isDense: true,
                        ),
                        style: TextStyle(color: t.text0, fontSize: 13),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      _Label('下载到客户端', t: t),
                      const SizedBox(height: 7),
                      Column(
                        children: [
                          for (final c in _clients)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: AppCard(
                                onTap: () => setState(() => _client = c),
                                selected: c == _client,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    const StatusDot(DotStatus.off),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        c,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: t.text0,
                                        ),
                                      ),
                                    ),
                                    if (c == _client)
                                      Icon(Icons.check_rounded,
                                          size: 15, color: t.accent),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Label('分类', t: t),
                                const SizedBox(height: 7),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final c in _categories)
                                      AppChip(
                                        label: c,
                                        active: c == _category,
                                        compact: true,
                                        onTap: () =>
                                            setState(() => _category = c),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: t.hairline),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '添加后暂停',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: t.text0,
                                    ),
                                  ),
                                  Text(
                                    '先添加任务但不立即开始',
                                    style:
                                        TextStyle(fontSize: 12, color: t.text2),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _paused,
                              onChanged: (v) => setState(() => _paused = v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _Footer(
                hint: '$_linkCount 个链接 → $_client',
                t: t,
                disabled: _linkCount == 0,
                onSubmit: () => Navigator.of(context).pop(),
                onCancel: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
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
            Icon(Icons.download_rounded, size: 17, color: t.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '新建下载任务',
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
    required this.hint,
    required this.t,
    required this.disabled,
    required this.onSubmit,
    required this.onCancel,
  });

  final String hint;
  final DesignTokens t;
  final bool disabled;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.hairline)),
        ),
        child: Row(
          children: [
            Text(hint, style: TextStyle(fontSize: 11.5, color: t.text2)),
            const Spacer(),
            TextButton(onPressed: onCancel, child: const Text('取消')),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: disabled ? null : onSubmit,
              icon: const Icon(Icons.add_rounded, size: 14),
              label: const Text('添加任务'),
            ),
          ],
        ),
      );
}

class _Label extends StatelessWidget {
  const _Label(this.label, {required this.t});
  final String label;
  final DesignTokens t;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: t.text1,
        ),
      );
}
