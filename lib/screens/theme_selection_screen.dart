import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Thêm import để lưu theme
import '../providers/theme_provider.dart';

class ThemeSelectionScreen extends StatelessWidget {
  const ThemeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final currentTheme = themeProvider.currentThemeName;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chọn giao diện'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.builder(
          itemCount: ThemeProvider.availableThemes.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.25,
          ),
          itemBuilder: (context, index) {
            final themeName = ThemeProvider.availableThemes[index];
            final selected = themeName == currentTheme;
            return _ThemePreviewCard(
              themeName: themeName,
              displayName: _getThemeDisplayName(themeName),
              selected: selected,
              onTap: () async {
                await themeProvider.setTheme(themeName);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('app_theme', themeName);
                if (context.mounted) Navigator.pop(context);
              },
            );
          },
        ),
      ),
    );
  }

  String _getThemeDisplayName(String themeName) {
    switch (themeName) {
      case 'light':
        return 'Hồng mộng mơ';
      case 'nature':
        return 'Thiên nhiên';
      case 'ocean':
        return 'Biển xanh';
      case 'sunset':
        return 'Hoàng hôn';
      case 'lavender':
        return 'Lavender';
      case 'midnight':
        return 'Midnight';
      default:
        return themeName;
    }
  }
}

class _ThemePreviewCard extends StatelessWidget {
  final String themeName;
  final String displayName;
  final bool selected;
  final Future<void> Function() onTap;

  const _ThemePreviewCard({
    required this.themeName,
    required this.displayName,
    required this.selected,
    required this.onTap,
  });

  List<Color> _previewColors() {
    switch (themeName) {
      case 'light':
        return const [Color(0xFFD82D8B), Color(0xFFFFCFE7), Color(0xFFFFF4FA)];
      case 'nature':
        return const [Color(0xFF2E7D32), Color(0xFF81C784), Color(0xFFF1F8E9)];
      case 'ocean':
        return const [Color(0xFF0077B6), Color(0xFF00B4D8), Color(0xFFCAF0F8)];
      case 'sunset':
        return const [Color(0xFFFF6D00), Color(0xFFFF1744), Color(0xFFFFE0B2)];
      case 'lavender':
        return const [Color(0xFF7C4DFF), Color(0xFFB388FF), Color(0xFFE6DEFF)];
      case 'midnight':
        return const [Color(0xFF0B1220), Color(0xFF111A2E), Color(0xFF00E5FF)];
      default:
        return const [Colors.blue, Colors.lightBlue, Colors.white];
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _previewColors();
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          onTap();
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [colors[0], colors[1]],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            _SwatchDot(color: colors[0]),
                            const SizedBox(width: 6),
                            _SwatchDot(color: colors[1]),
                            const SizedBox(width: 6),
                            _SwatchDot(color: colors[2]),
                            const Spacer(),
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.palette_outlined,
                                size: 18,
                                color: themeName == 'midnight' ? Colors.white : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selected ? 'Đang dùng' : 'Chạm để áp dụng',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 160),
                scale: selected ? 1 : 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Icon(
                    Icons.check,
                    size: 16,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? scheme.primary : scheme.outline.withValues(alpha: 0.35),
                      width: selected ? 2 : 1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwatchDot extends StatelessWidget {
  final Color color;
  const _SwatchDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1),
      ),
    );
  }
}