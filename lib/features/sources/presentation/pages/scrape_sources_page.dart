import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/scraper/scrape_source.dart';
import 'package:my_nas/core/scraper/scrape_source_manager.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

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
    final added = await showAdaptiveModalSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ImportSheet(),
    );
    if (added != null && added > 0 && mounted) {
      await _load();
      // _load() 之后 sheet 可能已被 dismiss，需重新确认
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.scrapeSourcesPageImportedCount(added))),
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
        title: Text(context.l10n.scrapeSourcesPageDeleteTitle),
        content: Text(context.l10n.scrapeSourcesPageDeleteConfirm(s.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.scrapeSourcesPageCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.scrapeSourcesPageDelete),
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
        ScraperCapability.metadata => context.l10n.scrapeSourcesCapabilityMetadata,
        ScraperCapability.cover => context.l10n.scrapeSourcesCapabilityCover,
        ScraperCapability.lyrics => context.l10n.scrapeSourcesCapabilityLyrics,
        ScraperCapability.lyricsWordLevel => context.l10n.scrapeSourcesCapabilityLyricsWordLevel,
        _ => c,
      };

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
        leading: const RoundedBackButton(),
        title: Text(context.l10n.scrapeSourcesPageTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: _showImportSheet,
            tooltip: context.l10n.scrapeSourcesPageImportTooltip,
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
                          Text(context.l10n.scrapeSourcesVersionPrefix(s.version.toString())),
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

  Widget _buildEmpty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.code_rounded, size: 48),
              const SizedBox(height: 12),
              Text(
                context.l10n.scrapeSourcesEmptyTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.scrapeSourcesEmptyDesc,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
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
          SnackBar(content: Text(context.l10n.scrapeSourcesImportNoValidJson)),
        );
        return;
      }
      final added = await ScrapeSourceManager.instance.addMany(list);
      if (!mounted) return;
      Navigator.pop(context, added);
    } on Exception catch (e, st) {
      AppError.handleWithUI(context, e, st, context.l10n.scrapeSourcesImportFailed, 'scrapeSource.import');
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
                context.l10n.scrapeSourcesImportSheetTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  context.l10n.scrapeSourcesImportDisclaimer,
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(context.l10n.scrapeSourcesImportJsonTab)),
                  ButtonSegment(value: true, label: Text(context.l10n.scrapeSourcesImportUrlTab)),
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
                      ? context.l10n.scrapeSourcesImportUrlHint
                      : context.l10n.scrapeSourcesImportJsonHint,
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
                    : Text(context.l10n.scrapeSourcesImportButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
