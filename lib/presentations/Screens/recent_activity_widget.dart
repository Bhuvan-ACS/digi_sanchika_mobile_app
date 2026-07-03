import 'package:digi_sanchika/utils/screen_utils.dart';
import 'package:flutter/material.dart';

class ActivityItem {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final List<TextSpan> textSpans; // mix of bold (names/files) and normal text
  final String timeAgo;

  ActivityItem({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.textSpans,
    required this.timeAgo,
  });
}

class ActivityFeed extends StatelessWidget {
  final List<ActivityItem> activities;

  const ActivityFeed({super.key, required this.activities});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          
         height10,
          for (int i = 0; i < activities.length; i++)
            _buildActivityRow(activities[i], isLast: i == activities.length - 1),
        ],
      ),
    );
  }

  Widget _buildActivityRow(ActivityItem item, {required bool isLast}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + connecting line column
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: item.iconBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon, color: item.iconColor, size: 20),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: Colors.grey.shade300,
                  ),
                ),
            ],
          ),
         width10,
          // Text content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black,
                        height: 1.4,
                      ),
                      children: item.textSpans,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.timeAgo,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}