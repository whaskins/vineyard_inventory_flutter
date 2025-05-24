import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/vine.dart';
import '../models/maintenance.dart';
import '../models/issue.dart';
import 'database_service.dart';
import 'api/auth_service.dart';
import 'api/vine_api_service.dart';
import 'api/maintenance_api_service.dart';
import 'api/issue_api_service.dart';

class Repository {
  static final Repository _instance = Repository._internal();
  factory Repository() => _instance;
  
  Repository._internal();

  // Services
  final DatabaseService _databaseService = DatabaseService();
  final AuthService _authService = AuthService();
  final VineApiService _vineApiService = VineApiService();
  final MaintenanceApiService _maintenanceApiService = MaintenanceApiService();
  final IssueApiService _issueApiService = IssueApiService();

  // Connectivity
  final Connectivity _connectivity = Connectivity();
  bool _isOnline = false;
  
  // Initialize repository
  Future<void> initialize() async {
    // Initialize database
    await _databaseService.database;
    
    // Check initial connectivity
    _isOnline = await _checkConnectivity();
    print('DEBUG: Initial network connectivity: ${_isOnline ? 'online' : 'offline'}');
    
    // Listen for connectivity changes
    _connectivity.onConnectivityChanged.listen((result) async {
      final wasOnline = _isOnline;
      _isOnline = await _checkConnectivity();
      
      print('DEBUG: Network connectivity changed: ${_isOnline ? 'online' : 'offline'}');
      
      // If we just came online, attempt to sync data with the API in the background
      if (!wasOnline && _isOnline) {
        // Short delay to ensure network is stable
        await Future.delayed(const Duration(seconds: 2));
        
        // Check connectivity again to make sure we're still online
        if (!await _checkConnectivity()) {
          print('DEBUG: Lost connectivity during sync delay, aborting sync');
          return;
        }
        
        if (_authService.isAuthenticated()) {
          print('DEBUG: Regained connectivity, triggering background sync...');
          
          // Use a microtask to run sync in the background without blocking the UI
          Future.microtask(() async {
            try {
              print('DEBUG: Starting background sync after connectivity restored');
              
              // Sync all local vines to API
              final syncVinesCount = await syncLocalVinesToAPI();
              print('DEBUG: Synced $syncVinesCount vines to API after connectivity restored');
              
              // Sync all local maintenance types to API
              final syncTypesCount = await syncLocalMaintenanceTypesToAPI();
              print('DEBUG: Synced $syncTypesCount maintenance types to API after connectivity restored');
              
              // Sync all local maintenance activities to API
              final syncActivitiesCount = await syncLocalMaintenanceActivitiesToAPI();
              print('DEBUG: Synced $syncActivitiesCount maintenance activities to API after connectivity restored');
              
              // Then get all vines from API to ensure we have the latest data
              final vines = await getAllVines();
              print('DEBUG: Retrieved ${vines.length} vines from API after connectivity restored');
              
              print('DEBUG: Background sync after connectivity change completed successfully');
            } catch (e) {
              print('DEBUG: Error in background sync after connectivity change: $e');
            }
          });
        } else {
          print('DEBUG: Not authenticated, skipping auto-sync after connectivity change');
        }
      }
    });
  }
  
  // Check if device is online
  Future<bool> _checkConnectivity() async {
    // For web, always assume online for now - we'll check later with actual requests
    if (kIsWeb) {
      try {
        // Use a simple HTTP request instead of InternetAddress lookup for web
        final response = await http.get(Uri.parse('https://www.google.com'));
        return response.statusCode == 200;
      } catch (e) {
        print('DEBUG: Web connectivity check failed: $e');
        return false;
      }
    } else {
      // For mobile, use the usual approach
      try {
        final result = await InternetAddress.lookup('example.com');
        return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      } on SocketException catch (_) {
        return false;
      }
    }
  }
  
  // Get current connectivity status
  bool get isOnline => _isOnline;
  
  // Auth methods
  Future<bool> login(String email, String password) async {
    if (!_isOnline) {
      throw Exception('Internet connection required for login');
    }
    
    try {
      await _authService.login(email, password);
      
      // After successful login, trigger background sync
      print('DEBUG: Login successful, triggering background sync...');
      
      // Use a microtask to run sync in the background without blocking the UI
      Future.microtask(() async {
        try {
          print('DEBUG: Starting background sync after login');
          
          // First sync any local unsynced data to the API
          await syncLocalVinesToAPI();
          await syncLocalMaintenanceTypesToAPI();
          await syncLocalMaintenanceActivitiesToAPI();
          
          // Then force a complete refresh of all data from the API
          await forceRefreshFromAPI();
          
          print('DEBUG: Background sync completed successfully');
        } catch (syncError) {
          print('DEBUG: Error in background sync after login: $syncError');
        }
      });
      
      return true;
    } catch (e) {
      // Forward the specific error from the auth service
      rethrow;
    }
  }
  
