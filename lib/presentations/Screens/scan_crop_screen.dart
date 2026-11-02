// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../services/document_edge_detector.dart';

// ---------------------------------------------------------------------------
// DocumentCropScreen
//
// Shown immediately after each shutter press, CamScanner-style:
//   • Auto-detects the document's 4 corners (edge-based heuristic)
//   • Lets the user drag the corners to fit
//   • "Confirm" perspective-warps the quad flat into a straightened page
//     and hands that file back to the camera screen
//   • "Retake" discards the capture and returns to the camera
// ---------------------------------------------------------------------------
class DocumentCropScreen extends StatefulWidget {
  final File imageFile;

  const DocumentCropScreen({super.key, required this.imageFile});

  @override
  State<DocumentCropScreen> createState() => _DocumentCropScreenState();
}

enum _Stage { detecting, ready, warping }

class _DocumentCropScreenState extends State<DocumentCropScreen> {
  _Stage _stage = _Stage.detecting;
  Uint8List? _bytes;
  int _imgW = 0;
  int _imgH = 0;

  // Corners in WIDGET space, order: topLeft, topRight, bottomRight, bottomLeft.
  List<Offset> _corners = const [];

  late Rect _imageRect; // where the image is actually drawn (BoxFit.contain)

  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rawBytes = await widget.imageFile.readAsBytes();
      if (!mounted) return;
      // Show the raw photo immediately — don't make the user stare at a
      // blank/frozen screen for however long edge detection takes. It gets
      // swapped for the orientation-normalized bytes once detection
      // finishes, which is instant enough not to be noticeable.
      setState(() => _bytes = rawBytes);

