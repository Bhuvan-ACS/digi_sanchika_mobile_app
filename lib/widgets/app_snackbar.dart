import 'package:flutter/material.dart';
import 'package:digi_sanchika/utils/app_theme.dart';

/// Branded snackbar helper — replaces all raw SnackBar calls.
///
/// Usage:
///   AppSnackbar.success(context, 'File uploaded successfully');
///   AppSnackbar.error(context, 'Upload failed. Try again.');
///   AppSnackbar.info(context, 'Syncing your documents…');
///   AppSnackbar.warning(context, 'Storage permission not granted.');
class AppSnackbar {
  static void success(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) =>
      _show(
        context,
        message: message,
        icon: Icons.check_circle_rounded,
        bgColor: AppColors.success,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      );

  static void error(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) =>
      _show(
        context,
        message: message,
        icon: Icons.error_outline_rounded,
        bgColor: AppColors.error,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      );

  static void info(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) =>
      _show(
        context,
        message: message,
        icon: Icons.info_outline_rounded,
        bgColor: AppColors.primary,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      );

  static void warning(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) =>
      _show(
        context,
        message: message,
        icon: Icons.warning_amber_rounded,
        bgColor: AppColors.warning,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      );

  static void _show(
    BuildContext context, {
    required String message,
    required IconData icon,
    required Color bgColor,
    String? actionLabel,
    VoidCallback? onAction,
    required Duration duration,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: duration,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          action: actionLabel != null
              ? SnackBarAction(
                  label: actionLabel,
                  textColor: Colors.white.withAlpha(220),
                  onPressed: onAction ?? () {},
                )
              : null,
        ),
      );
  }
}
