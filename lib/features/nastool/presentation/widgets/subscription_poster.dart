import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';

/// NAStool 海报渲染：posterPath 可能是完整 URL 或 TMDB 相对路径。
class SubscriptionPoster extends StatelessWidget {
  const SubscriptionPoster({required this.path, super.key});

  final String? path;

  static String? resolve(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    final p = path.startsWith('/') ? path : '/$path';
    return 'https://image.tmdb.org/t/p/w500$p';
  }

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final url = resolve(path);
    final placeholder = ColoredBox(
      color: t.insetBg,
      child: Icon(Icons.movie_outlined, size: 22, color: t.text3),
    );
    if (url == null) return placeholder;
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}
