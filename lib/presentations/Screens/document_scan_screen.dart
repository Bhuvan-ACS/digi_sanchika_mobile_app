// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'scan_review_screen.dart';

/// ---------------------------------------------------------------------------
/// DocumentScanScreen
///
/// CamScanner-like scan flow:
///   1. Live camera preview with animated corner-guide overlay
///   2. Tap shutter to capture (auto-saved to temp)
///   3. Multi-page: keep capturing; thumbnail strip shows captured pages
///   4. "Review" navigates to ScanReviewScreen
///
/// Required packages (add to pubspec.yaml):
///   camera: ^0.11.0+2
///   path_provider: ^2.1.2
///   image: ^4.1.7            ← image manipulation (filters, rotate)
///   pdf: ^3.10.8             ← assemble scanned pages into a PDF
///   printing: ^5.12.0        ← PDF preview (optional)
/// ---------------------------------------------------------------------------
class DocumentScanScreen extends StatefulWidget {
  final Function(File) onScannedFileReady;
  final List<dynamic> folders; // your Folder model list
  final String? userName;

  const DocumentScanScreen({
    super.key,
    required this.onScannedFileReady,
    required this.folders,
    this.userName,
  });

  @override
  State<DocumentScanScreen> createState() => _DocumentScanScreenState();
}

