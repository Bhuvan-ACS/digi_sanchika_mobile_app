import 'package:digi_sanchika/presentations/Screens/shared_by_me_screen.dart';
import 'package:digi_sanchika/presentations/Screens/shared_folder_folder_screen.dart';
import 'package:digi_sanchika/presentations/Screens/shared_files_screen.dart';
import 'package:flutter/material.dart';

class SharedWithMeScreen extends StatefulWidget {
  const SharedWithMeScreen({super.key});

  @override
  State<SharedWithMeScreen> createState() => _SharedWithMeScreenState();
}

class _SharedWithMeScreenState extends State<SharedWithMeScreen> with SingleTickerProviderStateMixin {

  late final TabController _tabController;
   @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2, // Number of tabs
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    _tabController.animateTo(index);
    setState(() {});
  }

  Widget _buildTabSwitcher() {
    final selectedIndex = _tabController.index;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Container(
        height: 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFE7ECF4),
          borderRadius: BorderRadius.circular(50),
        ),
        child: Row(
          children: [
            _buildTabOption(
              label: 'Shared with me',
              selected: selectedIndex == 0,
              onTap: () => _selectTab(0),
            ),
            _buildTabOption(
              label: 'Shared by me',
              selected: selectedIndex == 1,
              onTap: () => _selectTab(1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.black87 : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: Column(
        children: [
          Material(
            color: const Color(0xFFF7F9FC),
            child: _buildTabSwitcher(),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                SharedMeScreen(),
                SharedByMeScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  } 
}
