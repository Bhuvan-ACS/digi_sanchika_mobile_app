import 'package:flutter/material.dart';
import 'package:digi_sanchika/utils/app_theme.dart';

/// Generic empty-state widget — icon, headline, optional body text + action.
///
/// Usage:
///   EmptyStateWidget(
///     icon: Icons.folder_off_outlined,
///     title: 'No Documents Yet',
///     subtitle: 'Upload your first document to get started.',
///     action: ElevatedButton(...),
///   )
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Color? iconColor;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppColors.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon container with soft background
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: color.withAlpha(18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color.withAlpha(200)),
            ),
            const SizedBox(height: 20),

            // Headline
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),

            // Optional body
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],

            // Optional action
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
