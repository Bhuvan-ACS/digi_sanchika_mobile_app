import 'package:flutter/material.dart';
import 'package:digi_sanchika/models/app_view_mode.dart';
import 'package:digi_sanchika/theme/ui_theme.dart';

/// Tiny capsule with List / 2x2 / 3x3 icons. A soft blue bubble slides
/// between the icons to mark the active layout.
class LayoutCapsule extends StatelessWidget {
  const LayoutCapsule({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  final AppViewMode value;
  final ValueChanged<AppViewMode> onChanged;

  /// When set, the active bubble is a flat solid circle of this colour
  /// (no gradient or glow).
  final Color? activeColor;

  static const _modes = [
    AppViewMode.list,
    AppViewMode.grid2x2,
    AppViewMode.grid3x3,
  ];
  static const _icons = [
    Icons.view_headline_rounded, // horizontal lines
    Icons.grid_view_rounded, // four squares
    Icons.apps_rounded, // nine small squares
  ];
  static const _tips = ['List', '2 x 2 grid', '3 x 3 grid'];

  static const double _cell = 34;
  static const double _pad = 4;

  @override
  Widget build(BuildContext context) {
    final index = _modes.contains(value) ? _modes.indexOf(value) : 0;
    return Container(
      padding: const EdgeInsets.all(_pad),
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: UiColors.border),
      ),
      child: SizedBox(
        width: _cell * 3,
        height: _cell,
        child: Stack(
          children: [
            // Sliding bubble
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              left: _cell * index,
              top: 0,
              width: _cell,
              height: _cell,
              child: DecoratedBox(
                decoration: activeColor != null
                    ? BoxDecoration(shape: BoxShape.circle, color: activeColor)
                    : BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF4F9BFF), UiColors.primary],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: UiColors.primary.withAlpha(70),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < _modes.length; i++)
                  Tooltip(
                    message: _tips[i],
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(_modes[i]),
                      child: SizedBox(
                        width: _cell,
                        height: _cell,
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              _icons[i],
                              key: ValueKey('${_modes[i]}_${i == index}'),
                              size: 19,
                              color: i == index
                                  ? Colors.white
                                  : UiColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
