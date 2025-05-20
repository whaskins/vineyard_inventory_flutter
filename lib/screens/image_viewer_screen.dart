import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import '../services/api/authenticated_image.dart';

class ImageViewerScreen extends StatefulWidget {
  final String? imageUrl;
  final String? imagePath;
  final String title;

  const ImageViewerScreen({
    Key? key,
    this.imageUrl,
    this.imagePath,
    this.title = 'Image Viewer',
  }) : super(key: key);

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  final TransformationController _transformationController = TransformationController();
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    // Hide status bar when entering full screen viewer
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  }

  @override
  void dispose() {
    // Restore status bar when leaving full screen viewer
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    super.dispose();
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      if (_isFullScreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      }
    });
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final Widget imageWidget;
    
    if (widget.imageUrl != null) {
      // Network image with authentication
      imageWidget = AuthenticatedNetworkImage(
        url: widget.imageUrl!,
        fit: BoxFit.contain,
      );
    } else if (widget.imagePath != null) {
      // Local file image
      imageWidget = Image.file(
        File(widget.imagePath!),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                Text(
                  'Failed to load image\n$error',
                  style: TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      );
    } else {
      // No image source provided
      imageWidget = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported, color: Colors.grey, size: 64),
            const SizedBox(height: 16),
            Text(
              'No image source provided',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullScreen 
          ? null 
          : AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(widget.title),
              actions: [
                IconButton(
                  icon: Icon(Icons.fullscreen),
                  onPressed: _toggleFullScreen,
                  tooltip: 'Toggle fullscreen',
                ),
                IconButton(
                  icon: Icon(Icons.refresh),
                  onPressed: _resetZoom,
                  tooltip: 'Reset zoom',
                ),
              ],
            ),
      body: GestureDetector(
        onTap: _toggleFullScreen,
        child: Stack(
          children: [
            // Zoomable and pannable image
            InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Hero(
                  tag: widget.imageUrl ?? widget.imagePath ?? 'image',
                  child: imageWidget,
                ),
              ),
            ),
            // Overlay UI when in fullscreen mode
            if (_isFullScreen)
              Positioned(
                top: 20,
                right: 20,
                child: SafeArea(
                  child: IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            if (_isFullScreen)
              Positioned(
                bottom: 20,
                right: 20,
                child: Row(
                  children: [
                    FloatingActionButton(
                      mini: true,
                      backgroundColor: Colors.black.withOpacity(0.6),
                      foregroundColor: Colors.white,
                      child: Icon(Icons.refresh),
                      onPressed: _resetZoom,
                      tooltip: 'Reset zoom',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}