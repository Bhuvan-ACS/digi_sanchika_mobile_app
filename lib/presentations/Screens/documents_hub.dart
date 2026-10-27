import 'package:digi_sanchika/utils/app_fonts.dart';
import 'package:flutter/material.dart';

class DocumentsHub extends StatefulWidget {
  final VoidCallback onViewAll;

  const DocumentsHub({super.key,required this.onViewAll});

  @override
  State<DocumentsHub> createState() => _DocumentsHubState();
}

class _DocumentsHubState extends State<DocumentsHub> {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade100,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Text(
        'SPACES',
        style: w600_16Poppins(color: Colors.grey.shade500),
      ),
    );
  }

}
