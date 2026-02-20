import '../../models/api/vine_api.dart';
import '../../models/vine.dart';
import '../../models/sync_models.dart';
import 'api_service.dart';

class VineApiService {
  final ApiService _apiService = ApiService();
  final String _endpoint = '/vines';

  // Get all vines with pagination support
  Future<List<Vine>> getAllVines({int pageSize = 1000, int maxPages = 10}) async {
    try {
      List<Vine> allVines = [];
      int currentPage = 0;
      bool hasMoreData = true;
      
      print('DEBUG: Getting all vines with pagination (pageSize=$pageSize, maxPages=$maxPages)');
      
      // Continue fetching pages until we have all data or reach max pages
      while (hasMoreData && currentPage < maxPages) {
        final skip = currentPage * pageSize;
        
        // Check if the API supports pagination parameters
        String paginatedEndpoint = '$_endpoint/?skip=$skip&limit=$pageSize';
        print('DEBUG: Fetching page $currentPage (skip=$skip, limit=$pageSize)');
        
        try {
          final response = await _apiService.get(paginatedEndpoint);
          
          // Handle different API response formats
          List<dynamic> vinesJson;
          
          if (response is List) {
            print('DEBUG: Response is a List with ${response.length} items');
            vinesJson = response;
          } else if (response is Map) {
            if (response.containsKey('data') && response['data'] is List) {
              print('DEBUG: Response is a Map with data List: ${response['data'].length} items');
              vinesJson = response['data'];
            } else {
              // Try to find some array in the response
              final possibleArrays = response.entries
                .where((entry) => entry.value is List)
                .map((entry) => entry.value as List)
                .toList();
                
              if (possibleArrays.isNotEmpty) {
                print('DEBUG: Found array in response with ${possibleArrays.first.length} items');
                vinesJson = possibleArrays.first;
              } else {
                print('DEBUG: No array found in response, using empty list');
                vinesJson = [];
              }
            }
          } else {
            print('DEBUG: Response is neither List nor Map: $response');
            vinesJson = [];
          }
          
          // Convert JSON to Vine models using the new API format
          final pageVines = vinesJson
              .map((json) {
                try {
                  return Vine.fromApiJson(json);
                } catch (e) {
                  print('DEBUG: Error parsing vine: $e for json: $json');
                  return null;
                }
              })
              .where((vine) => vine != null)
              .cast<Vine>()
              .toList();
          
          print('DEBUG: Page $currentPage: Received ${pageVines.length} vines');
          
          // Add this page's vines to the complete list
          allVines.addAll(pageVines);
          
          // If we got fewer items than the page size, assume we've reached the end
          if (pageVines.length < pageSize) {
            hasMoreData = false;
            print('DEBUG: End of data reached (received ${pageVines.length} < page size $pageSize)');
          }
          
          // Move to the next page
          currentPage++;
          
        } catch (pageError) {
          print('DEBUG: Error fetching page $currentPage: $pageError');
          // If fetching a page fails, stop pagination to avoid infinite loops
          hasMoreData = false;
        }
      }
      
      print('DEBUG: Total vines fetched across all pages: ${allVines.length}');
      return allVines;
      
    } catch (e) {
      print('DEBUG: Error in getAllVines: $e');
      rethrow;
    }
  }

  // Get a vine by ID
  Future<Vine?> getVineById(int id) async {
    try {
      final response = await _apiService.get('$_endpoint/$id');
      print('DEBUG: Processing API response for getVineById($id)');
      
      // Handle different API response formats
      Map<String, dynamic>? jsonData;
      
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data') && response['data'] is Map<String, dynamic>) {
          print('DEBUG: Response has data object');
          jsonData = response['data'];
        } else {
          print('DEBUG: Using response as is');
          jsonData = response;
        }
      } else {
        print('DEBUG: Unexpected response type: ${response.runtimeType}');
        return null;
      }
      
      if (jsonData == null) {
        print('DEBUG: No valid vine data found in response');
        return null;
      }
      
