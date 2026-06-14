import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/pt_sites/domain/entities/pt_torrent.dart';
import 'package:my_nas/features/pt_sites/presentation/widgets/send_to_downloader_sheet.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';

/// PT 种子详情浮层（设计稿 dialogs.jsx）。展示种子完整信息 + 发送到下载器。
class PtTorrentDetailSheet extends ConsumerWidget {
  const PtTorrentDetailSheet({
    required this.torrent,
    required this.sourceId,
    super.key,
  });

  final PTTorrent torrent;
  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final promo = torrent.status.promotionLabel;
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
              Container(
                padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.hairline)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            torrent.name,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: t.text0,
                              height: 1.3,
                            ),
                          ),
                          if (torrent.smallDescr != null &&
                              torrent.smallDescr!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              torrent.smallDescr!,
                              style: TextStyle(fontSize: 12.5, color: t.text2),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              if (promo != null)
                                AppTag(promo, variant: TagVariant.free),
                              if (torrent.category != null)
                                AppTag(torrent.category!,
                                    variant: TagVariant.neutral),
                              for (final label in torrent.labels.take(4))
                                AppTag(label),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, size: 16, color: t.text2),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _stat(l.ptDetailStatSize, torrent.formattedSize,
                              t.text0, t),
                          _stat(l.ptDetailStatSeeders, '${torrent.seeders}',
                              t.ok, t),
                          _stat(l.ptDetailStatLeechers, '${torrent.leechers}',
                              t.accentBright, t),
                          _stat(l.ptDetailStatSnatched, '${torrent.snatched}',
                              t.text0, t),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _MetaRow(
                        label: l.ptDetailMetaUploadTime,
                        value: torrent.formattedRemainingOrUpload(),
                        t: t,
                      ),
                      if (torrent.imdbId != null)
                        _MetaRow(label: 'IMDB', value: torrent.imdbId!, t: t),
                      if (torrent.doubanId != null)
                        _MetaRow(
                            label: l.ptDetailMetaDouban,
                            value: torrent.doubanId!,
                            t: t),
                      _MetaRow(
                          label: l.ptDetailMetaTorrentId,
                          value: torrent.id,
                          t: t),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.hairline)),
                ),
                child: Row(
                  children: [
                    if (torrent.detailUrl != null)
                      OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: torrent.detailUrl!));
                          context.showSuccessToast(l.ptDetailLinkCopied);
                        },
                        icon: const Icon(Icons.link_rounded, size: 15),
                        label: Text(l.ptDetailCopyLink),
                      ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        showAdaptiveModalSheet<void>(
                          context: context,
                          builder: (_) => SendToDownloaderSheet(
                            torrent: torrent,
                            sourceId: sourceId,
                          ),
                        );
                      },
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: Text(l.ptDetailSendToDownloader),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color, DesignTokens t) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11.5, color: t.text2)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value, required this.t});
  final String label;
  final String value;
  final DesignTokens t;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: TextStyle(fontSize: 12, color: t.text2)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: t.text1),
            ),
          ),
        ],
      ),
    );
  }
}

extension on PTTorrent {
  String formattedRemainingOrUpload() {
    final d = uploadTime;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
}
