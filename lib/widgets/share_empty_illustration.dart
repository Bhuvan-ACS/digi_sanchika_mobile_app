import 'package:flutter/material.dart';

/// "Person → document" mark used by the empty states of the Shared tabs.
class ShareEmptyIllustration extends StatelessWidget {
  const ShareEmptyIllustration({super.key, this.size = 64});

  /// Height of the person and document glyphs.
  final double size;

  static const _blue = Color(0xFF0866E9);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.person_rounded, size: size, color: _blue),
        Icon(Icons.arrow_forward_rounded, size: size * 0.45, color: _blue),
        Icon(Icons.insert_drive_file_outlined, size: size * 0.9, color: _blue),
      ],
    );
  }
}
