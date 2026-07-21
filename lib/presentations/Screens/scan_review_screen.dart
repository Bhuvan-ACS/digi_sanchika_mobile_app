// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'scan_save_screen.dart';

// ---------------------------------------------------------------------------
// ScanReviewScreen
//
// CamScanner-like review step:
//   • Page-by-page viewer (swipe left/right)
//   • Filter toolbar: Color | Grayscale | Black & White
//   • Rotate 90° CW / CCW
//   • Delete a page
//   • Reorder via drag-and-drop thumbnail strip
//   • "Add more" pops back to camera
//   • "Save" opens ScanSaveScreen
// ---------------------------------------------------------------------------
class ScanReviewScreen extends StatefulWidget {
  final List<File> pages;
  final List<dynamic> folders;
  final String? userName;
  final Function(File) onSaved;

  const ScanReviewScreen({
    super.key,
    required this.pages,
    required this.folders,
    required this.onSaved,
    this.userName,
  });

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

enum ScanFilter { color, grayscale, blackWhite }

class _PageState {
  File file;
  ScanFilter filter;
  int rotation; // degrees: 0 | 90 | 180 | 270
  bool isProcessing;

  _PageState({
    required this.file,
    this.filter = ScanFilter.color,
    this.rotation = 0,
    this.isProcessing = false,
  });
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  late List<_PageState> _pages;
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pages = widget.pages.map((f) => _PageState(file: f)).toList();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ── Filter application ─────────────────────────────────────────────────
  Future<void> _applyFilter(int index, ScanFilter filter) async {
    if (_pages[index].filter == filter) return;
    setState(() => _pages[index].isProcessing = true);

    try {
      final processed = await _processImage(
        _pages[index].file,
        filter,
        _pages[index].rotation,
      );
      setState(() {
        _pages[index].file = processed;
        _pages[index].filter = filter;
        _pages[index].isProcessing = false;
      });
    } catch (e) {
      setState(() => _pages[index].isProcessing = false);
      _showSnack('Filter error: $e');
    }
  }

  // ── Rotation ───────────────────────────────────────────────────────────
  Future<void> _rotate(int index, int degrees) async {
    setState(() => _pages[index].isProcessing = true);
    try {
      final newRotation = (_pages[index].rotation + degrees) % 360;
      final processed = await _processImage(
        _pages[index].file,
        _pages[index].filter,
        newRotation,
      );
      setState(() {
        _pages[index].file = processed;
        _pages[index].rotation = newRotation;
        _pages[index].isProcessing = false;
      });
    } catch (e) {
      setState(() => _pages[index].isProcessing = false);
      _showSnack('Rotate error: $e');
    }
  }

  // ── Image processing ───────────────────────────────────────────────────
  Future<File> _processImage(
    File source,
    ScanFilter filter,
    int rotation,
  ) async {
    final bytes = await source.readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return source;

    // Apply rotation
    if (rotation == 90) {
      image = img.copyRotate(image, angle: 90);
    } else if (rotation == 180) {
      image = img.copyRotate(image, angle: 180);
    } else if (rotation == 270) {
      image = img.copyRotate(image, angle: 270);
    }

    // Apply filter
    switch (filter) {
      case ScanFilter.grayscale:
        image = img.grayscale(image);
        break;
      case ScanFilter.blackWhite:
        image = img.grayscale(image);
        // Threshold for B&W
        for (int y = 0; y < image.height; y++) {
          for (int x = 0; x < image.width; x++) {
            final pixel = image.getPixel(x, y);
            final lum = img.getLuminance(pixel);
            final bw = lum > 128 ? 255 : 0;
            image.setPixelRgba(x, y, bw, bw, bw, 255);
          }
        }
        break;
      case ScanFilter.color:
        // Boost contrast slightly for scanned docs
        image = img.adjustColor(image, contrast: 1.15, brightness: 0.02);
        break;
    }

    final tempDir = await getTemporaryDirectory();
    final outFile = File(
      '${tempDir.path}/scan_processed_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await outFile.writeAsBytes(img.encodeJpg(image, quality: 92));
    return outFile;
  }

  // ── Delete page ────────────────────────────────────────────────────────
  void _deletePage(int index) {
    if (_pages.length == 1) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete last page?'),
          content: const Text(
            'This is the only scanned page. Deleting it will close the review screen.',
          ),
          actions: [
            TextButton(
              onPressed: Navigator.of(context).pop,
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // back to camera
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _pages.removeAt(index);
      _currentIndex = _currentIndex.clamp(0, _pages.length - 1);
    });
    _pageController.jumpToPage(_currentIndex);
  }

  // ── Proceed to save ────────────────────────────────────────────────────
  void _proceed() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScanSaveScreen(
          pages: _pages.map((p) => p.file).toList(),
          folders: widget.folders,
          userName: widget.userName,
          onSaved: widget.onSaved,
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final page = _pages[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // ── Page viewer ─────────────────────────────────────────────
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (_, i) => _buildPageView(i),
            ),
          ),

          // ── Filter toolbar ──────────────────────────────────────────
          _buildFilterBar(page),

          // ── Edit toolbar ────────────────────────────────────────────
          _buildEditBar(),

          // ── Thumbnail strip ─────────────────────────────────────────
          _buildThumbnailStrip(),
        ],
      ),

