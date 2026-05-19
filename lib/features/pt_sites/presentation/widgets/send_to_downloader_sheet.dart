import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/features/pt_sites/domain/entities/pt_torrent.dart';
import 'package:my_nas/features/pt_sites/presentation/providers/pt_site_provider.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/service_adapters/aria2/api/aria2_api.dart';
import 'package:my_nas/service_adapters/qbittorrent/api/qbittorrent_api.dart';
import 'package:my_nas/service_adapters/transmission/api/transmission_api.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

/// 发送到下载器的底部弹窗
class SendToDownloaderSheet extends ConsumerStatefulWidget {
  const SendToDownloaderSheet({
    required this.torrent,
    required this.sourceId,
    super.key,
  });

  final PTTorrent torrent;
  final String sourceId;

  @override
  ConsumerState<SendToDownloaderSheet> createState() =>
      _SendToDownloaderSheetState();
}

class _SendToDownloaderSheetState extends ConsumerState<SendToDownloaderSheet> {
  bool _isLoading = false;
  String? _downloadUrl;
  String? _selectedDownloaderId;
  bool _pauseAfterAdd = false;

  @override
  void initState() {
    super.initState();
    _loadDownloadUrl();
  }

  Future<void> _loadDownloadUrl() async {
    try {
      final api = ref.read(ptSiteConnectionProvider(widget.sourceId)).api;
      if (api != null) {
        _downloadUrl = await api.getDownloadUrl(widget.torrent.id);
        if (mounted) setState(() {});
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '获取专属下载链接失败，回退使用 torrent.downloadUrl');
      _downloadUrl = widget.torrent.downloadUrl;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sourcesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 获取所有下载器
    final downloaders = sources.valueOrNull
            ?.where((s) => s.type.category == SourceCategory.downloadTools)
            .where((s) => s.type.isSupported)
            .toList() ??
        [];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                const Icon(Icons.download_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '发送到下载器',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 种子信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.torrent.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.storage,
                        size: 14,
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.torrent.formattedSize,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant
                              : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                      if (widget.torrent.status.hasPromotion) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.torrent.status.promotionLabel ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 下载器列表
            if (downloaders.isEmpty) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 48,
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      const Text('尚未添加下载器'),
                      const SizedBox(height: 8),
                      Text(
                        '请先在设置中添加 qBittorrent、Transmission 或 Aria2',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant
                              : AppColors.lightOnSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Text(
                '选择下载器',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _selectedDownloaderId,
                onChanged: (value) {
                  setState(() {
                    _selectedDownloaderId = value;
                  });
                },
                child: Column(
                  children: downloaders.map((downloader) => ListTile(
                    leading: Icon(downloader.type.icon),
                    title: Text(
                      downloader.name.isEmpty
                          ? downloader.type.displayName
                          : downloader.name,
                    ),
                    subtitle: Text(
                      '${downloader.host}:${downloader.port}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                    trailing: Radio<String>(value: downloader.id),
                    onTap: () {
                      setState(() {
                        _selectedDownloaderId = downloader.id;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                  )).toList(),
                ),
              ),

              // 选项
              const Divider(),
              SwitchListTile(
                value: _pauseAfterAdd,
                onChanged: (value) {
                  setState(() {
                    _pauseAfterAdd = value;
                  });
                },
                title: const Text('添加后暂停'),
                subtitle: const Text('添加种子后不立即开始下载'),
                contentPadding: EdgeInsets.zero,
              ),
            ],

            const SizedBox(height: 16),

            // 操作按钮
            Row(
              children: [
                // 复制链接按钮
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _downloadUrl != null
                        ? () async {
                            await Clipboard.setData(
                              ClipboardData(text: _downloadUrl!),
                            );
                            if (!mounted) return;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('下载链接已复制到剪贴板'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('复制链接'),
                  ),
                ),
                const SizedBox(width: 12),
                // 发送按钮
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _selectedDownloaderId != null &&
                            _downloadUrl != null &&
                            !_isLoading
                        ? _sendToDownloader
                        : null,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                    label: const Text('发送'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendToDownloader() async {
    if (_selectedDownloaderId == null || _downloadUrl == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final sources = ref.read(sourcesProvider).valueOrNull ?? [];
      final downloader = sources.firstWhere(
        (s) => s.id == _selectedDownloaderId,
      );

      // 获取凭证
      final sourceManager = ref.read(sourceManagerProvider);
      final credential = await sourceManager.getCredential(downloader.id);

      switch (downloader.type) {
        case SourceType.qbittorrent:
          await _sendToQBittorrent(downloader, credential);
        case SourceType.transmission:
          await _sendToTransmission(downloader, credential);
        case SourceType.aria2:
          await _sendToAria2(downloader);
        default:
          throw Exception('不支持的下载器类型');
      }

      if (!mounted) return;
      Navigator.pop(context);
      context.showSuccessToast('已发送到 ${downloader.name.isEmpty ? downloader.type.displayName : downloader.name}');
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('发送失败: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendToQBittorrent(
    SourceEntity downloader,
    SourceCredential? credential,
  ) async {
    final protocol = downloader.useSsl ? 'https' : 'http';
    final baseUrl = '$protocol://${downloader.host}:${downloader.port}';
    final password = credential?.password ?? '';

    final api = QBittorrentApi(
      baseUrl: baseUrl,
      username: downloader.username,
      password: password,
      apiKey: downloader.apiKey,
    );

    try {
      final loggedIn = await api.login();
      if (!loggedIn) {
        throw Exception('登录失败');
      }

      await api.addTorrentByUrl(
        _downloadUrl!,
        paused: _pauseAfterAdd,
      );
    } finally {
      api.dispose();
    }
  }

  Future<void> _sendToTransmission(
    SourceEntity downloader,
    SourceCredential? credential,
  ) async {
    final protocol = downloader.useSsl ? 'https' : 'http';
    final baseUrl = '$protocol://${downloader.host}:${downloader.port}';
    final rpcPath = downloader.extraConfig?['rpcPath'] as String? ??
        '/transmission/rpc';
    final password = credential?.password ?? '';

    final api = TransmissionApi(
      baseUrl: baseUrl,
      rpcPath: rpcPath,
      username: downloader.username,
      password: password,
    );

    try {
      await api.torrentAdd(
        filename: _downloadUrl,
        paused: _pauseAfterAdd,
      );
    } finally {
      api.dispose();
    }
  }

  Future<void> _sendToAria2(SourceEntity downloader) async {
    // Aria2 通过 JSON-RPC 提交 URI 任务，BT 种子直接传 URL，让 Aria2 自行下载并解析
    final protocol = downloader.useSsl ? 'https' : 'http';
    final baseUrl = '$protocol://${downloader.host}:${downloader.port}';
    final rpcSecret = downloader.extraConfig?['rpcSecret'] as String?;
    final downloadDir = downloader.extraConfig?['downloadDir'] as String?;

    final api = Aria2Api(baseUrl: baseUrl, rpcSecret: rpcSecret);

    try {
      // 先验证连接（顺带拿到版本，便于 UI 反馈）
      await api.connect();

      final options = <String, dynamic>{};
      if (downloadDir != null && downloadDir.isNotEmpty) {
        options['dir'] = downloadDir;
      }
      // Aria2 的 pause 选项必须是字符串
      if (_pauseAfterAdd) {
        options['pause'] = 'true';
      }

      await api.addUri(
        [_downloadUrl!],
        options: options.isEmpty ? null : options,
      );
    } finally {
      api.dispose();
    }
  }
}
