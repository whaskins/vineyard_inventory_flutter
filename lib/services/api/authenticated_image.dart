import 'package:flutter/material.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'dart:async';
import '../api/api_service.dart';

class AuthenticatedNetworkImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final double width;
  final double height;

  const AuthenticatedNetworkImage({
    Key? key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width = double.infinity,
    this.height = double.infinity,
  }) : super(key: key);

  @override
  _AuthenticatedNetworkImageState createState() => _AuthenticatedNetworkImageState();
}

class _AuthenticatedNetworkImageState extends State<AuthenticatedNetworkImage> {
  final ApiService _apiService = ApiService();
  Uint8List? _imageBytes;
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get auth headers from ApiService
      final headers = _apiService.getAuthHeaders();
      print('DEBUG: Loading authenticated image from: ${widget.url}');
      print('DEBUG: Using headers: $headers');

      // Make HTTP request with auth headers
      final response = await http.get(
        Uri.parse(widget.url),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      print('DEBUG: Image response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        if (!mounted) return;
        
        setState(() {
          _imageBytes = response.bodyBytes;
          _isLoading = false;
        });
      } else if (response.statusCode == 401) {
        if (!mounted) return;
        
        setState(() {
          _errorMessage = 'Authentication failed (401)';
          _isLoading = false;
        });
        print('DEBUG: Authentication failed when loading image');
      } else {
        if (!mounted) return;
        
        setState(() {
          _errorMessage = 'Failed to load image (${response.statusCode})';
          _isLoading = false;
        });
        print('DEBUG: Failed to load image with status ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
      print('DEBUG: Error loading image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey[200],
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    } else if (_errorMessage != null) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image, color: Colors.red),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: _loadImage,
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else {
      return Image.memory(
        _imageBytes!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
      );
    }
  }
}