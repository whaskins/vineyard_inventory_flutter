import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:intl/intl.dart';
import '../models/maintenance.dart';
import '../services/repository.dart';

class MaintenanceScreen extends StatefulWidget {
  final int vineId;

  const MaintenanceScreen({super.key, required this.vineId});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final _typeFormKey = GlobalKey<FormBuilderState>();
  final _repository = Repository();
  
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _showNewTypeForm = false;
  List<MaintenanceType> _maintenanceTypes = [];
  List<MaintenanceActivity> _activities = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Load maintenance types using the repository
      final types = await _repository.getAllMaintenanceTypes();
      
      // Load maintenance activities for this vine using the repository
      final activities = await _repository.getMaintenanceActivitiesForVine(widget.vineId);
      
      setState(() {
        _maintenanceTypes = types;
        _activities = activities;
        _isLoading = false;
        
        // Show new type form if no types exist
        if (types.isEmpty) {
          _showNewTypeForm = true;
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading maintenance data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _addMaintenanceActivity() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() {
        _isSubmitting = true;
        _errorMessage = null;
      });

      try {
        final formValues = _formKey.currentState!.value;
        
        // Create maintenance activity
        final activity = MaintenanceActivity(
          vineID: widget.vineId,
          typeID: formValues['typeID'],
          activityDate: formValues['activityDate'] ?? DateTime.now(),
          notes: formValues['notes'],
        );
        
        // Save using repository (handles both local DB and API)
        await _repository.addMaintenanceActivity(activity);
        
        // Reset form and reload data
        _formKey.currentState?.reset();
        await _loadData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maintenance activity recorded')),
          );
        }
      } catch (e) {
        setState(() {
          _errorMessage = 'Error recording maintenance: $e';
        });
      } finally {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _addMaintenanceType() async {
    if (_typeFormKey.currentState?.saveAndValidate() ?? false) {
      setState(() {
        _isSubmitting = true;
        _errorMessage = null;
      });

      try {
        final formValues = _typeFormKey.currentState!.value;
        
        // Create maintenance type
        final type = MaintenanceType(
          name: formValues['name'],
          description: formValues['description'],
        );
        
        // Save using repository (handles both local DB and API)
        await _repository.createMaintenanceType(type);
        
        // Reset form and reload data
        _typeFormKey.currentState?.reset();
        setState(() {
          _showNewTypeForm = false;
        });
        await _loadData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maintenance type added')),
          );
        }
      } catch (e) {
        setState(() {
          _errorMessage = 'Error adding maintenance type: $e';
        });
      } finally {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _toggleNewTypeForm() {
    setState(() {
      _showNewTypeForm = !_showNewTypeForm;
    });
  }

  String _getTypeName(int typeId) {
    final type = _maintenanceTypes.firstWhere(
      (t) => t.id == typeId,
      orElse: () => MaintenanceType(id: -1, name: 'Unknown'),
    );
    return type.name;
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
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
                      onPressed: _loadData,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
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
                              'Record Maintenance',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FormBuilder(
                              key: _formKey,
                              child: Column(
                                children: [
                                  if (_maintenanceTypes.isEmpty)
                                    const Text(
                                      'Please add a maintenance type first',
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: Colors.grey,
                                      ),
                                    )
                                  else
                                    FormBuilderDropdown<int>(
                                      name: 'typeID',
                                      decoration: const InputDecoration(
                                        labelText: 'Maintenance Type',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: _maintenanceTypes
                                          .map((type) => DropdownMenuItem(
                                                value: type.id,
                                                child: Text(type.name),
                                              ))
                                          .toList(),
                                      validator: FormBuilderValidators.required(),
                                    ),
                                  const SizedBox(height: 16),
                                  FormBuilderDateTimePicker(
                                    name: 'activityDate',
                                    decoration: const InputDecoration(
                                      labelText: 'Date',
                                      border: OutlineInputBorder(),
                                    ),
                                    inputType: InputType.date,
                                    format: DateFormat('yyyy-MM-dd'),
                                    initialValue: DateTime.now(),
                                    validator: FormBuilderValidators.required(),
                                  ),
                                  const SizedBox(height: 16),
                                  FormBuilderTextField(
                                    name: 'notes',
                                    decoration: const InputDecoration(
                                      labelText: 'Notes',
                                      border: OutlineInputBorder(),
                                      hintText: 'Optional',
                                    ),
                                    maxLines: 3,
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: _maintenanceTypes.isEmpty || _isSubmitting
                                              ? null
                                              : _addMaintenanceActivity,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                          ),
                                          child: _isSubmitting
                                              ? const SizedBox(
                                                  height: 20,
                                                  width: 20,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : const Text('Record Maintenance'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton.icon(
                                        onPressed: _toggleNewTypeForm,
                                        icon: Icon(_showNewTypeForm ? Icons.close : Icons.add),
                                        label: Text(_showNewTypeForm ? 'Cancel' : 'Add Type'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // New Type Form (conditionally displayed)
                    if (_showNewTypeForm)
                      Card(
                        margin: const EdgeInsets.only(top: 16.0),
                        color: Colors.grey[100],
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: FormBuilder(
                            key: _typeFormKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Add Maintenance Type',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                FormBuilderTextField(
                                  name: 'name',
                                  decoration: const InputDecoration(
                                    labelText: 'Type Name',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: FormBuilderValidators.required(),
                                ),
                                const SizedBox(height: 16),
                                FormBuilderTextField(
                                  name: 'description',
                                  decoration: const InputDecoration(
                                    labelText: 'Description',
                                    border: OutlineInputBorder(),
                                    hintText: 'Optional',
                                  ),
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _isSubmitting ? null : _addMaintenanceType,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: _isSubmitting
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text('Add Type'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    
                    // Maintenance History
                    const SizedBox(height: 24),
                    const Text(
                      'Maintenance History',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_activities.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(
                            child: Text(
                              'No maintenance activities recorded yet',
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      ...(_activities.map((activity) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8.0),
                          child: ListTile(
                            title: Text(_getTypeName(activity.typeID)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(DateFormat('yyyy-MM-dd').format(activity.activityDate)),
                                if (activity.notes != null && activity.notes!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      activity.notes!,
                                      style: const TextStyle(fontStyle: FontStyle.italic),
                                    ),
                                  ),
                              ],
                            ),
                            leading: const CircleAvatar(
                              backgroundColor: Colors.green,
                              child: Icon(Icons.eco, color: Colors.white),
                            ),
                          ),
                        );
                      }).toList()),
                  ],
                ),
              );
  }
}