      try {
        return Vine.fromApiJson(jsonData);
      } catch (e) {
        print('DEBUG: Error parsing vine: $e for json: $jsonData');
        return null;
      }
    } catch (e) {
      print('DEBUG: Error in getVineById: $e');
      rethrow;
    }
  }

  // Get a vine by alphanumeric ID
  Future<Vine?> getVineByAlphaNumericId(String alphaNumericId) async {
    try {
      // Use the correct endpoint format: /by-alpha-id/{alpha_id} instead of /code/{alpha_id}
      final response = await _apiService.get('$_endpoint/by-alpha-id/$alphaNumericId');
      print('DEBUG: Processing API response for getVineByAlphaNumericId($alphaNumericId)');
      
      if (response == null) {
        print('DEBUG: Response is null');
        return null;
      }
      
      // Handle different API response formats
      Map<String, dynamic>? jsonData;
      
      if (response is Map<String, dynamic>) {
        if (response.containsKey('data') && response['data'] is Map<String, dynamic>) {
          print('DEBUG: Response has data object');
          jsonData = response['data'];
        } else {
          print('DEBUG: Using response as is');
          jsonData = response;
        }
      } else {
        print('DEBUG: Unexpected response type: ${response.runtimeType}');
        return null;
      }
      
      if (jsonData == null) {
        print('DEBUG: No valid vine data found in response');
        return null;
      }
      
      try {
        return Vine.fromApiJson(jsonData);
      } catch (e) {
        print('DEBUG: Error parsing vine: $e for json: $jsonData');
        return null;
      }
    } catch (e) {
      print('DEBUG: Error in getVineByAlphaNumericId: $e');
      rethrow;
    }
  }

  // Create a new vine
  Future<Vine> createVine(Vine vine) async {
    try {
      final vineApi = VineApiModel.fromLocalModel(vine);
      print('DEBUG: Creating new vine with data: ${vineApi.toJson()}');
      
      try {
        // First check if the vine already exists to avoid 409 conflicts
        print('DEBUG: Checking if vine exists before creating');
        try {
          final checkResponse = await _apiService.get('$_endpoint/by-alpha-id/${vine.alphaNumericID}');
          print('DEBUG: Vine already exists, using existing ID ${checkResponse['id']}');
          
          // Vine exists, so use PUT update instead
          final updateResponse = await _apiService.put('$_endpoint/${checkResponse['id']}', vineApi.toJson());
          print('DEBUG: Updated existing vine instead of creating new one');
          
          // Process the response
          if (updateResponse is Map<String, dynamic>) {
            if (updateResponse.containsKey('data') && updateResponse['data'] is Map<String, dynamic>) {
              return Vine.fromApiJson(updateResponse['data']);
            } else {
              return Vine.fromApiJson(updateResponse);
            }
          }
          
          return vine;
        } catch (checkError) {
          // Vine doesn't exist, proceed with creation
          print('DEBUG: Vine does not exist, proceeding with creation');
          
          final response = await _apiService.post('$_endpoint/', vineApi.toJson());
          print('DEBUG: Processing API response for createVine()');
          
          // Handle different API response formats
          Map<String, dynamic>? jsonData;
          
          if (response is Map<String, dynamic>) {
            if (response.containsKey('data') && response['data'] is Map<String, dynamic>) {
              print('DEBUG: Response has data object');
              jsonData = response['data'];
            } else {
              print('DEBUG: Using response as is');
              jsonData = response;
            }
          } else {
            print('DEBUG: Unexpected response type: ${response.runtimeType}');
            // Return the original vine as fallback
            return vine;
          }
          
          if (jsonData == null) {
            print('DEBUG: No valid vine data found in response');
            return vine;
          }
          
          try {
            return Vine.fromApiJson(jsonData);
          } catch (e) {
            print('DEBUG: Error parsing vine: $e for json: $jsonData');
            return vine;
          }
        }
      } catch (e) {
        // If we get a 409 Conflict error during creation
        if (e.toString().contains('409')) {
          print('DEBUG: Received 409 conflict during creation, attempting to get existing vine');
          try {
            // Try to get the existing vine
            final existingVine = vine.hasTag ? await getVineByAlphaNumericId(vine.alphaNumericID!) : null;
            if (existingVine != null) {
              print('DEBUG: Successfully retrieved existing vine after 409');
              return existingVine;
            }
          } catch (getError) {
            print('DEBUG: Failed to get existing vine after 409: $getError');
          }
        }
        
        print('DEBUG: Error in createVine: $e');
        // Return the original vine if API fails
        return vine;
      }
    } catch (e) {
      print('DEBUG: Error in createVine outer block: $e');
      // Return the original vine if API fails
      return vine;
    }
  }

  // Sync vine to backend - handles both tagged and untagged vines
  Future<Vine> syncVine(Vine vine) async {
    try {
      // For vines with tags, use the existing alphaNumericID-based sync
      if (vine.hasTag) {
        return await updateVine(vine);
      }
      
      // For vines without tags, use location-based sync
      return await syncVineByLocation(vine);
    } catch (e) {
      print('DEBUG: Error in syncVine: $e');
      return vine;
    }
  }
  
  // Sync vine without tag using location information
  Future<Vine> syncVineByLocation(Vine vine) async {
    try {
      if (vine.vineyardName == null || vine.fieldName == null || 
          vine.rowNumber == null || vine.spotNumber == null) {
        print('DEBUG: Cannot sync vine without tag - missing location information');
        throw Exception('Vine without tag must have complete location information');
      }
      
      print('DEBUG: Syncing vine without tag using location: ${vine.vineyardName}/${vine.fieldName}/${vine.rowNumber}/${vine.spotNumber}');
      
      // For vines without tags, we need to create/update a VineLocation record
      final locationData = {
        'vineyard_name': vine.vineyardName,
        'field_name': vine.fieldName,
        'row_number': vine.rowNumber,
        'spot_number': vine.spotNumber,
        'year_of_planting': vine.yearOfPlanting,
        'alpha_numeric_id': null, // No tag for this vine
        'latitude': vine.location?.latitude,
        'longitude': vine.location?.longitude,
        'gps_accuracy': vine.location?.gpsAccuracy,
        'is_dead': vine.isDead,
        'date_died': vine.dateDied?.toIso8601String(),
      };
      
      try {
        // Use the new vine location sync endpoint
        final response = await _apiService.put('$_endpoint/locations/sync', locationData);
        print('DEBUG: Synced vine location without tag');
        
        if (response is Map<String, dynamic>) {
          try {
            // Convert the VineLocation response back to a Vine model for compatibility
            final updatedVine = vine.copyWith(
              id: response['id'],
              // Keep all existing vine data, just update the ID if needed
            );
            return updatedVine;
          } catch (e) {
            print('DEBUG: Error parsing synced vine location: $e');
            return vine;
          }
        }
        
        return vine;
      } catch (syncError) {
        print('DEBUG: Error syncing vine location: $syncError');
        return vine;
      }
    } catch (e) {
      print('DEBUG: Error in syncVineByLocation: $e');
      return vine;
    }
  }
  
  // First check if vine exists, then either create or update it
  Future<Vine> updateVine(Vine vine) async {
    try {
      if (vine.alphaNumericID == null || vine.alphaNumericID!.isEmpty) {
        print('DEBUG: Vine alphaNumericID is null/empty - use syncVineByLocation instead');
        return await syncVineByLocation(vine);
      }
      
      final vineApi = VineApiModel.fromLocalModel(vine);
      print('DEBUG: Processing vine ${vine.alphaNumericID} for API update');
      
      // First check if the vine exists in the API
      try {
        print('DEBUG: Checking if vine exists in API');
        // Try to get by alphanumeric ID
        try {
          final checkResponse = await _apiService.get('$_endpoint/by-alpha-id/${vine.alphaNumericID}');
          print('DEBUG: Vine exists in API - will update');
          
          // Vine exists, so update it
          final response = await _apiService.put('$_endpoint/${checkResponse['id']}', vineApi.toJson());
          print('DEBUG: Vine updated via ID endpoint');
          
          // Parse and return the updated vine
          Map<String, dynamic>? jsonData;
          if (response is Map<String, dynamic>) {
            if (response.containsKey('data') && response['data'] is Map<String, dynamic>) {
              jsonData = response['data'];
            } else {
              jsonData = response;
            }
            
            try {
              if (jsonData != null) {
                return Vine.fromApiJson(jsonData);
              } else {
                print('DEBUG: jsonData is null, returning original vine');
                return vine;
              }
            } catch (e) {
              print('DEBUG: Error parsing updated vine: $e');
              return vine;
            }
          }
          
          return vine;
        } catch (getError) {
          // If direct get fails, try to query for it
          print('DEBUG: Direct get failed, trying to query all vines: $getError');
          
          // Get all vines and search for matching alphaNumericID
          final allVines = await _apiService.get('$_endpoint/');
          if (allVines is List) {
            print('DEBUG: Searching through ${allVines.length} vines for matching ID');
            for (var item in allVines) {
              if (item is Map && item['alpha_numeric_id'] == vine.alphaNumericID) {
                print('DEBUG: Found vine in all vines query, will update');
                // Update the vine
                final response = await _apiService.put('$_endpoint/${item['id']}', vineApi.toJson());
                print('DEBUG: Vine updated via ID endpoint');
                
                if (response is Map<String, dynamic>) {
                  try {
                    Map<String, dynamic> responseData = response;
                    return Vine.fromApiJson(responseData);
                  } catch (e) {
                    print('DEBUG: Error parsing updated vine: $e');
                    return vine;
                  }
                }
                return vine;
              }
            }
          } else if (allVines is Map && allVines.containsKey('data') && allVines['data'] is List) {
            print('DEBUG: Searching through ${allVines['data'].length} vines for matching ID');
            for (var item in allVines['data']) {
              if (item is Map && item['alpha_numeric_id'] == vine.alphaNumericID) {
                print('DEBUG: Found vine in all vines query, will update');
                // Update the vine
                final response = await _apiService.put('$_endpoint/${item['id']}', vineApi.toJson());
                print('DEBUG: Vine updated via ID endpoint');
                
                if (response is Map<String, dynamic>) {
                  try {
                    Map<String, dynamic> responseData = response;
                    return Vine.fromApiJson(responseData);
                  } catch (e) {
                    print('DEBUG: Error parsing updated vine: $e');
                    return vine;
                  }
                }
                return vine;
              }
            }
          }
          
          // If we get here, the vine doesn't exist in any of our queries, so try to create it
          throw Exception('Vine not found in API');
        }
      } catch (queryError) {
        // Only create the vine if we've exhausted all search options and it truly doesn't exist
        print('DEBUG: Vine truly not found in API: $queryError');
        
        // Attempt to create a new vine, but handle 409 conflict properly
        print('DEBUG: Attempting to create new vine in API');
        try {
          final createResponse = await _apiService.post('$_endpoint/', vineApi.toJson());
          print('DEBUG: Create response received');
          
          if (createResponse is Map<String, dynamic>) {
            Map<String, dynamic>? createData;
            if (createResponse.containsKey('data') && createResponse['data'] is Map<String, dynamic>) {
              createData = createResponse['data'];
            } else {
              createData = createResponse;
            }
            
            if (createData != null) {
              try {
                return Vine.fromApiJson(createData);
              } catch (e) {
                print('DEBUG: Error parsing created vine: $e');
              }
            }
          }
        } catch (createError) {
          // If creation fails with 409, it means the vine actually exists but our searches missed it
          // Try one more time to update it using alphaNumericID in the URL path
          if (createError.toString().contains('409')) {
            print('DEBUG: Vine creation failed with 409 - trying direct update');
            try {
              // Try to update by alphaNumericID endpoint if it exists
              final updateResponse = await _apiService.put('$_endpoint/by-alpha-id/${vine.alphaNumericID}', vineApi.toJson());
              print('DEBUG: Vine updated via alphaNumericID endpoint');
              
              if (updateResponse is Map<String, dynamic>) {
                try {
                  Map<String, dynamic> responseData = updateResponse;
                  return Vine.fromApiJson(responseData);
                } catch (e) {
                  print('DEBUG: Error parsing updated vine: $e');
                }
              }
            } catch (updateError) {
              print('DEBUG: Final update attempt failed: $updateError');
            }
          }
          
          print('DEBUG: Error creating vine in API: $createError');
        }
        
        // Return the original vine if all API operations fail
        return vine;
      }
    } catch (e) {
      print('DEBUG: Error in updateVine outer block: $e');
      // Return the original vine if API fails
      return vine;
    }
  }

  // Get all vine locations with coordinates (includes empty spots)
  Future<List<Map<String, dynamic>>> getMapLocations() async {
    try {
      print('DEBUG: Fetching all map locations from API');
      final response = await _apiService.get('$_endpoint/locations/map');

      List<dynamic> locationsJson;
      if (response is List) {
        locationsJson = response;
      } else if (response is Map && response.containsKey('data') && response['data'] is List) {
        locationsJson = response['data'];
      } else {
        locationsJson = [];
      }

      print('DEBUG: API returned ${locationsJson.length} map locations');
      return locationsJson.cast<Map<String, dynamic>>();
    } catch (e) {
      print('DEBUG: Error in getMapLocations: $e');
      rethrow;
    }
  }

  // Delete a vine by ID
  Future<void> deleteVine(int id) async {
    try {
      print('DEBUG: Deleting vine with id $id - using numeric ID');
      await _apiService.delete('$_endpoint/$id');
      print('DEBUG: Vine deletion completed');
    } catch (e) {
      print('DEBUG: Error in deleteVine: $e');
      rethrow;
    }
  }
  
  // Delete a vine by alphanumeric ID
  Future<void> deleteVineByAlphaNumericId(String alphaNumericId) async {
    try {
      print('DEBUG: Deleting vine with alphanumeric ID $alphaNumericId');
      await _apiService.delete('$_endpoint/by-alpha-id/$alphaNumericId');
      print('DEBUG: Vine deletion completed');
    } catch (e) {
      print('DEBUG: Error in deleteVineByAlphaNumericId: $e');
      rethrow;
    }
  }
  
  // Sync a vine's location data (including GPS) to the backend location endpoint.
  // This is needed because the vine PUT endpoint only updates vine fields,
  // not the related VineLocation record.
  Future<void> syncLocationForVine(Vine vine) async {
    if (vine.location == null) return;
    final loc = vine.location!;
    // Only sync if there's meaningful location data
    if (loc.vineyardName.isEmpty && loc.fieldName.isEmpty &&
        loc.latitude == null && loc.longitude == null) return;

    final locationData = {
      'alpha_numeric_id': vine.alphaNumericID,
      'vineyard_name': loc.vineyardName,
      'field_name': loc.fieldName,
      'row_number': loc.rowNumber,
      'spot_number': loc.spotNumber,
      'latitude': loc.latitude,
      'longitude': loc.longitude,
      'gps_accuracy': loc.gpsAccuracy,
    };

    try {
      print('DEBUG: Syncing location data for vine ${vine.alphaNumericID}: $locationData');
      await _apiService.put('$_endpoint/locations/sync', locationData);
      print('DEBUG: Location sync successful for vine ${vine.alphaNumericID}');
    } catch (e) {
      print('DEBUG: Error syncing location for vine ${vine.alphaNumericID}: $e');
      // Don't rethrow — location sync failure shouldn't fail the whole operation
    }
  }

  // Create or update a vine location (for untagged vines)
  Future<Map<String, dynamic>> syncVineLocation(Map<String, dynamic> locationData) async {
    try {
      print('DEBUG: Syncing vine location: $locationData');
      final response = await _apiService.put('$_endpoint/locations/sync', locationData);
      print('DEBUG: Vine location sync successful');
      
      if (response is Map<String, dynamic>) {
        return response;
      } else {
        print('DEBUG: Unexpected response type: ${response.runtimeType}');
        return locationData;
      }
    } catch (e) {
      print('DEBUG: Error in syncVineLocation: $e');
      rethrow;
    }
  }
  
  // Check if a vine location already exists
  Future<bool> checkVineLocationExists(String vineyardName, String fieldName, int rowNumber, int spotNumber, String? alphaNumericId) async {
    try {
      print('DEBUG: Checking vine location existence via API');
      
      // Use query parameters to check if location exists
      final Map<String, String> queryParams = {
        'vineyard_name': vineyardName,
        'field_name': fieldName,
        'row_number': rowNumber.toString(),
        'spot_number': spotNumber.toString(),
      };
      
      if (alphaNumericId != null) {
        queryParams['alpha_numeric_id'] = alphaNumericId;
      }
      
      final queryString = queryParams.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
      
      final response = await _apiService.get('$_endpoint/locations/check?$queryString');
      
      if (response is Map<String, dynamic>) {
        return response['exists'] == true;
      }
      
      return false;
    } catch (e) {
      print('DEBUG: Error checking vine location existence: $e');
      // If error occurs, assume it doesn't exist to allow creation
      return false;
    }
  }

  // New Sync Methods for Efficient Data Synchronization

  /// Get delta sync - only items changed since a specific timestamp
  Future<DeltaSyncResponse> getDeltaSync(DeltaSyncRequest request) async {
    try {
      final queryParams = request.toQueryParams();
      final queryString = queryParams.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
      
      print('DEBUG: Getting delta sync since ${request.since}');
      final response = await _apiService.get('$_endpoint/sync/delta?$queryString');
      
      return DeltaSyncResponse.fromJson(response);
    } catch (e) {
      print('DEBUG: Error in getDeltaSync: $e');
      rethrow;
    }
  }

  /// Batch sync multiple vines and vine locations
  Future<VineSyncResponse> batchSync(VineSyncRequest request) async {
    try {
      print('DEBUG: Batch syncing ${request.vines.length} vines and ${request.vineLocations.length} vine locations');
      final response = await _apiService.post('$_endpoint/sync/batch', request.toJson());
      
      return VineSyncResponse.fromJson(response);
    } catch (e) {
      print('DEBUG: Error in batchSync: $e');
      rethrow;
    }
  }

  /// Get sync status from server
  Future<SyncStatus> getSyncStatus() async {
    try {
      print('DEBUG: Getting sync status from server');
      final response = await _apiService.get('$_endpoint/sync/status');
      
      return SyncStatus.fromJson(response);
    } catch (e) {
      print('DEBUG: Error in getSyncStatus: $e');
      rethrow;
    }
  }

  /// Check server connectivity and get current time
  Future<DateTime> getServerTime() async {
    try {
      final syncStatus = await getSyncStatus();
      return syncStatus.serverTime;
    } catch (e) {
      print('DEBUG: Error getting server time: $e');
      // Fallback to local time if server is unreachable
      return DateTime.now();
    }
  }
}