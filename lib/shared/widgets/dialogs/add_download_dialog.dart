import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/aria2/presentation/providers/aria2_provider.dart';
import 'package:my_nas/features/downloader/presentation/providers/downloader_aggregate_provider.dart';
import 'package:my_nas/features/qbittorrent/presentation/providers/qbittorrent_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/transmission/presentation/providers/transmission_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 设计稿 dialogs.jsx 中 AddDownload：新建下载任务弹窗。
///
/// 客户端列表跟随已配置「下载工具」源；提交时按所选客户端类型分发到
/// aria2 / qBittorrent / Transmission 的 addUri / addTorrent。
class AddDownloadDialog extends ConsumerStatefulWidget {
  const AddDownloadDialog({this.prefill, super.key});

  /// 从 PT 详情等场景预填一组磁力链接。
  final String? prefill;

  @override
  ConsumerState<AddDownloadDialog> createState() => _AddDownloadDialogState();
}

class _AddDownloadDialogState extends ConsumerState<AddDownloadDialog> {
  late final TextEditingController _uri =
      TextEditingController(text: widget.prefill ?? '');
  final TextEditingController _savePath = TextEditingController();
  String? _sourceId;
  String _category = '电影';
  bool _paused = false;
  bool _submitting = false;

  static const _categories = ['电影', '剧集', '动画', '音乐', '其他'];

  @override
  void dispose() {
    _uri.dispose();
    _savePath.dispose();
    super.dispose();
  }

  int get _linkCount =>
      _uri.text.split('\n').where((e) => e.trim().isNotEmpty).length;

  List<String> get _links =>
      _uri.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  String _categoryLabel(AppLocalizations l, String value) => switch (value) {
        '电影' => l.addDlCategoryMovie,
        '剧集' => l.addDlCategorySeries,
        '动画' => l.addDlCategoryAnime,
        '音乐' => l.addDlCategoryMusic,
        _ => l.addDlCategoryOther,
      };

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final clients = ref.watch(downloaderClientsProvider);
    if (_sourceId == null && clients.isNotEmpty) {
      _sourceId = clients
          .firstWhere((c) => c.connected, orElse: () => clients.first)
          .source
          .id;
    }
    final selectedName = clients
            .where((c) => c.source.id == _sourceId)
            .map((c) => c.source.displayName)
            .firstOrNull ??
        '—';
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
                      _Label(l.addDlLinksLabel, t: t),
                      const SizedBox(height: 7),
                      TextField(
                        controller: _uri,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: l.addDlLinksHint,
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
                      _Label(l.addDlClientLabel, t: t),
                      const SizedBox(height: 7),
                      if (clients.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: t.insetBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: t.hairline),
                          ),
                          child: Text(
                            l.addDlNoClientHint,
                            style: TextStyle(
                                fontSize: 12, color: t.text2, height: 1.5),
                          ),
                        )
                      else
                        Column(
                          children: [
                            for (final c in clients)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 7),
                                child: AppCard(
                                  onTap: () =>
                                      setState(() => _sourceId = c.source.id),
                                  selected: c.source.id == _sourceId,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 13,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      StatusDot(c.connected
                                          ? DotStatus.ok
                                          : DotStatus.off),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '${c.source.displayName} · '
                                          '${c.source.type.displayName}',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: t.text0,
                                          ),
                                        ),
                                      ),
                                      if (c.source.id == _sourceId)
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
                                _Label(l.addDlCategoryLabel, t: t),
                                const SizedBox(height: 7),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final c in _categories)
                                      AppChip(
                                        label: _categoryLabel(l, c),
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
                      _Label(l.addDlSavePathLabel, t: t),
                      const SizedBox(height: 7),
                      TextField(
                        controller: _savePath,
                        style: TextStyle(color: t.text0, fontSize: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: l.addDlSavePathHint,
                          hintStyle: TextStyle(color: t.text3, fontSize: 12.5),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: t.hairline),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: t.hairline),
                          ),
                        ),
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
                                    l.addDlPausedTitle,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: t.text0,
                                    ),
                                  ),
                                  Text(
                                    l.addDlPausedSubtitle,
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
                hint: l.addDlFooterHint(_linkCount, selectedName),
                t: t,
                disabled: _linkCount == 0 || _sourceId == null || _submitting,
                onSubmit: _submit,
                onCancel: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final clients = ref.read(downloaderClientsProvider);
    final client =
        clients.where((c) => c.source.id == _sourceId).firstOrNull;
    if (client == null || _links.isEmpty) return;

    setState(() => _submitting = true);
    final source = client.source;
    final savePath = _savePath.text.trim();
    final dir = savePath.isEmpty ? null : savePath;
    try {
      switch (source.type) {
        case SourceType.aria2:
          final gid = await ref
              .read(aria2ActionsProvider(source.id))
              .addUri(_links, dir: dir);
          // aria2 addUri 无 paused 参数，添加后立即暂停以兑现「添加后暂停」开关。
          if (_paused) {
            await ref.read(aria2ActionsProvider(source.id)).pause(gid);
          }
        case SourceType.qbittorrent:
          for (final link in _links) {
            await ref.read(qbittorrentActionsProvider(source.id)).addTorrent(
                  link,
                  savePath: dir,
                  category: _category,
                  paused: _paused,
                );
          }
        case SourceType.transmission:
          for (final link in _links) {
            await ref
                .read(transmissionActionsProvider(source.id))
                .addTorrent(link, downloadDir: dir, paused: _paused);
          }
        default:
          break;
      }
      if (mounted) {
        Navigator.of(context).pop();
        context.showSuccessToast(
            l.addDlSuccessToast(_links.length, source.displayName));
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        context.showErrorToast(l.addDlFailToast('$e'));
      }
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.t, required this.onClose});
  final DesignTokens t;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
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
              l.addDlTitle,
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
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          Text(hint, style: TextStyle(fontSize: 11.5, color: t.text2)),
          const Spacer(),
          TextButton(onPressed: onCancel, child: Text(l.addDlCancel)),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: disabled ? null : onSubmit,
            icon: const Icon(Icons.add_rounded, size: 14),
            label: Text(l.addDlSubmit),
          ),
        ],
      ),
    );
  }
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
