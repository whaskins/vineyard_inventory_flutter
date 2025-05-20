import 'dart:io';
import 'dart:async';
import 'package:csv/csv.dart';
import 'package:vineyard_inventory_flutter/models/vine.dart';
import 'package:vineyard_inventory_flutter/services/database_service.dart';
import 'package:vineyard_inventory_flutter/services/repository.dart';

Future<void> main() async {
  print('Starting CSV import process...');
  
  // Initialize database service
  final repository = Repository();
  await repository.initialize();
  
  // Path to the CSV file
  final csvFilePath = '/Users/whaskins/Downloads/Grape Inventory - Full Grape Inventory.csv';
  
  // Read the CSV file
  final file = File(csvFilePath);
  if (!await file.exists()) {
    print('Error: CSV file not found at $csvFilePath');
    exit(1);
  }
  
  final csvString = await file.readAsString();
  final csvTable = const CsvToListConverter().convert(csvString);
  
  // Get the header row to determine column indices
  final headers = csvTable[0].map((h) => h.toString().trim()).toList();
  
  final idIndex = headers.indexWhere((h) => h == 'ID');
  final yearIndex = headers.indexWhere((h) => h == 'Planting Year');
  final varietyIndex = headers.indexWhere((h) => h == 'Variety');
  final rootstockIndex = headers.indexWhere((h) => h == 'Rootstock');
  final nurseryIndex = headers.indexWhere((h) => h == 'Source Nursery');
  final rowIndex = headers.indexWhere((h) => h == 'Row');
  final deadIndex = headers.indexWhere((h) => h == 'Dead');
  final dateDeadIndex = headers.indexWhere((h) => h == 'Date dead');
  
  if (idIndex == -1) {
    print('Error: ID column not found in CSV');
    exit(1);
  }
  
  // Statistics tracking
  int totalRows = csvTable.length - 1; // Excluding header
  int vinesToUpdate = 0;
  int vinesUpdated = 0;
  int vinesNotFound = 0;
  
  // Process each row in the CSV (skip the header row)
  for (int i = 1; i < csvTable.length; i++) {
    final row = csvTable[i];
    
    // Skip empty rows
    if (row.isEmpty || row.length <= idIndex || row[idIndex] == null || row[idIndex].toString().trim().isEmpty) {
      continue;
    }
    
    final alphaNumericID = row[idIndex].toString().trim();
    
    // Check if this vine exists in the database
    final existingVine = await repository.getVineByAlphaNumericID(alphaNumericID);
    
    if (existingVine == null) {
      vinesNotFound++;
      print('Vine not found: $alphaNumericID');
      continue;
    }
    
    // Check if we need to update any fields
    bool needsUpdate = false;
    
    // Prepare updated vine with only the fields that need updating
    final updatedVine = existingVine.copyWith();
    
    // Update yearOfPlanting if it's null in the database but exists in the CSV
    if (existingVine.yearOfPlanting == null && 
        yearIndex >= 0 && 
        row.length > yearIndex && 
        row[yearIndex] != null && 
        row[yearIndex].toString().trim().isNotEmpty) {
      
      try {
        final year = int.parse(row[yearIndex].toString().trim());
        updatedVine = updatedVine.copyWith(yearOfPlanting: year);
        needsUpdate = true;
        print('Will update yearOfPlanting for $alphaNumericID: $year');
      } catch (e) {
        print('Invalid year format for $alphaNumericID: ${row[yearIndex]}');
      }
    }
    
    // Update variety if it's null in the database but exists in the CSV
    if (existingVine.variety == null && 
        varietyIndex >= 0 && 
        row.length > varietyIndex && 
        row[varietyIndex] != null && 
        row[varietyIndex].toString().trim().isNotEmpty) {
      
      final variety = row[varietyIndex].toString().trim();
      updatedVine = updatedVine.copyWith(variety: variety);
      needsUpdate = true;
      print('Will update variety for $alphaNumericID: $variety');
    }
    
    // Update rootstock if it's null in the database but exists in the CSV
    if (existingVine.rootstock == null && 
        rootstockIndex >= 0 && 
        row.length > rootstockIndex && 
        row[rootstockIndex] != null && 
        row[rootstockIndex].toString().trim().isNotEmpty) {
      
      final rootstock = row[rootstockIndex].toString().trim();
      updatedVine = updatedVine.copyWith(rootstock: rootstock);
      needsUpdate = true;
      print('Will update rootstock for $alphaNumericID: $rootstock');
    }
    
    // Update nursery if it's null in the database but exists in the CSV
    if (existingVine.nursery == null && 
        nurseryIndex >= 0 && 
        row.length > nurseryIndex && 
        row[nurseryIndex] != null && 
        row[nurseryIndex].toString().trim().isNotEmpty) {
      
      final nursery = row[nurseryIndex].toString().trim();
      updatedVine = updatedVine.copyWith(nursery: nursery);
      needsUpdate = true;
      print('Will update nursery for $alphaNumericID: $nursery');
    }
    
    // Update rowNumber if it's null in the database but exists in the CSV
    if (existingVine.rowNumber == null && 
        rowIndex >= 0 && 
        row.length > rowIndex && 
        row[rowIndex] != null && 
        row[rowIndex].toString().trim().isNotEmpty) {
      
      try {
        final rowNum = int.parse(row[rowIndex].toString().trim());
        updatedVine = updatedVine.copyWith(rowNumber: rowNum);
        needsUpdate = true;
        print('Will update rowNumber for $alphaNumericID: $rowNum');
      } catch (e) {
        print('Invalid row number format for $alphaNumericID: ${row[rowIndex]}');
      }
    }
    
    // Update isDead and dateDied if needed
    if (deadIndex >= 0 && 
        row.length > deadIndex && 
        row[deadIndex] != null && 
        row[deadIndex].toString().trim().toUpperCase() == 'Y') {
      
      if (!existingVine.isDead) {
        updatedVine = updatedVine.copyWith(isDead: true);
        needsUpdate = true;
        print('Will update isDead for $alphaNumericID to true');
        
        // Try to parse the date dead if available
        if (dateDeadIndex >= 0 && 
            row.length > dateDeadIndex && 
            row[dateDeadIndex] != null && 
            row[dateDeadIndex].toString().trim().isNotEmpty) {
          
          try {
            final deadDateStr = row[dateDeadIndex].toString().trim();
            final deadDate = DateTime.parse(deadDateStr);
            updatedVine = updatedVine.copyWith(dateDied: deadDate);
            print('Will update dateDied for $alphaNumericID: $deadDate');
          } catch (e) {
            print('Invalid date format for $alphaNumericID: ${row[dateDeadIndex]}');
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
      vinesToUpdate++;
      try {
        await repository.updateVine(updatedVine);
        vinesUpdated++;
        print('Successfully updated vine: $alphaNumericID');
      } catch (e) {
        print('Error updating vine $alphaNumericID: $e');
      }
    }
    
    // Print progress every 100 rows
    if (i % 100 == 0 || i == csvTable.length - 1) {
      print('Progress: ${i}/${totalRows} rows processed');
    }
  }
  
  // Print summary
  print('\nCSV Import Summary:');
  print('Total rows in CSV: $totalRows');
  print('Vines not found in database: $vinesNotFound');
  print('Vines that needed updates: $vinesToUpdate');
  print('Vines successfully updated: $vinesUpdated');
  
  print('\nImport completed.');
  exit(0);
}