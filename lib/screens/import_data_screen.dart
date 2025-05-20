import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/vine.dart';
import '../services/repository.dart';

class ImportDataScreen extends StatefulWidget {
  const ImportDataScreen({Key? key}) : super(key: key);

  @override
  _ImportDataScreenState createState() => _ImportDataScreenState();
}

class _ImportDataScreenState extends State<ImportDataScreen> {
  final Repository _repository = Repository();
  
  bool _isLoading = false;
  bool _isImporting = false;
  int _totalRecords = 0;
  int _processedRecords = 0;
  int _vinesToUpdate = 0;
  int _vinesNotFound = 0;
  int _vinesUpdated = 0;
  String _status = '';
  List<String> _logs = [];
  
  // JSON path is fixed for this example
  final String _jsonPath = '/Users/whaskins/Downloads/grape_inventory.json';
  
  @override
  void initState() {
    super.initState();
    _checkJsonFile();
  }
  
  Future<void> _checkJsonFile() async {
    setState(() {
      _isLoading = true;
      _status = 'Checking for JSON file...';
    });
    
    try {
      final file = File(_jsonPath);
      if (await file.exists()) {
        // Count records in JSON file
        final String contents = await file.readAsString();
        final List<dynamic> data = jsonDecode(contents);
        
        setState(() {
          _totalRecords = data.length;
          _status = 'Found JSON file with $_totalRecords records';
          _isLoading = false;
        });
      } else {
        setState(() {
          _status = 'JSON file not found at $_jsonPath';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error checking JSON file: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _importData() async {
    if (_isImporting) return;
    
    setState(() {
      _isImporting = true;
      _processedRecords = 0;
      _vinesToUpdate = 0;
      _vinesNotFound = 0;
      _vinesUpdated = 0;
      _logs = [];
      _status = 'Starting import...';
    });
    
    try {
      // Load JSON data
      final file = File(_jsonPath);
      final String contents = await file.readAsString();
      final List<dynamic> data = jsonDecode(contents);
      
      _log('Loaded ${data.length} records from JSON file');
      
      // Process each record
      for (int i = 0; i < data.length; i++) {
        final record = data[i];
        
        if (record['ID'] == null || record['ID'].toString().trim().isEmpty) {
          continue;
        }
        
        final alphaNumericID = record['ID'].toString().trim();
        
        // Check if this vine exists in the database
        final existingVine = await _repository.getVineByAlphaNumericID(alphaNumericID);
        
        if (existingVine == null) {
          _vinesNotFound++;
          if (_vinesNotFound <= 10) {
            // Only log first 10 not found vines to avoid UI clutter
            _log('Vine not found: $alphaNumericID');
          }
          continue;
        }
        
        // Check if we need to update any fields
        bool needsUpdate = false;
        var updatedVine = existingVine;
        
        // Update yearOfPlanting if it's null in the database but exists in the data
        if (existingVine.yearOfPlanting == null && 
            record['Planting Year'] != null && 
            record['Planting Year'].toString().trim().isNotEmpty) {
          
          try {
            final year = int.parse(record['Planting Year'].toString().trim());
            updatedVine = updatedVine.copyWith(yearOfPlanting: year);
            needsUpdate = true;
            _log('Will update yearOfPlanting for $alphaNumericID: $year');
          } catch (e) {
            _log('Invalid year format for $alphaNumericID: ${record['Planting Year']}');
          }
        }
        
        // Update variety if it's null in the database but exists in the data
        if (existingVine.variety == null && 
            record['Variety'] != null && 
            record['Variety'].toString().trim().isNotEmpty) {
          
          final variety = record['Variety'].toString().trim();
          updatedVine = updatedVine.copyWith(variety: variety);
          needsUpdate = true;
          _log('Will update variety for $alphaNumericID: $variety');
        }
        
        // Update rootstock if it's null in the database but exists in the data
        if (existingVine.rootstock == null && 
            record['Rootstock'] != null && 
            record['Rootstock'].toString().trim().isNotEmpty) {
          
          final rootstock = record['Rootstock'].toString().trim();
          updatedVine = updatedVine.copyWith(rootstock: rootstock);
          needsUpdate = true;
          _log('Will update rootstock for $alphaNumericID: $rootstock');
        }
        
        // Update nursery if it's null in the database but exists in the data
        if (existingVine.nursery == null && 
            record['Source Nursery'] != null && 
            record['Source Nursery'].toString().trim().isNotEmpty) {
          
          final nursery = record['Source Nursery'].toString().trim();
          updatedVine = updatedVine.copyWith(nursery: nursery);
          needsUpdate = true;
          _log('Will update nursery for $alphaNumericID: $nursery');
        }
        
        // Update rowNumber if it's null in the database but exists in the data
        if (existingVine.rowNumber == null && 
            record['Row'] != null && 
            record['Row'].toString().trim().isNotEmpty) {
          
          try {
            final rowNum = int.parse(record['Row'].toString().trim());
            updatedVine = updatedVine.copyWith(rowNumber: rowNum);
            needsUpdate = true;
            _log('Will update rowNumber for $alphaNumericID: $rowNum');
          } catch (e) {
            _log('Invalid row number format for $alphaNumericID: ${record['Row']}');
          }
        }
        
        // Update isDead and dateDied if needed
        if (record['Dead'] != null && 
            record['Dead'].toString().trim().toUpperCase() == 'Y') {
          
          if (!existingVine.isDead) {
            updatedVine = updatedVine.copyWith(isDead: true);
            needsUpdate = true;
            _log('Will update isDead for $alphaNumericID to true');
            
            // Try to parse the date dead if available
            if (record['Date dead'] != null && 
                record['Date dead'].toString().trim().isNotEmpty) {
              
              try {
                final deadDateStr = record['Date dead'].toString().trim();
                final deadDate = DateTime.parse(deadDateStr);
                updatedVine = updatedVine.copyWith(dateDied: deadDate);
                _log('Will update dateDied for $alphaNumericID: $deadDate');
              } catch (e) {
                _log('Invalid date format for $alphaNumericID: ${record['Date dead']}');
                // Use current date as fallback
                updatedVine = updatedVine.copyWith(dateDied: DateTime.now());
              }
            } else {
              // If no date provided but marked as dead, use current date
              updatedVine = updatedVine.copyWith(dateDied: DateTime.now());
            }
          }
        }
        
        // Update the vine if any fields need updating
        if (needsUpdate) {
          _vinesToUpdate++;
          try {
            await _repository.updateVine(updatedVine);
            _vinesUpdated++;
            _log('Successfully updated vine: $alphaNumericID');
          } catch (e) {
            _log('Error updating vine $alphaNumericID: $e');
          }
        }
        
        setState(() {
          _processedRecords = i + 1;
        });
        
        // Yield to the main thread to allow UI updates
        await Future.delayed(Duration.zero);
      }
      
      setState(() {
        _status = 'Import completed';
        _isImporting = false;
      });
      
    } catch (e) {
      setState(() {
        _status = 'Error during import: $e';
        _isImporting = false;
      });
    }
  }
  
  void _log(String message) {
    setState(() {
      _logs.add(message);
      // Keep at most 100 log messages
      if (_logs.length > 100) {
        _logs.removeAt(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import CSV Data'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'JSON Import',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text('File: $_jsonPath'),
                          const SizedBox(height: 8),
                          Text('Records: $_totalRecords'),
                          const SizedBox(height: 16),
                          Text('Status: $_status'),
                          const SizedBox(height: 8),
                          if (_isImporting)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: _totalRecords > 0
                                      ? _processedRecords / _totalRecords
                                      : 0,
                                ),
                                const SizedBox(height: 8),
                                Text('Processed: $_processedRecords / $_totalRecords'),
                                Text('Vines to update: $_vinesToUpdate'),
                                Text('Vines updated: $_vinesUpdated'),
                                Text('Vines not found: $_vinesNotFound'),
                              ],
                            ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _isImporting ? null : _importData,
                            child: _isImporting
                                ? const Text('Importing...')
                                : const Text('Start Import'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Logs:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Card(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          return Text(
                            _logs[_logs.length - 1 - index],
                            style: const TextStyle(fontSize: 12),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}