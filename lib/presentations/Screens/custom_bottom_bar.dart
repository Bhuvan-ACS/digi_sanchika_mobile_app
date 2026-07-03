import 'package:flutter/material.dart';

class CustomBottomBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;

  final VoidCallback onAddPressed;

  const CustomBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
    required this.onAddPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // Bottom Navigation Container
          Positioned(
            bottom: 0,
            left: 16,
            right: 16,
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(35),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(
                    icon: Icons.home_outlined,
                    label: 'Home',
                    index: 0,
                  ),
                  _navItem(
                    icon: Icons.folder_outlined,
                    label: 'Documents',
                    index: 1,
                  ),

                  // Space for center button
                  const SizedBox(width: 55),

                  _navItem(
                    icon: Icons.grid_view_outlined,
                    label: 'Hub',
                    index: 2,
                  ),
                  _navItem(
                    icon: Icons.person_outline,
                    label: 'Profile',
                    index: 3,
                  ),
                ],
              ),
            ),
          ),

          // Floating Center Button
          Positioned(
            top: 0,
            child: GestureDetector(
              onTap:onAddPressed,
              child: Container(
                height: 65,
                width: 65,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4A5FFF),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4A5FFF).withOpacity(0.35),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = selectedIndex == index;

    return GestureDetector(
      onTap: () => onItemTapped(index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 24,
            color: isSelected
                ? const Color(0xFF4A5FFF)
                : Colors.grey.shade400,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected
                  ? const Color(0xFF4A5FFF)
                  : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}