  // Force a complete refresh from the API, bypassing the database layer
  // This is exposed so it can be called from outside the class
  Future<void> forceRefreshFromAPI() async {
    if (!_isOnline || !_authService.isAuthenticated()) {
      print('DEBUG: Cannot refresh - offline or not authenticated');
      return;
    }
    
    try {
      print('DEBUG: Forcing complete refresh from API');
      
      // Get all vines from API
      final apiVines = await _vineApiService.getAllVines();
      print('DEBUG: API returned ${apiVines.length} vines');
      
      // Get the database directly for batch operations
      Database db = await _databaseService.database;
      
      // Begin transaction for performance
      await db.transaction((txn) async {
        // Process each API vine, cleaning data and updating local DB
        int updated = 0;
        int varietyUpdates = 0;
        
        // Process in batches to improve performance
        for (var i = 0; i < apiVines.length; i += 50) {
          final end = (i + 50 < apiVines.length) ? i + 50 : apiVines.length;
          final batch = apiVines.sublist(i, end);
          
          print('DEBUG: Processing batch ${i ~/ 50 + 1}/${(apiVines.length / 50).ceil()} (${batch.length} vines)');
          
          for (var apiVine in batch) {
            // Clean up variety field
            var variety = apiVine.variety;
            if (variety != null && variety.trim().isEmpty) {
              variety = null;
            }
            
            // Check if this vine has a variety value that would be considered "Unknown"
            final isUnknown = variety == null || variety.trim().isEmpty;
            
            // Try to get existing vine from database to compare
            final results = await txn.query(
              'vines', 
              where: 'alphaNumericID = ?', 
              whereArgs: [apiVine.alphaNumericID]
            );
            
            if (results.isNotEmpty) {
              // Vine exists - update it directly with API data
              final localVine = Vine.fromMap(results.first);
              
              // Check specifically for variety differences
              final localVariety = localVine.variety;
              final localIsUnknown = localVariety == null || localVariety.trim().isEmpty;
              
              if (isUnknown != localIsUnknown || 
                  (!isUnknown && !localIsUnknown && variety!.trim() != localVariety!.trim())) {
                varietyUpdates++;
                print('DEBUG: Updating variety for ${apiVine.alphaNumericID} from "${localVariety ?? 'null'}" to "${variety ?? 'null'}"');
              }
              
              // Update the vine in database
              await txn.update(
                'vines',
                {
                  'variety': variety,
                  'nursery': apiVine.nursery,
                  'rootstock': apiVine.rootstock,
                  'yearOfPlanting': apiVine.yearOfPlanting,
                  'vineyardName': apiVine.vineyardName,
                  'fieldName': apiVine.fieldName,
                  'rowNumber': apiVine.rowNumber,
                  'spotNumber': apiVine.spotNumber,
                  'isDead': apiVine.isDead ? 1 : 0,
                  'dateDied': apiVine.dateDied?.toIso8601String(),
                  'recordCreated': apiVine.recordCreated.toIso8601String(),
                },
                where: 'alphaNumericID = ?',
                whereArgs: [apiVine.alphaNumericID],
              );
              updated++;
            } else {
              // Vine doesn't exist - insert it
              await txn.insert(
                'vines',
                {
                  'alphaNumericID': apiVine.alphaNumericID,
                  'variety': variety,
                  'nursery': apiVine.nursery,
                  'rootstock': apiVine.rootstock,
                  'yearOfPlanting': apiVine.yearOfPlanting,
                  'vineyardName': apiVine.vineyardName,
                  'fieldName': apiVine.fieldName,
                  'rowNumber': apiVine.rowNumber,
                  'spotNumber': apiVine.spotNumber,
                  'isDead': apiVine.isDead ? 1 : 0,
                  'dateDied': apiVine.dateDied?.toIso8601String(),
                  'recordCreated': apiVine.recordCreated.toIso8601String(),
                },
              );
            }
          }
        }
        
        print('DEBUG: Total vines updated: $updated, variety updates: $varietyUpdates');
      });
      
      print('DEBUG: API refresh complete - counting final variety statistics');
      
      // Print the variety statistics after the update
      final updatedVines = await _databaseService.getAllVines();
      final Map<String, int> varietyStats = {};
      int unknownCount = 0;
      
      for (var vine in updatedVines) {
        if (vine.variety == null || vine.variety!.trim().isEmpty) {
          unknownCount++;
        } else {
          final variety = vine.variety!.trim();
          varietyStats[variety] = (varietyStats[variety] ?? 0) + 1;
        }
      }
      
      if (unknownCount > 0) {
        varietyStats['Unknown'] = unknownCount;
      }
      
      print('DEBUG: Variety statistics after refresh:');
      varietyStats.forEach((variety, count) {
        print('DEBUG:   $variety: $count vines');
      });
      
    } catch (e) {
      print('DEBUG: Error in forceRefreshFromAPI: $e');
    }
  }
  
  // Direct database update of a specific vine from API - used for batch operations
  Future<bool> forceUpdateVineFromAPI(String alphaNumericID) async {
    if (!_isOnline || !_authService.isAuthenticated()) {
      return false;
    }
    
    try {
      print('DEBUG: Force updating vine $alphaNumericID directly from API');
      
      // Get the vine from API
      final apiVine = await _vineApiService.getVineByAlphaNumericId(alphaNumericID);
      if (apiVine == null) {
        print('DEBUG: Vine $alphaNumericID not found in API');
        return false;
      }
      
      // Clean up variety field
      Vine cleanApiVine = apiVine;
      if (apiVine.variety != null && apiVine.variety!.trim().isEmpty) {
        cleanApiVine = apiVine.copyWith(variety: null);
      }
      
      // Update the local database
      await _databaseService.updateVine(cleanApiVine);
      print('DEBUG: Successfully updated vine $alphaNumericID from API');
      return true;
      
    } catch (e) {
      print('DEBUG: Error updating vine $alphaNumericID from API: $e');
      return false;
    }
  }
  
  // Emergency direct update of all varieties from API - bypasses most of the codebase
  // This function directly accesses the database and API service, then does SQL updates
  // to fix the variety issue.
  Future<Map<String, int>> emergencyDirectUpdateVarietiesFromAPI() async {
    if (!_isOnline || !_authService.isAuthenticated()) {
      print('DEBUG: Cannot perform emergency update - offline or not authenticated');
      return {"updated": 0, "errors": 0, "total": 0};
    }
    
    try {
      print('DEBUG: EMERGENCY UPDATE - Starting direct variety update from API');
      
      // Get all vines from API with pagination support - increase max pages to ensure all vines are fetched
      final apiVines = await _vineApiService.getAllVines(pageSize: 250, maxPages: 20);
      print('DEBUG: EMERGENCY UPDATE - API returned ${apiVines.length} vines');
      
      // Get the database directly for SQL operations
      Database db = await _databaseService.database;
      
      int updated = 0;
      int errors = 0;
      
      // Begin transaction for performance and atomicity
      await db.transaction((txn) async {
        // First, delete all vines to ensure a clean slate
        print('DEBUG: EMERGENCY UPDATE - Deleting all existing vines from local database');
        await txn.delete('vines');
        
        // Process each API vine
        for (var apiVine in apiVines) {
          try {
            // Insert the complete vine with all fields
            await txn.insert('vines', {
              'alphaNumericID': apiVine.alphaNumericID,
              'yearOfPlanting': apiVine.yearOfPlanting,
              'nursery': apiVine.nursery,
              'variety': apiVine.variety?.trim(),
              'rootstock': apiVine.rootstock,
              'vineyardName': apiVine.vineyardName,
              'fieldName': apiVine.fieldName,
              'rowNumber': apiVine.rowNumber,
              'spotNumber': apiVine.spotNumber,
              'isDead': apiVine.isDead ? 1 : 0,
              'dateDied': apiVine.dateDied?.toIso8601String(),
              'recordCreated': apiVine.recordCreated.toIso8601String(),
            });
            
            if (apiVine.variety != null && apiVine.variety!.trim().isNotEmpty) {
              updated++;
              if (updated % 50 == 0) {
                print('DEBUG: EMERGENCY UPDATE - Progress: $updated vines with varieties inserted');
              }
            }
          } catch (e) {
            print('DEBUG: EMERGENCY UPDATE - Error inserting ${apiVine.alphaNumericID}: $e');
            errors++;
          }
        }
      });
      
      // Get the counts after update
      final varietyCount = await db.rawQuery('SELECT COUNT(*) as count FROM vines WHERE variety IS NOT NULL AND trim(variety) != ""');
      final totalCount = await db.rawQuery('SELECT COUNT(*) as count FROM vines');
      final hasVariety = varietyCount.first['count'] as int;
      final total = totalCount.first['count'] as int;
      
      print('DEBUG: EMERGENCY UPDATE - Complete: successfully inserted $total vines, $hasVariety with varieties, encountered $errors errors');
      return {
        "updated": updated,
        "errors": errors,
        "total": apiVines.length,
        "with_variety": hasVariety,
        "without_variety": total - hasVariety
      };
    } catch (e) {
      print('DEBUG: EMERGENCY UPDATE - Fatal error: $e');
      return {
        "updated": 0,
        "errors": 1,
        "total": 0
      };
    }
  }
  
  Future<bool> register(String email, String password, String fullName) async {
    if (!_isOnline) {
      throw Exception('Internet connection required for registration');
    }
    
    try {
      await _authService.register(email, password, fullName);
      return true;
    } catch (e) {
      rethrow;
    }
  }
  
  bool get isAuthenticated => _authService.isAuthenticated();
  
  void logout() {
    _authService.logout();
  }
  
