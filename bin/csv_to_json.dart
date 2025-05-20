import 'dart:io';
import 'dart:convert';
import 'package:csv/csv.dart';

// This script only converts the CSV to a JSON format that we can process
// in the Flutter app directly, avoiding the Flutter dependencies issue

void main() async {
  print('Starting CSV to JSON conversion...');
  
  // Path to the CSV file
  final csvFilePath = '/Users/whaskins/Downloads/Grape Inventory - Full Grape Inventory.csv';
  final jsonOutputPath = '/Users/whaskins/Downloads/grape_inventory.json';
  
  // Read the CSV file
  final file = File(csvFilePath);
  if (!await file.exists()) {
    print('Error: CSV file not found at $csvFilePath');
    exit(1);
  }
  
  final csvString = await file.readAsString();
  final csvTable = const CsvToListConverter().convert(csvString);
  
  // Get the header row
  final headers = csvTable[0].map((h) => h.toString().trim()).toList();
  
  // Create JSON array of objects
  final List<Map<String, dynamic>> data = [];
  
  // Process each row in the CSV (skip the header row)
  for (int i = 1; i < csvTable.length; i++) {
    final row = csvTable[i];
    
    // Skip empty rows
    if (row.isEmpty || row.length < headers.length) {
      continue;
    }
    
    final item = <String, dynamic>{};
    
    // Map each column to its header
    for (int j = 0; j < headers.length && j < row.length; j++) {
      final header = headers[j];
      var value = row[j];
      
      // For empty values, set to null
      if (value == null || value.toString().trim().isEmpty) {
        value = null;
      }
      
      item[header] = value;
    }
    
    data.add(item);
    
    // Print progress
    if (i % 100 == 0 || i == csvTable.length - 1) {
      print('Progress: ${i}/${csvTable.length - 1} rows processed');
    }
  }
  
  // Write to JSON file
  final jsonFile = File(jsonOutputPath);
  await jsonFile.writeAsString(jsonEncode(data), flush: true);
  
  print('Conversion complete! JSON file written to: $jsonOutputPath');
  print('Total rows converted: ${data.length}');
}