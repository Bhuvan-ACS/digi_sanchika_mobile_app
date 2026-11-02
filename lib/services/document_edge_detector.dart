import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// ---------------------------------------------------------------------------
// Document edge detection + perspective "straightening", CamScanner-style.
//
// Both entry points below are designed to run inside `compute()` (a
// background isolate): they take/return only primitive-safe data (bytes,
// lists of doubles, ints) so Dart can copy them across the isolate boundary
// without issue, and so the (fairly expensive) per-pixel work never blocks
// the UI thread.
// ---------------------------------------------------------------------------

/// Result of [detectDocumentQuad]: the EXIF-orientation-normalized JPEG
/// bytes (see below), its pixel dimensions, and a best-guess document
/// quadrilateral, as 8 values `[tlX, tlY, trX, trY, brX, brY, blX, blY]` —
/// all in that SAME normalized image's pixel space.
class CropDetectResult {
  final Uint8List normalizedBytes;
  final int width;
  final int height;
  final List<double> corners;
  const CropDetectResult(
    this.normalizedBytes,
    this.width,
    this.height,
    this.corners,
  );
}

/// Decodes [bytes], bakes in the EXIF orientation, and returns a re-encoded
/// JPEG plus its dimensions and an auto-detected (or sensibly-defaulted)
/// document corner quad for the crop screen to seed its draggable handles
/// with.
///
/// The crop screen displays and perspective-warps this SAME normalized byte
/// buffer (rather than re-deriving it separately in more than one place) so
/// there's exactly one orientation-correction pass to reason about: the
/// photo on screen, the detected corners, and the final straightened output
/// are all guaranteed to agree on pixel layout. `decodeImage` does NOT
/// rotate pixels for the EXIF orientation tag on its own (camera photos are
/// very often stored sensor-landscape + orientation=6/8) — without baking it
/// in, whatever displays the raw bytes (which may apply EXIF orientation
/// differently, or not at all) can disagree with where we computed the
/// corners to be.
CropDetectResult detectDocumentQuad(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unable to decode captured image');
  }
  final baked = img.bakeOrientation(decoded);
  final normalized = Uint8List.fromList(img.encodeJpg(baked, quality: 95));
  final w = baked.width;
  final h = baked.height;
  final corners = _autoDetectCorners(baked) ?? _fallbackCorners(w, h);
  return CropDetectResult(normalized, w, h, corners);
}

/// A generous inset rectangle used whenever auto-detection can't find a
/// confident document boundary (e.g. low contrast background). The user can
/// still drag the corners to fit before confirming.
List<double> _fallbackCorners(int w, int h) {
  final iw = w * 0.05;
  final ih = h * 0.05;
  return [iw, ih, w - iw, ih, w - iw, h - ih, iw, h - ih]; // tl, tr, br, bl
}

/// Lightweight (pure-Dart, no OpenCV) document-boundary guess:
///   1. Downscale for speed.
/// 2. Sobel edge magnitude on the grayscale image.
///   3. Threshold edges using the image's own mean+stddev (adapts to
///      lighting instead of a fixed constant).
///   4. Pick the 4 extreme edge pixels that maximize/minimize x+y and x-y —
///      the classic "corners of the convex hull" shortcut for a roughly
///      rectangular document against a contrasting background.
/// This is intentionally a starting guess, not a precise contour fit — the
/// crop screen lets the user correct it before the perspective warp runs.
List<double>? _autoDetectCorners(img.Image decoded) {
  const workMax = 480;
  final longSide = math.max(decoded.width, decoded.height);
  final scale = longSide > workMax ? workMax / longSide : 1.0;
  final work = scale < 1.0
      ? img.copyResize(
          decoded,
          width: (decoded.width * scale).round(),
          height: (decoded.height * scale).round(),
        )
      : decoded;

  final edges = img.sobel(img.grayscale(work), amount: 1);
  final w = edges.width;
  final h = edges.height;

  final lums = Float32List(w * h);
  double sum = 0;
  double sumSq = 0;
  var idx = 0;
  for (final p in edges) {
    final l = p.luminanceNormalized.toDouble();
    lums[idx++] = l;
    sum += l;
    sumSq += l * l;
  }
  final n = lums.length;
  if (n == 0) return null;
  final mean = sum / n;
  final variance = math.max(0.0, sumSq / n - mean * mean);
  final threshold = mean + math.sqrt(variance) * 1.1;

  var found = false;
  double bestTL = double.infinity;
  double bestBR = -double.infinity;
  double bestTR = -double.infinity;
  double bestBL = -double.infinity;
  int tlx = 0, tly = 0;
  int brx = w - 1, bry = h - 1;
  int trx = w - 1, tryY = 0;
  int blx = 0, bly = h - 1;

  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      if (lums[row + x] < threshold) continue;
      found = true;
      final s = (x + y).toDouble();
      final d = (x - y).toDouble();
      if (s < bestTL) {
        bestTL = s;
        tlx = x;
        tly = y;
      }
      if (s > bestBR) {
        bestBR = s;
        brx = x;
        bry = y;
      }
      if (d > bestTR) {
        bestTR = d;
        trx = x;
        tryY = y;
      }
      if (-d > bestBL) {
        bestBL = -d;
        blx = x;
        bly = y;
      }
    }
  }

  if (!found) return null;

  final invScale = 1 / scale;
  final quad = [
    tlx * invScale, tly * invScale,
    trx * invScale, tryY * invScale,
    brx * invScale, bry * invScale,
    blx * invScale, bly * invScale,
  ];

  // Reject degenerate/too-small guesses (e.g. detected on a stray shadow)
  // rather than hand the user a useless crop box.
  final area = _quadArea(quad);
  if (area < decoded.width * decoded.height * 0.15) return null;

  return quad;
}