  // Vine methods
  Future<Vine?> getVineByAlphaNumericID(String alphaNumericID) async {
    // Try to get from local database first
    Vine? vine = await _databaseService.getVineByAlphaNumericID(alphaNumericID);
    
    // If online and authenticated, try to get from API
    if (_isOnline && _authService.isAuthenticated()) {
      try {
        Vine? apiVine = await _vineApiService.getVineByAlphaNumericId(alphaNumericID);
        
        // If vine exists in API but not locally, save it locally
        if (apiVine != null && vine == null) {
          await _databaseService.insertVine(apiVine);
          return apiVine;
        }
        
        // If vine exists in both API and locally, return API version (more up-to-date)
        if (apiVine != null && vine != null) {
          // Update local copy
          await _databaseService.updateVine(apiVine);
          return apiVine;
        }
      } catch (e) {
        // If API call fails, fall back to local data
        print('API error: $e');
      }
    }
    
    // Return local vine (or null if not found)
    return vine;
  }
  
  Future<Vine?> getVineById(int id) async {
    // Try to get from local database first
    Vine? vine = await _databaseService.getVine(id);
    
    // If online and authenticated, try to get from API
    if (_isOnline && _authService.isAuthenticated()) {
      try {
        Vine? apiVine = await _vineApiService.getVineById(id);
        
        // If vine exists in API, update local copy
        if (apiVine != null) {
          if (vine == null) {
            await _databaseService.insertVine(apiVine);
          } else {
            await _databaseService.updateVine(apiVine);
          }
          return apiVine;
        }
      } catch (e) {
        // If API call fails, fall back to local data
        print('API error: $e');
      }
    }
    
    // Return local vine (or null if not found)
    return vine;
  }
  
  // Get vines from local database only (fast, non-blocking)
  Future<List<Vine>> getLocalVines() async {
    return await _databaseService.getAllVines();
  }
  
  // Start background vine sync (non-blocking)
  Future<void> startBackgroundVineSync() async {
    if (!_isOnline || !_authService.isAuthenticated()) {
      print('DEBUG: Cannot start background sync - offline or not authenticated');
      return;
    }
    
    print('DEBUG: Starting background vine sync');
    
    try {
      // Get API vines in background
      List<Vine> apiVines = await _vineApiService.getAllVines();
      print('DEBUG: Background sync fetched ${apiVines.length} vines from API');
      
      // Get current local vines for comparison
      List<Vine> localVines = await _databaseService.getAllVines();
      print('DEBUG: Background sync comparing with ${localVines.length} local vines');
      
      // Create a map of local vines by alphaNumericID for easier lookup
      final Map<String, Vine> localVineMap = {
        for (var vine in localVines) vine.uniqueIdentifier: vine
      };
      
      int inserted = 0;
      int updated = 0;
      
      // Process each API vine
      for (var apiVine in apiVines) {
        // Clean up variety field first - convert empty strings to null
        Vine cleanApiVine = apiVine;
        if (apiVine.variety != null && apiVine.variety!.trim().isEmpty) {
          cleanApiVine = apiVine.copyWith(variety: null);
        }
        
        final Vine? localVine = localVineMap[cleanApiVine.alphaNumericID];
        
        if (localVine == null) {
          // Vine exists in API but not locally - insert it
          await _databaseService.insertVine(cleanApiVine);
          inserted++;
        } else {
          // Check if we should update (same logic as before but simplified)
          bool shouldUpdate = cleanApiVine.recordCreated.isAfter(
            localVine.recordCreated.add(const Duration(seconds: 5))
          );
          
          if (shouldUpdate) {
            // Create updated vine with local ID but API data
            Vine updatedVine = cleanApiVine.copyWith(id: localVine.id);
            await _databaseService.updateVine(updatedVine);
            updated++;
          }
        }
      }
      
      print('DEBUG: Background sync completed - inserted: $inserted, updated: $updated');
    } catch (e) {
      print('DEBUG: Error in background vine sync: $e');
      rethrow;
    }
  }

  Future<List<Vine>> getAllVines() async {
    
    // Get vines from local database
    List<Vine> localVines = await _databaseService.getAllVines();
    print('Local DB has ${localVines.length} vines');
    
    // If online and authenticated, try to get from API
    if (_isOnline && _authService.isAuthenticated()) {
      print('Online and authenticated, fetching from API');
      try {
        List<Vine> apiVines = await _vineApiService.getAllVines();
        print('API returned ${apiVines.length} vines');
        
        // Create a map of local vines by alphaNumericID for easier lookup
        final Map<String, Vine> localVineMap = {
          for (var vine in localVines) vine.uniqueIdentifier: vine
        };
        
        // Update or insert each API vine in local database with timestamp conflict resolution
        for (var apiVine in apiVines) {
          // Clean up variety field first - convert empty strings to null
          Vine cleanApiVine = apiVine;
          if (apiVine.variety != null && apiVine.variety!.trim().isEmpty) {
            // Create a clean copy with null variety instead of empty string
            cleanApiVine = apiVine.copyWith(variety: null);
            print('DEBUG: Cleaned up empty variety for vine ${apiVine.alphaNumericID}');
          }
          
          final Vine? localVine = localVineMap[cleanApiVine.alphaNumericID];
          
          if (localVine == null) {
            // Vine exists in API but not locally - insert it
            print('Inserting new vine from API: ${cleanApiVine.alphaNumericID}');
            await _databaseService.insertVine(cleanApiVine);
          } else {
            // Vine exists both in API and locally - compare timestamps
            bool apiIsNewer = false;
            
            // Compare timestamps to determine which version is newer
            // Add a small buffer (5 seconds) to avoid false positives due to clock differences
            if (cleanApiVine.recordCreated != null && localVine.recordCreated != null) {
              apiIsNewer = cleanApiVine.recordCreated.isAfter(
                localVine.recordCreated.add(const Duration(seconds: 5))
              );
              
              print('DEBUG: Timestamp comparison for ${cleanApiVine.alphaNumericID}: '
                  'API: ${cleanApiVine.recordCreated}, '
                  'Local: ${localVine.recordCreated}, '
                  'API is newer: $apiIsNewer');
            } else {
              // If timestamps are missing, assume API is newer (safer option)
              apiIsNewer = true;
              print('DEBUG: Missing timestamp for ${cleanApiVine.alphaNumericID}, assuming API is newer');
            }
            
            // Check if key data is actually different, including variety
            bool isVarietyDifferent = false;
            
            // Compare varieties accounting for null and empty strings
            if ((cleanApiVine.variety == null || cleanApiVine.variety!.trim().isEmpty) && 
                (localVine.variety == null || localVine.variety!.trim().isEmpty)) {
              // Both null or empty, not different
              isVarietyDifferent = false;
            } else if ((cleanApiVine.variety == null || cleanApiVine.variety!.trim().isEmpty) != 
                       (localVine.variety == null || localVine.variety!.trim().isEmpty)) {
              // One null, one not
              isVarietyDifferent = true;
            } else {
              // Both non-null, compare trimmed values
              isVarietyDifferent = cleanApiVine.variety!.trim() != localVine.variety!.trim();
            }
            
            bool dataIsDifferent = cleanApiVine.isDead != localVine.isDead ||
                cleanApiVine.vineyardName != localVine.vineyardName ||
                cleanApiVine.fieldName != localVine.fieldName ||
                cleanApiVine.rowNumber != localVine.rowNumber ||
                cleanApiVine.spotNumber != localVine.spotNumber ||
                isVarietyDifferent;
            
            if (dataIsDifferent) {
              if (apiIsNewer) {
                // API data is newer - update local database
                print('DEBUG: API vine ${cleanApiVine.alphaNumericID} is newer than local, updating local database');
                if (isVarietyDifferent) {
                  print('DEBUG: Variety different - API: ${cleanApiVine.variety}, Local: ${localVine.variety}');
                }
                await _databaseService.updateVine(cleanApiVine);
              } else {
                // Local data is newer - we'll handle this in syncLocalVinesToAPI
                print('DEBUG: Local vine ${cleanApiVine.alphaNumericID} is newer than API, keeping local version');
              }
            } else {
              print('DEBUG: Vine ${cleanApiVine.alphaNumericID} data is identical in API and local, no update needed');
            }
          }
        }
        
        // Get updated vines from database
        return await _databaseService.getAllVines();
      } catch (e) {
        // If API call fails, fall back to local data
        print('API error getting vines: $e');
      }
    } else {
      print('Offline or not authenticated. Online: $_isOnline, Auth: ${_authService.isAuthenticated()}');
    }
    
    // Return local vines
    return localVines;
  }
  
