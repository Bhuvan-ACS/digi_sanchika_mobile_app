import 'package:flutter/material.dart';
import 'package:digi_sanchika/presentations/Screens/shared_me.dart';
import 'package:digi_sanchika/presentations/Screens/document_library.dart';
import 'package:digi_sanchika/presentations/screens/folder_manager_screen.dart';

class DocumentsHub extends StatelessWidget {
  const DocumentsHub({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Redesigned Header with creative gradient section
          Container(
            padding: const EdgeInsets.only(
              top: 50,
              bottom: 40, // Increased bottom padding
              left: 24,
              right: 24,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white,
                  const Color(0xFFF7FAFF),
                  const Color(0xFFF0F7FF), // Soft blue tint
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade50.withOpacity(0.5),
                  blurRadius: 16,
                  spreadRadius: 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Simplified Title Section without icon
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Main Title with subtle styling
                    Text(
                      'Document Hub',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A237E),
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: 8),
                    // Creative subtitle with gradient accent
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Your central workspace for ',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF5A5A5A),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          TextSpan(
                            text: 'organizational documents',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF1A237E),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Optional: Add a minimal decorative element
                Container(
                  height: 4,
                  width: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF3949AB).withOpacity(0.8),
                        const Color(0xFF7986CB).withOpacity(0.6),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content Area (unchanged except for WORKSPACES label)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              color: Colors.grey.shade50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Section Header
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'WORKSPACES',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Document Library Card
                  _buildRepositoryCard(
                    title: 'Document Library',
                    subtitle: 'Organization-wide public documents',
                    icon: Icons.library_books_rounded,
                    iconColor: const Color(0xFF26A69A),
                    iconBackground: const Color(0xFF26A69A).withOpacity(0.1),
                    onTap: () =>
                        _navigateToScreen(context, const DocumentLibrary()),
                  ),

                  const SizedBox(height: 16),

                  // Shared Documents Card
                  _buildRepositoryCard(
                    title: 'Shared with Me',
                    subtitle: 'Team documents shared directly with you',
                    icon: Icons.group_rounded,
                    iconColor: const Color(0xFF7E57C2),
                    iconBackground: const Color(0xFF7E57C2).withOpacity(0.1),
                    onTap: () =>
                        _navigateToScreen(context, const SharedMeScreen()),
                  ),

                  const SizedBox(height: 16),

                  // Folders Card
                  _buildRepositoryCard(
                    title: 'Folders',
                    subtitle: 'Create, organize, and manage folders',
                    icon: Icons.folder_rounded,
                    iconColor: const Color(0xFFFFA000),
                    iconBackground: const Color(0xFFFFA000).withOpacity(0.12),
                    onTap: () =>
                        _navigateToScreen(context, const FolderManagerScreen()),
                  ),
                ],
              ),
            ),
          ),
        ],
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade400,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToScreen(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
  }
}
