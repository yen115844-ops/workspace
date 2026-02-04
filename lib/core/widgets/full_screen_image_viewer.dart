import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:ionicons/ionicons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

/// Full-screen image viewer with zoom capabilities
/// Supports:
/// - Double-tap to zoom in/out
/// - Pinch to zoom
/// - Drag to pan
/// - Swipe down to close
/// - Multiple images gallery
class FullScreenImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final String? heroTag;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
    this.heroTag,
  });

  /// Show single image
  static void show(BuildContext context, String imageUrl, {String? heroTag}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FullScreenImageViewer(
            imageUrls: [imageUrl],
            initialIndex: 0,
            heroTag: heroTag,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  /// Show gallery with multiple images
  static void showGallery(
    BuildContext context,
    List<String> imageUrls, {
    int initialIndex = 0,
    String? heroTag,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FullScreenImageViewer(
            imageUrls: imageUrls,
            initialIndex: initialIndex,
            heroTag: heroTag,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;
  bool _isZoomed = false;
  double _verticalDragOffset = 0;
  bool _isDragging = false;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    // Hide system UI for immersive experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _pageController.dispose();
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _onScaleStateChanged(PhotoViewScaleState scaleState) {
    setState(() {
      _isZoomed = scaleState != PhotoViewScaleState.initial;
    });
  }

  /// Download current image and save to gallery
  Future<void> _downloadImage() async {
    if (_isDownloading) return;
    
    final imageUrl = widget.imageUrls[_currentIndex];
    
    setState(() => _isDownloading = true);
    
    try {
      // Request permission to save to gallery
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cần cấp quyền để lưu ảnh vào thư viện'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }
      
      // Download image from network
      final dio = Dio();
      final response = await dio.get<List<int>>(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      
      if (response.data == null) {
        throw Exception('Không thể tải ảnh');
      }
      
      // Generate filename from URL or use timestamp
      String filename = imageUrl.split('/').last.split('?').first;
      if (!filename.contains('.')) {
        filename = 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
      }
      
      // Save to temporary file first
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$filename';
      final file = File(tempPath);
      await file.writeAsBytes(Uint8List.fromList(response.data!));
      
      // Save to gallery
      await Gal.putImage(tempPath, album: 'WorkChat');
      
      // Clean up temp file
      if (await file.exists()) {
        await file.delete();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã lưu ảnh vào thư viện'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi lưu ảnh: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  void _handleVerticalDragStart(DragStartDetails details) {
    if (!_isZoomed) {
      setState(() {
        _isDragging = true;
      });
    }
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isZoomed && _isDragging) {
      setState(() {
        _verticalDragOffset += details.delta.dy;
      });
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (!_isZoomed && _isDragging) {
      // Close if dragged more than 100 pixels
      if (_verticalDragOffset.abs() > 100) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _verticalDragOffset = 0;
          _isDragging = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMultiple = widget.imageUrls.length > 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onVerticalDragStart: _handleVerticalDragStart,
        onVerticalDragUpdate: _handleVerticalDragUpdate,
        onVerticalDragEnd: _handleVerticalDragEnd,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          transform: Matrix4.translationValues(0, _verticalDragOffset, 0),
          child: Stack(
            children: [
              // Image Gallery
              if (isMultiple)
                PhotoViewGallery.builder(
                  scrollPhysics: _isZoomed
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  builder: (context, index) {
                    final imageUrl = widget.imageUrls[index];
                    return PhotoViewGalleryPageOptions(
                      imageProvider: NetworkImage(imageUrl),
                      initialScale: PhotoViewComputedScale.contained,
                      minScale: PhotoViewComputedScale.contained,
                      maxScale: PhotoViewComputedScale.covered * 3,
                      heroAttributes: widget.heroTag != null && index == widget.initialIndex
                          ? PhotoViewHeroAttributes(tag: widget.heroTag!)
                          : null,
                      onScaleEnd: (context, details, controllerValue) {
                        _onScaleStateChanged(
                          controllerValue.scale! > 1.0
                              ? PhotoViewScaleState.zoomedIn
                              : PhotoViewScaleState.initial,
                        );
                      },
                    );
                  },
                  itemCount: widget.imageUrls.length,
                  loadingBuilder: (context, event) => Center(
                    child: CircularProgressIndicator(
                      value: event == null
                          ? null
                          : event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1),
                      color: Colors.white,
                    ),
                  ),
                  backgroundDecoration: const BoxDecoration(color: Colors.transparent),
                  pageController: _pageController,
                  onPageChanged: _onPageChanged,
                )
              else
                Center(
                  child: PhotoView(
                    imageProvider: NetworkImage(widget.imageUrls.first),
                    initialScale: PhotoViewComputedScale.contained,
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 3,
                    backgroundDecoration: const BoxDecoration(color: Colors.transparent),
                    heroAttributes: widget.heroTag != null
                        ? PhotoViewHeroAttributes(tag: widget.heroTag!)
                        : null,
                    loadingBuilder: (context, event) => Center(
                      child: CircularProgressIndicator(
                        value: event == null
                            ? null
                            : event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1),
                        color: Colors.white,
                      ),
                    ),
                    onScaleEnd: (context, details, controllerValue) {
                      _onScaleStateChanged(
                        controllerValue.scale! > 1.0
                            ? PhotoViewScaleState.zoomedIn
                            : PhotoViewScaleState.initial,
                      );
                    },
                  ),
                ),

              // Close button
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Ionicons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),

              // Download button
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                child: GestureDetector(
                  onTap: _isDownloading ? null : _downloadImage,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: _isDownloading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Ionicons.download_outline,
                            color: Colors.white,
                            size: 24,
                          ),
                  ),
                ),
              ),

              // Page indicator for gallery
              if (isMultiple)
                Positioned(
                  bottom: MediaQuery.of(context).padding.bottom + 24,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_currentIndex + 1} / ${widget.imageUrls.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),

              // Zoom hint (show briefly on first open)
              if (!_isZoomed)
                Positioned(
                  bottom: MediaQuery.of(context).padding.bottom + (isMultiple ? 70 : 24),
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Ionicons.finger_print_outline, color: Colors.white70, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Nhấn 2 lần hoặc kéo để phóng to',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