class _DocumentScanScreenState extends State<DocumentScanScreen>
    with TickerProviderStateMixin {
  // ── Camera ──────────────────────────────────────────────────────────────
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isCameraReady = false;
  bool _isCapturing = false;
  FlashMode _flashMode = FlashMode.off;
  bool _isAutoMode = true; // auto edge-detect hint

  // ── Captured pages ──────────────────────────────────────────────────────
  final List<File> _capturedPages = [];

  // ── Animations ──────────────────────────────────────────────────────────
  late AnimationController _scanLineController;
  late Animation<double> _scanLineAnimation;
  late AnimationController _shutterController;
  late Animation<double> _shutterScale;

  // ── Corner guide animation ───────────────────────────────────────────────
  late AnimationController _cornerPulseController;
  late Animation<double> _cornerPulse;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initCamera();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  void _initAnimations() {
    // Scan-line sweeps up and down
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scanLineAnimation = Tween<double>(begin: 0.1, end: 0.9).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOut),
    );

    // Shutter press feedback
    _shutterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _shutterScale = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _shutterController, curve: Curves.easeOut),
    );

    // Corner guides gently pulse
    _cornerPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _cornerPulse = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _cornerPulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _showError('No camera found on this device');
        return;
      }

      // Prefer back camera
      final back = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      await _controller!.setFlashMode(FlashMode.off);
      await _controller!.setFocusMode(FocusMode.auto);

      if (mounted) setState(() => _isCameraReady = true);
    } catch (e) {
      _showError('Camera initialisation failed: $e');
    }
  }

  // ── Flash cycle ──────────────────────────────────────────────────────────
  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    final next = _flashMode == FlashMode.off
        ? FlashMode.torch
        : _flashMode == FlashMode.torch
        ? FlashMode.auto
        : FlashMode.off;
    await _controller!.setFlashMode(next);
    setState(() => _flashMode = next);
  }

  IconData get _flashIcon {
    switch (_flashMode) {
      case FlashMode.torch:
        return Icons.flash_on;
      case FlashMode.auto:
        return Icons.flash_auto;
      default:
        return Icons.flash_off;
    }
  }

  // ── Capture ──────────────────────────────────────────────────────────────
  Future<void> _capture() async {
    if (_isCapturing || _controller == null || !_isCameraReady) return;
    setState(() => _isCapturing = true);

    // Shutter animation
    await _shutterController.forward();
    await _shutterController.reverse();

    try {
      final xFile = await _controller!.takePicture();
      final tempDir = await getTemporaryDirectory();
      final dest = File(
        '${tempDir.path}/scan_page_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await File(xFile.path).copy(dest.path);

      setState(() {
        _capturedPages.add(dest);
        _isCapturing = false;
      });

      // Brief white-flash feedback
      _showCaptureFlash();
    } catch (e) {
      setState(() => _isCapturing = false);
      _showError('Capture failed: $e');
    }
  }

  void _showCaptureFlash() {
    // Overlay a white flash for 150 ms via an overlay entry
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: Container(color: Colors.white.withOpacity(0.6)),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 150), entry.remove);
  }

  // ── Review ────────────────────────────────────────────────────────────────
  void _openReview() {
    if (_capturedPages.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScanReviewScreen(
          pages: List<File>.from(_capturedPages),
          folders: widget.folders,
          userName: widget.userName,
          onSaved: (File savedFile) {
            widget.onScannedFileReady(savedFile);
            Navigator.of(context).popUntil((r) => r.isFirst);
          },
        ),
      ),
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _shutterController.dispose();
    _cornerPulseController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview ──────────────────────────────────────────────
          if (_isCameraReady && _controller != null)
            _CameraPreviewFit(controller: _controller!)
          else
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Initialising camera…',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),

          // ── Edge-detection overlay ──────────────────────────────────────
          if (_isCameraReady) _buildScanOverlay(),

          // ── Top bar ─────────────────────────────────────────────────────
          _buildTopBar(),

          // ── Bottom controls ─────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomBar(),
          ),
        ],
      ),
    );
  }

  // ── Scan overlay (corners + scan-line) ───────────────────────────────────
  Widget _buildScanOverlay() {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = box.maxHeight;

      // Guide rectangle centred in camera feed
      const hPad = 28.0;
      const vPad = 100.0;
      final rx = hPad;
      final ry = vPad;
      final rw = w - hPad * 2;
      final rh = h - vPad * 2 - 160; // leave space for bottom bar

      return Stack(
        children: [
          // Semi-transparent mask outside the guide rect
          CustomPaint(
            size: Size(w, h),
            painter: _ScanMaskPainter(
              rect: Rect.fromLTWH(rx, ry, rw, rh),
            ),
          ),

          // Corner guides
          AnimatedBuilder(
            animation: _cornerPulse,
            builder: (_, __) => CustomPaint(
              size: Size(w, h),
              painter: _CornerGuidesPainter(
                rect: Rect.fromLTWH(rx, ry, rw, rh),
                opacity: _cornerPulse.value,
                color: _capturedPages.isNotEmpty
                    ? Colors.green
                    : Colors.white,
              ),
            ),
          ),

          // Scan line
          if (_isAutoMode)
            AnimatedBuilder(
              animation: _scanLineAnimation,
              builder: (_, __) {
                final lineY = ry + rh * _scanLineAnimation.value;
                return Positioned(
                  left: rx + 8,
                  right: w - rx - rw + 8,
                  top: lineY,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.greenAccent.withOpacity(0.9),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

          // Hint label
          Positioned(
            left: rx,
            right: w - rx - rw,
            top: ry + rh + 8,
            child: Text(
              _isAutoMode
                  ? 'Auto • Align document inside frame'
                  : 'Manual mode',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    });
  }

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              // Close
              _IconBtn(
                icon: Icons.close,
                onTap: () => Navigator.pop(context),
              ),
              const Spacer(),
              // Auto / Manual toggle
              _LabelBtn(
                label: _isAutoMode ? 'Auto' : 'Manual',
                onTap: () => setState(() => _isAutoMode = !_isAutoMode),
              ),
              const SizedBox(width: 8),
              // Flash
              _IconBtn(icon: _flashIcon, onTap: _toggleFlash),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom bar ────────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Thumbnail strip of captured pages
          if (_capturedPages.isNotEmpty) _buildThumbnailStrip(),
          const SizedBox(height: 16),

          // Bottom row: cancel | shutter | review
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Gallery / last page button
              _buildLastPageThumb(),

              // Shutter button
              _buildShutter(),

              // Review / done button
              _buildReviewBtn(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailStrip() {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _capturedPages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          return GestureDetector(
            onTap: _openReview,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    _capturedPages[i],
                    width: 44,
                    height: 62,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLastPageThumb() {
    if (_capturedPages.isEmpty) {
      return const SizedBox(width: 56);
    }
    return GestureDetector(
      onTap: _openReview,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              _capturedPages.last,
              width: 48,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${_capturedPages.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShutter() {
    return GestureDetector(
      onTap: _capture,
      child: ScaleTransition(
        scale: _shutterScale,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          padding: const EdgeInsets.all(4),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isCapturing ? Colors.grey : Colors.white,
            ),
            child: _isCapturing
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildReviewBtn() {
    return GestureDetector(
      onTap: _capturedPages.isEmpty ? null : _openReview,
      child: Opacity(
        opacity: _capturedPages.isEmpty ? 0.35 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green,
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.4),
                    blurRadius: 10,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 4),
            const Text(
              'Review',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Camera preview that fills the screen properly ────────────────────────────
class _CameraPreviewFit extends StatelessWidget {
  final CameraController controller;
  const _CameraPreviewFit({required this.controller});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      final previewRatio = controller.value.aspectRatio;
      double scale = size.width / size.height * previewRatio;
      if (scale < 1) scale = 1 / scale;
      return ClipRect(
        child: Transform.scale(
          scale: scale,
          child: Center(child: CameraPreview(controller)),
        ),
      );
    });
  }
}

// ── Painters ─────────────────────────────────────────────────────────────────
class _ScanMaskPainter extends CustomPainter {
  final Rect rect;
  _ScanMaskPainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.55);
    final full = Rect.fromLTWH(0, 0, size.width, size.height);
    final path = Path()
      ..addRect(full)
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ScanMaskPainter old) => old.rect != rect;
}

class _CornerGuidesPainter extends CustomPainter {
  final Rect rect;
  final double opacity;
  final Color color;
  _CornerGuidesPainter({
    required this.rect,
    required this.opacity,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const len = 22.0;
    final l = rect.left;
    final t = rect.top;
    final r = rect.right;
    final b = rect.bottom;

    // Top-left
    canvas.drawLine(Offset(l, t + len), Offset(l, t), paint);
    canvas.drawLine(Offset(l, t), Offset(l + len, t), paint);
    // Top-right
    canvas.drawLine(Offset(r - len, t), Offset(r, t), paint);
    canvas.drawLine(Offset(r, t), Offset(r, t + len), paint);
    // Bottom-left
    canvas.drawLine(Offset(l, b - len), Offset(l, b), paint);
    canvas.drawLine(Offset(l, b), Offset(l + len, b), paint);
    // Bottom-right
    canvas.drawLine(Offset(r - len, b), Offset(r, b), paint);
    canvas.drawLine(Offset(r, b), Offset(r, b - len), paint);
  }

  @override
  bool shouldRepaint(_CornerGuidesPainter old) =>
      old.opacity != opacity || old.color != color;
}

// ── Small reusable button widgets ─────────────────────────────────────────────
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black38,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _LabelBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _LabelBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white38),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }
}