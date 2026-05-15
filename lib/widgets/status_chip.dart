import 'package:flutter/material.dart';
import 'package:digi_sanchika/utils/app_theme.dart';

enum StatusType { success, warning, error, info, neutral }

/// Compact, pill-shaped status chip with icon + label.
///
/// Usage:
///   StatusChip(label: 'Approved', type: StatusType.success)
///   StatusChip(label: 'Pending', type: StatusType.warning, icon: Icons.schedule)
///   StatusChip.fromString('approved')   // auto-detects type from common status words
class StatusChip extends StatelessWidget {
  final String label;
  final StatusType type;
  final IconData? icon;
  final double fontSize;

  const StatusChip({
    super.key,
    required this.label,
    this.type = StatusType.neutral,
    this.icon,
    this.fontSize = 11.5,
  });

  /// Automatically infer StatusType from common status strings.
  factory StatusChip.fromString(String status, {double fontSize = 11.5}) {
    final s = status.trim().toLowerCase();
    StatusType type;
    IconData icon;

    if (s.contains('approv') || s.contains('grant') || s.contains('success') ||
        s.contains('complet') || s.contains('active') || s.contains('done')) {
      type = StatusType.success;
      icon = Icons.check_circle_rounded;
    } else if (s.contains('pend') || s.contains('review') ||
        s.contains('process') || s.contains('wait')) {
      type = StatusType.warning;
      icon = Icons.schedule_rounded;
    } else if (s.contains('deny') || s.contains('deni') || s.contains('reject') ||
        s.contains('fail') || s.contains('error') || s.contains('expired') ||
        s.contains('inactiv')) {
      type = StatusType.error;
      icon = Icons.cancel_rounded;
    } else if (s.contains('info') || s.contains('notif') || s.contains('new')) {
      type = StatusType.info;
      icon = Icons.info_rounded;
    } else {
      type = StatusType.neutral;
      icon = Icons.circle_outlined;
    }

    return StatusChip(
      label: status,
      type: type,
      icon: icon,
      fontSize: fontSize,
    );
  }

  Color get _fg => switch (type) {
        StatusType.success => AppColors.success,
        StatusType.warning => AppColors.warning,
        StatusType.error => AppColors.error,
        StatusType.info => AppColors.info,
        StatusType.neutral => AppColors.textSecondary,
      };

  Color get _bg => switch (type) {
        StatusType.success => AppColors.successLight,
        StatusType.warning => AppColors.warningLight,
        StatusType.error => AppColors.errorLight,
        StatusType.info => AppColors.infoLight,
        StatusType.neutral => AppColors.surfaceVariant,
      };

  Color get _border => switch (type) {
        StatusType.success => AppColors.successBorder,
        StatusType.warning => AppColors.warningBorder,
        StatusType.error => AppColors.errorBorder,
        StatusType.info => AppColors.infoBorder,
        StatusType.neutral => AppColors.border,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: _border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 1.5, color: _fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: _fg,
            ),
          ),
        ],
      ),
    );
  }
}