double _quadArea(List<double> q) {
  double area = 0;
  for (var i = 0; i < 4; i++) {
    final x1 = q[i * 2];
    final y1 = q[i * 2 + 1];
    final j = (i + 1) % 4;
    final x2 = q[j * 2];
    final y2 = q[j * 2 + 1];
    area += x1 * y2 - x2 * y1;
  }
  return area.abs() / 2;
}

/// Argument bundle for [warpDocumentQuad] (kept to primitive-safe fields so
/// it can be handed to `compute()`).
class WarpArgs {
  final Uint8List bytes;
  final List<double> corners; // tl, tr, br, bl (x,y pairs), 8 values
  const WarpArgs(this.bytes, this.corners);
}

/// Perspective-corrects (flattens) the document bounded by [WarpArgs.corners]
/// into a straight, cropped page — the actual "scan -> straight page" step.
Uint8List warpDocumentQuad(WarpArgs args) {
  var decoded = img.decodeImage(args.bytes);
  if (decoded == null) {
    throw const FormatException('Unable to decode captured image');
  }
  // Corners were picked against the EXIF-corrected orientation shown on
  // screen (see detectDocumentQuad) — bake it in here too so pixel space
  // matches, or the warp samples from the wrong part of the raw buffer.
  decoded = img.bakeOrientation(decoded);
  final c = args.corners;
  final tl = img.Point(c[0], c[1]);
  final tr = img.Point(c[2], c[3]);
  final br = img.Point(c[4], c[5]);
  final bl = img.Point(c[6], c[7]);

  double dist(img.Point a, img.Point b) =>
      math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2)).toDouble();

  var outW = math.max(dist(tl, tr), dist(bl, br)).round().clamp(50, 1 << 20);
  var outH = math.max(dist(tl, bl), dist(tr, br)).round().clamp(50, 1 << 20);

  // Cap the straightened page's resolution (scaling both sides together, so
  // the page doesn't get stretched). Every filter/rotate edit in the review
  // screen re-decodes and re-encodes this file from scratch, so an
  // uncapped 4000px+ photo made each of those edits noticeably slow.
  // 2200px on the long side is still sharp for on-screen review, printing,
  // and OCR, at a fraction of the processing cost.
  const maxSide = 2200;
  final longSide = math.max(outW, outH);
  if (longSide > maxSide) {
    final scale = maxSide / longSide;
    outW = (outW * scale).round();
    outH = (outH * scale).round();
  }

  final straightened = img.copyRectify(
    decoded,
    topLeft: tl,
    topRight: tr,
    bottomLeft: bl,
    bottomRight: br,
    interpolation: img.Interpolation.linear,
    toImage: img.Image(
      width: outW,
      height: outH,
      numChannels: decoded.numChannels,
    ),
  );

  return Uint8List.fromList(img.encodeJpg(straightened, quality: 92));
}