  Future<Vine> insertVine(Vine vine) async {
    // Insert into local database
    print('DEBUG: Inserting new vine in repository: ${vine.alphaNumericID}');
    
    Vine localVine = Vine(
      id: await _databaseService.insertVine(vine),
      alphaNumericID: vine.alphaNumericID,
      yearOfPlanting: vine.yearOfPlanting,
      nursery: vine.nursery,
      variety: vine.variety,
      rootstock: vine.rootstock,
      vineyardName: vine.vineyardName,
      fieldName: vine.fieldName,
      rowNumber: vine.rowNumber,
      spotNumber: vine.spotNumber,
      isDead: vine.isDead,
      dateDied: vine.dateDied,
      recordCreated: vine.recordCreated,
    );
    
    print('DEBUG: Local database insert completed, new ID: ${localVine.id}');
    
    // If online and authenticated, insert into API
    if (_isOnline && _authService.isAuthenticated()) {
      print('DEBUG: Online and authenticated, creating vine in API');
      try {
        Vine apiVine = await _vineApiService.createVine(localVine);
        print('DEBUG: API creation successful, returned ID: ${apiVine.id}');
        
        // Update local vine with API vine
        await _databaseService.updateVine(apiVine);
        return apiVine;
      } catch (e) {
        // If API call fails, return local vine
        print('DEBUG: API error creating vine: $e');
      }
    } else {
      print('DEBUG: Offline or not authenticated, skipping API creation. Online: $_isOnline, Auth: ${_authService.isAuthenticated()}');
    }
    
    // Return local vine
    return localVine;
  }
  
  // Insert vine location (for untagged vines in row scan mode)
  Future<Map<String, dynamic>> insertVineLocation(Map<String, dynamic> locationData) async {
    print('DEBUG: Inserting vine location in repository: $locationData');
    
    // If online and authenticated, insert into API
    if (_isOnline && _authService.isAuthenticated()) {
      print('DEBUG: Online and authenticated, creating vine location in API');
      try {
        Map<String, dynamic> apiResponse = await _vineApiService.syncVineLocation(locationData);
        print('DEBUG: API vine location creation successful: $apiResponse');
        return apiResponse;
      } catch (e) {
        print('DEBUG: API error creating vine location: $e');
        throw e;
      }
    } else {
      print('DEBUG: Offline or not authenticated, cannot create vine location. Online: $_isOnline, Auth: ${_authService.isAuthenticated()}');
      throw Exception('Cannot create vine location - offline or not authenticated');
    }
  }
  
  Future<Vine> updateVine(Vine vine) async {
    // Update local database
    print('DEBUG: Updating vine in repository: ${vine.alphaNumericID}, ID: ${vine.id}');
    await _databaseService.updateVine(vine);
    print('DEBUG: Local database update completed');
    
    // If online and authenticated, update API
    if (_isOnline && _authService.isAuthenticated()) {
      print('DEBUG: Online and authenticated, updating vine in API');
      try {
        // Use the new syncVine method which handles both tagged and untagged vines
        print('DEBUG: Syncing vine to API using syncVine method');
        Vine apiVine = await _vineApiService.syncVine(vine);
        print('DEBUG: API sync successful, returned ID: ${apiVine.id}');
        
        // Update local vine with API vine
        await _databaseService.updateVine(apiVine);
        return apiVine;
      } catch (e) {
        // Log the error but continue
        print('DEBUG: API error updating vine: $e');
        
        // If error contains "409", the vine already exists but we couldn't update it
        if (e.toString().contains('409')) {
          print('DEBUG: Received 409 conflict - vine exists but couldn\'t be updated');
          try {
            // Try one more time to get the current state of the vine from API
            // For 409 conflicts, try to sync again since the vine might exist
            Vine? currentVine = await _vineApiService.syncVine(vine);
            if (currentVine != null) {
              print('DEBUG: Retrieved existing vine after 409 conflict');
              // Update local DB with current API state
              await _databaseService.updateVine(currentVine);
              return currentVine;
            }
          } catch (retryError) {
            print('DEBUG: Final retrieval attempt failed: $retryError');
          }
        }
        
        // We still want to return the local vine that was updated
        return vine;
      }
    } else {
      print('DEBUG: Offline or not authenticated, skipping API update. Online: $_isOnline, Auth: ${_authService.isAuthenticated()}');
    }
    
    // Return local vine
    return vine;
  }
  
  Future<void> deleteVine(int id) async {
    // Get the vine first to get its alphanumeric ID
    final vine = await _databaseService.getVine(id);
    
    // Delete from local database
    await _databaseService.deleteVine(id);
    
    // If online and authenticated, delete from API
    if (_isOnline && _authService.isAuthenticated() && vine != null) {
      try {
        // Use alphanumeric ID for API deletion
        // Only delete by alphanumeric ID if the vine has a tag
        if (vine.hasTag) {
          await _vineApiService.deleteVineByAlphaNumericId(vine.alphaNumericID!);
        } else {
          // For vines without tags, delete by numeric ID if available
          if (vine.id != null) {
            await _vineApiService.deleteVine(vine.id!);
          }
        }
      } catch (e) {
        // If API call fails, continue
        print('DEBUG: API error deleting vine: $e');
      }
    }
  }
  
  // Issue methods
  Future<List<VineIssue>> getAllIssues() async {
    List<VineIssue> allIssues = [];
    
    // If online and authenticated, try to get from API
    if (_isOnline && _authService.isAuthenticated()) {
      try {
        List<VineIssue> apiIssues = await _issueApiService.getAllIssues();
        
        // Update or insert each API issue in local database
        for (var apiIssue in apiIssues) {
          await _databaseService.insertVineIssue(apiIssue);
        }
        return apiIssues;
      } catch (e) {
        // If API call fails, build a combined list from local data
        print('API error getting all issues: $e');
        
        // Get all vines
        List<Vine> vines = await _databaseService.getAllVines();
        
        // For each vine, get its issues and add to allIssues
        for (var vine in vines) {
          if (vine.id != null) {
            List<VineIssue> vineIssues = await _databaseService.getIssuesForVine(vine.id!);
            allIssues.addAll(vineIssues);
          }
        }
      }
    } else {
      // If offline, build a combined list from local data
      List<Vine> vines = await _databaseService.getAllVines();
      
      // For each vine, get its issues and add to allIssues
      for (var vine in vines) {
        if (vine.id != null) {
          List<VineIssue> vineIssues = await _databaseService.getIssuesForVine(vine.id!);
          allIssues.addAll(vineIssues);
        }
      }
    }
    
    // Return combined issues
    return allIssues;
  }
  
