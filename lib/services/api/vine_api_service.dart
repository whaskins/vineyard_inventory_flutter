import '../../models/api/vine_api.dart';
import '../../models/vine.dart';
import 'api_service.dart';

class VineApiService {
  final ApiService _apiService = ApiService();
  final String _endpoint = '/vines';

  // Get all vines with pagination support
  Future<List<Vine>> getAllVines({int pageSize = 100, int maxPages = 10}) async {
    try {
      List<Vine> allVines = [];
      int currentPage = 0;
      bool hasMoreData = true;
      
      print('DEBUG: Getting all vines with pagination (pageSize=$pageSize, maxPages=$maxPages)');
      
      // Continue fetching pages until we have all data or reach max pages
      while (hasMoreData && currentPage < maxPages) {
        final skip = currentPage * pageSize;
        
        // Check if the API supports pagination parameters
        String paginatedEndpoint = '$_endpoint?skip=$skip&limit=$pageSize';
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
          
          // Convert JSON to Vine models
          final pageVines = vinesJson
              .map((json) {
                try {
                  return VineApiModel.fromJson(json).toLocalModel();
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
        return VineApiModel.fromJson(jsonData).toLocalModel();
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
        return VineApiModel.fromJson(jsonData).toLocalModel();
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
              return VineApiModel.fromJson(updateResponse['data']).toLocalModel();
            } else {
              return VineApiModel.fromJson(updateResponse).toLocalModel();
            }
          }
          
          return vine;
        } catch (checkError) {
          // Vine doesn't exist, proceed with creation
          print('DEBUG: Vine does not exist, proceeding with creation');
          
          final response = await _apiService.post(_endpoint, vineApi.toJson());
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
            return VineApiModel.fromJson(jsonData).toLocalModel();
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
            final existingVine = await getVineByAlphaNumericId(vine.alphaNumericID);
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

  // First check if vine exists, then either create or update it
  Future<Vine> updateVine(Vine vine) async {
    try {
      if (vine.alphaNumericID.isEmpty) {
        print('DEBUG: Vine alphaNumericID is empty for update operation');
        throw Exception('Vine alphaNumericID cannot be empty for update operation');
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
                return VineApiModel.fromJson(jsonData).toLocalModel();
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
          final allVines = await _apiService.get(_endpoint);
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
                    return VineApiModel.fromJson(responseData).toLocalModel();
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
                    return VineApiModel.fromJson(responseData).toLocalModel();
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
          final createResponse = await _apiService.post(_endpoint, vineApi.toJson());
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
                return VineApiModel.fromJson(createData).toLocalModel();
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
                  return VineApiModel.fromJson(responseData).toLocalModel();
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
}