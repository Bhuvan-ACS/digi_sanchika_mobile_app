import 'package:buttons_tabbar/buttons_tabbar.dart';
import 'package:digi_sanchika/presentations/Screens/shared_folder_folder_screen.dart';
import 'package:digi_sanchika/presentations/Screens/shared_folder_screen.dart';
import 'package:digi_sanchika/presentations/Screens/shared_files_screen.dart';
import 'package:digi_sanchika/utils/app_fonts.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.indigo),
        title: const Text('Shared with Me',style: TextStyle(color: Colors.indigo,
            fontWeight: FontWeight.w600,
        ),
        
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
          bottom: TabBar(
          controller: _tabController, labelColor: Colors.indigo,
  unselectedLabelColor: Colors.black54,

  // Text styles
 
          labelStyle: w600_16Poppins(),
          unselectedLabelStyle: w400_16Poppins(),



          tabs: const [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.file_copy_outlined, size: 16),
                  SizedBox(width: 6),
                  Text("Files"),
                ],
              ),
            
            ),
            Tab(
               child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_copy_sharp, size: 16),
                  SizedBox(width: 6),
                  Text("Folders"),
                ],
              ),
            ),
          ],
        ),
      ),
      body:Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children:  [

      Expanded(
        child: TabBarView(
          controller: _tabController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
       SharedMeScreen(),
            SharedFolderFolderScreen(),
          ],
        ),
      ),
        ],
      ),
    );
  }
}