  Future<List<VineIssue>> getIssuesForVine(int vineId) async {
    // Get issues from local database
    List<VineIssue> issues = await _databaseService.getIssuesForVine(vineId);
    
    // If online and authenticated, try to get from API
    if (_isOnline && _authService.isAuthenticated()) {
      try {
        print('DEBUG: Fetching issues for vine $vineId from API');
        List<VineIssue> apiIssues = await _issueApiService.getIssuesByVineId(vineId);
        print('DEBUG: Successfully received ${apiIssues.length} issues from API');
        
        // Update or insert each API issue in local database
        for (var apiIssue in apiIssues) {
          try {
            await _databaseService.insertVineIssue(apiIssue);
          } catch (dbError) {
            print('DEBUG: Error saving API issue to local database: $dbError');
          }
        }
        return apiIssues;
      } catch (e) {
        // If API call fails, fall back to local data
        print('API error getting issues for vine: $e');
      }
    } else {
      print('DEBUG: Not fetching issues from API - Online: $_isOnline, Auth: ${_authService.isAuthenticated()}');
    }
    
    // Return local issues
    print('DEBUG: Returning ${issues.length} local issues for vine $vineId');
    return issues;
  }
  
  Future<VineIssue?> getIssueById(int id) async {
    VineIssue? issue;
    
    // Get all vines
    List<Vine> vines = await _databaseService.getAllVines();
    
    // Look for the issue in each vine's issues
    for (var vine in vines) {
      if (vine.id != null) {
        List<VineIssue> vineIssues = await _databaseService.getIssuesForVine(vine.id!);
        try {
          issue = vineIssues.firstWhere((i) => i.id == id);
          if (issue != null) break;
        } catch (e) {
          // Issue not found in this vine's issues, continue to next vine
        }
      }
    }
    
    // If online and authenticated, try to get from API
    if (_isOnline && _authService.isAuthenticated()) {
      try {
        VineIssue apiIssue = await _issueApiService.getIssueById(id);
        
        // Update local database
        await _databaseService.insertVineIssue(apiIssue);
        return apiIssue;
      } catch (e) {
        // If API call fails, fall back to local data
        print('API error getting issue by ID: $e');
      }
    }
    
    // Return local issue
    return issue;
  }
  
  Future<VineIssue> reportIssue(VineIssue issue) async {
    // Save to local database
    final localIssue = VineIssue(
      id: await _databaseService.insertVineIssue(issue),
      vineID: issue.vineID,
      description: issue.description,
      photoPath: issue.photoPath,
      dateReported: issue.dateReported,
      reportedBy: issue.reportedBy,
      isResolved: issue.isResolved,
      dateResolved: issue.dateResolved,
      resolvedBy: issue.resolvedBy,
    );
    
    // If online and authenticated, save to API
    if (_isOnline && _authService.isAuthenticated()) {
      try {
        VineIssue apiIssue = await _issueApiService.createIssue(localIssue);
        
        // Update local database with API response
        await _databaseService.updateVineIssue(apiIssue);
        return apiIssue;
      } catch (e) {
        // If API call fails, return local issue
        print('API error reporting issue: $e');
      }
    }
    
    return localIssue;
  }
  
  Future<VineIssue> updateIssue(VineIssue issue) async {
    // Update local database
    await _databaseService.updateVineIssue(issue);
    
    // If online and authenticated, update API
    if (_isOnline && _authService.isAuthenticated()) {
      try {
        VineIssue apiIssue = await _issueApiService.updateIssue(issue);
        
        // Update local database with API response
        await _databaseService.updateVineIssue(apiIssue);
        return apiIssue;
      } catch (e) {
        // If API call fails, return local issue
        print('API error updating issue: $e');
      }
    }
    
    return issue;
  }
  
  Future<void> deleteIssue(int id) async {
    // First, find the issue to get its vineID
    VineIssue? issue = await getIssueById(id);
    
    if (issue != null && issue.id != null) {
      // Get the database to delete the issue using SQL directly
      Database db = await _databaseService.database;
      await db.delete(
        'vineIssues',
        where: 'id = ?',
        whereArgs: [issue.id],
      );
    }
    
    // If online and authenticated, delete from API
    if (_isOnline && _authService.isAuthenticated()) {
      try {
        await _issueApiService.deleteIssue(id);
      } catch (e) {
        // If API call fails, continue
        print('API error deleting issue: $e');
      }
    }
  }
  
  // Maintenance methods
  
  // Get all maintenance types
  Future<List<MaintenanceType>> getAllMaintenanceTypes() async {
    // Get types from local database
    List<MaintenanceType> localTypes = await _databaseService.getAllMaintenanceTypes();
    print('DEBUG: Local DB has ${localTypes.length} maintenance types');
    
    // If online and authenticated, try to get from API
    if (_isOnline && _authService.isAuthenticated()) {
      print('DEBUG: Online and authenticated, fetching maintenance types from API');
      try {
        List<MaintenanceType> apiTypes = await _maintenanceApiService.getAllMaintenanceTypes();
        print('DEBUG: API returned ${apiTypes.length} maintenance types');
        
        // Create a map of local types by name for easier lookup
        final Map<String, MaintenanceType> localTypeMap = {
          for (var type in localTypes) type.name: type
        };
        
        // Update or insert each API type in local database
        for (var apiType in apiTypes) {
          final MaintenanceType? localType = localTypeMap[apiType.name];
          
          if (localType == null) {
            // Type exists in API but not locally - insert it
            print('DEBUG: Inserting new maintenance type from API: ${apiType.name}');
            await _databaseService.insertMaintenanceType(apiType);
          } else {
            // Type exists both in API and locally - update if needed
            if (apiType.description != localType.description) {
              print('DEBUG: Updating existing maintenance type: ${apiType.name}');
              await _databaseService.updateMaintenanceType(apiType);
            }
          }
        }
        
        // Get updated types from database
        return await _databaseService.getAllMaintenanceTypes();
      } catch (e) {
        // If API call fails, fall back to local data
        print('DEBUG: API error getting maintenance types: $e');
      }
    }
    
    // Return local types
    return localTypes;
  }
  
  // Create a maintenance type
  Future<MaintenanceType> createMaintenanceType(MaintenanceType type) async {
    // Insert into local database
    print('DEBUG: Inserting new maintenance type in repository: ${type.name}');
    
    final id = await _databaseService.insertMaintenanceType(type);
    MaintenanceType localType = MaintenanceType(
      id: id,
      name: type.name,
      description: type.description,
    );
    
    // If online and authenticated, insert into API
    if (_isOnline && _authService.isAuthenticated()) {
      print('DEBUG: Online and authenticated, creating maintenance type in API');
      try {
        MaintenanceType apiType = await _maintenanceApiService.createMaintenanceType(localType);
        print('DEBUG: API creation successful, returned ID: ${apiType.id}');
        
        // Update local type with API type
        await _databaseService.updateMaintenanceType(apiType);
        return apiType;
      } catch (e) {
        // If API call fails, return local type
        print('DEBUG: API error creating maintenance type: $e');
      }
    }
    
    // Return local type
    return localType;
  }
  
