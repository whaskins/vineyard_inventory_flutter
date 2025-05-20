import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// This script runs directly on your Mac to update the SQLite database
// with data from the CSV (via the JSON we already generated)

void main() async {
  // Initialize FFI for SQLite on desktop
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  print('Starting direct SQLite import...');
  
  // Paths
  final String jsonPath = '/Users/whaskins/Downloads/grape_inventory.json';
  final String dbPath = '/Users/whaskins/dev/vinyard/inventory/vineyard_inventory_flutter/desktop_db.sqlite';
  
  // Check JSON file
  final jsonFile = File(jsonPath);
  if (!await jsonFile.exists()) {
    print('Error: JSON file not found at $jsonPath');
    exit(1);
  }
  
  // Open the database
  print('Opening database at $dbPath');
  final db = await openDatabase(
    dbPath,
    version: 1,
    onCreate: (Database db, int version) async {
      // Create vines table if it doesn't exist
      await db.execute('''
CREATE TABLE vines (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  alphaNumericID TEXT UNIQUE NOT NULL,
  yearOfPlanting INTEGER,
  nursery TEXT,
  variety TEXT,
  rootstock TEXT,
  vineyardName TEXT,
  fieldName TEXT,
  rowNumber INTEGER,
  spotNumber INTEGER,
  isDead INTEGER NOT NULL,
  dateDied TEXT,
  recordCreated TEXT NOT NULL
)
      ''');
    },
  );
  
  // Check if the database is opened successfully
  print('Database opened. Checking for vines table...');
  final tables = await db.query('sqlite_master', 
    where: 'type = ? AND name = ?',
    whereArgs: ['table', 'vines']);
  
  if (tables.isEmpty) {
    print('Error: vines table not found in database');
    await db.close();
    exit(1);
  }
  
  // Load JSON data
  print('Loading JSON data...');
  final String contents = await jsonFile.readAsString();
  final List<dynamic> data = jsonDecode(contents);
  print('Loaded ${data.length} records from JSON file');
  
  // Counters for statistics
  int processedRecords = 0;
  int vinesToUpdate = 0;
  int vinesNotFound = 0;
  int vinesUpdated = 0;
  int vinesInserted = 0;
  
  // Process each record in batches
  final batchSize = 100;
  for (int i = 0; i < data.length; i += batchSize) {
    final end = (i + batchSize < data.length) ? i + batchSize : data.length;
    final batch = data.sublist(i, end);
    
    // Begin transaction for better performance
    await db.transaction((txn) async {
      for (final record in batch) {
        if (record['ID'] == null || record['ID'].toString().trim().isEmpty) {
          continue;
        }
        
        final alphaNumericID = record['ID'].toString().trim();
        
        // Check if vine exists
        final existingVines = await txn.query(
          'vines',
          where: 'alphaNumericID = ?',
          whereArgs: [alphaNumericID],
        );
        
        if (existingVines.isEmpty) {
          vinesNotFound++;
          
          // Option: Insert new vine with data from CSV
          // Uncomment if you want to insert new vines
          /*
          final Map<String, dynamic> newVine = {
            'alphaNumericID': alphaNumericID,
            'isDead': 0,
            'recordCreated': DateTime.now().toIso8601String(),
          };
          
          // Add data from CSV if available
          if (record['Planting Year'] != null && record['Planting Year'].toString().trim().isNotEmpty) {
            try {
              newVine['yearOfPlanting'] = int.parse(record['Planting Year'].toString().trim());
            } catch (e) {
              // Invalid year, ignore
            }
          }
          
          if (record['Variety'] != null && record['Variety'].toString().trim().isNotEmpty) {
            newVine['variety'] = record['Variety'].toString().trim();
          }
          
          if (record['Rootstock'] != null && record['Rootstock'].toString().trim().isNotEmpty) {
            newVine['rootstock'] = record['Rootstock'].toString().trim();
          }
          
          if (record['Source Nursery'] != null && record['Source Nursery'].toString().trim().isNotEmpty) {
            newVine['nursery'] = record['Source Nursery'].toString().trim();
          }
          
          if (record['Row'] != null && record['Row'].toString().trim().isNotEmpty) {
            try {
              newVine['rowNumber'] = int.parse(record['Row'].toString().trim());
            } catch (e) {
              // Invalid row, ignore
            }
          }
          
          // Insert new vine
          await txn.insert('vines', newVine);
          vinesInserted++;
          */
          
          continue;
        }
        
        final existingVine = existingVines.first;
        bool needsUpdate = false;
        final Map<String, dynamic> updates = {};
        
        // Update yearOfPlanting if it's null in the database but exists in the data
        if ((existingVine['yearOfPlanting'] == null) && 
            record['Planting Year'] != null && 
            record['Planting Year'].toString().trim().isNotEmpty) {
          
          try {
            final year = int.parse(record['Planting Year'].toString().trim());
            updates['yearOfPlanting'] = year;
            needsUpdate = true;
          } catch (e) {
            print('Invalid year format for $alphaNumericID: ${record['Planting Year']}');
          }
        }
        
        // Update variety if it's null in the database but exists in the data
        if ((existingVine['variety'] == null) && 
            record['Variety'] != null && 
            record['Variety'].toString().trim().isNotEmpty) {
          
          final variety = record['Variety'].toString().trim();
          updates['variety'] = variety;
          needsUpdate = true;
        }
        
        // Update rootstock if it's null in the database but exists in the data
        if ((existingVine['rootstock'] == null) && 
            record['Rootstock'] != null && 
            record['Rootstock'].toString().trim().isNotEmpty) {
          
          final rootstock = record['Rootstock'].toString().trim();
          updates['rootstock'] = rootstock;
          needsUpdate = true;
        }
        
        // Update nursery if it's null in the database but exists in the data
        if ((existingVine['nursery'] == null) && 
            record['Source Nursery'] != null && 
            record['Source Nursery'].toString().trim().isNotEmpty) {
          
          final nursery = record['Source Nursery'].toString().trim();
          updates['nursery'] = nursery;
          needsUpdate = true;
        }
        
        // Update rowNumber if it's null in the database but exists in the data
        if ((existingVine['rowNumber'] == null) && 
            record['Row'] != null && 
            record['Row'].toString().trim().isNotEmpty) {
          
          try {
            final rowNum = int.parse(record['Row'].toString().trim());
            updates['rowNumber'] = rowNum;
            needsUpdate = true;
          } catch (e) {
            print('Invalid row number format for $alphaNumericID: ${record['Row']}');
          }
        }
        
        // Update isDead and dateDied if needed
        if (record['Dead'] != null && 
            record['Dead'].toString().trim().toUpperCase() == 'Y') {
          
          final currentIsDead = existingVine['isDead'] == 1;
          
          if (!currentIsDead) {
            updates['isDead'] = 1;
            needsUpdate = true;
            
            // Try to parse the date dead if available
            if (record['Date dead'] != null && 
                record['Date dead'].toString().trim().isNotEmpty) {
              
              try {
                final deadDateStr = record['Date dead'].toString().trim();
                final deadDate = DateTime.parse(deadDateStr).toIso8601String();
                updates['dateDied'] = deadDate;
              } catch (e) {
                print('Invalid date format for $alphaNumericID: ${record['Date dead']}');
                // Use current date as fallback
                updates['dateDied'] = DateTime.now().toIso8601String();
              }
            } else {
              // If no date provided but marked as dead, use current date
              updates['dateDied'] = DateTime.now().toIso8601String();
            }
          }
        }
        
        // Update the vine if any fields need updating
        if (needsUpdate) {
          vinesToUpdate++;
          try {
            await txn.update(
              'vines',
              updates,
              where: 'alphaNumericID = ?',
              whereArgs: [alphaNumericID],
            );
            vinesUpdated++;
          } catch (e) {
            print('Error updating vine $alphaNumericID: $e');
          }
        }
        
        processedRecords++;
      }
    });
    
    // Print progress
    print('Progress: ${processedRecords}/${data.length} records processed');
  }
  
  // Close the database
  await db.close();
  
  // Print summary
  print('\nImport Summary:');
  print('Total records processed: $processedRecords');
  print('Vines not found in database: $vinesNotFound');
  print('Vines that needed updates: $vinesToUpdate');
  print('Vines successfully updated: $vinesUpdated');
  print('Vines inserted: $vinesInserted');
  
  print('\nImport completed successfully.');
  print('\nYou can now copy this database file to your device or use the app\'s sync feature.');
}