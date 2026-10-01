import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

class AndroidMediaPickerService {
  static const MethodChannel _channel = MethodChannel(
    'digi_sanchika/media_picker',
  );

  static Future<List<PlatformFile>> pickImages({
    required bool allowMultiple,
  }) {
    return _pickMedia(mediaType: 'image', allowMultiple: allowMultiple);
  }

  static Future<List<PlatformFile>> pickVideos({
    required bool allowMultiple,
  }) {
    return _pickMedia(mediaType: 'video', allowMultiple: allowMultiple);
  }

  static Future<List<PlatformFile>> _pickMedia({
    required String mediaType,
    required bool allowMultiple,
  }) async {
    final selected = await _channel.invokeMethod<List<dynamic>>('pickMedia', {
      'mediaType': mediaType,
      'allowMultiple': allowMultiple,
    });

    return (selected ?? const <dynamic>[]).map((item) {
      final map = Map<dynamic, dynamic>.from(item as Map<dynamic, dynamic>);
      final name = map['name']?.toString() ?? 'selected_media';
      final path = map['path']?.toString();
      final sizeValue = map['size'];
      final size = sizeValue is int
          ? sizeValue
          : int.tryParse(sizeValue?.toString() ?? '') ?? 0;

      return PlatformFile(
        name: name,
        size: size,
        path: path,
      );
    }).toList();
  }
}