  // Update a maintenance type
  Future<MaintenanceType> updateMaintenanceType(MaintenanceType type) async {
    // Update local database
    print('DEBUG: Updating maintenance type in repository: ${type.name}');
    await _databaseService.updateMaintenanceType(type);
    
    // If online and authenticated, update API
    if (_isOnline && _authService.isAuthenticated()) {
      print('DEBUG: Online and authenticated, updating maintenance type in API');
      try {
        MaintenanceType apiType = await _maintenanceApiService.updateMaintenanceType(type);
        print('DEBUG: API update successful');
        
        // Update local database with API response
        await _databaseService.updateMaintenanceType(apiType);
        return apiType;
      } catch (e) {
        // If API call fails, return local type
        print('DEBUG: API error updating maintenance type: $e');
      }
    }
    
    // Return local type
    return type;
  }
  
  // Delete a maintenance type
  Future<void> deleteMaintenanceType(int id) async {
    // Delete from local database first
    await _databaseService.deleteMaintenanceType(id);
    
    // If online and authenticated, delete from API
    if (_isOnline && _authService.isAuthenticated()) {
      try {
        await _maintenanceApiService.deleteMaintenanceType(id);
        print('DEBUG: Successfully deleted maintenance type from API');
      } catch (e) {
        print('DEBUG: API error deleting maintenance type: $e');
      }
    }
  }
  
  // Get maintenance activities for a vine
  Future<List<MaintenanceActivity>> getMaintenanceActivitiesForVine(int vineId) async {
    // Get activities from local database
    List<MaintenanceActivity> localActivities = await _databaseService.getMaintenanceActivitiesForVine(vineId);
    print('DEBUG: Local DB has ${localActivities.length} maintenance activities for vine $vineId');
    
    // If online and authenticated, try to get from API
    if (_isOnline && _authService.isAuthenticated()) {
      print('DEBUG: Online and authenticated, fetching maintenance activities from API');
      try {
        List<MaintenanceActivity> apiActivities = await _maintenanceApiService.getMaintenanceActivitiesByVineId(vineId);
        print('DEBUG: API returned ${apiActivities.length} maintenance activities');
        
        // Create a map of local activities by id for easier lookup
        final Map<int, MaintenanceActivity> localActivityMap = {};
        for (var activity in localActivities) {
          if (activity.id != null) {
            localActivityMap[activity.id!] = activity;
          }
        }
        
        // Update or insert each API activity in local database
        for (var apiActivity in apiActivities) {
          if (apiActivity.id != null) {
            final MaintenanceActivity? localActivity = localActivityMap[apiActivity.id];
            
            if (localActivity == null) {
              // Activity exists in API but not locally - insert it
              print('DEBUG: Inserting new maintenance activity from API, ID: ${apiActivity.id}');
              await _databaseService.insertMaintenanceActivity(apiActivity);
            } else {
              // Activity exists both in API and locally - no need to update as maintenance is immutable
              print('DEBUG: Maintenance activity already exists locally, ID: ${apiActivity.id}');
            }
          }
        }
        
        // Get updated activities from database
        return await _databaseService.getMaintenanceActivitiesForVine(vineId);
      } catch (e) {
        // If API call fails, fall back to local data
        print('DEBUG: API error getting maintenance activities: $e');
      }
    }
    
    // Return local activities
    return localActivities;
  }
  
  // Add a maintenance activity
  Future<MaintenanceActivity> addMaintenanceActivity(MaintenanceActivity activity) async {
    // Insert into local database
    print('DEBUG: Inserting new maintenance activity in repository for vine ${activity.vineID}');
    
    final id = await _databaseService.insertMaintenanceActivity(activity);
    MaintenanceActivity localActivity = MaintenanceActivity(
      id: id,
      vineID: activity.vineID,
      typeID: activity.typeID,
      activityDate: activity.activityDate,
      notes: activity.notes,
    );
    
    // If online and authenticated, insert into API
    if (_isOnline && _authService.isAuthenticated()) {
      print('DEBUG: Online and authenticated, creating maintenance activity in API');
      try {
        MaintenanceActivity apiActivity = await _maintenanceApiService.createMaintenanceActivity(localActivity);
        print('DEBUG: API creation successful, returned ID: ${apiActivity.id}');
        
        // Update local activity with API activity
        await _databaseService.updateMaintenanceActivity(apiActivity);
        return apiActivity;
      } catch (e) {
        // If API call fails, return local activity
        print('DEBUG: API error creating maintenance activity: $e');
      }
    }
    
    // Return local activity
    return localActivity;
  }
  
  // Update a maintenance activity
  Future<MaintenanceActivity> updateMaintenanceActivity(MaintenanceActivity activity) async {
    // Update local database
    print('DEBUG: Updating maintenance activity in repository, ID: ${activity.id}');
    await _databaseService.updateMaintenanceActivity(activity);
    
    // If online and authenticated, update API
    if (_isOnline && _authService.isAuthenticated()) {
      print('DEBUG: Online and authenticated, updating maintenance activity in API');
      try {
        MaintenanceActivity apiActivity = await _maintenanceApiService.updateMaintenanceActivity(activity);
        print('DEBUG: API update successful');
        
        // Update local database with API response
        await _databaseService.updateMaintenanceActivity(apiActivity);
        return apiActivity;
      } catch (e) {
        // If API call fails, return local activity
        print('DEBUG: API error updating maintenance activity: $e');
      }
    }
    
    // Return local activity
    return activity;
  }
  
  // Delete a maintenance activity
  Future<void> deleteMaintenanceActivity(int id) async {
    // Delete from local database
    await _databaseService.deleteMaintenanceActivity(id);
    
    // If online and authenticated, delete from API
    if (_isOnline && _authService.isAuthenticated()) {
      try {
        await _maintenanceApiService.deleteMaintenanceActivity(id);
        print('DEBUG: Successfully deleted maintenance activity from API');
      } catch (e) {
        print('DEBUG: API error deleting maintenance activity: $e');
      }
    }
  }
  
