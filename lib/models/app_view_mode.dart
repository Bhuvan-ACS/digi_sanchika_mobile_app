import 'package:flutter/material.dart';

enum AppViewMode { list, grid2x2, grid3x3, compact, detailed }

extension AppViewModeX on AppViewMode {
  IconData get icon {
    switch (this) {
      case AppViewMode.list:
        return Icons.list;
      case AppViewMode.grid2x2:
        return Icons.grid_on;
      case AppViewMode.grid3x3:
        return Icons.view_module;
      case AppViewMode.compact:
        return Icons.view_headline;
      case AppViewMode.detailed:
        return Icons.table_rows;
    }
  }

  String get label {
    switch (this) {
      case AppViewMode.list:
        return 'List View';
      case AppViewMode.grid2x2:
        return 'Grid (2×2)';
      case AppViewMode.grid3x3:
        return 'Grid (3×3)';
      case AppViewMode.compact:
        return 'Compact View';
      case AppViewMode.detailed:
        return 'Detailed View';
    }
  }
}

