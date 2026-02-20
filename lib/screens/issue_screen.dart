import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../models/issue.dart';
import '../models/issue_type.dart';
import '../services/repository.dart';
import '../services/api/authenticated_image.dart';
import 'image_viewer_screen.dart';

class IssueScreen extends StatefulWidget {
  final int vineId;

  const IssueScreen({super.key, required this.vineId});

  @override
  State<IssueScreen> createState() => _IssueScreenState();
}

class _IssueScreenState extends State<IssueScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final _repository = Repository();
  final _imagePicker = ImagePicker();
  
  bool _isLoading = true;
  bool _isSubmitting = false;
  List<VineIssue> _issues = [];
  List<IssueType> _issueTypes = [];
  int? _selectedIssueTypeId;
  String? _errorMessage;
  String? _selectedImagePath;

  // Mocked user ID (in a real app, this would come from authentication)
  final int _currentUserId = 1;

  @override
  void initState() {
    super.initState();
    _loadIssues();
    _loadIssueTypes();
  }

  Future<void> _loadIssueTypes() async {
    try {
      final types = await _repository.getAllIssueTypes();
      if (mounted) {
        setState(() {
          _issueTypes = types;
        });
      }
    } catch (e) {
      print('Error loading issue types: $e');
    }
  }

  Future<void> _loadIssues() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Use repository to get issues for a vine (this will try API if online, otherwise fallback to local DB)
      final issues = await _repository.getIssuesForVine(widget.vineId);
      
      setState(() {
        _issues = issues;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading issues: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(source: ImageSource.camera);
      
      if (image != null) {
        setState(() {
          _selectedImagePath = image.path;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error capturing image: $e')),
      );
    }
  }

  Future<void> _reportIssue() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() {
        _isSubmitting = true;
        _errorMessage = null;
      });

      try {
        final formValues = _formKey.currentState!.value;
        
        // Create issue
        final issue = VineIssue(
          vineID: widget.vineId,
          issueTypeID: _selectedIssueTypeId,
          description: formValues['description'],
          photoPath: _selectedImagePath,
          dateReported: DateTime.now(),
          reportedBy: _currentUserId,
          isResolved: false,
        );
        
        // Use repository to save issue (will save to both local DB and API if online)
        await _repository.reportIssue(issue);
        
        // Reset form and reload data
        _formKey.currentState?.reset();
        setState(() {
          _selectedImagePath = null;
          _selectedIssueTypeId = null;
        });
        await _loadIssues();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
              _repository.isOnline 
                ? 'Issue reported and synchronized with server' 
                : 'Issue saved locally (offline mode)'
            )),
          );
        }
      } catch (e) {
        setState(() {
          _errorMessage = 'Error reporting issue: $e';
        });
      } finally {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _toggleIssueResolution(VineIssue issue) async {
    try {
      final updatedIssue = VineIssue(
        id: issue.id,
        vineID: issue.vineID,
        description: issue.description,
        photoPath: issue.photoPath,
        dateReported: issue.dateReported,
        reportedBy: issue.reportedBy,
        isResolved: !issue.isResolved,
        dateResolved: !issue.isResolved ? DateTime.now() : null,
        resolvedBy: !issue.isResolved ? _currentUserId : null,
      );
      
      // Use repository to update issue (will update both local DB and API if online)
      await _repository.updateIssue(updatedIssue);
      await _loadIssues();
      
      if (mounted) {
        final action = updatedIssue.isResolved ? 'resolved' : 'reopened';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            _repository.isOnline 
              ? 'Issue $action and synchronized with server' 
              : 'Issue $action locally (offline mode)'
          )),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating issue: $e')),
        );
      }
    }
  }

  Future<void> _showAddIssueTypeDialog() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Issue Type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Type Name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      try {
        final newType = await _repository.createIssueType(IssueType(
          name: nameController.text.trim(),
          description: descController.text.trim().isEmpty
              ? null
              : descController.text.trim(),
        ));
        await _loadIssueTypes();
        setState(() {
          _selectedIssueTypeId = newType.id;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error creating issue type: $e')),
          );
        }
      }
    }

    nameController.dispose();
    descController.dispose();
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
                      onPressed: _loadIssues,
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
                              'Report an Issue',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FormBuilder(
                              key: _formKey,
                              child: Column(
                                children: [
                                  // Issue type dropdown
                                  DropdownButtonFormField<int?>(
                                    value: _selectedIssueTypeId,
                                    decoration: const InputDecoration(
                                      labelText: 'Issue Type',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: [
                                      const DropdownMenuItem<int?>(
                                        value: null,
                                        child: Text('Select type (optional)'),
                                      ),
                                      ..._issueTypes.map((type) => DropdownMenuItem<int?>(
                                            value: type.id,
                                            child: Text(type.name),
                                          )),
                                      const DropdownMenuItem<int?>(
                                        value: -1,
                                        child: Text('+ Add New Type...'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value == -1) {
                                        _showAddIssueTypeDialog();
                                      } else {
                                        setState(() {
                                          _selectedIssueTypeId = value;
                                        });
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  FormBuilderTextField(
                                    name: 'description',
                                    decoration: const InputDecoration(
                                      labelText: 'Description',
                                      border: OutlineInputBorder(),
                                      hintText: 'Describe the issue...',
                                    ),
                                    maxLines: 3,
                                    validator: FormBuilderValidators.required(),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _pickImage,
                                          icon: const Icon(Icons.camera_alt),
                                          label: const Text('Take Photo'),
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(color: Theme.of(context).primaryColor),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_selectedImagePath != null) ...[
                                    const SizedBox(height: 16),
                                    Stack(
                                      alignment: Alignment.topRight,
                                      children: [
                                        GestureDetector(
                                          onTap: () {
                                            // Navigate to full screen image viewer
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => ImageViewerScreen(
                                                  imagePath: _selectedImagePath,
                                                  title: 'Preview Image',
                                                ),
                                              ),
                                            );
                                          },
                                          child: Stack(
                                            alignment: Alignment.bottomRight,
                                            children: [
                                              Container(
                                                height: 150,
                                                width: double.infinity,
                                                decoration: BoxDecoration(
                                                  border: Border.all(color: Colors.grey),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Hero(
                                                  tag: _selectedImagePath!,
                                                  child: Image.file(
                                                    File(_selectedImagePath!),
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                              ),
                                              // Zoom indicator
                                              Positioned(
                                                right: 8,
                                                bottom: 8,
                                                child: Container(
                                                  padding: EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withOpacity(0.6),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Icon(
                                                    Icons.zoom_in,
                                                    color: Colors.white,
                                                    size: 16,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.close, color: Colors.red),
                                          onPressed: () {
                                            setState(() {
                                              _selectedImagePath = null;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: ElevatedButton(
                                      onPressed: _isSubmitting ? null : _reportIssue,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
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
                                          : const Text('Report Issue'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Issues History
                    const SizedBox(height: 24),
                    const Text(
                      'Reported Issues',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_issues.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(
                            child: Text(
                              'No issues reported yet',
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      ...(_issues.map((issue) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: issue.isResolved ? Colors.green : Colors.red,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                title: Text(
                                  issue.description,
                                  style: TextStyle(
                                    decoration: issue.isResolved
                                        ? TextDecoration.lineThrough
                                        : TextDecoration.none,
                                    color: issue.isResolved ? Colors.grey : Colors.black,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (issue.issueTypeID != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Chip(
                                          label: Text(
                                            _issueTypes
                                                .where((t) => t.id == issue.issueTypeID)
                                                .map((t) => t.name)
                                                .firstOrNull ?? 'Type #${issue.issueTypeID}',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Reported: ${DateFormat('yyyy-MM-dd').format(issue.dateReported)}',
                                    ),
                                    if (issue.isResolved && issue.dateResolved != null)
                                      Text(
                                        'Resolved: ${DateFormat('yyyy-MM-dd').format(issue.dateResolved!)}',
                                        style: const TextStyle(color: Colors.green),
                                      ),
                                  ],
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: issue.isResolved ? Colors.green : Colors.red,
                                  child: Icon(
                                    issue.isResolved ? Icons.check : Icons.warning,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              if (issue.hasPhoto)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                  child: GestureDetector(
                                    onTap: () {
                                      // Navigate to full screen image viewer
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ImageViewerScreen(
                                            imageUrl: issue.photoUrl,
                                            imagePath: issue.photoPath,
                                            title: 'Issue Photo',
                                          ),
                                        ),
                                      );
                                    },
                                    child: Stack(
                                      children: [
                                        Container(
                                          height: 150,
                                          width: double.infinity,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.grey.shade300),
                                          ),
                                          child: Hero(
                                            tag: issue.photoUrl ?? issue.photoPath ?? 'issue_image_${issue.id}',
                                            child: issue.photoUrl != null
                                              ? AuthenticatedNetworkImage(
                                                  url: issue.photoUrl!,
                                                  fit: BoxFit.cover,
                                                  width: double.infinity,
                                                  height: double.infinity,
                                                )
                                              : issue.photoPath != null && issue.photoPath!.isNotEmpty
                                                ? Image.file(
                                                    File(issue.photoPath!),
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                    height: double.infinity,
                                                    errorBuilder: (context, error, stackTrace) {
                                                      print('Error loading file image: $error');
                                                      return Center(
                                                        child: Column(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(Icons.broken_image, color: Colors.red),
                                                            const SizedBox(height: 8),
                                                            Text('Failed to load local image', 
                                                              style: TextStyle(color: Colors.red),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  )
                                                : const Center(child: Text('No image available')),
                                          ),
                                        ),
                                        // Zoom indicator in the corner
                                        Positioned(
                                          right: 8,
                                          bottom: 8,
                                          child: Container(
                                            padding: EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(0.6),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Icon(
                                              Icons.zoom_in,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ButtonBar(
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _toggleIssueResolution(issue),
                                    icon: Icon(
                                      issue.isResolved ? Icons.refresh : Icons.check_circle,
                                      color: issue.isResolved ? Colors.orange : Colors.green,
                                    ),
                                    label: Text(
                                      issue.isResolved ? 'Reopen Issue' : 'Mark Resolved',
                                      style: TextStyle(
                                        color: issue.isResolved ? Colors.orange : Colors.green,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList()),
                  ],
                ),
              );
  }
}