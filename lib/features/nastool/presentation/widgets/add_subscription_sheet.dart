import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/nastool/presentation/widgets/subscription_poster.dart';
import 'package:my_nas/service_adapters/nastool/models/search_result_models.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';

/// 新增订阅浮层：搜索 TMDB 媒体 → 一键添加订阅。
class AddSubscriptionSheet extends ConsumerStatefulWidget {
  const AddSubscriptionSheet({required this.sourceId, super.key});

  final String sourceId;

  @override
  ConsumerState<AddSubscriptionSheet> createState() =>
      _AddSubscriptionSheetState();
}

class _AddSubscriptionSheetState extends ConsumerState<AddSubscriptionSheet> {
  final _ctrl = TextEditingController();
  List<NtMediaSearchResult> _results = const [];
  bool _searching = false;
  String? _addingKey;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final results =
          await ref.read(nastoolActionsProvider(widget.sourceId))
              .searchMediaResources(q);
      if (mounted) setState(() => _results = results);
    } on Object catch (e) {
      if (mounted) context.showErrorToast('搜索失败：$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(NtMediaSearchResult r) async {
    setState(() => _addingKey = '${r.key}');
    final type = (r.type ?? '').toUpperCase().contains('TV') ? 'TV' : 'MOV';
    try {
      await ref.read(nastoolActionsProvider(widget.sourceId)).addSubscribe(
            name: r.title,
            type: type,
            year: r.year,
            mediaId: r.tmdbId,
          );
      ref.invalidate(nastoolSubscribesProvider(widget.sourceId));
      if (mounted) {
        Navigator.of(context).pop();
        context.showSuccessToast('已订阅《${r.title}》');
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _addingKey = null);
        context.showErrorToast('订阅失败：$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: GlassPanel(
          strong: true,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.hairline)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.bookmark_add_rounded, size: 17, color: t.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '新增订阅',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.text0,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, size: 16, color: t.text2),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: '搜索电影 / 剧集名称…',
                    hintStyle: TextStyle(color: t.text3, fontSize: 13),
                    prefixIcon:
                        Icon(Icons.search_rounded, size: 18, color: t.text2),
                    suffixIcon: TextButton(
                        onPressed: _search, child: const Text('搜索')),
                    filled: true,
                    fillColor: t.insetBg,
                    isDense: true,
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
                      borderSide: BorderSide(color: t.accent, width: 1.5),
                    ),
                  ),
                  style: TextStyle(color: t.text0, fontSize: 13),
                ),
              ),
              Flexible(
                child: _searching
                    ? const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _results.isEmpty
                        ? SizedBox(
                            height: 200,
                            child: Center(
                              child: Text(
                                '输入名称后搜索 TMDB，从结果中选择订阅。',
                                style:
                                    TextStyle(fontSize: 13, color: t.text2),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            itemCount: _results.length,
                            itemBuilder: (_, i) => _ResultRow(
                              result: _results[i],
                              adding: _addingKey == '${_results[i].key}',
                              onAdd: () => _add(_results[i]),
                              t: t,
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.result,
    required this.adding,
    required this.onAdd,
    required this.t,
  });

  final NtMediaSearchResult result;
  final bool adding;
  final VoidCallback onAdd;
  final DesignTokens t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            height: 68,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SubscriptionPoster(path: result.coverImage),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: t.text0,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    if (result.year != null) AppTag(result.year!),
                    if (result.type != null)
                      AppTag(
                        (result.type!).toUpperCase().contains('TV')
                            ? '剧集'
                            : '电影',
                        variant: TagVariant.neutral,
                      ),
                    if (result.vote != null && result.vote!.isNotEmpty)
                      AppTag('★ ${result.vote}', variant: TagVariant.free),
                  ],
                ),
                if (result.overview != null &&
                    result.overview!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    result.overview!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: t.text2, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          adding
              ? const SizedBox(
                  width: 32,
                  height: 32,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  onPressed: onAdd,
                  icon: Icon(Icons.add_circle_outline_rounded,
                      color: t.accent),
                  tooltip: '订阅',
                ),
        ],
      ),
    );
  }
}
