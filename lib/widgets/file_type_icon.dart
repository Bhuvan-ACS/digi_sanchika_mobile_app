import 'package:flutter/material.dart';

/// Document-type icon backed by the PNGs in `icons/`. Falls back to a
/// generic file glyph for types without a dedicated image.
class FileTypeIcon extends StatelessWidget {
  final String type;
  final double size;

  const FileTypeIcon({super.key, required this.type, this.size = 28});

  /// Returns the asset path for [type] (extension or file name), or null.
  static String? assetFor(String type) {
    var ext = type.toLowerCase().trim();
    if (ext.startsWith('image/')) return 'icons/image-icon.png';
    if (ext.contains('.')) ext = ext.substring(ext.lastIndexOf('.') + 1);
    switch (ext) {
      case 'image':
      case 'images':
      case 'jfif':
      case 'heic':
      case 'tif':
      case 'tiff':
      case 'svg':
        return 'icons/image-icon.png';
      case 'pdf':
        return 'icons/pdf-file.png';
      case 'doc':
      case 'docx':
        return 'icons/docx.png';
      case 'xls':
      case 'xlsx':
      case 'csv':
        return 'icons/xlsx-file.png';
      case 'ppt':
      case 'pptx':
        return 'icons/pptx.png';
      case 'txt':
        return 'icons/txt.png';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
        return 'icons/image-icon.png';
      default:
        return null;
    }
  }

  static bool isVideo(String type) {
    var e = type.toLowerCase().trim();
    if (e.startsWith('video/')) return true;
    if (e.contains('.')) e = e.substring(e.lastIndexOf('.') + 1);
    return const {'mp4', 'm4v', 'mov', 'webm', 'mkv', '3gp', 'video'}
        .contains(e);
  }

  static String? videoAssetFor(String type) =>
      isVideo(type) ? 'icons/video.png' : null;

  /// The image icon for [type] when one exists, otherwise [fallback].
  static Widget orElse(String type, double size, Widget fallback) =>
      assetFor(type) != null || isVideo(type)
          ? FileTypeIcon(type: type, size: size)
          : fallback;

  @override
  Widget build(BuildContext context) {
    final asset = assetFor(type) ?? videoAssetFor(type);
    if (asset == null) {
      if (isVideo(type)) {
        return Icon(Icons.play_circle_fill_rounded,
            size: size, color: const Color(0xFF7C3AED));
      }
      return Icon(Icons.insert_drive_file_rounded,
          size: size, color: Colors.blueGrey);
    }
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(Icons.insert_drive_file_rounded,
          size: size, color: Colors.blueGrey),
    );
  }
}
