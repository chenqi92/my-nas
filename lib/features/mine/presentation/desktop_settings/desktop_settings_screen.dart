import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/mine/presentation/desktop_settings/settings_pane_registry.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';

/// 桌面端「设置」master-detail 外壳。对齐设计稿 `settings.jsx` 的 `.settings-wrap`：
/// 左侧 262px 分组导航（设置标题 + 搜索 + 6 组分类），右侧独立滚动详情 pane。
///
/// 仅桌面端使用（由 `mine_page` 在 `context.isDesktopLayout` 时挂载）；移动端
/// 仍走 mine_page 的 ListView。
class DesktopSettingsScreen extends ConsumerStatefulWidget {
  const DesktopSettingsScreen({super.key});

  @override
  ConsumerState<DesktopSettingsScreen> createState() =>
      _DesktopSettingsScreenState();
}

class _DesktopSettingsScreenState extends ConsumerState<DesktopSettingsScreen> {
  String _selected = settingsGroups.first.cats.first.id;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final cat = allSettingsCats.firstWhere(
      (c) => c.id == _selected,
      orElse: () => settingsGroups.first.cats.first,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 262, child: _buildRail(t)),
        Expanded(
          child: ColoredBox(
            color: t.bg,
            child: SingleChildScrollView(
              key: ValueKey(cat.id),
              padding: const EdgeInsets.fromLTRB(38, 32, 38, 96),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 780),
                  child: buildSettingsPane(cat.id),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ===== 左栏：标题 + 搜索 + 分组分类 =====
  Widget _buildRail(DesignTokens t) {
    final ql = _query.trim().toLowerCase();
    bool match(SettingsCat c) => ql.isEmpty || c.label.toLowerCase().contains(ql);
    final visibleGroups =
        settingsGroups.where((g) => g.cats.any(match)).toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.sidebarBg,
        border: Border(right: BorderSide(color: t.hairline)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 48),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Text(
              '设置',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.38,
                color: t.text0,
              ),
            ),
          ),
          _buildSearch(t),
          if (visibleGroups.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
              child: Text(
                '没有匹配 “$_query” 的设置项',
                style: TextStyle(fontSize: 12.5, color: t.text2),
              ),
            )
          else
            for (final g in visibleGroups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 5),
                child: Text(
                  g.title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.55,
                    color: t.text3,
                  ),
                ),
              ),
              for (final c in g.cats.where(match)) _buildCat(t, c),
            ],
        ],
      ),
    );
  }

  Widget _buildSearch(DesignTokens t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 1),
          decoration: BoxDecoration(
            color: t.insetBg,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: t.hairline, width: 0.5),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 15, color: t.text2),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _query = v),
                  style: TextStyle(fontSize: 12.5, color: t.text0),
                  cursorColor: t.accent,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    hintText: '搜索设置项…',
                    hintStyle: TextStyle(fontSize: 12.5, color: t.text3),
                  ),
                ),
              ),
              if (_query.isNotEmpty)
                InkWell(
                  onTap: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Icon(Icons.close_rounded, size: 14, color: t.text2),
                ),
            ],
          ),
        ),
      );

  Widget _buildCat(DesignTokens t, SettingsCat c) {
    final on = c.id == _selected;
    final fg = on ? t.accentContrast : t.text1;
    final iconColor = on ? t.accentContrast : t.text2;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _selected = c.id),
          borderRadius: BorderRadius.circular(8),
          hoverColor: on ? null : t.chipBg,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: DesignTokens.ease,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: on ? t.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(c.icon, size: 17, color: iconColor),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    c.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                      color: fg,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (c.planned)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: on
                          ? Colors.white.withValues(alpha: 0.22)
                          : const Color(0x29F5B754),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '规划',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: on ? Colors.white : const Color(0xFFCAA23F),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 占位 pane（pane 尚未实现时显示），保证外壳可编译、结构可见。
class StubPane extends StatelessWidget {
  const StubPane({required this.cat, super.key});
  final SettingsCat cat;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(icon: cat.icon, title: cat.label, subtitle: cat.subtitle),
        SetSection(
          children: [
            SetRow(
              title: '建设中',
              desc: '该设置页正在按设计稿迁移',
              last: true,
              trailing: Icon(Icons.construction_rounded, color: t.text3),
            ),
          ],
        ),
      ],
    );
  }
}
