// lib/utils/file_type_detector.dart
enum FileCategory {
  pdf,
  image,
  video,
  audio,
  word,
  excel,
  powerpoint,
  text,
  code,
  other,
}

class FileTypeDetector {
  static FileCategory getCategory(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();

    if (['pdf'].contains(ext)) return FileCategory.pdf;
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp'].contains(ext))
      return FileCategory.image;
    if (['mp4', 'avi', 'mov', 'mkv'].contains(ext)) return FileCategory.video;
    if (['mp3', 'wav', 'aac'].contains(ext)) return FileCategory.audio;
    if (['doc', 'docx'].contains(ext)) return FileCategory.word;
    if (['xls', 'xlsx'].contains(ext)) return FileCategory.excel;
    if (['ppt', 'pptx'].contains(ext)) return FileCategory.powerpoint;
    if (['txt', 'rtf'].contains(ext)) return FileCategory.text;
    if (['dart', 'js', 'py', 'java', 'cpp', 'html', 'css'].contains(ext))
      return FileCategory.code;

    return FileCategory.other;
  }
}
