import 'dart:io';

/// A single scanned page: the untouched camera shot plus the
/// auto-cropped/straightened result derived from it. Keeping [raw] around
/// lets the review screen's "Recrop" action redo the perspective-crop from
/// scratch if the automatic edge detection didn't get it quite right.
class ScannedPage {
  final File raw;
  final File cropped;

  const ScannedPage({required this.raw, required this.cropped});
}
