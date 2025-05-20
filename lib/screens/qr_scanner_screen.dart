import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vibration/vibration.dart';
import '../services/qr_scanner_service.dart';
import '../services/repository.dart';
import '../models/vine.dart';
import 'vine_detail_screen.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  final Repository _repository = Repository();
  bool _isScanning = true;
  bool _hasProcessedResult = false;
  bool _isProcessing = false;
  String? _lastScannedCode;
  DateTime? _lastScanTime;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQrDetect(BarcodeCapture capture) async {
    // Prevent multiple detections
    if (!_isScanning || _hasProcessedResult || _isProcessing) return;
    
    if (capture.barcodes.isEmpty) return;
    
    // Process the first barcode
    final firstBarcode = capture.barcodes.first;
    final String qrValue = firstBarcode.rawValue ?? '';
    
    if (qrValue.isEmpty) return;
    
    // Extract the vine ID from the QR value
    final String vineId = QrScannerService.extractVineId(qrValue);
    
      // Update scan tracking information
    _lastScannedCode = vineId;
    _lastScanTime = DateTime.now();
    
    setState(() {
      _hasProcessedResult = true;
      _isProcessing = true;
    });
    
    // Vibrate when QR code is detected
    _triggerVibration();
    
    _pauseScanner();
    
    debugPrint('QR code scanned: $vineId');
      
      try {
        // Check if the vine exists in the database
        final vine = await _repository.getVineByAlphaNumericID(vineId);
        
        if (vine == null && mounted) {
          debugPrint('Vine with ID $vineId not found, creating new vine');
          
          // Show a loading indicator
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Creating new vine record...')),
          );
          
          // Create a new vine with minimal info
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
        
        // Navigate to the vine detail screen
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
    _controller.stop();
  }

  void _resumeScanner() {
    setState(() {
      _isScanning = true;
      _hasProcessedResult = false;
      // Reset scan state
    });
    _controller.start();
  }
  
  // Vibration feedback when a QR code is scanned
  Future<void> _triggerVibration() async {
    // Check if vibration is available
    final bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      // Vibrate with a pattern to simulate a "success" feedback
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VineDetailScreen(vineId: vineId),
      ),
    ).then((_) {
      // Resume scanning when returning from the detail screen
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        _resumeScanner();
      }
    });
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
          Expanded(
            flex: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16.0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onQrDetect,
                  ),
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
                  const SizedBox(height: 16.0),
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
                        onPressed: () {
                          _controller.toggleTorch();
                        },
                        icon: const Icon(Icons.flashlight_on),
                        label: const Text('Toggle Flash'),
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