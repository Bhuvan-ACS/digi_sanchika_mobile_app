import 'package:flutter/material.dart';

/// "My Files" tab: the Workspace and Library pages behind one swipeable
/// two-way switcher (same pill switcher as the Shared tab).
class MyFilesScreen extends StatefulWidget {
  const MyFilesScreen({
    super.key,
    required this.workspace,
    required this.library,
    this.onTabChanged,
  });

  final Widget workspace;
  final Widget library;

  /// Called with 0 (Workspace) or 1 (Library) when the visible tab changes.
  final ValueChanged<int>? onTabChanged;

  @override
  State<MyFilesScreen> createState() => _MyFilesScreenState();
}

class _MyFilesScreenState extends State<MyFilesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  )..addListener(_onTabChanged);

  void _onTabChanged() {
    // Fires for taps and swipes; only react once the index has settled.
    if (_tabController.indexIsChanging) return;
    setState(() {});
    widget.onTabChanged?.call(_tabController.index);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  Widget _buildTabSwitcher() {
    final selectedIndex = _tabController.index;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Container(
        height: 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFE7ECF4),
          borderRadius: BorderRadius.circular(50),
        ),
        child: Row(
          children: [
            _buildTabOption('Workspace', selectedIndex == 0, 0),
            _buildTabOption('Library', selectedIndex == 1, 1),
          ],
        ),
      ),
    );
  }

  Widget _buildTabOption(String label, bool selected, int index) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(index),
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
    return Column(
      children: [
        _buildTabSwitcher(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _KeepAlive(child: widget.workspace),
              _KeepAlive(child: widget.library),
            ],
          ),
        ),
      ],
    );
  }
}

/// Keeps a tab's state (scroll position, loaded data) when swiped away.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
