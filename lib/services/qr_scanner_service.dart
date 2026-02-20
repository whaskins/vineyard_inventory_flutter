import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QrScannerService {
  static const String _zoomPrefKey = 'camera_zoom_level';

  // Zoom presets: label -> zoom value
  static const Map<String, double> zoomPresets = {
    '0.5x': 0.5,
    '1x': 1.0,
    '2x': 2.0,
    '3x': 3.0,
  };

  // Parse QR code value to extract vine ID
  static String extractVineId(String qrValue) {
    final String urlPrefix =
        'http://vineinfo.isleta.abqwebdev.com/inventory/';

    if (qrValue.startsWith(urlPrefix)) {
      return qrValue.substring(urlPrefix.length);
    }

    return qrValue;
  }

  // Pick image from gallery and scan for QR codes
  static Future<String?> scanQrFromGallery() async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile =
        await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) return null;

    try {
      debugPrint('Selected image: ${pickedFile.path}');
      final inputImage = InputImage.fromFilePath(pickedFile.path);
      final barcodeScanner =
          BarcodeScanner(formats: [BarcodeFormat.qrCode]);
      final barcodes = await barcodeScanner.processImage(inputImage);
      await barcodeScanner.close();

      if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
        return extractVineId(barcodes.first.rawValue!);
      }
    } catch (e) {
      debugPrint('Error processing gallery image: $e');
    }

    return null;
  }

  /// Initialize a [CameraController] for the back camera with the correct
  /// image format for ML Kit processing on each platform.
  static Future<CameraController> initCamera() async {
    final cameras = await availableCameras();
    final backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final formatGroup =
        Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888;

    final controller = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: formatGroup,
    );

    await controller.initialize();
    await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

    // Restore saved zoom level
    final savedZoom = await getSavedZoom();
    final minZoom = await controller.getMinZoomLevel();
    final maxZoom = await controller.getMaxZoomLevel();
    final clampedZoom = savedZoom.clamp(minZoom, maxZoom);
    await controller.setZoomLevel(clampedZoom);

    return controller;
  }

  /// Convert a [CameraImage] frame into an ML Kit [InputImage].
  static InputImage? inputImageFromCameraImage(
    CameraImage image,
    CameraDescription camera,
  ) {
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;

    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    }

    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Persist the user's preferred zoom level.
  static Future<void> saveZoom(double zoom) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_zoomPrefKey, zoom);
  }

  /// Read the previously-saved zoom level (defaults to 2.0 for standard lens).
  static Future<double> getSavedZoom() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_zoomPrefKey) ?? 2.0;
  }

  /// Return the subset of [zoomPresets] that fall within [minZoom]..[maxZoom].
  static List<MapEntry<String, double>> availablePresets(
    double minZoom,
    double maxZoom,
  ) {
    return zoomPresets.entries
        .where((e) => e.value >= minZoom && e.value <= maxZoom)
        .toList();
  }
}
