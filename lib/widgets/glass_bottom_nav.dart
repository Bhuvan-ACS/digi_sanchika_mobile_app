import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/ui_theme.dart';

/// One tab of [GlassBottomNav].
class GlassNavItem {
  const GlassNavItem(this.icon, this.activeIcon, this.label);

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// A nav card beside an isolated "+" upload button.
class GlassBottomNav extends StatelessWidget {
  const GlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onUploadTap,
    this.items = defaultItems,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onUploadTap;
  final List<GlassNavItem> items;

  static const defaultItems = [
    GlassNavItem(PhosphorIconsRegular.house, PhosphorIconsFill.house, 'Home'),
    GlassNavItem(
      PhosphorIconsRegular.books,
      PhosphorIconsFill.books,
      'Library',
    ),
    GlassNavItem(PhosphorIconsRegular.users, PhosphorIconsFill.users, 'Shared'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: UiColors.surface,
              borderRadius: BorderRadius.circular(26),
              boxShadow: softShadow(0.12),
            ),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _NavItem(
                      icon: items[i].icon,
                      activeIcon: items[i].activeIcon,
                      label: items[i].label,
                      active: currentIndex == i,
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
        _UploadFab(onTap: onUploadTap),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: active ? 4 : 2,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: active ? UiColors.primaryTint : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  active ? activeIcon : icon,
                  size: 24,
                  color: active ? UiColors.primary : UiColors.textSecondary,
                ),
                const SizedBox(height: 2),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: active ? 10 : 10.5,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                        color: active
                            ? UiColors.primary
                            : UiColors.textSecondary,
                      ),
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

class _UploadFab extends StatelessWidget {
  const _UploadFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Upload documents',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: UiColors.primary,
              boxShadow: primaryGlow(),
            ),
            child: const Icon(
              PhosphorIconsRegular.plus,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }
}
