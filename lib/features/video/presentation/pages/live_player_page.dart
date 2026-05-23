import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/domain/entities/live_stream_models.dart';
import 'package:my_nas/features/video/presentation/providers/live_stream_provider.dart';
import 'package:my_nas/shared/providers/bottom_nav_visibility_provider.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';
import 'package:screen_brightness/screen_brightness.dart';

/// 收藏频道 Provider
final favoriteChannelsProvider =
    StateNotifierProvider<FavoriteChannelsNotifier, Set<String>>(
  (ref) => FavoriteChannelsNotifier(),
);

/// 收藏频道 Notifier
class FavoriteChannelsNotifier extends StateNotifier<Set<String>> {
  FavoriteChannelsNotifier() : super({}) {
    _init();
  }

  static const _boxName = 'live_favorites';
  Box<String>? _box;

  Future<void> _init() async {
    _box = await Hive.openBox<String>(_boxName);
    state = _box!.values.toSet();
  }

  bool isFavorite(String channelId) => state.contains(channelId);

  Future<void> toggle(String channelId) async {
    if (state.contains(channelId)) {
      state = {...state}..remove(channelId);
      await _box?.delete(channelId);
    } else {
      state = {...state, channelId};
      await _box?.put(channelId, channelId);
    }
  }
}

/// 画面比例模式
enum AspectRatioMode {
  auto('自动'),
  fill('填充'),
  ratio16x9('16:9'),
  ratio4x3('4:3'),
  ratio21x9('21:9');

  const AspectRatioMode(this.label);
  final String label;

  BoxFit get boxFit {
    switch (this) {
      case AspectRatioMode.fill:
        return BoxFit.cover;
      case AspectRatioMode.auto:
      case AspectRatioMode.ratio16x9:
      case AspectRatioMode.ratio4x3:
      case AspectRatioMode.ratio21x9:
        return BoxFit.contain;
    }
  }

  double? get aspectRatio {
    switch (this) {
      case AspectRatioMode.auto:
      case AspectRatioMode.fill:
        return null;
      case AspectRatioMode.ratio16x9:
        return 16 / 9;
      case AspectRatioMode.ratio4x3:
        return 4 / 3;
      case AspectRatioMode.ratio21x9:
        return 21 / 9;
    }
  }
}

/// 直播播放器页面
class LivePlayerPage extends ConsumerStatefulWidget {
  const LivePlayerPage({
    super.key,
    required this.channel,
  });

  final LiveChannel channel;

  @override
  ConsumerState<LivePlayerPage> createState() => _LivePlayerPageState();
}

class _LivePlayerPageState extends ConsumerState<LivePlayerPage> {
  late Player _player;
  late VideoController _controller;
  bool _isBuffering = true;
  bool _showControls = true;
  bool _hasError = false;
  String? _errorMessage;
  LiveChannel? _currentChannel;
  AspectRatioMode _aspectRatioMode = AspectRatioMode.auto;

  // 手势控制
  bool _isDragging = false;
  bool _isVolumeGesture = false;
  double _currentGestureValue = 0;
  double _currentVolume = 1.0;
  final double _sensitivity = 1.5;