      // ── FAB: Save ──────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _proceed,
        backgroundColor: Colors.green,
        icon: const Icon(Icons.save_alt, color: Colors.white),
        label: Text(
          'Save  (${_pages.length} page${_pages.length > 1 ? 's' : ''})',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(
        'Review  ${_currentIndex + 1} / ${_pages.length}',
        style: const TextStyle(fontSize: 16),
      ),
      actions: [
        // Add more pages (pop back to camera)
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.add_a_photo_outlined),
          tooltip: 'Add more pages',
        ),
        // Delete current page
        IconButton(
          onPressed: () => _deletePage(_currentIndex),
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          tooltip: 'Delete page',
        ),
      ],
    );
  }

  Widget _buildPageView(int index) {
    final page = _pages[index];
    return Stack(
      fit: StackFit.expand,
      children: [
        InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: Image.file(
              page.file,
              fit: BoxFit.contain,
            ),
          ),
        ),
        // Processing overlay
        if (page.isProcessing)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 12),
                  Text('Processing…', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFilterBar(_PageState page) {
    return Container(
      color: Colors.grey.shade900,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        children: [
          const Text(
            'Filter:',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(width: 12),
          _FilterChip(
            label: 'Color',
            icon: Icons.color_lens_outlined,
            selected: page.filter == ScanFilter.color,
            color: Colors.blue,
            onTap: () => _applyFilter(_currentIndex, ScanFilter.color),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Gray',
            icon: Icons.tonality,
            selected: page.filter == ScanFilter.grayscale,
            color: Colors.grey,
            onTap: () => _applyFilter(_currentIndex, ScanFilter.grayscale),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'B&W',
            icon: Icons.contrast,
            selected: page.filter == ScanFilter.blackWhite,
            color: Colors.white,
            onTap: () => _applyFilter(_currentIndex, ScanFilter.blackWhite),
          ),
        ],
      ),
    );
  }

  Widget _buildEditBar() {
    return Container(
      color: Colors.grey.shade800,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _EditButton(
            icon: Icons.rotate_left,
            label: 'Rotate L',
            onTap: () => _rotate(_currentIndex, 270),
          ),
          _EditButton(
            icon: Icons.rotate_right,
            label: 'Rotate R',
            onTap: () => _rotate(_currentIndex, 90),
          ),
          _EditButton(
            icon: Icons.flip,
            label: 'Flip',
            onTap: () => _rotate(_currentIndex, 180),
          ),
          _EditButton(
            icon: Icons.delete_outline,
            label: 'Delete',
            color: Colors.redAccent,
            onTap: () => _deletePage(_currentIndex),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailStrip() {
    return Container(
      height: 100,
      color: Colors.black,
      padding: const EdgeInsets.only(bottom: 70, top: 8), // space for FAB
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _pages.length,
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex--;
            final item = _pages.removeAt(oldIndex);
            _pages.insert(newIndex, item);
            _currentIndex = newIndex;
          });
          _pageController.jumpToPage(_currentIndex);
        },
        itemBuilder: (_, i) {
          final selected = i == _currentIndex;
          return GestureDetector(
            key: ValueKey(_pages[i].file.path),
            onTap: () {
              setState(() => _currentIndex = i);
              _pageController.animateToPage(
                i,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 52,
              margin: EdgeInsets.symmetric(
                horizontal: selected ? 5 : 3,
                vertical: selected ? 0 : 4,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected ? Colors.green : Colors.white30,
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Image.file(
                      _pages[i].file,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    bottom: 2,
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
            ),
          );
        },
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.white24,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? color : Colors.white54, size: 14),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : Colors.white54,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _EditButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(color: c, fontSize: 10)),
        ],
      ),
    );
  }
}