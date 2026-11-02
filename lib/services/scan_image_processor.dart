import 'dart:typed_data';

import 'package:image/image.dart' as img;

// ---------------------------------------------------------------------------
// Scan page filter/rotation processing — runs inside `compute()` (a
// background isolate) so the review screen's UI thread never blocks on the
// decode/rotate/filter/encode pixel work. All inputs/outputs are
// primitive-safe (bytes, ints) so Dart can copy them across the isolate
// boundary.
// ---------------------------------------------------------------------------

/// Filter kinds, mirrored as plain ints (rather than passing the review
/// screen's enum across the isolate boundary) to keep this fully decoupled.
const int scanFilterColor = 0;
const int scanFilterGrayscale = 1;
const int scanFilterBlackWhite = 2;

class ScanProcessArgs {
  final Uint8List bytes;
  final int filter; // scanFilterColor | scanFilterGrayscale | scanFilterBlackWhite
  final int rotationDegrees; // 0 | 90 | 180 | 270

  const ScanProcessArgs(this.bytes, this.filter, this.rotationDegrees);
}

/// Applies rotation + filter to the source image bytes and returns a
/// re-encoded JPEG. Intended to always be called with the *original*,
/// untouched page capture (see ScanReviewScreen) so repeated edits stay
/// reversible instead of compounding on top of a previous edit's output.
Uint8List processScanImage(ScanProcessArgs args) {
  img.Image? image = img.decodeImage(args.bytes);
  if (image == null) {
    throw const FormatException('Unable to decode scanned page');
  }

  switch (args.rotationDegrees) {
    case 90:
      image = img.copyRotate(image, angle: 90);
      break;
    case 180:
      image = img.copyRotate(image, angle: 180);
      break;
    case 270:
      image = img.copyRotate(image, angle: 270);
      break;
  }

  switch (args.filter) {
    case scanFilterGrayscale:
      image = img.grayscale(image);
      break;
    case scanFilterBlackWhite:
      image = img.grayscale(image);
      for (final p in image) {
        final bw = p.luminanceNormalized > 0.5 ? 255 : 0;
        p
          ..r = bw
          ..g = bw
          ..b = bw;
      }
      break;
    case scanFilterColor:
    default:
      // Boost contrast slightly for scanned docs.
      image = img.adjustColor(image, contrast: 1.15, brightness: 0.02);
      break;
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}
