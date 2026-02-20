import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import '../models/vine.dart';
import '../models/vine_location.dart';
import '../services/database_service.dart';
import '../services/repository.dart';
import '../services/qr_scanner_service.dart';
import '../services/gps_service.dart';

class RowScanScreen extends StatefulWidget {
  const RowScanScreen({super.key});

  @override
  State<RowScanScreen> createState() => _RowScanScreenState();
}

class _RowScanScreenState extends State<RowScanScreen> {
  CameraController? _controller;
  final BarcodeScanner _barcodeScanner =
      BarcodeScanner(formats: [BarcodeFormat.qrCode]);
  final GpsService _gpsService = GpsService();
  late final DatabaseService _databaseService;
  late final Repository _repository;
  Position? _currentPosition;
  StreamSubscription<Position>? _gpsSubscription;

  bool _isDetecting = false;
  bool _isCameraReady = false;
  bool _isFlashOn = false;

  double _currentZoom = 2.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  List<MapEntry<String, double>> _zoomPresets = [];

  // Dropdown options
  List<String> _vineyardOptions = [];
  Map<String, List<String>> _fieldOptionsByVineyard = {};
  List<String> _currentFieldOptions = [];

  @override
  void initState() {
    super.initState();
    _databaseService = DatabaseService();
    _repository = Repository();
    _initGps();
    _loadDropdownOptions();
    _initCamera();
    debugPrint('Row scan screen initialized');
  }

