// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:digi_sanchika/utils/app_theme.dart';

enum ConfirmVariant { neutral, danger, warning }

/// Custom branded confirm dialog — replaces every raw AlertDialog.
///
/// Usage:
///   final confirmed = await ConfirmDialog.show(
///     context,
///     title: 'Delete Document',
///     message: 'This cannot be undone.',
///     variant: ConfirmVariant.danger,
///   );
///   if (confirmed == true) { ... }
class ConfirmDialog {
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    ConfirmVariant variant = ConfirmVariant.neutral,
    IconData? icon,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ConfirmDialogWidget(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        variant: variant,
        icon: icon,
      ),
    );
  }
}

class _ConfirmDialogWidget extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final ConfirmVariant variant;
  final IconData? icon;

  const _ConfirmDialogWidget({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.variant,
    this.icon,
  });

  Color get _accentColor => switch (variant) {
        ConfirmVariant.danger => AppColors.error,
        ConfirmVariant.warning => AppColors.warning,
        ConfirmVariant.neutral => AppColors.primary,
      };

  Color get _accentBg => switch (variant) {
        ConfirmVariant.danger => AppColors.errorLight,
        ConfirmVariant.warning => AppColors.warningLight,
        ConfirmVariant.neutral => AppColors.primaryContainer,
      };

  IconData get _defaultIcon => switch (variant) {
        ConfirmVariant.danger => Icons.delete_outline_rounded,
        ConfirmVariant.warning => Icons.warning_amber_rounded,
        ConfirmVariant.neutral => Icons.help_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final effectiveIcon = icon ?? _defaultIcon;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      backgroundColor: AppColors.surface,
      elevation: 12,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon + accent strip
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _accentBg,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(effectiveIcon, color: _accentColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Divider
            const Divider(color: AppColors.divider),

            const SizedBox(height: 14),

            // Message
            Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.55,
              ),
            ),

            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(cancelLabel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(confirmLabel),
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