  // Bulk add maintenance activities
  Future<List<MaintenanceActivity>> bulkAddMaintenanceActivities(List<MaintenanceActivity> activities) async {
    print('DEBUG: Bulk adding ${activities.length} maintenance activities');
    
    // List to hold the created activities
    List<MaintenanceActivity> createdActivities = [];
    List<String> errors = [];
    
    // First save all activities to local database
    final db = await _databaseService.database;
    await db.transaction((txn) async {
      for (var activity in activities) {
        try {
          // Insert activity to local database
          final id = await txn.insert('maintenanceActivities', activity.toMap());
          
          // Create a local activity with the new ID
          final localActivity = MaintenanceActivity(
            id: id,
            vineID: activity.vineID,
            typeID: activity.typeID,
            activityDate: activity.activityDate,
            notes: activity.notes,
          );
          
          createdActivities.add(localActivity);
        } catch (e) {
          print('DEBUG: Error inserting activity to local database: $e');
          errors.add('Error inserting activity for vine ${activity.vineID}: $e');
        }
      }
    });
    
    print('DEBUG: Inserted ${createdActivities.length} activities to local database');
    
    // If online and authenticated, create in API
    if (_isOnline && _authService.isAuthenticated()) {
      print('DEBUG: Online and authenticated, creating activities in API');
      
      // Process activities in batches to avoid overwhelming the API
      final int batchSize = 10;
      for (var i = 0; i < createdActivities.length; i += batchSize) {
        final end = (i + batchSize < createdActivities.length) ? i + batchSize : createdActivities.length;
        final batch = createdActivities.sublist(i, end);
        
        print('DEBUG: Processing batch ${i ~/ batchSize + 1}/${(createdActivities.length / batchSize).ceil()} (${batch.length} activities)');
        
        // Process each activity in the batch
        for (var j = 0; j < batch.length; j++) {
          try {
            // Check if we're still online before each API call
            if (!await _checkConnectivity()) {
              print('DEBUG: Lost connectivity during API operations, stopping');
              break;
            }
            
            final activity = batch[j];
            print('DEBUG: Creating activity ${j+1}/${batch.length} in API (ID: ${activity.id})');
            
            final apiActivity = await _maintenanceApiService.createMaintenanceActivity(activity);
            print('DEBUG: API creation successful, returned ID: ${apiActivity.id}');
            
            // Update the local activity with the API activity ID
            await _databaseService.updateMaintenanceActivity(apiActivity);
            
            // Update the created activities list with the API activity
            createdActivities[i + j] = apiActivity;
          } catch (e) {
            print('DEBUG: API error creating activity: $e');
            errors.add('Error creating activity in API: $e');
          }
        }
      }
    } else {
      print('DEBUG: Offline or not authenticated, skipping API creation');
    }
    
    if (errors.isNotEmpty) {
      print('DEBUG: Completed with ${errors.length} errors: ${errors.join(', ')}');
    }
    
    return createdActivities;
  }
  
  // Bulk add maintenance activities for a specific vine
  Future<List<MaintenanceActivity>> bulkAddMaintenanceActivitiesForVine(int vineID, List<MaintenanceActivity> activities) async {
    print('DEBUG: Bulk adding ${activities.length} maintenance activities for vine $vineID');
    
    // Ensure all activities have the correct vineID
    final List<MaintenanceActivity> activitiesWithVineID = activities.map((activity) {
      return MaintenanceActivity(
        id: activity.id,
        vineID: vineID,
        typeID: activity.typeID,
        activityDate: activity.activityDate,
        notes: activity.notes,
      );
    }).toList();
    
    // Use the bulk add method
    return await bulkAddMaintenanceActivities(activitiesWithVineID);
  }
  
  // Bulk add the same maintenance activity to multiple vines
  Future<List<MaintenanceActivity>> bulkAddMaintenanceActivityForVines(
    List<int> vineIDs, 
    int typeID, 
    DateTime activityDate, 
    String? notes
  ) async {
    print('DEBUG: Bulk adding maintenance activity of type $typeID to ${vineIDs.length} vines');
    
    // Create a list of activities, one for each vine
    final List<MaintenanceActivity> activities = vineIDs.map((vineID) {
      return MaintenanceActivity(
        vineID: vineID,
        typeID: typeID,
        activityDate: activityDate,
        notes: notes,
      );
    }).toList();
    
    // Use the bulk add method
    return await bulkAddMaintenanceActivities(activities);
  }
  
  // Sync all local maintenance activities to the API
  Future<int> syncLocalMaintenanceActivitiesToAPI() async {
    if (!_isOnline || !_authService.isAuthenticated()) {
      print('DEBUG: Cannot sync maintenance activities - offline or not authenticated');
      return 0;
    }
    
    try {
      print('DEBUG: Starting sync of all local maintenance activities to API');
      
      // Get all maintenance activities from local database
      List<MaintenanceActivity> localActivities = await _databaseService.getAllMaintenanceActivities();
      print('DEBUG: Found ${localActivities.length} local maintenance activities to sync');
      
      int syncCount = 0;
      List<int?> failedActivities = [];
      
      // For each local activity, check if it exists in API and create/update as needed
      for (var localActivity in localActivities) {
        try {
          // Check if we're still online before each API call
          if (!await _checkConnectivity()) {
            print('DEBUG: Lost connectivity during sync, stopping sync process');
            break;
          }
          
          // If activity has no ID, we can't sync it
          if (localActivity.id == null) {
            print('DEBUG: Skipping activity with null ID');
            continue;
          }
          
          try {
            // Try to get activity from API first
            await _maintenanceApiService.getMaintenanceActivityById(localActivity.id!);
            print('DEBUG: Activity ${localActivity.id} exists in API, updating');
            
            // Update the activity in the API
            await _maintenanceApiService.updateMaintenanceActivity(localActivity);
            syncCount++;
            print('DEBUG: Successfully updated activity ${localActivity.id} in API');
          } catch (e) {
            // If not found in API, create it
            if (e.toString().contains('404') || e.toString().contains('not found')) {
              print('DEBUG: Activity ${localActivity.id} not found in API, creating');
              
              try {
                // Create the activity in the API
                final apiActivity = await _maintenanceApiService.createMaintenanceActivity(localActivity);
                print('DEBUG: Successfully created activity in API with ID: ${apiActivity.id}');
                syncCount++;
              } catch (createError) {
                print('DEBUG: Failed to create activity in API: $createError');
                failedActivities.add(localActivity.id);
              }
            } else {
              // For other API errors, add to failed activities
              print('DEBUG: API error checking activity ${localActivity.id}: $e');
              failedActivities.add(localActivity.id);
            }
          }
        } catch (e) {
          print('DEBUG: Unexpected error syncing activity ${localActivity.id}: $e');
          failedActivities.add(localActivity.id);
          // Continue with next activity even if one fails
        }
      }
      
      if (failedActivities.isNotEmpty) {
        print('DEBUG: Failed to sync ${failedActivities.length} activities: ${failedActivities.join(', ')}');
      }
      
      print('DEBUG: Successfully synced $syncCount out of ${localActivities.length} activities');
      return syncCount;
    } catch (e) {
      print('DEBUG: Error in syncLocalMaintenanceActivitiesToAPI: $e');
      return 0;
    }
  }
  
