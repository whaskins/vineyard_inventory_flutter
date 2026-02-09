import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:intl/intl.dart';
import '../models/vine.dart';
import '../models/vine_location.dart';
import '../services/repository.dart';
import '../services/gps_service.dart';
import 'maintenance_screen.dart';
import 'issue_screen.dart';

class VineDetailScreen extends StatefulWidget {
  final String vineId;
  final double? gpsLatitude;
  final double? gpsLongitude;
  final double? gpsAccuracy;

  const VineDetailScreen({
    super.key,
    required this.vineId,
    this.gpsLatitude,
    this.gpsLongitude,
    this.gpsAccuracy,
  });

  @override
  State<VineDetailScreen> createState() => _VineDetailScreenState();
}

class _VineDetailScreenState extends State<VineDetailScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormBuilderState>();
  final _repository = Repository();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isNewVine = false;
  Vine? _vine;
  String? _errorMessage;
  late TabController _tabController;

  // GPS state
  double? _pendingLatitude;
  double? _pendingLongitude;
  double? _pendingGpsAccuracy;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _pendingLatitude = widget.gpsLatitude;
    _pendingLongitude = widget.gpsLongitude;
    _pendingGpsAccuracy = widget.gpsAccuracy;
    _loadVineData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when the screen is shown again
    _loadVineData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadVineData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint('Looking up vine by ID: ${widget.vineId}');
      final vine = await _repository.getVineByAlphaNumericID(widget.vineId);

      setState(() {
        if (vine != null) {
          _vine = vine;
          _isNewVine = false;
          // If vine already has coordinates and no pending GPS from scanner, use existing
          if (_pendingLatitude == null && vine.location?.latitude != null) {
            _pendingLatitude = vine.location!.latitude;
            _pendingLongitude = vine.location!.longitude;
            _pendingGpsAccuracy = vine.location!.gpsAccuracy;
          }
          debugPrint('Found vine: ${widget.vineId}, ID: ${vine.id}');
        } else {
          // Create a new vine with the scanned ID
          _isNewVine = true;
          debugPrint('No vine found with ID: ${widget.vineId}, will create new');
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading vine: $e');
      setState(() {
        _errorMessage = 'Error loading vine data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _updateGpsPosition() async {
    final gpsService = GpsService();
    final position = await gpsService.getCurrentPosition();
    if (position != null && mounted) {
      setState(() {
        _pendingLatitude = position.latitude;
        _pendingLongitude = position.longitude;
        _pendingGpsAccuracy = position.accuracy;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GPS updated (${position.accuracy.toStringAsFixed(1)}m accuracy)')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get GPS position')),
      );
    }
  }

  Future<void> _saveVine() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() {
        _isSaving = true;
        _errorMessage = null;
      });

      try {
        final formValues = _formKey.currentState!.value;

        // Parse row and position numbers
        final rowNumber = int.tryParse(formValues['rowNumber'].toString());
        final spotNumber = int.tryParse(formValues['spotNumber'].toString());

        // Validate required fields
        final fieldName = formValues['fieldName']?.toString() ?? '';

        if (rowNumber == null || spotNumber == null) {
          setState(() {
            _errorMessage = 'Row and Position must be valid numbers';
            _isSaving = false;
          });
          return;
        }

        if (fieldName.isEmpty) {
          setState(() {
            _errorMessage = 'Field name is required';
            _isSaving = false;
          });
          return;
        }

        // Create VineLocation object for location data (including GPS)
        final VineLocation? vineLocation = VineLocation(
          id: _vine?.location?.id,
          alphaNumericId: widget.vineId, // Foreign key to vine
          vineyardName: formValues['vineyardName'] ?? '',
          fieldName: formValues['fieldName'] ?? '',
          rowNumber: rowNumber, // Now validated
          spotNumber: spotNumber, // Now validated
          latitude: _pendingLatitude,
          longitude: _pendingLongitude,
          gpsAccuracy: _pendingGpsAccuracy,
          recordCreated: _vine?.location?.recordCreated,
          updatedAt: _vine?.location?.updatedAt,
        );

        // Convert form values to Vine object
        final Vine vineData = Vine(
          id: _vine?.id,
          alphaNumericID: widget.vineId,
          yearOfPlanting: formValues['yearOfPlanting'] != null && formValues['yearOfPlanting'].toString().isNotEmpty
              ? int.tryParse(formValues['yearOfPlanting'].toString())
              : null,
          nursery: formValues['nursery'],
          variety: formValues['variety'],
          rootstock: formValues['rootstock'],
          isDead: formValues['isDead'] ?? false,
          dateDied: formValues['isDead'] == true
            ? (formValues['dateDied'] ?? DateTime.now())
            : null,
          recordCreated: _vine?.recordCreated,
          location: vineLocation,
        );

        debugPrint('Saving vine: ${vineData.alphaNumericID}, isNew: $_isNewVine');

        if (_isNewVine) {
          // Insert new vine using repository (will save to both local DB and API if online)
          debugPrint('Inserting new vine');
          final savedVine = await _repository.insertVine(vineData);

          setState(() {
            _vine = savedVine;
            _isNewVine = false;
          });

          debugPrint('Vine saved with ID: ${savedVine.id}');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Vine added successfully')),
            );
          }
        } else {
          // Update existing vine using repository (will update both local DB and API if online)
          debugPrint('Updating existing vine with ID: ${vineData.id}');
          final updatedVine = await _repository.updateVine(vineData);

          setState(() {
            _vine = updatedVine;
          });

          debugPrint('Vine updated successfully');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Vine updated successfully')),
            );
          }
        }
      } catch (e) {
        debugPrint('Error saving vine: $e');
        setState(() {
          _errorMessage = 'Error saving vine: $e';
        });
      } finally {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNewVine ? 'Add New Vine' : 'Vine Details'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isSaving ? null : _saveVine,
              tooltip: 'Save',
            ),
        ],
        bottom: !_isNewVine && _vine != null ? TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Details'),
            Tab(text: 'Maintenance'),
            Tab(text: 'Issues'),
          ],
          labelColor: Colors.white, // Set selected tab text color to white
          unselectedLabelColor: Colors.white70, // Set unselected tab text color to slightly transparent white
          indicatorColor: Colors.white, // Set the indicator line color to white
        ) : null,
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadVineData,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : !_isNewVine && _vine != null
            ? TabBarView(
                controller: _tabController,
                children: [
                  _buildVineForm(),
                  MaintenanceScreen(vineId: _vine!.id!),
                  IssueScreen(vineId: _vine!.id!),
                ],
              )
            : _buildVineForm(),
    );
  }

  Widget _buildGpsCard() {
    final hasCoords = _pendingLatitude != null && _pendingLongitude != null;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'GPS Coordinates',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Icon(
                  hasCoords ? Icons.gps_fixed : Icons.gps_off,
                  color: hasCoords ? Colors.green : Colors.grey,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasCoords) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lat: ${_pendingLatitude!.toStringAsFixed(6)}',
                          style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Lon: ${_pendingLongitude!.toStringAsFixed(6)}',
                          style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                  if (_pendingGpsAccuracy != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _pendingGpsAccuracy! <= 5
                            ? Colors.green[100]
                            : _pendingGpsAccuracy! <= 15
                                ? Colors.orange[100]
                                : Colors.red[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_pendingGpsAccuracy!.toStringAsFixed(1)}m',
                        style: TextStyle(
                          fontSize: 12,
                          color: _pendingGpsAccuracy! <= 5
                              ? Colors.green[800]
                              : _pendingGpsAccuracy! <= 15
                                  ? Colors.orange[800]
                                  : Colors.red[800],
                        ),
                      ),
                    ),
                ],
              ),
            ] else
              const Text(
                'No GPS coordinates captured',
                style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _updateGpsPosition,
                icon: const Icon(Icons.my_location, size: 18),
                label: Text(hasCoords ? 'Update GPS' : 'Capture GPS'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVineForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: FormBuilder(
        key: _formKey,
        initialValue: {
          'alphaNumericID': widget.vineId,
          'yearOfPlanting': _vine?.yearOfPlanting?.toString(),
          'nursery': _vine?.nursery,
          'variety': _vine?.variety,
          'rootstock': _vine?.rootstock,
          'vineyardName': _vine?.vineyardName,
          'fieldName': _vine?.fieldName,
          'rowNumber': _vine?.rowNumber?.toString(),
          'spotNumber': _vine?.spotNumber?.toString(),
          'isDead': _vine?.isDead ?? false,
          'dateDied': _vine?.dateDied,
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Vine Identification',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FormBuilderTextField(
                      name: 'alphaNumericID',
                      decoration: const InputDecoration(
                        labelText: 'Vine ID',
                        border: OutlineInputBorder(),
                      ),
                      readOnly: true,
                      validator: FormBuilderValidators.required(),
                    ),
                    const SizedBox(height: 16),
                    FormBuilderTextField(
                      name: 'variety',
                      decoration: const InputDecoration(
                        labelText: 'Variety',
                        border: OutlineInputBorder(),
                        hintText: 'Optional',
                      ),
                    ),
                    const SizedBox(height: 16),
                    FormBuilderTextField(
                      name: 'rootstock',
                      decoration: const InputDecoration(
                        labelText: 'Rootstock',
                        border: OutlineInputBorder(),
                        hintText: 'Optional',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Planting Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FormBuilderTextField(
                      name: 'nursery',
                      decoration: const InputDecoration(
                        labelText: 'Nursery',
                        border: OutlineInputBorder(),
                        hintText: 'Optional',
                      ),
                    ),
                    const SizedBox(height: 16),
                    FormBuilderTextField(
                      name: 'yearOfPlanting',
                      decoration: const InputDecoration(
                        labelText: 'Year Planted',
                        border: OutlineInputBorder(),
                        hintText: 'Optional',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Location',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FormBuilderTextField(
                      name: 'vineyardName',
                      decoration: const InputDecoration(
                        labelText: 'Vineyard',
                        border: OutlineInputBorder(),
                        hintText: 'Optional',
                      ),
                    ),
                    const SizedBox(height: 16),
                    FormBuilderTextField(
                      name: 'fieldName',
                      decoration: const InputDecoration(
                        labelText: 'Field',
                        border: OutlineInputBorder(),
                        hintText: 'Required',
                      ),
                      validator: FormBuilderValidators.required(errorText: 'Field name is required'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FormBuilderTextField(
                            name: 'rowNumber',
                            decoration: const InputDecoration(
                              labelText: 'Row',
                              border: OutlineInputBorder(),
                              hintText: 'Required',
                            ),
                            keyboardType: TextInputType.number,
                            validator: FormBuilderValidators.compose([
                              FormBuilderValidators.required(errorText: 'Row is required'),
                              FormBuilderValidators.numeric(errorText: 'Must be a number'),
                            ]),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FormBuilderTextField(
                            name: 'spotNumber',
                            decoration: const InputDecoration(
                              labelText: 'Position',
                              border: OutlineInputBorder(),
                              hintText: 'Required',
                            ),
                            keyboardType: TextInputType.number,
                            validator: FormBuilderValidators.compose([
                              FormBuilderValidators.required(errorText: 'Position is required'),
                              FormBuilderValidators.numeric(errorText: 'Must be a number'),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildGpsCard(),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FormBuilderCheckbox(
                      name: 'isDead',
                      title: const Text('Plant is dead'),
                      onChanged: (value) {
                        setState(() {
                          // Update the form to show/hide the date died field
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    if (_formKey.currentState?.fields['isDead']?.value == true)
                      FormBuilderDateTimePicker(
                        name: 'dateDied',
                        decoration: const InputDecoration(
                          labelText: 'Date Died',
                          border: OutlineInputBorder(),
                        ),
                        inputType: InputType.date,
                        format: DateFormat('yyyy-MM-dd'),
                        initialValue: _vine?.dateDied ?? DateTime.now(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveVine,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(_isNewVine ? 'Add Vine' : 'Update Vine'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
