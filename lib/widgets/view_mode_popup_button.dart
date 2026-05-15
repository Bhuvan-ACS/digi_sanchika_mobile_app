import 'package:digi_sanchika/models/app_view_mode.dart';
import 'package:flutter/material.dart';

class ViewModePopupButton extends StatelessWidget {
  final AppViewMode value;
  final ValueChanged<AppViewMode> onSelected;
  final Color iconColor;
  final double iconSize;

  const ViewModePopupButton({
    super.key,
    required this.value,
    required this.onSelected,
    this.iconColor = Colors.indigo,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AppViewMode>(
      tooltip: 'Change Layout',
      icon: Icon(value.icon, color: iconColor, size: iconSize),
      onSelected: onSelected,
      itemBuilder: (context) => AppViewMode.values
          .map(
            (mode) => PopupMenuItem<AppViewMode>(
              value: mode,
              child: Row(
                children: [
                  Icon(mode.icon, color: Colors.indigo),
                  const SizedBox(width: 10),
                  Expanded(child: Text(mode.label)),
                  if (mode == value)
                    const Icon(Icons.check, color: Colors.green, size: 16),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

