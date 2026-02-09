import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vibration/vibration.dart';
import '../models/vine.dart';
import '../models/vine_location.dart';
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
  
  // Focus nodes to control text field focus
  final FocusNode _vineyardFocusNode = FocusNode();
  final FocusNode _fieldFocusNode = FocusNode();
  final FocusNode _rowFocusNode = FocusNode();
  final FocusNode _positionFocusNode = FocusNode();
  
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
    _vineyardFocusNode.dispose();
    _fieldFocusNode.dispose();
    _rowFocusNode.dispose();
    _positionFocusNode.dispose();
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

    // Store previous position for messaging
    final int savedPosition = _currentSpotNumber;
    final int nextPosition = _isForwardDirection ? _currentSpotNumber + 1 : _currentSpotNumber - 1;
    
    // Immediately update UI to show success and move to next position
    setState(() {
      _lastScannedVineId = vineId;
      _successMessage = 'Vine $vineId queued for saving at position $savedPosition.\nReady for position $nextPosition';
      _currentSpotNumber = nextPosition;
      _showSettings = false;
    });
    
    // Resume scanning immediately to keep UI responsive
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _resumeScanner();
      }
    });
    
    // Process the save operation in the background
    _processSaveInBackground(vineId, savedPosition);
  }
  
  void _processSaveInBackground(String vineId, int position) {
    // Run the save operation in the background without blocking the UI
    Future.microtask(() async {
      try {
        debugPrint('Background: Processing save for vine $vineId at position $position');
        
        // Check if this vine ID already exists - use repository to check both local and API
        debugPrint('Background: Checking if vine ID already exists: $vineId');
        final existingVine = await _repository.getVineByAlphaNumericID(vineId);
        
        if (existingVine != null) {
          debugPrint('Background: Updating existing vine with ID: $vineId');
          // Create updated location
          final updatedLocation = VineLocation(
            id: existingVine.location?.id,
            alphaNumericId: vineId,
            vineyardName: _vineyardNameController.text,
            fieldName: _fieldNameController.text,
            rowNumber: int.parse(_rowNumberController.text),
            spotNumber: position,
            recordCreated: existingVine.location?.recordCreated,
            updatedAt: existingVine.location?.updatedAt,
          );
          
          // Update the existing vine with new position
          final updatedVine = Vine(
            id: existingVine.id,
            alphaNumericID: vineId,
            yearOfPlanting: existingVine.yearOfPlanting,
            nursery: existingVine.nursery,
            variety: existingVine.variety,
            rootstock: existingVine.rootstock,
            isDead: existingVine.isDead,
            dateDied: existingVine.dateDied,
            recordCreated: existingVine.recordCreated,
            location: updatedLocation,
          );
          
          // Update using repository (will update both local DB and API if online)
          final updatedResult = await _repository.updateVine(updatedVine);
          debugPrint('Background: Update result: ${updatedResult.id}');
        } else {
          debugPrint('Background: Creating new vine with ID: $vineId');
          // Create location for new vine
          final newLocation = VineLocation(
            alphaNumericId: vineId,
            vineyardName: _vineyardNameController.text,
            fieldName: _fieldNameController.text,
            rowNumber: int.parse(_rowNumberController.text),
            spotNumber: position,
          );
          
          // Create a new vine with the current position
          final newVine = Vine(
            alphaNumericID: vineId,
            isDead: false,
            location: newLocation,
          );
          
          // Insert using repository (will insert both locally and to API if online)
          final insertedVine = await _repository.insertVine(newVine);
          debugPrint('Background: Insert result: ${insertedVine.id}');
        }
        
        // Also create a vine_locations entry to track this vine's position if it doesn't already exist
        try {
          final bool locationExists = await _repository.vineLocationExists(
            _vineyardNameController.text,
            _fieldNameController.text, 
            int.parse(_rowNumberController.text),
            position,
            vineId
          );
          
          if (!locationExists) {
            final locationData = {
              'vineyard_name': _vineyardNameController.text,
              'field_name': _fieldNameController.text,
              'row_number': int.parse(_rowNumberController.text),
              'spot_number': position,
              'year_of_planting': null, // Will be populated from vine data
              'alpha_numeric_id': vineId,
            };
            
            debugPrint('Background: Creating vine location entry for scanned tag: $locationData');
            await _repository.insertVineLocation(locationData);
          } else {
            debugPrint('Background: Vine location already exists for $vineId at this position, skipping');
          }
        } catch (e) {
          debugPrint('Background: Warning - Could not create vine location entry: $e');
          // Don't fail the whole operation if location entry fails
        }
        
        debugPrint('Background: Successfully saved vine $vineId at position $position');
        
      } catch (e, stackTrace) {
        debugPrint('Background: Error saving vine $vineId: $e');
        debugPrint('Background: Stack trace: $stackTrace');
        // Error is logged but user continues working - data saved locally
      }
    });
  }
  

  Future<void> _skipPosition() async {
    // Store current position for messaging
    final int skippedPosition = _currentSpotNumber;
    final int nextPosition = _isForwardDirection ? _currentSpotNumber + 1 : _currentSpotNumber - 1;
    
    // Validate that row settings are entered
    if (_vineyardNameController.text.isEmpty || _fieldNameController.text.isEmpty || _rowNumberController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter vineyard name, field name, and row number first';
      });
      return;
    }
    
    // Vibrate with a different pattern for skip (shorter)
    Vibration.vibrate(duration: 50);
    
    setState(() {
      _successMessage = 'Marked position $skippedPosition as empty. Ready for position $nextPosition';
      _currentSpotNumber = nextPosition;
      _errorMessage = null;
      
      // Briefly pause the scanner to show the message
      _pauseScanner();
    });
    
    // Resume scanner after a short delay
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        _resumeScanner();
      }
    });
    
    // Process the skip operation in the background
    _processSkipInBackground(skippedPosition);
  }
  
  void _processSkipInBackground(int position) {
    // Run the skip operation in the background without blocking the UI
    Future.microtask(() async {
      try {
        debugPrint('Background: Processing skip for position $position');
        
        // Create a vine_locations entry for the empty position if it doesn't already exist
        final bool locationExists = await _repository.vineLocationExists(
          _vineyardNameController.text,
          _fieldNameController.text,
          int.parse(_rowNumberController.text),
          position,
          null // No vine at this position
        );
        
        if (!locationExists) {
          final locationData = {
            'vineyard_name': _vineyardNameController.text,
            'field_name': _fieldNameController.text,
            'row_number': int.parse(_rowNumberController.text),
            'spot_number': position,
            'year_of_planting': null,
            'alpha_numeric_id': null, // No vine at this position
          };
          
          debugPrint('Background: Creating vine location entry for empty position: $locationData');
          await _repository.insertVineLocation(locationData);
        } else {
          debugPrint('Background: Location entry already exists for this empty position, skipping');
        }
        
        debugPrint('Background: Successfully processed skip for position $position');
        
      } catch (e) {
        debugPrint('Background: Warning - Could not create vine location entry for empty position: $e');
        // Error is logged but user continues working - will sync when online
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
      // Use repository to sync pending changes
      final syncCount = await _repository.syncPendingChangesToAPI();
      
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

  // Show dialog to select vine age for untagged vines
  Future<void> _showAgeSelectionDialog() async {
    if (_vineyardNameController.text.isEmpty || 
        _fieldNameController.text.isEmpty || 
        _rowNumberController.text.isEmpty) {
      setState(() {
        _errorMessage = "Please fill in vineyard, field, and row information before adding vines.";
      });
      return;
    }
    
    // Completely dismiss all focus and keyboard
    for (var node in [_vineyardFocusNode, _fieldFocusNode, _rowFocusNode, _positionFocusNode]) {
      if (node.hasFocus) {
        node.unfocus();
      }
    }
    
    // Clear primary focus completely
    FocusManager.instance.primaryFocus?.unfocus();
    
    // Wait longer for keyboard to fully dismiss
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Check if widget is still mounted after delay
    if (!mounted) return;

    final int? selectedAge = await showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return PopScope(
          onPopInvoked: (didPop) {
            // Ensure keyboard stays dismissed when dialog closes
            FocusScope.of(context).unfocus();
          },
          child: AlertDialog(
            title: const Text('Vine Age'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('A vine exists at position $_currentSpotNumber but has no tag.'),
                const SizedBox(height: 16),
                const Text('How old is this vine?'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  Navigator.of(context).pop();
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  Navigator.of(context).pop(1);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('1 Year Old'),
              ),
              ElevatedButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  Navigator.of(context).pop(2);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('2 Years Old'),
              ),
            ],
          ),
        );
      },
    );

    if (selectedAge != null) {
      // Ensure keyboard stays dismissed after dialog closes
      if (mounted) {
        FocusManager.instance.primaryFocus?.unfocus();
        for (var node in [_vineyardFocusNode, _fieldFocusNode, _rowFocusNode, _positionFocusNode]) {
          if (node.hasFocus) {
            node.unfocus();
          }
        }
      }
      await _createUntaggedVine(selectedAge);
    } else {
      // Even if cancelled, make sure keyboard stays dismissed
      if (mounted) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
    }
  }

  // Create a vine location record without a QR tag
  Future<void> _createUntaggedVine(int ageInYears) async {
    final savedPosition = _currentSpotNumber;
    
    // Provide vibration feedback
    await _triggerVibration();
    
    // Move to next position immediately
    final nextPosition = _isForwardDirection ? _currentSpotNumber + 1 : _currentSpotNumber - 1;
    
    setState(() {
      _successMessage = 'Untagged vine (${ageInYears}y old) queued for position $savedPosition. Ready for position $nextPosition';
      _currentSpotNumber = nextPosition;
      _errorMessage = null;
    });
    
    // Brief pause before continuing
    _pauseScanner();
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        _resumeScanner();
      }
    });
    
    // Process the untagged vine creation in the background
    _processUntaggedVineInBackground(savedPosition, ageInYears);
  }
  
  void _processUntaggedVineInBackground(int position, int ageInYears) {
    // Run the creation operation in the background without blocking the UI
    Future.microtask(() async {
      try {
        debugPrint('Background: Creating untagged vine at position $position');
        
        final currentYear = DateTime.now().year;
        final plantingYear = currentYear - ageInYears;
        
        // For untagged vines, create a vine location record (not a vine record)
        final locationData = {
          'vineyard_name': _vineyardNameController.text,
          'field_name': _fieldNameController.text,
          'row_number': int.parse(_rowNumberController.text),
          'spot_number': position,
          'year_of_planting': plantingYear,
          'alpha_numeric_id': null, // No tag for this location
        };
        
        debugPrint('Background: Creating untagged vine location: $locationData');
        
        // Save directly to backend via API (since this is vine location, not vine)
        debugPrint('Background: Repository online status: ${_repository.isOnline}');
        await _repository.insertVineLocation(locationData);
        debugPrint('Background: Vine location insertion completed');
        
        debugPrint('Background: Successfully created untagged vine at position $position');
        
      } catch (e) {
        debugPrint('Background: Error creating untagged vine: $e');
        // Error is logged but user continues working - will sync when online
      }
    });
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
                    _repository.isOnline ? 'Backend Connected' : 'Backend Offline',
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
      body: GestureDetector(
        onTap: () {
          // Dismiss keyboard when tapping outside of text fields
          FocusScope.of(context).unfocus();
        },
        behavior: HitTestBehavior.opaque,
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - AppBar().preferredSize.height - MediaQuery.of(context).padding.top,
            ),
            child: Column(
            children: [
              // Row information section
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                constraints: BoxConstraints(
                  minHeight: 60,
                  maxHeight: _showSettings ? 320 : 60,
                ),
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
                      focusNode: _vineyardFocusNode,
                      decoration: const InputDecoration(
                        labelText: 'Vineyard Name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _fieldNameController,
                      focusNode: _fieldFocusNode,
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
                            focusNode: _rowFocusNode,
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
                            focusNode: _positionFocusNode,
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
          SizedBox(
            height: 400, // Fixed height for scanner
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
                          message: _repository.isOnline ? 'Backend connected - data syncing' : 'Backend offline - data saved locally',
                          child: Icon(
                            _repository.isOnline ? Icons.cloud_done : Icons.cloud_off,
                            color: _repository.isOnline ? Colors.green[700] : Colors.orange[700],
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
                const SizedBox(height: 12),
                
                // Vine exists but no tag button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _showAgeSelectionDialog,
                    icon: const Icon(Icons.local_florist),
                    label: const Text('Vine Exists But No Tag'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
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
        ),
        ),
      ),
    );
  }
}