  final TextEditingController _vineyardNameController = TextEditingController();
  final TextEditingController _fieldNameController = TextEditingController();
  final TextEditingController _rowNumberController = TextEditingController();
  final TextEditingController _startingPositionController =
      TextEditingController(text: "1");

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
        _currentPosition = position;
      }
    });
    final pos = await _gpsService.getCurrentPosition();
    if (pos != null && mounted) {
      _currentPosition = pos;
    }
  }

  Future<void> _loadDropdownOptions() async {
    final allVines = await _repository.getLocalVines();

    // Extract unique vineyard names
    final vineyards = allVines
        .where((v) => v.vineyardName != null && v.vineyardName!.isNotEmpty)
        .map((v) => v.vineyardName!)
        .toSet()
        .toList()
      ..sort();

    // Build field names grouped by vineyard
    final fieldsByVineyard = <String, Set<String>>{};
    for (final vine in allVines) {
      if (vine.vineyardName != null &&
          vine.vineyardName!.isNotEmpty &&
          vine.fieldName != null &&
          vine.fieldName!.isNotEmpty) {
        fieldsByVineyard
            .putIfAbsent(vine.vineyardName!, () => <String>{})
            .add(vine.fieldName!);
      }
    }

    final fieldOptionsMap = fieldsByVineyard.map(
      (k, v) => MapEntry(k, v.toList()..sort()),
    );

    // Load last used values from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final lastVineyard = prefs.getString('lastVineyard');
    final lastField = prefs.getString('lastField');

    if (mounted) {
      setState(() {
        _vineyardOptions = vineyards;
        _fieldOptionsByVineyard = fieldOptionsMap;

        // Pre-select last used vineyard
        if (lastVineyard != null && vineyards.contains(lastVineyard)) {
          _vineyardNameController.text = lastVineyard;
          _currentFieldOptions = fieldOptionsMap[lastVineyard] ?? [];
          // Pre-select last used field if it belongs to this vineyard
          if (lastField != null && _currentFieldOptions.contains(lastField)) {
            _fieldNameController.text = lastField;
          }
        }
      });
    }
  }

  void _onVineyardChanged(String? value) {
    if (value == null) return;
    setState(() {
      _vineyardNameController.text = value;
      _currentFieldOptions = _fieldOptionsByVineyard[value] ?? [];
      // Clear field if it doesn't belong to the new vineyard
      if (!_currentFieldOptions.contains(_fieldNameController.text)) {
        _fieldNameController.text = '';
      }
    });
    _saveLastUsed();
  }

  void _onFieldChanged(String? value) {
    if (value == null) return;
    setState(() {
      _fieldNameController.text = value;
    });
    _saveLastUsed();
  }

  Future<void> _saveLastUsed() async {
    final prefs = await SharedPreferences.getInstance();
    if (_vineyardNameController.text.isNotEmpty) {
      await prefs.setString('lastVineyard', _vineyardNameController.text);
    }
    if (_fieldNameController.text.isNotEmpty) {
      await prefs.setString('lastField', _fieldNameController.text);
    }
  }

  Future<String?> _showAddNewDialog(String label) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add New $label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(context).pop(value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.of(context).pop(controller.text.trim());
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _gpsSubscription?.cancel();
    _gpsService.stopTracking();
    _controller?.dispose();
    _barcodeScanner.close();
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

  void _onQrDetect(List<Barcode> barcodes) {
    // Prevent multiple detections
    if (!_isScanning || _hasProcessedResult) return;

    if (barcodes.isEmpty) return;

    // Process the first barcode
    final firstBarcode = barcodes.first;
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
    _controller?.stopImageStream();
  }

  void _resumeScanner() {
    setState(() {
      _isScanning = true;
      _hasProcessedResult = false;
      _errorMessage = null;
      _successMessage = null;
    });
    _controller?.startImageStream(_onCameraFrame);
  }

  Future<void> _saveVine(String vineId) async {
    debugPrint('Attempting to save vine with ID: $vineId');

    // Validate that row settings are entered
    if (_vineyardNameController.text.isEmpty ||
        _fieldNameController.text.isEmpty ||
        _rowNumberController.text.isEmpty) {
      setState(() {
        _errorMessage =
            'Please enter vineyard name, field name, and row number first';
        _hasProcessedResult = false;
      });
      debugPrint('Missing required field information');
      _resumeScanner();
      return;
    }

    // Store previous position for messaging
    final int savedPosition = _currentSpotNumber;
    final int nextPosition =
        _isForwardDirection ? _currentSpotNumber + 1 : _currentSpotNumber - 1;

    // Immediately update UI to show success and move to next position
    setState(() {
      _lastScannedVineId = vineId;
      _successMessage =
          'Vine $vineId queued for saving at position $savedPosition.\nReady for position $nextPosition';
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
    // Capture GPS at time of scan
    final gpsPosition = _currentPosition;

    // Run the save operation in the background without blocking the UI
    Future.microtask(() async {
      try {
        debugPrint(
            'Background: Processing save for vine $vineId at position $position');

        // Check if this vine ID already exists - use repository to check both local and API
        debugPrint('Background: Checking if vine ID already exists: $vineId');
        final existingVine =
            await _repository.getVineByAlphaNumericID(vineId);

        // Determine GPS values to use: update if no existing coords or new reading is more accurate
        double? lat = gpsPosition?.latitude;
        double? lon = gpsPosition?.longitude;
        double? accuracy = gpsPosition?.accuracy;

        if (existingVine != null) {
          final existingLoc = existingVine.location;
          if (existingLoc?.hasCoordinates == true && gpsPosition != null) {
            // Only overwrite if new reading is more accurate
            if (existingLoc!.gpsAccuracy != null &&
                gpsPosition.accuracy >= existingLoc.gpsAccuracy!) {
              lat = existingLoc.latitude;
              lon = existingLoc.longitude;
              accuracy = existingLoc.gpsAccuracy;
            }
          }

          debugPrint(
              'Background: Updating existing vine with ID: $vineId');
          // Create updated location
          final updatedLocation = VineLocation(
            id: existingLoc?.id,
            alphaNumericId: vineId,
            vineyardName: _vineyardNameController.text,
            fieldName: _fieldNameController.text,
            rowNumber: int.parse(_rowNumberController.text),
            spotNumber: position,
            latitude: lat,
            longitude: lon,
            gpsAccuracy: accuracy,
            recordCreated: existingLoc?.recordCreated,
            updatedAt: existingLoc?.updatedAt,
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
          debugPrint(
              'Background: Update result: ${updatedResult.id}');
        } else {
          debugPrint(
              'Background: Creating new vine with ID: $vineId');
          // Create location for new vine
          final newLocation = VineLocation(
            alphaNumericId: vineId,
            vineyardName: _vineyardNameController.text,
            fieldName: _fieldNameController.text,
            rowNumber: int.parse(_rowNumberController.text),
            spotNumber: position,
            latitude: lat,
            longitude: lon,
            gpsAccuracy: accuracy,
          );

          // Create a new vine with the current position
          final newVine = Vine(
            alphaNumericID: vineId,
            isDead: false,
            location: newLocation,
          );

          // Insert using repository (will insert both locally and to API if online)
          final insertedVine = await _repository.insertVine(newVine);
          debugPrint(
              'Background: Insert result: ${insertedVine.id}');
        }

        debugPrint(
            'Background: Successfully saved vine $vineId at position $position');
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
    final int nextPosition =
        _isForwardDirection ? _currentSpotNumber + 1 : _currentSpotNumber - 1;

    // Validate that row settings are entered
    if (_vineyardNameController.text.isEmpty ||
        _fieldNameController.text.isEmpty ||
        _rowNumberController.text.isEmpty) {
      setState(() {
        _errorMessage =
            'Please enter vineyard name, field name, and row number first';
      });
      return;
    }

    // Vibrate with a different pattern for skip (shorter)
    Vibration.vibrate(duration: 50);

    setState(() {
      _successMessage =
          'Marked position $skippedPosition as empty. Ready for position $nextPosition';
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
    // Capture GPS at time of action; try fresh reading if null
    var gpsPosition = _currentPosition;
    if (gpsPosition == null) {
      _gpsService.getCurrentPosition().then((pos) {
        if (pos != null) _currentPosition = pos;
      });
      gpsPosition = _currentPosition;
    }

    // Run the skip operation in the background without blocking the UI
    Future.microtask(() async {
      try {
        debugPrint('Background: Processing skip (empty spot) for position $position, GPS: ${gpsPosition != null}');

        final vineyardName = _vineyardNameController.text;
        final fieldName = _fieldNameController.text;
        final rowNumber = int.parse(_rowNumberController.text);

        // Check if a vine record already exists at this location
        final existingVine = await _databaseService.getVineByLocation(
            vineyardName, fieldName, rowNumber, position);

        final location = VineLocation(
          vineyardName: vineyardName,
          fieldName: fieldName,
          rowNumber: rowNumber,
          spotNumber: position,
          latitude: gpsPosition?.latitude,
          longitude: gpsPosition?.longitude,
          gpsAccuracy: gpsPosition?.accuracy,
        );

        if (existingVine != null) {
          // Update existing vine to mark as empty spot (clear tag, not dead)
          final updatedVine = Vine(
            id: existingVine.id,
            alphaNumericID: null,
            isDead: false,
            yearOfPlanting: null,
            recordCreated: existingVine.recordCreated,
            location: location,
          );
          await _repository.updateVine(updatedVine);
          debugPrint('Background: Updated existing vine at position $position as empty spot');
        } else {
          // Create a new vine record for the empty spot
          final emptyVine = Vine(
            alphaNumericID: null,
            isDead: false,
            yearOfPlanting: null,
            location: location,
          );
          await _repository.insertVine(emptyVine);
          debugPrint('Background: Created new empty spot vine at position $position');
        }

        debugPrint('Background: Successfully processed skip for position $position');
      } catch (e) {
        debugPrint('Background: Error processing skip for position $position: $e');
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
          _successMessage =
              "Successfully synced $syncCount vines with server.";
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
        _errorMessage =
            "Please fill in vineyard, field, and row information before adding vines.";
      });
      return;
    }

    // Completely dismiss all focus and keyboard
    for (var node in [
      _vineyardFocusNode,
      _fieldFocusNode,
      _rowFocusNode,
      _positionFocusNode
    ]) {
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
                Text(
                    'A vine exists at position $_currentSpotNumber but has no tag.'),
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
              ElevatedButton(
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  Navigator.of(context).pop(3);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
                child: const Text('3 Years Old'),
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
        for (var node in [
          _vineyardFocusNode,
          _fieldFocusNode,
          _rowFocusNode,
          _positionFocusNode
        ]) {
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
    final nextPosition =
        _isForwardDirection ? _currentSpotNumber + 1 : _currentSpotNumber - 1;

    setState(() {
      _successMessage =
          'Untagged vine (${ageInYears}y old) queued for position $savedPosition. Ready for position $nextPosition';
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
    // Capture GPS at time of action
    final gpsPosition = _currentPosition;

    // Run the creation operation in the background without blocking the UI
    Future.microtask(() async {
      try {
        debugPrint('Background: Creating untagged vine at position $position');

        final vineyardName = _vineyardNameController.text;
        final fieldName = _fieldNameController.text;
        final rowNumber = int.parse(_rowNumberController.text);
        final currentYear = DateTime.now().year;
        final plantingYear = currentYear - ageInYears;

        // Check if a vine record already exists at this location
        final existingVine = await _databaseService.getVineByLocation(
            vineyardName, fieldName, rowNumber, position);

        final location = VineLocation(
          vineyardName: vineyardName,
          fieldName: fieldName,
          rowNumber: rowNumber,
          spotNumber: position,
          latitude: gpsPosition?.latitude,
          longitude: gpsPosition?.longitude,
          gpsAccuracy: gpsPosition?.accuracy,
        );

        if (existingVine != null) {
          // Update existing vine record with untagged vine data
          final updatedVine = Vine(
            id: existingVine.id,
            alphaNumericID: null,
            isDead: false,
            yearOfPlanting: plantingYear,
            recordCreated: existingVine.recordCreated,
            location: location,
          );
          await _repository.updateVine(updatedVine);
          debugPrint('Background: Updated existing vine at position $position as untagged');
        } else {
          // Create a new vine record for the untagged vine
          final untaggedVine = Vine(
            alphaNumericID: null,
            isDead: false,
            yearOfPlanting: plantingYear,
            location: location,
          );
          await _repository.insertVine(untaggedVine);
          debugPrint('Background: Created new untagged vine at position $position');
        }

        debugPrint('Background: Successfully created untagged vine at position $position');
      } catch (e) {
        debugPrint('Background: Error creating untagged vine: $e');
      }
    });
  }

  Future<void> _markDeadVine() async {
    // Validate that row settings are entered
    if (_vineyardNameController.text.isEmpty ||
        _fieldNameController.text.isEmpty ||
        _rowNumberController.text.isEmpty) {
      setState(() {
        _errorMessage =
            'Please enter vineyard name, field name, and row number first';
      });
      return;
    }

    final int deadPosition = _currentSpotNumber;
    final int nextPosition =
        _isForwardDirection ? _currentSpotNumber + 1 : _currentSpotNumber - 1;

    // Vibrate with a different pattern for dead vine
    Vibration.vibrate(duration: 200);

    setState(() {
      _successMessage =
          'Marked position $deadPosition as dead vine. Ready for position $nextPosition';
      _currentSpotNumber = nextPosition;
      _errorMessage = null;

      _pauseScanner();
    });

    // Resume scanner after a short delay
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        _resumeScanner();
      }
    });

    // Process the dead vine in the background
    _processDeadVineInBackground(deadPosition);
  }

  void _processDeadVineInBackground(int position) {
    // Capture GPS at time of action
    final gpsPosition = _currentPosition;

    Future.microtask(() async {
      try {
        debugPrint('Background: Marking position $position as dead vine');

        final vineyardName = _vineyardNameController.text;
        final fieldName = _fieldNameController.text;
        final rowNumber = int.parse(_rowNumberController.text);

        // Check if a vine record already exists at this location
        final existingVine = await _databaseService.getVineByLocation(
            vineyardName, fieldName, rowNumber, position);

        final location = VineLocation(
          vineyardName: vineyardName,
          fieldName: fieldName,
          rowNumber: rowNumber,
          spotNumber: position,
          latitude: gpsPosition?.latitude,
          longitude: gpsPosition?.longitude,
          gpsAccuracy: gpsPosition?.accuracy,
        );

        if (existingVine != null) {
          // Update existing vine to mark as dead
          final updatedVine = Vine(
            id: existingVine.id,
            alphaNumericID: existingVine.alphaNumericID,
            isDead: true,
            dateDied: DateTime.now(),
            yearOfPlanting: existingVine.yearOfPlanting,
            recordCreated: existingVine.recordCreated,
            location: location,
          );
          await _repository.updateVine(updatedVine);
          debugPrint('Background: Updated existing vine at position $position as dead');
        } else {
          // Create a new vine record marked as dead
          final deadVine = Vine(
            alphaNumericID: null,
            isDead: true,
            dateDied: DateTime.now(),
            location: location,
          );
          await _repository.insertVine(deadVine);
          debugPrint('Background: Created new dead vine at position $position');
        }

        debugPrint('Background: Successfully marked position $position as dead vine');
      } catch (e) {
        debugPrint('Background: Error marking dead vine at position $position: $e');
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

  Widget _buildZoomSelector() {
    if (_zoomPresets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(_isFlashOn ? Icons.flash_off : Icons.flash_on),
            onPressed: _toggleFlash,
            tooltip: _isFlashOn ? 'Flash Off' : 'Flash On',
            color: _isFlashOn ? Colors.amber : Colors.grey[600],
          ),
          const SizedBox(width: 8),
          ..._zoomPresets.map((entry) {
            final isSelected = (_currentZoom - entry.value).abs() < 0.01;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ChoiceChip(
                label: Text(entry.key),
                selected: isSelected,
                onSelected: (_) => _setZoom(entry.value),
                selectedColor: Colors.green,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : null,
                  fontWeight: isSelected ? FontWeight.bold : null,
                  fontSize: 13,
                ),
                visualDensity: VisualDensity.compact,
              ),
            );
          }),
        ],
      ),
    );
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
                        : Colors.white.withValues(alpha: 0.6),
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _repository.isOnline
                        ? 'Backend Connected'
                        : 'Backend Offline',
                    style: TextStyle(
                      fontSize: 12,
                      color: _repository.isOnline
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.6),
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
            icon: Icon(
                _showSettings ? Icons.visibility_off : Icons.settings),
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
              minHeight: MediaQuery.of(context).size.height -
                  AppBar().preferredSize.height -
                  MediaQuery.of(context).padding.top,
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
                    border: Border(
                        bottom: BorderSide(color: Colors.green[200]!)),
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
                            // GPS status indicator
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _currentPosition != null
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _currentPosition != null ? Icons.gps_fixed : Icons.gps_off,
                                    size: 14,
                                    color: _currentPosition != null ? Colors.green[700] : Colors.red[700],
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    _currentPosition != null
                                        ? '${_currentPosition!.accuracy.toStringAsFixed(0)}m'
                                        : 'No GPS',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _currentPosition != null ? Colors.green[700] : Colors.red[700],
                                    ),
                                  ),
                                ],
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
                          InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Vineyard Name',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value:
                                    _vineyardNameController.text.isEmpty
                                        ? null
                                        : _vineyardNameController.text,
                                hint: const Text('Select Vineyard'),
                                isExpanded: true,
                                items: [
                                  ..._vineyardOptions.map(
                                      (name) => DropdownMenuItem(
                                            value: name,
                                            child: Text(name),
                                          )),
                                  const DropdownMenuItem(
                                    value: '__add_new__',
                                    child: Row(
                                      children: [
                                        Icon(Icons.add, size: 18),
                                        SizedBox(width: 8),
                                        Text('Add New Vineyard...'),
                                      ],
                                    ),
                                  ),
                                ],
                                onChanged: (value) async {
                                  if (value == '__add_new__') {
                                    final newName = await _showAddNewDialog(
                                        'Vineyard Name');
                                    if (newName != null &&
                                        newName.isNotEmpty) {
                                      setState(() {
                                        if (!_vineyardOptions
                                            .contains(newName)) {
                                          _vineyardOptions.add(newName);
                                          _vineyardOptions.sort();
                                        }
                                      });
                                      _onVineyardChanged(newName);
                                    }
                                  } else {
                                    _onVineyardChanged(value);
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Field Name',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _fieldNameController.text.isEmpty
                                    ? null
                                    : _fieldNameController.text,
                                hint: const Text('Select Field'),
                                isExpanded: true,
                                items: [
                                  ..._currentFieldOptions.map(
                                      (name) => DropdownMenuItem(
                                            value: name,
                                            child: Text(name),
                                          )),
                                  const DropdownMenuItem(
                                    value: '__add_new__',
                                    child: Row(
                                      children: [
                                        Icon(Icons.add, size: 18),
                                        SizedBox(width: 8),
                                        Text('Add New Field...'),
                                      ],
                                    ),
                                  ),
                                ],
                                onChanged: (value) async {
                                  if (value == '__add_new__') {
                                    final newName = await _showAddNewDialog(
                                        'Field Name');
                                    if (newName != null &&
                                        newName.isNotEmpty) {
                                      final vineyard =
                                          _vineyardNameController.text;
                                      setState(() {
                                        if (!_currentFieldOptions
                                            .contains(newName)) {
                                          _currentFieldOptions
                                              .add(newName);
                                          _currentFieldOptions.sort();
                                        }
                                        if (vineyard.isNotEmpty) {
                                          _fieldOptionsByVineyard
                                              .putIfAbsent(
                                                  vineyard, () => [])
                                              .add(newName);
                                        }
                                      });
                                      _onFieldChanged(newName);
                                    }
                                  } else {
                                    _onFieldChanged(value);
                                  }
                                },
                              ),
                            ),
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
                                  controller:
                                      _startingPositionController,
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
                                    _currentSpotNumber = int.tryParse(
                                            _startingPositionController
                                                .text) ??
                                        1;
                                    _successMessage =
                                        'Position set to $_currentSpotNumber';
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
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Scanning Direction:',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      Expanded(
                                        child: RadioListTile<bool>(
                                          title:
                                              const Text('Ascending ↑'),
                                          value: true,
                                          groupValue:
                                              _isForwardDirection,
                                          onChanged: (value) {
                                            setState(() {
                                              _isForwardDirection =
                                                  value!;
                                            });
                                          },
                                          dense: true,
                                        ),
                                      ),
                                      Expanded(
                                        child: RadioListTile<bool>(
                                          title: const Text(
                                              'Descending ↓'),
                                          value: false,
                                          groupValue:
                                              _isForwardDirection,
                                          onChanged: (value) {
                                            setState(() {
                                              _isForwardDirection =
                                                  value!;
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
                      // Camera preview
                      if (_isCameraReady && _controller != null)
                        CameraPreview(_controller!)
                      else
                        const Center(child: CircularProgressIndicator()),

                      // Scanner animation overlay
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _isScanning
                                ? Colors.green
                                : Colors.orange,
                            width: 3.0,
                          ),
                          borderRadius: BorderRadius.circular(16.0),
                          boxShadow: [
                            BoxShadow(
                              color: (_isScanning
                                      ? Colors.green
                                      : Colors.orange)
                                  .withValues(alpha: 0.3),
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
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 16),
                          margin:
                              const EdgeInsets.symmetric(horizontal: 50),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
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

                // Zoom selector
                _buildZoomSelector(),

                // Status messages
                if (_errorMessage != null || _successMessage != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12.0, horizontal: 16.0),
                    margin: const EdgeInsets.symmetric(
                        horizontal: 8.0, vertical: 4.0),
                    decoration: BoxDecoration(
                      color: _errorMessage != null
                          ? Colors.red[50]
                          : Colors.green[50],
                      borderRadius: BorderRadius.circular(8.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
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
                            _errorMessage != null
                                ? Icons.error_outline
                                : Icons.check_circle_outline,
                            color: _errorMessage != null
                                ? Colors.red[700]
                                : Colors.green[700],
                            size: 24.0,
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        Expanded(
                          child: Text(
                            _errorMessage ?? _successMessage ?? '',
                            style: TextStyle(
                              color: _errorMessage != null
                                  ? Colors.red[700]
                                  : Colors.green[700],
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
                              Icon(Icons.qr_code_scanner,
                                  color: Colors.green[700]),
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
                                message: _repository.isOnline
                                    ? 'Backend connected - data syncing'
                                    : 'Backend offline - data saved locally',
                                child: Icon(
                                  _repository.isOnline
                                      ? Icons.cloud_done
                                      : Icons.cloud_off,
                                  color: _repository.isOnline
                                      ? Colors.green[700]
                                      : Colors.orange[700],
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),

                      // Position navigation buttons
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                // Go back one position - direction agnostic
                                int prevPosition = _isForwardDirection
                                    ? _currentSpotNumber - 1
                                    : _currentSpotNumber + 1;
                                if (prevPosition > 0) {
                                  setState(() {
                                    _currentSpotNumber = prevPosition;
                                    _successMessage =
                                        'Moved to position $_currentSpotNumber';
                                  });
                                }
                              },
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Previous'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                // Go forward one position - direction agnostic
                                int nextPosition = _isForwardDirection
                                    ? _currentSpotNumber + 1
                                    : _currentSpotNumber - 1;
                                if (nextPosition > 0) {
                                  setState(() {
                                    _currentSpotNumber = nextPosition;
                                    _successMessage =
                                        'Moved to position $_currentSpotNumber';
                                  });
                                }
                              },
                              icon: const Icon(Icons.arrow_forward),
                              label: const Text('Next'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
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
                          label:
                              const Text('Skip Position (No Plant)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 16),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Dead vine button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _markDeadVine,
                          icon: const Icon(Icons.dangerous),
                          label: const Text('Dead Vine'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[700],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 16),
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
                          label:
                              const Text('Vine Exists But No Tag'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 16),
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