  // 频道列表抽屉
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    // 隐藏原生 Tab Bar（iOS 玻璃风格）
    NativeTabBarService.instance.setTabBarVisible(false);
    // 隐藏 Flutter 导航栏（经典风格）
    BottomNavVisibilityNotifier.instance?.hide();
    _currentChannel = widget.channel;
    _initPlayer();
    _setFullScreen();
  }

  Future<void> _initPlayer() async {
    _player = Player();
    _controller = VideoController(_player);

    _player.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    });

    _player.stream.error.listen((error) {
      if (mounted && error.isNotEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = error;
        });
      }
    });

    _player.stream.volume.listen((volume) {
      if (mounted) setState(() => _currentVolume = volume / 100.0);
    });

    await _playChannel(_currentChannel!);
  }

  Future<void> _playChannel(LiveChannel channel) async {
    setState(() {
      _currentChannel = channel;
      _isBuffering = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      await _player.open(
        Media(channel.streamUrl, httpHeaders: channel.headers ?? {}),
      );
    } catch (e, st) {
      AppError.ignore(e, st, '播放直播流失败');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _setFullScreen() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullScreen() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    // 恢复导航栏可见性（通过 Provider 引用计数，由 MainScaffold 决定实际状态）
    BottomNavVisibilityNotifier.instance?.show();
    _player.dispose();
    _exitFullScreen();
    super.dispose();
  }

  void _switchChannel(LiveChannel channel) {
    context.showToast('切换到: ${channel.displayName}');
    _playChannel(channel);
    if (_scaffoldKey.currentState?.isEndDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  void _toggleFavorite() {
    if (_currentChannel != null) {
      ref.read(favoriteChannelsProvider.notifier).toggle(_currentChannel!.id);
    }
  }

  void _cycleAspectRatio() {
    final modes = AspectRatioMode.values;
    final currentIndex = modes.indexOf(_aspectRatioMode);
    final nextIndex = (currentIndex + 1) % modes.length;
    setState(() => _aspectRatioMode = modes[nextIndex]);
    context.showToast('画面比例: ${_aspectRatioMode.label}');
  }

  void _onVerticalDragStart(DragStartDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    _isVolumeGesture = details.localPosition.dx > screenWidth / 2;
    setState(() {
      _isDragging = true;
      _currentGestureValue = _isVolumeGesture ? _currentVolume : 0.5;
    });
    if (!_isVolumeGesture) {
      ScreenBrightness().application.then((brightness) {
        if (mounted) setState(() => _currentGestureValue = brightness);
      });
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    final delta = -details.delta.dy / screenHeight * _sensitivity;
    final newValue = (_currentGestureValue + delta).clamp(0.0, 1.0);
    setState(() => _currentGestureValue = newValue);
    if (_isVolumeGesture) {
      _player.setVolume(newValue * 100);
    } else {
      ScreenBrightness().setApplicationScreenBrightness(newValue);
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _isDragging = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final allChannels = ref.watch(allLiveChannelsProvider);
    final channelsByCategory = ref.watch(liveChannelsByCategoryProvider);
    final favorites = ref.watch(favoriteChannelsProvider);
    final currentIndex = allChannels.indexWhere((c) => c.id == _currentChannel?.id);
    final isFavorite = _currentChannel != null && favorites.contains(_currentChannel!.id);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.black,
      endDrawer: _buildChannelDrawer(channelsByCategory, favorites),
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Stack(
          children: [
            Center(
              child: _aspectRatioMode.aspectRatio != null
                  ? AspectRatio(
                      aspectRatio: _aspectRatioMode.aspectRatio!,
                      child: Video(controller: _controller, fill: Colors.black, fit: _aspectRatioMode.boxFit),
                    )
                  : Video(controller: _controller, fill: Colors.black, fit: _aspectRatioMode.boxFit),
            ),
            if (_isBuffering && !_hasError)
              const Center(child: CircularProgressIndicator(color: Colors.white)),
            if (_hasError) _buildErrorWidget(),
            if (_isDragging) _buildGestureIndicator(),
            if (_showControls) _buildControlsOverlay(allChannels, currentIndex, isFavorite),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            const Text('播放失败', style: TextStyle(color: Colors.white, fontSize: 18)),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_errorMessage!, style: TextStyle(color: Colors.grey[400], fontSize: 12), textAlign: TextAlign.center),
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _playChannel(_currentChannel!),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      );

  Widget _buildGestureIndicator() {
    final icon = _isVolumeGesture
        ? (_currentGestureValue > 0 ? Icons.volume_up_rounded : Icons.volume_off_rounded)
        : (_currentGestureValue > 0.5 ? Icons.brightness_high_rounded : Icons.brightness_low_rounded);
    final label = _isVolumeGesture ? '音量' : '亮度';
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 8),
            SizedBox(width: 120, child: LinearProgressIndicator(value: _currentGestureValue, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation<Color>(Colors.white))),
            const SizedBox(height: 4),
            Text('${(_currentGestureValue * 100).round()}%', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsOverlay(List<LiveChannel> allChannels, int currentIndex, bool isFavorite) => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent, Colors.transparent, Colors.black.withValues(alpha: 0.7)],
          stops: const [0.0, 0.2, 0.8, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 顶部栏
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back_rounded), color: Colors.white, onPressed: () => Navigator.pop(context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_currentChannel?.displayName ?? '', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        if (_currentChannel?.category != null)
                          Text(_currentChannel!.category!, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_border_rounded), color: isFavorite ? Colors.amber : Colors.white, onPressed: _toggleFavorite),
                  IconButton(icon: const Icon(Icons.aspect_ratio_rounded), color: Colors.white, onPressed: _cycleAspectRatio),
                  IconButton(icon: const Icon(Icons.list_rounded), color: Colors.white, onPressed: () => _scaffoldKey.currentState?.openEndDrawer()),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, color: Colors.white, size: 8), SizedBox(width: 4), Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))]),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // 底部控制栏
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(icon: const Icon(Icons.skip_previous_rounded), color: Colors.white, iconSize: 36, onPressed: currentIndex > 0 ? () => _switchChannel(allChannels[currentIndex - 1]) : null),
                  const SizedBox(width: 32),
                  StreamBuilder<bool>(
                    stream: _player.stream.playing,
                    builder: (context, snapshot) => IconButton(
                      icon: Icon((snapshot.data ?? false) ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      color: Colors.white,
                      iconSize: 56,
                      onPressed: () => _player.playOrPause(),
                    ),
                  ),
                  const SizedBox(width: 32),
                  IconButton(icon: const Icon(Icons.skip_next_rounded), color: Colors.white, iconSize: 36, onPressed: currentIndex < allChannels.length - 1 ? () => _switchChannel(allChannels[currentIndex + 1]) : null),
                ],
              ),
            ),
          ],
        ),
      ),
    );

  Widget _buildChannelDrawer(Map<String, List<LiveChannel>> channelsByCategory, Set<String> favorites) {
    final favoriteChannels = ref.watch(allLiveChannelsProvider).where((c) => favorites.contains(c.id)).toList();
    final categories = ['收藏', ...channelsByCategory.keys];
    final selectedCat = _selectedCategory ?? categories.first;

    return Drawer(
      backgroundColor: Colors.grey[900],
      width: 320,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.live_tv_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text('频道列表', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close_rounded), color: Colors.white54, onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            SizedBox(
              height: 48,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final isSelected = category == selectedCat;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: FilterChip(
                      label: Text(category, style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontSize: 12)),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _selectedCategory = category),
                      backgroundColor: Colors.grey[800],
                      selectedColor: Colors.amber,
                      checkmarkColor: Colors.black,
                      side: BorderSide.none,
                    ),
                  );
                },
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            Expanded(child: _buildChannelList(selectedCat == '收藏' ? favoriteChannels : (channelsByCategory[selectedCat] ?? []), favorites)),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelList(List<LiveChannel> channels, Set<String> favorites) {
    if (channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Icon(Icons.tv_off_rounded, color: Colors.grey[600], size: 48), const SizedBox(height: 8), Text('暂无频道', style: TextStyle(color: Colors.grey[600]))],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        final isPlaying = channel.id == _currentChannel?.id;
        final isFav = favorites.contains(channel.id);
        return ListTile(
          leading: channel.logoUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: channel.logoUrl!,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => _buildChannelIcon(isPlaying),
                    errorWidget: (context, url, error) => _buildChannelIcon(isPlaying),
                    fadeInDuration: const Duration(milliseconds: 200),
                    memCacheWidth: 80,
                  ),
                )
              : _buildChannelIcon(isPlaying),
          title: Text(channel.displayName, style: TextStyle(color: isPlaying ? Colors.amber : Colors.white, fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: channel.category != null ? Text(channel.category!, style: TextStyle(color: Colors.grey[500], fontSize: 12)) : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isPlaying) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(4)), child: const Text('播放中', style: TextStyle(color: Colors.white, fontSize: 10))),
              IconButton(icon: Icon(isFav ? Icons.star_rounded : Icons.star_border_rounded, size: 20), color: isFav ? Colors.amber : Colors.grey[600], onPressed: () => ref.read(favoriteChannelsProvider.notifier).toggle(channel.id)),
            ],
          ),
          onTap: () => _switchChannel(channel),
          selectedTileColor: Colors.white10,
          selected: isPlaying,
        );
      },
    );
  }

  Widget _buildChannelIcon(bool isPlaying) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: isPlaying ? Colors.amber : Colors.grey[800], borderRadius: BorderRadius.circular(4)),
        child: Icon(Icons.tv, color: isPlaying ? Colors.black : Colors.white54, size: 20),
      );
}