  // Sync all local maintenance types to the API
  Future<int> syncLocalMaintenanceTypesToAPI() async {
    if (!_isOnline || !_authService.isAuthenticated()) {
      print('DEBUG: Cannot sync maintenance types - offline or not authenticated');
      return 0;
    }
    
    try {
      print('DEBUG: Starting sync of all local maintenance types to API');
      
      // Get all maintenance types from local database
      List<MaintenanceType> localTypes = await _databaseService.getAllMaintenanceTypes();
      print('DEBUG: Found ${localTypes.length} local maintenance types to sync');
      
      int syncCount = 0;
      List<int?> failedTypes = [];
      
      // For each local type, check if it exists in API and create/update as needed
      for (var localType in localTypes) {
        try {
          // Check if we're still online before each API call
          if (!await _checkConnectivity()) {
            print('DEBUG: Lost connectivity during sync, stopping sync process');
            break;
          }
          
          // If type has no ID, we can't sync it
          if (localType.id == null) {
            print('DEBUG: Skipping type with null ID');
            continue;
          }
          
          try {
            // Try to get type from API first to check if it exists
            await _maintenanceApiService.getMaintenanceTypeById(localType.id!);
            print('DEBUG: Type ${localType.id} exists in API, updating');
            
            // Update the type in the API
            await _maintenanceApiService.updateMaintenanceType(localType);
            syncCount++;
            print('DEBUG: Successfully updated type ${localType.id} in API');
          } catch (e) {
            // If not found in API, create it
            if (e.toString().contains('404') || e.toString().contains('not found')) {
              print('DEBUG: Type ${localType.id} not found in API, creating');
              
              try {
                // Create the type in the API
                final apiType = await _maintenanceApiService.createMaintenanceType(localType);
                print('DEBUG: Successfully created type in API with ID: ${apiType.id}');
                syncCount++;
              } catch (createError) {
                print('DEBUG: Failed to create type in API: $createError');
                failedTypes.add(localType.id);
              }
            } else {
              // For other API errors, add to failed types
              print('DEBUG: API error checking type ${localType.id}: $e');
              failedTypes.add(localType.id);
            }
          }
        } catch (e) {
          print('DEBUG: Unexpected error syncing type ${localType.id}: $e');
          failedTypes.add(localType.id);
          // Continue with next type even if one fails
        }
      }
      
      if (failedTypes.isNotEmpty) {
        print('DEBUG: Failed to sync ${failedTypes.length} types: ${failedTypes.join(', ')}');
      }
      
      print('DEBUG: Successfully synced $syncCount out of ${localTypes.length} types');
      return syncCount;
    } catch (e) {
      print('DEBUG: Error in syncLocalMaintenanceTypesToAPI: $e');
      return 0;
    }
  }
  
  // Sync all local vines to the API with timestamp-based conflict resolution
  Future<int> syncLocalVinesToAPI() async {
    if (!_isOnline || !_authService.isAuthenticated()) {
      print('DEBUG: Cannot sync vines - offline or not authenticated');
      return 0;
    }
    
    try {
      print('DEBUG: Starting sync of all local vines to API with timestamp-based conflict resolution');
      
      // Get all vines from local database
      List<Vine> localVines = await _databaseService.getAllVines();
      print('DEBUG: Found ${localVines.length} local vines to sync');
      
      int syncCount = 0;
      List<String> failedVines = [];
      
      // For each local vine, send to API if local data is newer
      for (var localVine in localVines) {
        try {
          // Check if we're still online before each API call
          if (!await _checkConnectivity()) {
            print('DEBUG: Lost connectivity during sync, stopping sync process');
            break;
          }
          
          try {
            // Check if vine exists in API (handle both tagged and untagged vines)
            Vine? existingApiVine;
            
            if (localVine.hasTag) {
              // For vines with tags, check by alphaNumericID
              existingApiVine = await _vineApiService.getVineByAlphaNumericId(localVine.alphaNumericID!);
            } else {
              // For vines without tags, we'll need to use the sync method which handles location-based lookup
              print('DEBUG: Vine without tag found: ${localVine.uniqueIdentifier}, will use syncVine method');
            }
            
            if (existingApiVine != null && localVine.hasTag) {
              // Compare timestamps to determine which version is newer
              bool localIsNewer = false;
              
              // If API vine has creation time, compare timestamps
              if (existingApiVine.recordCreated != null) {
                // Compare timestamps to determine which version is newer
                // Add a small buffer (5 seconds) to avoid false positives due to clock differences
                localIsNewer = localVine.recordCreated.isAfter(
                  existingApiVine.recordCreated.add(const Duration(seconds: 5))
                );
                
                print('DEBUG: Timestamp comparison for ${localVine.uniqueIdentifier}: '
                    'Local: ${localVine.recordCreated}, '
                    'API: ${existingApiVine.recordCreated}, '
                    'Local is newer: $localIsNewer');
              } else {
                // If API vine has no timestamp, assume local is newer (safer option)
                localIsNewer = true;
                print('DEBUG: API vine ${localVine.uniqueIdentifier} has no timestamp, assuming local is newer');
              }
              
              // Compare data to see if we need to update
              bool dataIsDifferent = localVine.isDead != existingApiVine.isDead ||
                  localVine.vineyardName != existingApiVine.vineyardName ||
                  localVine.fieldName != existingApiVine.fieldName ||
                  localVine.rowNumber != existingApiVine.rowNumber ||
                  localVine.spotNumber != existingApiVine.spotNumber;
              
              if (dataIsDifferent) {
                if (localIsNewer) {
                  // Local data is newer, update API
                  print('DEBUG: Local vine ${localVine.uniqueIdentifier} is newer than API, updating API');
                  await _vineApiService.updateVine(localVine);
                  syncCount++;
                  print('DEBUG: Successfully updated API with newer local data for ${localVine.uniqueIdentifier}');
                } else {
                  // API data is newer, update local
                  print('DEBUG: API vine ${localVine.uniqueIdentifier} is newer than local, updating local database');
                  await _databaseService.updateVine(existingApiVine);
                  print('DEBUG: Successfully updated local database with newer API data for ${localVine.uniqueIdentifier}');
                }
              } else {
                print('DEBUG: Vine ${localVine.uniqueIdentifier} data is identical in API and local, no update needed');
              }
            } else {
              // Vine doesn't exist in API, or vine without tag - use syncVine method
              print('DEBUG: Vine ${localVine.uniqueIdentifier} not in API or is untagged, syncing with API');
              await _vineApiService.syncVine(localVine);
              syncCount++;
              print('DEBUG: Successfully synced vine ${localVine.uniqueIdentifier}');
            }
          } catch (e) {
            // Handle 404 "Not Found" errors specifically - this indicates the vine doesn't exist
            if (e.toString().contains('404') || e.toString().contains('not found')) {
              print('DEBUG: Vine ${localVine.uniqueIdentifier} confirmed not in API, syncing it');
              
              try {
                // Use syncVine method which handles both tagged and untagged vines
                await _vineApiService.syncVine(localVine);
                syncCount++;
                print('DEBUG: Successfully synced new vine ${localVine.uniqueIdentifier} after 404');
              } catch (createError) {
                print('DEBUG: Failed to create vine after 404: $createError');
                failedVines.add(localVine.uniqueIdentifier);
              }
            } else {
              // For other API errors, add to failed vines
              print('DEBUG: Non-404 error checking vine ${localVine.uniqueIdentifier}: $e');
              failedVines.add(localVine.uniqueIdentifier);
            }
          }
        } catch (e) {
          print('DEBUG: Unexpected error syncing vine ${localVine.uniqueIdentifier}: $e');
          failedVines.add(localVine.uniqueIdentifier);
          // Continue with next vine even if one fails
        }
      }
      
      if (failedVines.isNotEmpty) {
        print('DEBUG: Failed to sync ${failedVines.length} vines: ${failedVines.join(', ')}');
      }
      
      print('DEBUG: Successfully synced $syncCount out of ${localVines.length} vines');
      return syncCount;
    } catch (e) {
      print('DEBUG: Error in syncLocalVinesToAPI: $e');
      return 0;
    }
  }
}