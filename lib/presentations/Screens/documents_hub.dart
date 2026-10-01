import 'package:digi_sanchika/presentations/Screens/favorites_screen.dart';
import 'package:digi_sanchika/presentations/Screens/shared_with_me_screen.dart';
import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:flutter/material.dart';
import 'package:digi_sanchika/presentations/Screens/document_library.dart';
import 'package:digi_sanchika/presentations/screens/folder_manager_screen.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class DocumentsHub extends StatefulWidget {
  final VoidCallback onViewAll;

  const DocumentsHub({super.key,required this.onViewAll});

  @override
  State<DocumentsHub> createState() => _DocumentsHubState();
}

class _DocumentsHubState extends State<DocumentsHub> {
  @override
  Widget build(BuildContext context) {
    return  Container(
      color: Colors.grey.shade100,
      child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
          children: [
      
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                   
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Section Header
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'SPACES',
                      style: w600_16Poppins(color: Colors.grey.shade500)
                    ),
                  ),
                  const SizedBox(height: 8),
            
                  // Document Library Card
                  Row(
                    children: [
                      _buildRepositoryCard(
                        title: 'Library',
                        subtitle: 'Organization-wide public documents',
                        icon: Icons.library_books_rounded,
                        iconColor: const Color(0xFF26A69A),
                        iconBackground: const Color(0xFF26A69A).withValues(alpha: 0.1),
                        onTap: () =>
                            _navigateToScreen(context, const DocumentLibrary()),
                      ),
               
            width10,
                  // Shared Documents Card
                  _buildRepositoryCard(
                    title: 'Shared',
                    subtitle: 'Team documents shared directly with you',
                    icon: Icons.group_rounded,
                    iconColor: const Color(0xFF7E57C2),
                    iconBackground: const Color(0xFF7E57C2).withValues(alpha: 0.1),
                    onTap: () =>
                        _navigateToScreen(context, const SharedWithMeScreen()),
                  ),
                    ]),
            height10,
            
                  // Folders Card
                  Row(
                    children: [
                      _buildRepositoryCard(
                        title: 'Folders',
                        subtitle: 'Create, organize, and manage folders',
                        icon: Icons.folder_rounded,
                        iconColor: const Color(0xFFFFA000),
                        iconBackground: const Color(0xFFFFA000).withValues(alpha: 0.12),
                        onTap: widget.onViewAll,
                      ),
            width10,
            
                      _buildRepositoryCard(
                    title: 'Favourites',
                    subtitle: 'Create, organize, and manage folders',
                    icon: Icons.favorite,
                    iconColor: Colors.pinkAccent,
                    iconBackground: Colors.pinkAccent.withValues(alpha: 0.12),
                    onTap: () =>
                        _navigateToScreen(context, const FavoritesScreen()),
                  ),
                    ],
                  ),
                ],
              ),
            ),
          ]
        
      ),
    );
  }

  // Rest of the code remains the same...
  Widget _buildRepositoryCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
         width: 136.w,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 35.w,
                  height: 35.h,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                height10,
                    Text(
                    title,
                    style:w500_16Poppins()
                  ),
                  const SizedBox(height: 4),
                 
              ],
            ),
          
           
          width10,
          
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey.shade400,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToScreen(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
  }
}
