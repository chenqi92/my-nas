import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';

/// 桌面端「照片」骨架。
///
/// 视觉对齐设计稿 media2.jsx (Photos)：时间线 / 相册 / 地图 segmented +
/// 人物 row + 响应式网格。地图展示 [TagVariant.plan] 占位（PHO-22 规划）。
class PhotoListDesktopPage extends StatefulWidget {
  const PhotoListDesktopPage({super.key});

  @override
  State<PhotoListDesktopPage> createState() => _PhotoListDesktopPageState();
}

class _PhotoListDesktopPageState extends State<PhotoListDesktopPage> {
  String _view = 'timeline';

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return DesktopPageScaffold(
      title: '照片',
      subtitle: '人脸识别 · EXIF · 重复检测 · 自动增量扫描',
      actions: Row(
        children: [
          AppSegmented<String>(
            value: _view,
            onChanged: (v) => setState(() => _view = v),
            dense: true,
            options: const [
              AppSegmentedOption(value: 'timeline', label: '时间线'),
              AppSegmentedOption(value: 'albums', label: '相册'),
              AppSegmentedOption(value: 'map', label: '地图'),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '人物',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: t.text0,
                ),
              ),
              const SizedBox(width: 9),
              Text(
                '人脸聚类 · 128 维特征',
                style: TextStyle(fontSize: 12, color: t.text2),
              ),
              if (_view == 'map') ...[
                const Spacer(),
                const AppTag('即将推出', variant: TagVariant.plan),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 8,
              separatorBuilder: (_, _) => const SizedBox(width: 18),
              itemBuilder: (_, _) => Column(
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.insetBg,
                      border: Border.all(color: t.hairline),
                    ),
                    child: Icon(Icons.person_outline_rounded,
                        size: 36, color: t.text3),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '未识别',
                    style: TextStyle(fontSize: 11.5, color: t.text3),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          DesktopComingSoon(
            icon: _view == 'map'
                ? Icons.map_outlined
                : Icons.photo_library_outlined,
            message: _view == 'map'
                ? '按 GPS EXIF 在地图上聚合照片足迹（规划中）。'
                : '映射「照片」媒体库后，此处显示响应式网格 + 时间分组。',
          ),
        ],
      ),
    );
  }
}
