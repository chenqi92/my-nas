import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/domain/entities/live_stream_models.dart';
import 'package:my_nas/features/video/presentation/pages/live_channel_list_page.dart';
import 'package:my_nas/features/video/presentation/pages/live_player_page.dart';
import 'package:my_nas/features/video/presentation/providers/live_stream_provider.dart';

/// 直播流区块组件
///
/// 在视频首页显示直播频道的横向滚动列表
class LiveStreamSection extends ConsumerWidget {
  const LiveStreamSection({
    super.key,
    required this.isDark,
  });

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasLiveSources = ref.watch(hasLiveSourcesProvider);
    
    // 如果没有配置直播源，不显示此区块
    if (!hasLiveSources) {
      return const SizedBox.shrink();
    }

    final channels = ref.watch(featuredLiveChannelsProvider(10));
    final allChannels = ref.watch(allLiveChannelsProvider);

    if (channels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            children: [
              // 直播图标
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.live_tv_rounded,
                  size: 18,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.l10n.videoLiveStreamSectionTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              // 查看全部按钮
              TextButton(
                onPressed: () => _navigateToChannelList(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n.videoLiveStreamViewAllButton(allChannels.length),
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 频道列表
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: channels.length,
            itemBuilder: (context, index) => _LiveChannelCard(
              channel: channels[index],
              isDark: isDark,
              onTap: () => _playChannel(context, channels[index]),
            ),
          ),
        ),
      ],
    );
  }

  void _navigateToChannelList(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const LiveChannelListPage(),
      ),
    );
  }

  void _playChannel(BuildContext context, LiveChannel channel) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LivePlayerPage(channel: channel),
      ),
    );
  }
}

/// 直播频道卡片
class _LiveChannelCard extends StatefulWidget {
  const _LiveChannelCard({
    required this.channel,
    required this.isDark,
    required this.onTap,
  });

  final LiveChannel channel;
  final bool isDark;
  final VoidCallback onTap;

  @override
  State<_LiveChannelCard> createState() => _LiveChannelCardState();
}

class _LiveChannelCardState extends State<_LiveChannelCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) => Container(
      width: 142,
      margin: const EdgeInsets.only(right: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _isHovered ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Column(
              children: [
                // Logo 容器
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 130,
                  height: 80,
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? AppColors.darkSurfaceVariant
                        : AppColors.lightSurfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isHovered
                          ? Colors.red
                          : (widget.isDark
                              ? Colors.grey[700]!
                              : Colors.grey[300]!),
                      width: _isHovered ? 2 : 1,
                    ),
                    boxShadow: _isHovered
                        ? [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: widget.channel.logoUrl != null
                        ? CachedNetworkImage(
                            imageUrl: widget.channel.logoUrl!,
                            fit: BoxFit.contain,
                            placeholder: (_, _) => _buildPlaceholder(),
                            errorWidget: (_, _, _) => _buildPlaceholder(),
                          )
                        : _buildPlaceholder(),
                  ),
                ),
                const SizedBox(height: 8),
                // 频道名称
                Text(
                  widget.channel.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: widget.isDark ? Colors.white : Colors.black87,
                  ),
                ),
                // 分类
                if (widget.channel.category != null)
                  Text(
                    widget.channel.category!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      color: widget.isDark
                          ? Colors.grey[500]
                          : Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

  Widget _buildPlaceholder() => Center(
        child: Icon(
          Icons.tv_rounded,
          size: 32,
          color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
        ),
      );
}
