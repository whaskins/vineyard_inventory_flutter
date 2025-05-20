import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vibration/vibration.dart';
import '../models/vine.dart';
import '../services/database_service.dart';
import '../services/repository.dart';
import '../services/qr_scanner_service.dart';

class RowScanScreen extends StatefulWidget {
  const RowScanScreen({super.key});

  @override
  State<RowScanScreen> createState() => _RowScanScreenState();
}

class _RowScanScreenState extends State<RowScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  late final DatabaseService _databaseService;
  late final Repository _repository;
  
  @override
  void initState() {
    super.initState();
    _databaseService = DatabaseService();
    _repository = Repository();
    debugPrint('Row scan screen initialized');
  }
  final TextEditingController _vineyardNameController = TextEditingController();
  final TextEditingController _fieldNameController = TextEditingController();
  final TextEditingController _rowNumberController = TextEditingController();
  final TextEditingController _startingPositionController = TextEditingController(text: "1");
  
  bool _isScanning = true;
  bool _hasProcessedResult = false;
  int _currentSpotNumber = 1;
  
  // Direction control (true = incrementing positions, false = decrementing positions)
  bool _isForwardDirection = true;
  
  String? _lastScannedVineId;
  DateTime? _lastScanTime;
  String? _errorMessage;
  String? _successMessage;
  bool _showSettings = true;

  @override
  void dispose() {
    _controller.dispose();
    _vineyardNameController.dispose();
    _fieldNameController.dispose();
    _rowNumberController.dispose();
    _startingPositionController.dispose();
    super.dispose();
  }

  void _onQrDetect(BarcodeCapture capture) {
    // Prevent multiple detections
    if (!_isScanning || _hasProcessedResult) return;
    
    if (capture.barcodes.isEmpty) return;
    
    // Process the first barcode
    final firstBarcode = capture.barcodes.first;
    final String qrValue = firstBarcode.rawValue ?? '';
    
    debugPrint('QR code detected with value: $qrValue');
    
    if (qrValue.isEmpty) return;
    
    // Extract the vine ID from the QR value
    final String vineId = QrScannerService.extractVineId(qrValue);
    
    // Update last scan information
    _lastScanTime = DateTime.now();
    
    _hasProcessedResult = true;
    
    // Vibrate when QR code is detected
    _triggerVibration();
    
    _pauseScanner();
    
    debugPrint('Extracted vineId: $vineId');
    
    // Save this vine with the current row and position
    _saveVine(vineId);
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
      _errorMessage = null;
      _successMessage = null;
    });
    _controller.start();
  }

  Future<void> _saveVine(String vineId) async {
    debugPrint('Attempting to save vine with ID: $vineId');
    
    // Validate that row settings are entered
    if (_vineyardNameController.text.isEmpty || _fieldNameController.text.isEmpty || _rowNumberController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter vineyard name, field name, and row number first';
        _hasProcessedResult = false;
      });
      debugPrint('Missing required field information');
      _resumeScanner();
      return;
    }

    try {
      // Check if this vine ID already exists - use repository to check both local and API
      debugPrint('Checking if vine ID already exists: $vineId');
      final existingVine = await _repository.getVineByAlphaNumericID(vineId);
      
      if (existingVine != null) {
        debugPrint('Updating existing vine with ID: $vineId');
        // Update the existing vine with new position
        final updatedVine = Vine(
          id: existingVine.id,
          alphaNumericID: vineId,
          yearOfPlanting: existingVine.yearOfPlanting,
          nursery: existingVine.nursery,
          variety: existingVine.variety,
          rootstock: existingVine.rootstock,
          vineyardName: _vineyardNameController.text,
          fieldName: _fieldNameController.text,
          rowNumber: int.parse(_rowNumberController.text),
          spotNumber: _currentSpotNumber,
          isDead: existingVine.isDead,
          dateDied: existingVine.dateDied,
          recordCreated: existingVine.recordCreated,
        );
        
        // Update using repository (will update both local DB and API if online)
        final updatedResult = await _repository.updateVine(updatedVine);
        debugPrint('Update result: ${updatedResult.id}');
      } else {
        debugPrint('Creating new vine with ID: $vineId');
        // Create a new vine with the current position
        final newVine = Vine(
          alphaNumericID: vineId,
          vineyardName: _vineyardNameController.text,
          fieldName: _fieldNameController.text,
          rowNumber: int.parse(_rowNumberController.text),
          spotNumber: _currentSpotNumber,
          isDead: false,
        );
        
        // Insert using repository (will insert both locally and to API if online)
        final insertedVine = await _repository.insertVine(newVine);
        debugPrint('Insert result: ${insertedVine.id}');
      }
      
      // Update state
      // Store previous position for messaging
      final int savedPosition = _currentSpotNumber;
      final int nextPosition = _isForwardDirection ? _currentSpotNumber + 1 : _currentSpotNumber - 1;
      
      // Check if we're online to update the success message
      final String syncStatus = _repository.isOnline 
          ? 'Saved locally and synced to cloud.' 
          : 'Saved locally. Will sync when online.';
      
      setState(() {
        _lastScannedVineId = vineId;
        _successMessage = 'Vine $vineId saved at position $savedPosition. $syncStatus\nReady for position $nextPosition';
        _currentSpotNumber = nextPosition;  // Move to next position based on direction
        _showSettings = false;
      });
      
      // Resume scanning after a short delay
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _resumeScanner();
        }
      });
    } catch (e, stackTrace) {
      debugPrint('Error saving vine: $e');
      debugPrint('Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Error saving vine: $e';
      });
      _resumeScanner();
    }
  }

  void _skipPosition() {
    // Store current position for messaging
    final int skippedPosition = _currentSpotNumber;
    final int nextPosition = _isForwardDirection ? _currentSpotNumber + 1 : _currentSpotNumber - 1;
    
    // Vibrate with a different pattern for skip (shorter)
    Vibration.vibrate(duration: 50);
    
    setState(() {
      _successMessage = 'Marked position $skippedPosition as empty. Ready for position $nextPosition';
      _currentSpotNumber = nextPosition;
      
      // Briefly pause the scanner to show the message
      _pauseScanner();
    });
    
    // Resume scanner after a short delay
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        _resumeScanner();
      }
    });
  }

  void _toggleSettings() {
    setState(() {
      _showSettings = !_showSettings;
    });
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
  
  // Trigger manual sync with backend
  Future<void> _syncWithBackend() async {
    // Show a progress indicator
    setState(() {
      _successMessage = "Syncing with cloud server...";
    });
    
    try {
      // Use repository to sync vines
      final syncCount = await _repository.syncLocalVinesToAPI();
      
      setState(() {
        if (syncCount > 0) {
          _successMessage = "Successfully synced $syncCount vines with server.";
        } else if (_repository.isOnline) {
          _successMessage = "Nothing to sync. All data is up to date.";
        } else {
          _errorMessage = "Cannot sync - not connected to the internet.";
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Error syncing: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Row Scan Mode'),
        centerTitle: true,
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        actions: [
          // Network status indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(
              child: Row(
                children: [
                  Icon(
                    _repository.isOnline
                        ? Icons.cloud_done
                        : Icons.cloud_off,
                    color: _repository.isOnline
                        ? Colors.white
                        : Colors.white.withOpacity(0.6),
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _repository.isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontSize: 12,
                      color: _repository.isOnline
                          ? Colors.white
                          : Colors.white.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Sync button
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _syncWithBackend,
            tooltip: 'Sync with server',
          ),
          IconButton(
            icon: Icon(_showSettings ? Icons.visibility_off : Icons.settings),
            onPressed: _toggleSettings,
            tooltip: _showSettings ? 'Hide Settings' : 'Show Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          // Row information section
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: _showSettings ? 320 : 60,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.green[50],
              border: Border(bottom: BorderSide(color: Colors.green[200]!)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Always visible row info summary
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Vineyard: ${_vineyardNameController.text}, Field: ${_fieldNameController.text}, Row: ${_rowNumberController.text}, Position: $_currentSpotNumber ${_isForwardDirection ? "↑" : "↓"}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16.0,
                          ),
                        ),
                      ),
                      if (!_showSettings)
                        IconButton(
                          icon: const Icon(Icons.arrow_downward),
                          onPressed: _toggleSettings,
                          tooltip: 'Show Settings',
                        ),
                    ],
                  ),
                  
                  // Settings fields (only shown when _showSettings is true)
                  if (_showSettings) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _vineyardNameController,
                      decoration: const InputDecoration(
                        labelText: 'Vineyard Name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _fieldNameController,
                      decoration: const InputDecoration(
                        labelText: 'Field Name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _rowNumberController,
                            decoration: const InputDecoration(
                              labelText: 'Row Number',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Position Settings
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _startingPositionController,
                            decoration: const InputDecoration(
                              labelText: 'Starting Position',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            // Apply the starting position from the controller
                            setState(() {
                              _currentSpotNumber = int.tryParse(_startingPositionController.text) ?? 1;
                              _successMessage = 'Position set to $_currentSpotNumber';
                            });
                          },
                          child: const Text('Set Position'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Direction Settings
                    Card(
                      color: Colors.white,
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Scanning Direction:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Expanded(
                                  child: RadioListTile<bool>(
                                    title: const Text('Ascending ↑'),
                                    value: true,
                                    groupValue: _isForwardDirection,
                                    onChanged: (value) {
                                      setState(() {
                                        _isForwardDirection = value!;
                                      });
                                    },
                                    dense: true,
                                  ),
                                ),
                                Expanded(
                                  child: RadioListTile<bool>(
                                    title: const Text('Descending ↓'),
                                    value: false,
                                    groupValue: _isForwardDirection,
                                    onChanged: (value) {
                                      setState(() {
                                        _isForwardDirection = value!;
                                      });
                                    },
                                    dense: true,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          // Scanner section
          Expanded(
            flex: 5,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // QR Scanner camera
                MobileScanner(
                  controller: _controller,
                  onDetect: _onQrDetect,
                ),
                
                // Scanner animation overlay
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _isScanning ? Colors.green : Colors.orange,
                      width: 3.0,
                    ),
                    borderRadius: BorderRadius.circular(16.0),
                    boxShadow: [
                      BoxShadow(
                        color: (_isScanning ? Colors.green : Colors.orange).withOpacity(0.3),
                        spreadRadius: 2,
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
                
                // Instructions overlay
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    margin: const EdgeInsets.symmetric(horizontal: 50),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Text(
                      'Position QR code in frame',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Status messages
          if (_errorMessage != null || _successMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
              margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              decoration: BoxDecoration(
                color: _errorMessage != null ? Colors.red[50] : Colors.green[50],
                borderRadius: BorderRadius.circular(8.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              width: double.infinity,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Icon(
                      _errorMessage != null ? Icons.error_outline : Icons.check_circle_outline,
                      color: _errorMessage != null ? Colors.red[700] : Colors.green[700],
                      size: 24.0,
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: Text(
                      _errorMessage ?? _successMessage ?? '',
                      style: TextStyle(
                        color: _errorMessage != null ? Colors.red[700] : Colors.green[700],
                        fontWeight: FontWeight.bold,
                        fontSize: 16.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // Last scanned info and action buttons
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.grey[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_lastScannedVineId != null)
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.qr_code_scanner, color: Colors.green[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Last scanned: $_lastScannedVineId',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800],
                            ),
                          ),
                        ),
                        // Sync status indicator
                        Tooltip(
                          message: _repository.isOnline ? 'Synced to cloud' : 'Not synced to cloud yet',
                          child: Icon(
                            _repository.isOnline ? Icons.cloud_done : Icons.cloud_upload,
                            color: _repository.isOnline ? Colors.green[700] : Colors.amber[700],
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                
                // Position navigation buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Go back one position - direction agnostic
                          int prevPosition = _isForwardDirection ? _currentSpotNumber - 1 : _currentSpotNumber + 1;
                          if (prevPosition > 0) {
                            setState(() {
                              _currentSpotNumber = prevPosition;
                              _successMessage = 'Moved to position $_currentSpotNumber';
                            });
                          }
                        },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Previous'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Go forward one position - direction agnostic
                          int nextPosition = _isForwardDirection ? _currentSpotNumber + 1 : _currentSpotNumber - 1;
                          if (nextPosition > 0) {
                            setState(() {
                              _currentSpotNumber = nextPosition;
                              _successMessage = 'Moved to position $_currentSpotNumber';
                            });
                          }
                        },
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Next'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Skip button - full width and prominent
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _skipPosition,
                    icon: const Icon(Icons.skip_next),
                    label: const Text('Skip Position (No Plant)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}