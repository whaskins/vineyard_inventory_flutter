import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:vibration/vibration.dart';
import '../services/qr_scanner_service.dart';
import '../services/repository.dart';
import '../services/gps_service.dart';
import '../services/location_identification_service.dart';
import '../models/vine.dart';
import 'vine_detail_screen.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  CameraController? _controller;
  final BarcodeScanner _barcodeScanner =
      BarcodeScanner(formats: [BarcodeFormat.qrCode]);
  final Repository _repository = Repository();
  final GpsService _gpsService = GpsService();

  bool _isScanning = true;
  bool _hasProcessedResult = false;
  bool _isProcessing = false;
  bool _isDetecting = false;
  bool _isCameraReady = false;
  bool _isFlashOn = false;
  String? _lastScannedCode;
  DateTime? _lastScanTime;
  Position? _currentPosition;
  StreamSubscription<Position>? _gpsSubscription;
  LocationEstimate? _locationEstimate;

  double _currentZoom = 2.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  List<MapEntry<String, double>> _zoomPresets = [];

  @override
  void initState() {
    super.initState();
    _initGps();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final controller = await QrScannerService.initCamera();
      if (!mounted) {
        controller.dispose();
        return;
      }

      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      final savedZoom = await QrScannerService.getSavedZoom();

      setState(() {
        _controller = controller;
        _minZoom = minZoom;
        _maxZoom = maxZoom;
        _currentZoom = savedZoom.clamp(minZoom, maxZoom);
        _zoomPresets = QrScannerService.availablePresets(minZoom, maxZoom);
        _isCameraReady = true;
      });

      controller.startImageStream(_onCameraFrame);
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _initGps() async {
    _gpsService.startTracking();
    _gpsSubscription = _gpsService.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
        _updateLocationEstimate(position);
      }
    });
    final pos = await _gpsService.getCurrentPosition();
    if (pos != null && mounted) {
      setState(() {
        _currentPosition = pos;
      });
      _updateLocationEstimate(pos);
    }
  }

  Future<void> _updateLocationEstimate(Position position) async {
    try {
      final vines = await _repository.getLocalVines();
      final estimate = LocationIdentificationService.identifyLocation(
        position.latitude,
        position.longitude,
        vines,
      );
      if (mounted) {
        setState(() {
          _locationEstimate = estimate;
        });
      }
    } catch (e) {
      debugPrint('Error updating location estimate: $e');
    }
  }

  @override
  void dispose() {
    _gpsSubscription?.cancel();
    _gpsService.stopTracking();
    _controller?.dispose();
    _barcodeScanner.close();
    super.dispose();
  }

  void _onCameraFrame(CameraImage image) {
    if (_isDetecting || !_isScanning || _hasProcessedResult) return;
    _isDetecting = true;

    final camera = _controller!.description;
    final inputImage =
        QrScannerService.inputImageFromCameraImage(image, camera);

    if (inputImage == null) {
      _isDetecting = false;
      return;
    }

    _barcodeScanner.processImage(inputImage).then((barcodes) {
      if (barcodes.isNotEmpty && _isScanning && !_hasProcessedResult) {
        _onQrDetect(barcodes);
      }
      _isDetecting = false;
    }).catchError((e) {
      debugPrint('Error processing barcode: $e');
      _isDetecting = false;
    });
  }

  void _onQrDetect(List<Barcode> barcodes) async {
    if (!_isScanning || _hasProcessedResult || _isProcessing) return;
    if (barcodes.isEmpty) return;

    final firstBarcode = barcodes.first;
    final String qrValue = firstBarcode.rawValue ?? '';
    if (qrValue.isEmpty) return;

    final String vineId = QrScannerService.extractVineId(qrValue);

    _lastScannedCode = vineId;
    _lastScanTime = DateTime.now();

    setState(() {
      _hasProcessedResult = true;
      _isProcessing = true;
    });

    _triggerVibration();
    _pauseScanner();

    debugPrint('QR code scanned: $vineId');

    try {
      final vine = await _repository.getVineByAlphaNumericID(vineId);

      if (vine == null && mounted) {
        debugPrint('Vine with ID $vineId not found, creating new vine');

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Creating new vine record...')),
        );

        try {
          await _repository.insertVine(
            Vine(
              alphaNumericID: vineId,
              recordCreated: DateTime.now(),
            ),
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('New vine record created')),
            );
          }
        } catch (e) {
          debugPrint('Error creating new vine: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error creating vine: $e')),
            );
          }
        }
      } else {
        debugPrint('Vine with ID $vineId found in database');
      }

      _navigateToVineDetail(vineId);
    } catch (e) {
      debugPrint('Error in QR processing: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() {
          _isProcessing = false;
          _hasProcessedResult = false;
        });
        _resumeScanner();
      }
    }
  }

  void _pauseScanner() {
    setState(() {
      _isScanning = false;
    });
    _controller?.stopImageStream();
  }

  void _resumeScanner() {
    setState(() {
      _isScanning = true;
      _hasProcessedResult = false;
    });
    _controller?.startImageStream(_onCameraFrame);
  }

  Future<void> _triggerVibration() async {
    final bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(duration: 100);
    }
  }

  Future<void> _scanFromGallery() async {
    _pauseScanner();

    final String? vineId = await QrScannerService.scanQrFromGallery();

    if (vineId != null && vineId.isNotEmpty) {
      if (mounted) {
        _navigateToVineDetail(vineId);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No QR code found in the image.')),
        );
        _resumeScanner();
      }
    }
  }

  void _navigateToVineDetail(String vineId) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => VineDetailScreen(
          vineId: vineId,
          gpsLatitude: _currentPosition?.latitude,
          gpsLongitude: _currentPosition?.longitude,
          gpsAccuracy: _currentPosition?.accuracy,
        ),
      ),
    )
        .then((_) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        _resumeScanner();
      }
    });
  }

  Future<void> _setZoom(double zoom) async {
    final clamped = zoom.clamp(_minZoom, _maxZoom);
    await _controller?.setZoomLevel(clamped);
    await QrScannerService.saveZoom(clamped);
    setState(() {
      _currentZoom = clamped;
    });
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    final newMode = _isFlashOn ? FlashMode.off : FlashMode.torch;
    await _controller!.setFlashMode(newMode);
    setState(() {
      _isFlashOn = !_isFlashOn;
    });
  }

  Widget _buildGpsStatusBadge() {
    if (_currentPosition == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gps_off, size: 14, color: Colors.white),
            SizedBox(width: 4),
            Text('No GPS',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      );
    }

    final accuracy = _currentPosition!.accuracy;
    Color badgeColor;
    String label;
    if (accuracy <= 5) {
      badgeColor = Colors.green;
      label = '${accuracy.toStringAsFixed(1)}m';
    } else if (accuracy <= 15) {
      badgeColor = Colors.orange;
      label = '${accuracy.toStringAsFixed(1)}m';
    } else {
      badgeColor = Colors.red;
      label = '${accuracy.toStringAsFixed(0)}m';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.gps_fixed, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildLocationBanner() {
    if (_locationEstimate == null || _locationEstimate!.confidence < 0.3) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.blue.withValues(alpha: 0.85),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "You're near ${_locationEstimate!.vineyardName} / ${_locationEstimate!.fieldName} / Row ${_locationEstimate!.rowNumber}",
              style: const TextStyle(color: Colors.white, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomSelector() {
    if (_zoomPresets.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: _zoomPresets.map((entry) {
        final isSelected = (_currentZoom - entry.value).abs() < 0.01;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ChoiceChip(
            label: Text(entry.key),
            selected: isSelected,
            onSelected: (_) => _setZoom(entry.value),
            selectedColor: Colors.green,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : null,
              fontWeight: isSelected ? FontWeight.bold : null,
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Vine QR Code'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildLocationBanner(),
          Expanded(
            flex: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16.0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_isCameraReady && _controller != null)
                    CameraPreview(_controller!)
                  else
                    const Center(child: CircularProgressIndicator()),
                  Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.green,
                        width: 2.0,
                      ),
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: _buildGpsStatusBadge(),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Position the QR code in the center of the screen',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16.0),
                  ),
                  const SizedBox(height: 8.0),
                  _buildZoomSelector(),
                  const SizedBox(height: 8.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _scanFromGallery,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('From Gallery'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _toggleFlash,
                        icon: Icon(
                            _isFlashOn ? Icons.flash_off : Icons.flash_on),
                        label: Text(_isFlashOn ? 'Flash Off' : 'Flash On'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[800],
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
