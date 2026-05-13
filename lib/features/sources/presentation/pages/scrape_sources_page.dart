import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/scraper/scrape_source.dart';
import 'package:my_nas/core/scraper/scrape_source_manager.dart';

/// 刮削源管理页（用户导入的 JSON 模板）。
///
/// 注意：本应用 **不内嵌任何 scrape 源**；启动时只列用户主动导入的源。
class ScrapeSourcesPage extends StatefulWidget {
  const ScrapeSourcesPage({super.key});

  @override
  State<ScrapeSourcesPage> createState() => _ScrapeSourcesPageState();
}

class _ScrapeSourcesPageState extends State<ScrapeSourcesPage> {
  List<ScraperConfig> _sources = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await ScrapeSourceManager.instance.init();
    final list = await ScrapeSourceManager.instance.getAll();
    if (!mounted) return;
    setState(() {
      _sources = list;
      _loading = false;
    });
  }

  Future<void> _showImportSheet() async {
    final added = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ImportSheet(),
    );
    if (added != null && added > 0 && mounted) {
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入 $added 个刮削源')),
      );
    }
  }

  Future<void> _toggle(ScraperConfig s, bool v) async {
    await ScrapeSourceManager.instance.setEnabled(s.id, enabled: v);
    await _load();
  }

  Future<void> _delete(ScraperConfig s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除刮削源'),
        content: Text('确认删除「${s.displayName}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if ((ok ?? false) && mounted) {
      await ScrapeSourceManager.instance.remove(s.id);
      await _load();
    }
  }

  String _capLabel(String c) => switch (c) {
        ScraperCapability.metadata => '元数据',
        ScraperCapability.cover => '封面',
        ScraperCapability.lyrics => '歌词',
        ScraperCapability.lyricsWordLevel => '逐字歌词',
        _ => c,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('音乐元数据源'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: _showImportSheet,
            tooltip: '导入',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sources.isEmpty
              ? _buildEmpty()
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: _sources.length,
                  separatorBuilder: (_, _) => const Divider(height: 0),
                  itemBuilder: (_, i) {
                    final s = _sources[i];
                    return ListTile(
                      isThreeLine: s.capabilities.isNotEmpty,
                      title: Text(s.displayName),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('版本 ${s.version}'),
                          if (s.capabilities.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  for (final c in s.capabilities)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .secondaryContainer,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _capLabel(c),
                                        style:
                                            Theme.of(context).textTheme.labelSmall,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          Switch(
                            value: s.enabled,
                            onChanged: (v) => _toggle(s, v),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => _delete(s),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.code_rounded, size: 48),
              const SizedBox(height: 12),
              Text(
                '暂无音乐元数据源',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '本应用不内嵌任何源。点击右上角「+」导入用户提供的 JSON 配置。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
  }
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet();

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  bool _isUrl = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) _controller.text = data!.text!;
  }

  Future<void> _doImport() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;
    setState(() => _busy = true);
    try {
      final list = _isUrl
          ? await ScrapeSourceManager.fetchFromUrl(raw)
          : ScrapeSourceManager.parseImport(raw);
      if (list.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未解析到有效的刮削源 JSON')),
        );
        return;
      }
      final added = await ScrapeSourceManager.instance.addMany(list);
      if (!mounted) return;
      Navigator.pop(context, added);
    } on Exception catch (e, st) {
      AppError.handleWithUI(context, e, st, '导入失败', 'scrapeSource.import');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '导入刮削源',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '本应用仅提供解析引擎，不内置、不分发任何音乐元数据源。 '
                  '导入的源由用户自行选择，您应确保来源合法、不侵犯第三方著作权。 '
                  '本应用不对所导入源的内容负责。',
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('粘贴 JSON')),
                  ButtonSegment(value: true, label: Text('远端 URL')),
                ],
                selected: {_isUrl},
                onSelectionChanged: (s) => setState(() => _isUrl = s.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                maxLines: _isUrl ? 1 : 8,
                keyboardType:
                    _isUrl ? TextInputType.url : TextInputType.multiline,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: _isUrl
                      ? 'https://example.com/scrape-sources.json'
                      : '粘贴 JSON（单对象或数组）',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: _pasteFromClipboard,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _doImport,
                child: _busy
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('导入'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
