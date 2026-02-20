import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../models/vine.dart';
import '../models/maintenance.dart';
import '../models/issue.dart';
import '../models/issue_type.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  
  DatabaseService._internal();
  
  static Database? _database;
  
  // Get database instance
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  // Initialize database
  Future<Database> _initDatabase() async {
    String path;
    
    if (kIsWeb) {
      // For web platform, use in-memory database
      debugPrint('Running on web, using in-memory database');
      
      // Initialize FFI for web
      sqfliteFfiInit();
      var databaseFactory = databaseFactoryFfi;
      
      // Use a temporary path for web
      path = 'vineyard_inventory_web.db';
      debugPrint('Initializing web database with path: $path');
      
      final db = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 6,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
      return db;
    } else {
      // For mobile platforms, use file-based database
      Directory documentsDirectory = await getApplicationDocumentsDirectory();
      path = join(documentsDirectory.path, 'vineyard_inventory.db');
      debugPrint('Initializing mobile database at path: $path');
      
      try {
        final db = await openDatabase(
          path,
          version: 6,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );
        debugPrint('Database initialized successfully');
        return db;
      } catch (e, stackTrace) {
        debugPrint('Error initializing database: $e');
        debugPrint('Stack trace: $stackTrace');
        rethrow;
      }
    }
  }
  
  // Database creation
  Future<void> _onCreate(Database db, int version) async {
    return _createDatabase(db, version);
  }
  
  // Database upgrade
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    return _upgradeDatabase(db, oldVersion, newVersion);
  }
  
  // Database migration for schema updates
  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    debugPrint('Upgrading database from version $oldVersion to $newVersion');
    
    if (oldVersion == 1 && newVersion >= 2) {
      // Add photoUrl column to vineIssues table for version 2
      await db.execute('ALTER TABLE vineIssues ADD COLUMN photoUrl TEXT');
      debugPrint('Added photoUrl column to vineIssues table');
    }
    
    if (oldVersion <= 2 && newVersion >= 3) {
      // Update vines table to allow nullable alphaNumericID for version 3
      debugPrint('Migrating vines table to support nullable alphaNumericID');
      
      // Create new table with nullable alphaNumericID
      await db.execute('''
        CREATE TABLE vines_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          alphaNumericID TEXT,
          yearOfPlanting INTEGER,
          nursery TEXT,
          variety TEXT,
          rootstock TEXT,
          vineyardName TEXT,
          fieldName TEXT,
          rowNumber INTEGER,
          spotNumber INTEGER,
          isDead INTEGER NOT NULL DEFAULT 0,
          dateDied TEXT,
          recordCreated TEXT NOT NULL
        )
      ''');
      
      // Copy data from old table to new table
      await db.execute('''
        INSERT INTO vines_new (id, alphaNumericID, yearOfPlanting, nursery, variety, rootstock, 
                              vineyardName, fieldName, rowNumber, spotNumber, isDead, dateDied, recordCreated)
        SELECT id, alphaNumericID, yearOfPlanting, nursery, variety, rootstock, 
               vineyardName, fieldName, rowNumber, spotNumber, isDead, dateDied, recordCreated
        FROM vines
      ''');
      
      // Drop old table and rename new table
      await db.execute('DROP TABLE vines');
      await db.execute('ALTER TABLE vines_new RENAME TO vines');
      
      // Add unique constraint for alphaNumericID when not null
      await db.execute('CREATE UNIQUE INDEX idx_vines_alpha_numeric_id ON vines(alphaNumericID) WHERE alphaNumericID IS NOT NULL');
      
      // Add unique constraint for location when alphaNumericID is null
      await db.execute('CREATE UNIQUE INDEX idx_vines_location ON vines(vineyardName, fieldName, rowNumber, spotNumber) WHERE alphaNumericID IS NULL');
      
      debugPrint('Successfully migrated vines table to support nullable alphaNumericID');
    }
    
    if (oldVersion <= 3 && newVersion >= 4) {
      // Add updatedAt column to vines table for version 4 (for delta sync support)
      debugPrint('Adding updatedAt column to vines table for delta sync');
      await db.execute('ALTER TABLE vines ADD COLUMN updatedAt TEXT');
      debugPrint('Successfully added updatedAt column to vines table');
    }

    if (oldVersion <= 4 && newVersion >= 5) {
      // Add GPS coordinate columns to vines table for version 5
      debugPrint('Adding GPS coordinate columns to vines table');
      await db.execute('ALTER TABLE vines ADD COLUMN latitude REAL');
      await db.execute('ALTER TABLE vines ADD COLUMN longitude REAL');
      await db.execute('ALTER TABLE vines ADD COLUMN gpsAccuracy REAL');
      debugPrint('Successfully added GPS coordinate columns to vines table');
    }

    if (oldVersion <= 5 && newVersion >= 6) {
      // Add issue types table and issueTypeID column for version 6
      debugPrint('Adding issueTypes table and issueTypeID column');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS issueTypes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT UNIQUE NOT NULL,
          description TEXT
        )
      ''');
      await db.execute('ALTER TABLE vineIssues ADD COLUMN issueTypeID INTEGER');
      debugPrint('Successfully added issueTypes table and issueTypeID column');
    }
  }
  
  // Create database tables
  Future<void> _createDatabase(Database db, int version) async {
    // Vines table (version 4+ with updatedAt column for delta sync)
    await db.execute('''
      CREATE TABLE vines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        alphaNumericID TEXT,
        yearOfPlanting INTEGER,
        nursery TEXT,
        variety TEXT,
        rootstock TEXT,
        vineyardName TEXT,
        fieldName TEXT,
        rowNumber INTEGER,
        spotNumber INTEGER,
        isDead INTEGER NOT NULL DEFAULT 0,
        dateDied TEXT,
        recordCreated TEXT NOT NULL,
        updatedAt TEXT,
        latitude REAL,
        longitude REAL,
        gpsAccuracy REAL
      )
    ''');
    
    // Add unique constraint for alphaNumericID when not null
    await db.execute('CREATE UNIQUE INDEX idx_vines_alpha_numeric_id ON vines(alphaNumericID) WHERE alphaNumericID IS NOT NULL');
    
    // Add unique constraint for location when alphaNumericID is null
    await db.execute('CREATE UNIQUE INDEX idx_vines_location ON vines(vineyardName, fieldName, rowNumber, spotNumber) WHERE alphaNumericID IS NULL');
    
    // Issue types table
    await db.execute('''
      CREATE TABLE issueTypes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        description TEXT
      )
    ''');

    // Maintenance types table
    await db.execute('''
      CREATE TABLE maintenanceTypes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        description TEXT
      )
    ''');
    
    // Maintenance activities table
    await db.execute('''
      CREATE TABLE maintenanceActivities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vineID INTEGER NOT NULL,
        typeID INTEGER NOT NULL,
        activityDate TEXT NOT NULL,
        notes TEXT,
        FOREIGN KEY (vineID) REFERENCES vines (id) ON DELETE CASCADE,
        FOREIGN KEY (typeID) REFERENCES maintenanceTypes (id) ON DELETE CASCADE
      )
    ''');
    
    // Vine issues table
    await db.execute('''
      CREATE TABLE vineIssues (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vineID INTEGER NOT NULL,
        issueTypeID INTEGER,
        description TEXT NOT NULL,
        photoPath TEXT,
        photoUrl TEXT,
        dateReported TEXT NOT NULL,
        reportedBy INTEGER NOT NULL,
        isResolved INTEGER NOT NULL DEFAULT 0,
        dateResolved TEXT,
        resolvedBy INTEGER,
        FOREIGN KEY (vineID) REFERENCES vines (id) ON DELETE CASCADE,
        FOREIGN KEY (issueTypeID) REFERENCES issueTypes (id) ON DELETE SET NULL
      )
    ''');
  }

  // Clear all data from all tables (used when switching organizations)
  Future<void> clearAllData() async {
    Database db = await database;
    await db.transaction((txn) async {
      await txn.delete('vineIssues');
      await txn.delete('maintenanceActivities');
      await txn.delete('maintenanceTypes');
      await txn.delete('issueTypes');
      await txn.delete('vines');
    });
    debugPrint('All local data cleared');
  }

  // VINE OPERATIONS
  
  // Insert a new vine
  Future<int> insertVine(Vine vine) async {
    Database db = await database;
    debugPrint('Inserting vine into database: ${vine.alphaNumericID}');
    try {
      final result = await db.insert('vines', vine.toMap());
      debugPrint('Vine inserted with result: $result');
      return result;
    } catch (e, stackTrace) {
      debugPrint('Error inserting vine: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  // Get a vine by ID
  Future<Vine?> getVine(int id) async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      'vines',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    if (maps.isNotEmpty) {
      return Vine.fromMap(maps.first);
    }
    return null;
  }
  
  // Get a vine by alphanumeric ID
  Future<Vine?> getVineByAlphaNumericID(String alphaNumericID) async {
    Database db = await database;
    debugPrint('Looking up vine by ID: $alphaNumericID');
    try {
      List<Map<String, dynamic>> maps = await db.query(
        'vines',
        where: 'alphaNumericID = ?',
        whereArgs: [alphaNumericID],
      );
      
      debugPrint('Query returned ${maps.length} results');
      
      if (maps.isNotEmpty) {
        final vine = Vine.fromMap(maps.first);
        debugPrint('Found vine: ${vine.alphaNumericID}, ID: ${vine.id}');
        return vine;
      }
      debugPrint('No vine found with ID: $alphaNumericID');
      return null;
    } catch (e, stackTrace) {
      debugPrint('Error looking up vine: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  // Get vine by location (for vines without tags)
  Future<Vine?> getVineByLocation(String vineyardName, String fieldName, int rowNumber, int spotNumber) async {
    Database db = await database;
    debugPrint('Looking up vine by location: $vineyardName/$fieldName/$rowNumber/$spotNumber');
    
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'vines',
        where: 'vineyardName = ? AND fieldName = ? AND rowNumber = ? AND spotNumber = ?',
        whereArgs: [vineyardName, fieldName, rowNumber, spotNumber],
      );
      
      debugPrint('Query returned ${maps.length} results');
      
      if (maps.isNotEmpty) {
        final vine = Vine.fromMap(maps.first);
        debugPrint('Found vine at location: vineyard=$vineyardName, field=$fieldName, row=$rowNumber, spot=$spotNumber, ID: ${vine.id}');
        return vine;
      }
      debugPrint('No vine found at location: $vineyardName/$fieldName/$rowNumber/$spotNumber');
      return null;
    } catch (e, stackTrace) {
      debugPrint('Error looking up vine by location: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  // Update a vine
  Future<int> updateVine(Vine vine) async {
    Database db = await database;
    debugPrint('Updating vine in database: ${vine.alphaNumericID} with ID: ${vine.id}');
    
    try {
      // Check for existing vine based on alphaNumericID or location
      Vine? existingVine;
      
      if (vine.hasTag) {
        // For vines with tags, check by alphaNumericID
        existingVine = await getVineByAlphaNumericID(vine.alphaNumericID!);
      } else if (vine.vineyardName != null && vine.fieldName != null && 
                 vine.rowNumber != null && vine.spotNumber != null) {
        // For vines without tags, check by location
        existingVine = await getVineByLocation(vine.vineyardName!, vine.fieldName!, vine.rowNumber!, vine.spotNumber!);
      }
      
      if (existingVine != null) {
        if (existingVine.id != vine.id) {
          // The API gave us a vine with a different ID but same alphaNumericID
          // In this case, use the local ID and update that record
          debugPrint('Vine exists with ID ${existingVine.id} but API returned ID ${vine.id}, using local ID');
          
          // Create a modified vine with the local ID
          Vine modifiedVine = Vine(
            id: existingVine.id,
            alphaNumericID: vine.alphaNumericID,
            yearOfPlanting: vine.yearOfPlanting,
            nursery: vine.nursery,
            variety: vine.variety, 
            rootstock: vine.rootstock,
            isDead: vine.isDead,
            dateDied: vine.dateDied,
            recordCreated: vine.recordCreated,
            location: vine.location,
          );
          
          final result = await db.update(
            'vines',
            modifiedVine.toMap(),
            where: 'id = ?',
            whereArgs: [existingVine.id],
          );
          debugPrint('Vine updated with local ID, result: $result');
          return result;
        }
      }
      
      // Normal update case
      final result = await db.update(
        'vines',
        vine.toMap(),
        where: 'id = ?',
        whereArgs: [vine.id],
      );
      debugPrint('Vine updated with result: $result');
      return result;
    } catch (e, stackTrace) {
      debugPrint('Error updating vine: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  // Get all vines
  Future<List<Vine>> getAllVines() async {
    Database db = await database;
    debugPrint('Getting all vines from database');
    try {
      List<Map<String, dynamic>> maps = await db.query('vines');
      debugPrint('Found ${maps.length} vines in database');
      
      final vines = List.generate(maps.length, (i) {
        // Clean up variety field by trimming whitespace or converting empty strings to null
        Map<String, dynamic> vineMap = {...maps[i]};
        if (vineMap['variety'] != null) {
          String varietyValue = vineMap['variety'] as String;
          if (varietyValue.trim().isEmpty) {
            // If variety is just whitespace, set it to null
            vineMap['variety'] = null;
          } else {
            // Otherwise trim any whitespace
            vineMap['variety'] = varietyValue.trim();
          }
        }
        
        return Vine.fromMap(vineMap);
      });
      
      // Log some statistics about varieties
      int nullVarieties = vines.where((v) => v.variety == null).length;
      int nonNullVarieties = vines.where((v) => v.variety != null).length;
      debugPrint('Variety statistics - null: $nullVarieties, non-null: $nonNullVarieties');
      
      if (vines.isNotEmpty) {
        debugPrint('Sample vine IDs: ${vines.take(3).map((v) => v.alphaNumericID).join(', ')}...');
      }
      
      return vines;
    } catch (e, stackTrace) {
      debugPrint('Error getting all vines: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }
  
  // Get vines by field
  Future<List<Vine>> getVinesByField(String fieldName) async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      'vines',
      where: 'fieldName = ?',
      whereArgs: [fieldName],
    );
    
    return List.generate(maps.length, (i) {
      return Vine.fromMap(maps[i]);
    });
  }
  
  // Get vines by position
  Future<List<Vine>> getVinesByPosition(String fieldName, int rowNumber, int spotNumber) async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      'vines',
      where: 'fieldName = ? AND rowNumber = ? AND spotNumber = ?',
      whereArgs: [fieldName, rowNumber, spotNumber],
    );
    
    return List.generate(maps.length, (i) {
      return Vine.fromMap(maps[i]);
    });
  }
  
  // Delete a vine
  Future<int> deleteVine(int id) async {
    Database db = await database;
    return await db.delete(
      'vines',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  // MAINTENANCE OPERATIONS
  
  // Insert a new maintenance type
  Future<int> insertMaintenanceType(MaintenanceType type) async {
    Database db = await database;
    return await db.insert('maintenanceTypes', type.toMap());
  }
  
  // Get all maintenance types
  Future<List<MaintenanceType>> getAllMaintenanceTypes() async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query('maintenanceTypes');
    
    return List.generate(maps.length, (i) {
      return MaintenanceType.fromMap(maps[i]);
    });
  }
  
  // Get a maintenance type by ID
  Future<MaintenanceType?> getMaintenanceType(int id) async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      'maintenanceTypes',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    if (maps.isNotEmpty) {
      return MaintenanceType.fromMap(maps.first);
    }
    return null;
  }
  
  // Update a maintenance type
  Future<int> updateMaintenanceType(MaintenanceType type) async {
    Database db = await database;
    return await db.update(
      'maintenanceTypes',
      type.toMap(),
      where: 'id = ?',
      whereArgs: [type.id],
    );
  }
  
  // Delete a maintenance type
  Future<int> deleteMaintenanceType(int id) async {
    Database db = await database;
    return await db.delete(
      'maintenanceTypes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  // Insert a new maintenance activity
  Future<int> insertMaintenanceActivity(MaintenanceActivity activity) async {
    Database db = await database;
    return await db.insert('maintenanceActivities', activity.toMap());
  }
  
  // Get maintenance activities for a vine
  Future<List<MaintenanceActivity>> getMaintenanceActivitiesForVine(int vineID) async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      'maintenanceActivities',
      where: 'vineID = ?',
      whereArgs: [vineID],
      orderBy: 'activityDate DESC',
    );
    
    return List.generate(maps.length, (i) {
      return MaintenanceActivity.fromMap(maps[i]);
    });
  }
  
  // Get a maintenance activity by ID
  Future<MaintenanceActivity?> getMaintenanceActivity(int id) async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      'maintenanceActivities',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    if (maps.isNotEmpty) {
      return MaintenanceActivity.fromMap(maps.first);
    }
    return null;
  }
  
  // Get all maintenance activities
  Future<List<MaintenanceActivity>> getAllMaintenanceActivities() async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      'maintenanceActivities',
      orderBy: 'activityDate DESC',
    );
    
    return List.generate(maps.length, (i) {
      return MaintenanceActivity.fromMap(maps[i]);
    });
  }
  
  // Update a maintenance activity
  Future<int> updateMaintenanceActivity(MaintenanceActivity activity) async {
    Database db = await database;
    return await db.update(
      'maintenanceActivities',
      activity.toMap(),
      where: 'id = ?',
      whereArgs: [activity.id],
    );
  }
  
  // Delete a maintenance activity
  Future<int> deleteMaintenanceActivity(int id) async {
    Database db = await database;
    return await db.delete(
      'maintenanceActivities',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  
  // ISSUE TYPE OPERATIONS

  // Insert a new issue type
  Future<int> insertIssueType(IssueType type) async {
    Database db = await database;
    return await db.insert('issueTypes', type.toMap());
  }

  // Get all issue types
  Future<List<IssueType>> getAllIssueTypes() async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query('issueTypes');
    return List.generate(maps.length, (i) {
      return IssueType.fromMap(maps[i]);
    });
  }

  // Get an issue type by ID
  Future<IssueType?> getIssueType(int id) async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      'issueTypes',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return IssueType.fromMap(maps.first);
    }
    return null;
  }

  // Update an issue type
  Future<int> updateIssueType(IssueType type) async {
    Database db = await database;
    return await db.update(
      'issueTypes',
      type.toMap(),
      where: 'id = ?',
      whereArgs: [type.id],
    );
  }

  // Delete an issue type
  Future<int> deleteIssueType(int id) async {
    Database db = await database;
    return await db.delete(
      'issueTypes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Get all unresolved issues (for problems map)
  Future<List<Map<String, dynamic>>> getUnresolvedIssuesWithVineLocation() async {
    Database db = await database;
    return await db.rawQuery('''
      SELECT vi.*, v.latitude, v.longitude, v.alphaNumericID as vineAlphaNumericID
      FROM vineIssues vi
      INNER JOIN vines v ON vi.vineID = v.id
      WHERE vi.isResolved = 0
        AND v.latitude IS NOT NULL
        AND v.longitude IS NOT NULL
    ''');
  }

  // ISSUES OPERATIONS
  
  // Insert a new vine issue
  Future<int> insertVineIssue(VineIssue issue) async {
    Database db = await database;
    return await db.insert('vineIssues', issue.toMap());
  }
  
  // Update a vine issue
  Future<int> updateVineIssue(VineIssue issue) async {
    Database db = await database;
    return await db.update(
      'vineIssues',
      issue.toMap(),
      where: 'id = ?',
      whereArgs: [issue.id],
    );
  }
  
  // Get issues for a vine
  Future<List<VineIssue>> getIssuesForVine(int vineID) async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      'vineIssues',
      where: 'vineID = ?',
      whereArgs: [vineID],
      orderBy: 'dateReported DESC',
    );
    
    return List.generate(maps.length, (i) {
      return VineIssue.fromMap(maps[i]);
    });
  }
  
  // Batch insert vines for better performance
  Future<void> batchInsertVines(List<Vine> vines) async {
    if (vines.isEmpty) return;
    
    Database db = await database;
    Batch batch = db.batch();
    
    for (var vine in vines) {
      batch.insert('vines', vine.toMap());
    }
    
    await batch.commit(noResult: true);
    print('DEBUG: Batch inserted ${vines.length} vines');
  }
  
  // Batch update vines for better performance  
  Future<void> batchUpdateVines(List<Vine> vines) async {
    if (vines.isEmpty) return;
    
    Database db = await database;
    Batch batch = db.batch();
    
    for (var vine in vines) {
      batch.update(
        'vines', 
        vine.toMap(),
        where: 'id = ?',
        whereArgs: [vine.id],
      );
    }
    
    await batch.commit(noResult: true);
    print('DEBUG: Batch updated ${vines.length} vines');
  }
}