      final result = await compute(detectDocumentQuad, rawBytes);
      if (!mounted) return;
      setState(() {
        // Use the SAME normalized bytes for display and (later) the warp
        // that detection computed its corners against — otherwise the
        // on-screen photo (and what gets perspective-warped) could disagree
        // with the detected coordinate space if whatever decodes the raw
        // bytes for display handles EXIF orientation differently than the
        // `image` package did when picking the corners.
        _bytes = result.normalizedBytes;
        _imgW = result.width;
        _imgH = result.height;
        _stage = _Stage.ready;
      });
      _seedCornersFromImageSpace(result.corners);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not read that photo: $e';
        _stage = _Stage.ready;
      });
    }
  }

  void _seedCornersFromImageSpace(List<double> c) {
    // Deferred until the image rect is known (first layout pass); stash and
    // apply as soon as _imageRect is computed in build().
    _pendingImageSpaceCorners = c;
  }

  List<double>? _pendingImageSpaceCorners;

  Rect _computeImageRect(Size container) {
    if (_imgW == 0 || _imgH == 0) return Rect.zero;
    final scale = (container.width / _imgW < container.height / _imgH)
        ? container.width / _imgW
        : container.height / _imgH;
    final dispW = _imgW * scale;
    final dispH = _imgH * scale;
    final dx = (container.width - dispW) / 2;
    final dy = (container.height - dispH) / 2;
    return Rect.fromLTWH(dx, dy, dispW, dispH);
  }

  Offset _imageToWidgetScaled(double x, double y) => Offset(
        _imageRect.left + x * (_imageRect.width / _imgW),
        _imageRect.top + y * (_imageRect.height / _imgH),
      );

  Offset _widgetToImage(Offset p) {
    final x = (p.dx - _imageRect.left) * _imgW / _imageRect.width;
    final y = (p.dy - _imageRect.top) * _imgH / _imageRect.height;
    return Offset(x.clamp(0, _imgW.toDouble()), y.clamp(0, _imgH.toDouble()));
  }

  void _applyPendingSeedIfNeeded() {
    final pending = _pendingImageSpaceCorners;
    if (pending == null || _imageRect == Rect.zero) return;
    _pendingImageSpaceCorners = null;
    _corners = [
      _imageToWidgetScaled(pending[0], pending[1]), // tl
      _imageToWidgetScaled(pending[2], pending[3]), // tr
      _imageToWidgetScaled(pending[4], pending[5]), // br
      _imageToWidgetScaled(pending[6], pending[7]), // bl
    ];
  }

  void _resetToFullImage() {
    setState(() {
      _corners = [
        _imageToWidgetScaled(0, 0),
        _imageToWidgetScaled(_imgW.toDouble(), 0),
        _imageToWidgetScaled(_imgW.toDouble(), _imgH.toDouble()),
        _imageToWidgetScaled(0, _imgH.toDouble()),
      ];
    });
  }

  Future<void> _reAutoDetect() async {
    if (_bytes == null) return;
    setState(() => _stage = _Stage.detecting);
    try {
      final result = await compute(detectDocumentQuad, _bytes!);
      if (!mounted) return;
      setState(() {
        _corners = [
          _imageToWidgetScaled(result.corners[0], result.corners[1]),
          _imageToWidgetScaled(result.corners[2], result.corners[3]),
          _imageToWidgetScaled(result.corners[4], result.corners[5]),
          _imageToWidgetScaled(result.corners[6], result.corners[7]),
        ];
        _stage = _Stage.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _stage = _Stage.ready);
      _showSnack('Auto-detect failed: $e');
    }
  }

  void _retake() => Navigator.of(context).pop(null);

  Future<void> _confirm() async {
    if (_bytes == null || _corners.length != 4) return;
    setState(() => _stage = _Stage.warping);
    try {
      final imgCorners = _corners.map(_widgetToImage).toList();
      final args = WarpArgs(_bytes!, [
        imgCorners[0].dx, imgCorners[0].dy, // tl
        imgCorners[1].dx, imgCorners[1].dy, // tr
        imgCorners[2].dx, imgCorners[2].dy, // br
        imgCorners[3].dx, imgCorners[3].dy, // bl
      ]);
      final warped = await compute(warpDocumentQuad, args);

      final tempDir = await getTemporaryDirectory();
      final outFile = File(
        '${tempDir.path}/scan_straight_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await outFile.writeAsBytes(warped);

      if (!mounted) return;
      Navigator.of(context).pop(outFile);
    } catch (e) {
      if (!mounted) return;
      setState(() => _stage = _Stage.ready);
      _showSnack('Could not straighten page: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _retake();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _retake,
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: 'Retake',
                    ),
                    const Spacer(),
                    const Text(
                      'Adjust edges',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(child: _buildBody()),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
      );
    }
    if (_bytes == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      // Recomputed on every build (cheap arithmetic) rather than cached by
      // container-size-equality: the photo now renders before _imgW/_imgH
      // are known (so corner detection doesn't block showing it), and with
      // an equality cache keyed only on container size, the rect never got
      // refreshed once those dimensions actually arrived — leaving the quad
      // overlay stuck at Rect.zero and never seeded.
      _imageRect = _computeImageRect(size);
      _applyPendingSeedIfNeeded();

      return Stack(
        fit: StackFit.expand,
        children: [
          // Shown the instant bytes are read — Flutter decodes/lays this out
          // on its own (BoxFit.contain), so it doesn't wait on our pixel-level
          // edge detection to finish.
          Positioned.fill(
            child: Image.memory(_bytes!, fit: BoxFit.contain),
          ),
          if (_corners.length == 4)
            CustomPaint(
              size: size,
              painter: _QuadPainter(corners: _corners),
            ),
          if (_corners.length == 4)
            for (var i = 0; i < 4; i++) _buildHandle(i),
          if (_stage == _Stage.detecting || _stage == _Stage.warping)
            Container(
              color: Colors.black38,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 12),
                    Text(
                      _stage == _Stage.detecting
                          ? 'Detecting edges…'
                          : 'Straightening…',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _buildHandle(int index) {
    const handleSize = 44.0;
    final p = _corners[index];
    return Positioned(
      left: p.dx - handleSize / 2,
      top: p.dy - handleSize / 2,
      width: handleSize,
      height: handleSize,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (details) {
          setState(() {
            final updated = p + details.delta;
            _corners = List.of(_corners);
            _corners[index] = Offset(
              updated.dx.clamp(_imageRect.left, _imageRect.right),
              updated.dy.clamp(_imageRect.top, _imageRect.bottom),
            );
          });
        },
        child: Center(
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.greenAccent.withOpacity(0.85),
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final busy = _stage != _Stage.ready;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _BottomAction(
            icon: Icons.replay,
            label: 'Reset',
            onTap: busy ? null : _resetToFullImage,
          ),
          _BottomAction(
            icon: Icons.auto_fix_high,
            label: 'Auto',
            onTap: busy ? null : _reAutoDetect,
          ),
          GestureDetector(
            onTap: busy ? null : _confirm,
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 32),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _BottomAction({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final color = disabled ? Colors.white30 : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  final List<Offset> corners; // tl, tr, br, bl

  _QuadPainter({required this.corners});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    final fillPaint = Paint()..color = Colors.greenAccent.withOpacity(0.18);
    canvas.drawPath(path, fillPaint);

    final strokePaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(_QuadPainter oldDelegate) =>
      oldDelegate.corners != corners;
}
