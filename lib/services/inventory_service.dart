import 'dart:async';
import '../models/vine.dart';
import 'repository.dart';

class InventoryService {
  static final InventoryService _instance = InventoryService._internal();
  factory InventoryService() => _instance;
  
  InventoryService._internal();
  
  final Repository _repository = Repository();
  
  // Stream controller for notifying UI about data updates
  final StreamController<String> _dataUpdateController = StreamController<String>.broadcast();
  Stream<String> get dataUpdates => _dataUpdateController.stream;
  
  // Dispose method to clean up resources
  void dispose() {
    _dataUpdateController.close();
  }
  
  // Helper method to start background sync and notify when complete
  void _startBackgroundSyncWithNotification(String context) {
    _repository.startBackgroundVineSync().then((_) {
      print('Background sync completed for $context');
      _dataUpdateController.add(context);
    }).catchError((error) {
      print('Background refresh error in $context: $error');
    });
  }
  
  // Force a full refresh of data from API
  Future<bool> refreshFromAPI() async {
    if (_repository.isOnline && _repository.isAuthenticated) {
      try {
        // First sync any local changes to API
        await _repository.syncWithDeltaMethod();
        
        // Then force a complete refresh from the API
        await _repository.forceRefreshFromAPI();
        
        return true;
      } catch (e) {
        print('Error refreshing inventory data: $e');
        return false;
      }
    }
    return false;
  }
  
  // DEBUG: Force refresh and reset sync timestamp to get all recent data
  Future<bool> debugRefreshAllData() async {
    if (_repository.isOnline && _repository.isAuthenticated) {
      try {
        print('DEBUG: Starting fresh data sync (bypassing timestamp)');
        
        // Reset sync timestamp to get data from the last 24 hours
        await _repository.resetSyncTimestamp(const Duration(hours: 24));
        
        // Sync with the reset timestamp
        final syncedCount = await _repository.syncWithDeltaMethod();
        print('DEBUG: Synced $syncedCount items with reset timestamp');
        
        // Force a complete refresh as well
        await _repository.forceRefreshFromAPI();
        
        return true;
      } catch (e) {
        print('DEBUG: Error in debugRefreshAllData: $e');
        return false;
      }
    }
    return false;
  }
  
  // Get all vineyards from local data (fast) - with optional background refresh
  Future<List<String>> getVineyards({bool backgroundRefresh = true}) async {
    // Get data from local database immediately (fast)
    final vines = await _repository.getLocalVines();
    final vineyards = vines
        .where((v) => v.vineyardName != null && v.vineyardName!.isNotEmpty)
        .map((v) => v.vineyardName!)
        .toSet()
        .toList();
    
    // Start background refresh if requested and online
    if (backgroundRefresh && _repository.isOnline && _repository.isAuthenticated) {
      _startBackgroundSyncWithNotification('vineyards');
    }
    
    return vineyards..sort();
  }
  
  // Get all fields for a specific vineyard from local data (fast)
  Future<List<String>> getFieldsForVineyard(String vineyardName, {bool backgroundRefresh = true}) async {
    // Get data from local database immediately (fast)
    final vines = await _repository.getLocalVines();
    final fields = vines
        .where((v) => v.vineyardName == vineyardName && 
                     v.fieldName != null && 
                     v.fieldName!.isNotEmpty)
        .map((v) => v.fieldName!)
        .toSet()
        .toList();
    
    // Start background refresh if requested and online
    if (backgroundRefresh && _repository.isOnline && _repository.isAuthenticated) {
      _startBackgroundSyncWithNotification('fields');
    }
    
    return fields..sort();
  }
  
  // Get all rows for a specific field in a vineyard from local data (fast)
  Future<List<String>> getRowsForField(String vineyardName, String fieldName, {bool backgroundRefresh = true}) async {
    // Get data from local database immediately (fast)
    final vines = await _repository.getLocalVines();
    final rows = vines
        .where((v) => v.vineyardName == vineyardName && 
                     v.fieldName == fieldName && 
                     v.rowNumber != null)
        .map((v) => v.rowNumber!.toString())
        .toSet()
        .toList();
    
    // Start background refresh if requested and online
    if (backgroundRefresh && _repository.isOnline && _repository.isAuthenticated) {
      _startBackgroundSyncWithNotification('rows');
    }
    
    return rows..sort();
  }
  
  // Get all vines for a specific row in a field from local data (fast)
  Future<List<Vine>> getVinesForRow(String vineyardName, String fieldName, String row, {bool backgroundRefresh = true}) async {
    // Convert row string to integer
    int? rowNumber;
    try {
      rowNumber = int.parse(row);
    } catch (e) {
      print('Failed to parse row number: $row');
      return [];
    }
    
    // Get data from local database immediately (fast)
    final vines = await _repository.getLocalVines();
    final rowVines = vines
        .where((v) => v.vineyardName == vineyardName && 
                     v.fieldName == fieldName && 
                     v.rowNumber == rowNumber)
        .toList();
    
    // Sort by spot number
    rowVines.sort((a, b) => 
      (a.spotNumber ?? 0).compareTo(b.spotNumber ?? 0)
    );
    
    // Start background refresh if requested and online
    if (backgroundRefresh && _repository.isOnline && _repository.isAuthenticated) {
      _startBackgroundSyncWithNotification('vines');
    }
    
    return rowVines;
  }
  
  // Get variety summary (counts by variety) from local data (fast)
  Future<Map<String, int>> getVarietySummary({bool backgroundRefresh = true}) async {
    // Get data from local database immediately (fast)
    final vines = await _repository.getLocalVines();
    
    // Start background refresh if requested and online
    if (backgroundRefresh && _repository.isOnline && _repository.isAuthenticated) {
      _startBackgroundSyncWithNotification('varieties');
    }
    final Map<String, int> varietyCounts = {};
    int unknownCount = 0;
    
    // Debug vine varieties
    print('DEBUG: Total vines: ${vines.length}');
    int nullCount = 0;
    int emptyCount = 0;
    int whitespaceCount = 0;
    int validCount = 0;
    
    for (var vine in vines) {
      // Analyze and categorize variety data for debugging
      if (vine.variety == null) {
        nullCount++;
      } else if (vine.variety!.isEmpty) {
        emptyCount++;
      } else if (vine.variety!.trim().isEmpty) {
        whitespaceCount++;
      } else {
        validCount++;
      }
      
      // Only count vines with valid non-empty varieties
      if (vine.variety != null && vine.variety!.trim().isNotEmpty) {
        varietyCounts[vine.variety!.trim()] = (varietyCounts[vine.variety!.trim()] ?? 0) + 1;
      } else {
        // Count unknown varieties but don't add to the map yet
        unknownCount++;
      }
    }
    
    // Print detailed diagnostic information
    print('DEBUG: Variety status counts: null: $nullCount, empty: $emptyCount, whitespace: $whitespaceCount, valid: $validCount');
    
    // Only add Unknown category if there are actually unknown varieties
    if (unknownCount > 0) {
      varietyCounts['Unknown'] = unknownCount;
      
      // Print sample of unknown vines for debugging
      print('DEBUG: Sample of unknown varieties:');
      int sampleCount = 0;
      for (var vine in vines) {
        if (vine.variety == null || vine.variety!.trim().isEmpty) {
          print('DEBUG: Unknown vine: ${vine.alphaNumericID}, vineyard: ${vine.vineyardName}, field: ${vine.fieldName}, row: ${vine.rowNumber}, spot: ${vine.spotNumber}');
          sampleCount++;
          if (sampleCount >= 5) break; // Only show 5 samples
        }
      }
    }
    
    print('DEBUG: Calculated variety summary: ${varietyCounts.entries.map((e) => '${e.key}: ${e.value}').join(', ')}');
    
    return varietyCounts;
  }
  
  // Get vineyard summary (counts by vineyard) from local data (fast)
  Future<Map<String, int>> getVineyardSummary({bool backgroundRefresh = true}) async {
    // Get data from local database immediately (fast)
    final vines = await _repository.getLocalVines();
    
    // Start background refresh if requested and online
    if (backgroundRefresh && _repository.isOnline && _repository.isAuthenticated) {
      _startBackgroundSyncWithNotification('vineyard_summary');
    }
    final Map<String, int> vineyardCounts = {};
    
    // DEBUG: Enhanced logging for vineyard debugging
    print('DEBUG: Processing ${vines.length} vines for vineyard summary');
    Map<String, int> vineyardNameAnalysis = {};
    int nullCount = 0;
    int emptyCount = 0;
    Set<String> uniqueVineyards = {};
    
    for (var vine in vines) {
      if (vine.vineyardName == null) {
        nullCount++;
      } else if (vine.vineyardName!.isEmpty) {
        emptyCount++;
      } else {
        uniqueVineyards.add(vine.vineyardName!);
        vineyardNameAnalysis[vine.vineyardName!] = (vineyardNameAnalysis[vine.vineyardName!] ?? 0) + 1;
      }
      
      if (vine.vineyardName != null && vine.vineyardName!.isNotEmpty) {
        vineyardCounts[vine.vineyardName!] = (vineyardCounts[vine.vineyardName!] ?? 0) + 1;
      } else {
        vineyardCounts['Unknown'] = (vineyardCounts['Unknown'] ?? 0) + 1;
      }
    }
    
    print('DEBUG: Vineyard analysis - null: $nullCount, empty: $emptyCount, unique vineyards: ${uniqueVineyards.length}');
    print('DEBUG: Unique vineyard names found: ${uniqueVineyards.join(', ')}');
    print('DEBUG: Calculated vineyard summary from ${vines.length} total vines:');
    print('DEBUG: Vineyard counts: ${vineyardCounts.entries.map((e) => '${e.key}: ${e.value}').join(', ')}');
    
    // Debug: Show unique vineyard names in database
    final uniqueVineyardNames = vines
        .where((v) => v.vineyardName != null && v.vineyardName!.isNotEmpty)
        .map((v) => v.vineyardName!)
        .toSet()
        .toList()..sort();
    print('DEBUG: Unique vineyards in database: ${uniqueVineyardNames.join(', ')}');
    
    // Debug: Count null/empty vineyard names
    final nullVineyardCount = vines.where((v) => v.vineyardName == null || v.vineyardName!.isEmpty).length;
    print('DEBUG: Vines with null/empty vineyard names: $nullVineyardCount');
    
    return vineyardCounts;
  }
  
  // Get field summary for a vineyard (counts by field) from local data (fast)
  Future<Map<String, int>> getFieldSummary(String vineyardName, {bool backgroundRefresh = true}) async {
    // Get data from local database immediately (fast)
    final vines = await _repository.getLocalVines();
    
    // Start background refresh if requested and online
    if (backgroundRefresh && _repository.isOnline && _repository.isAuthenticated) {
      _startBackgroundSyncWithNotification('field_summary');
    }
    final Map<String, int> fieldCounts = {};
    
    for (var vine in vines.where((v) => v.vineyardName == vineyardName)) {
      if (vine.fieldName != null && vine.fieldName!.isNotEmpty) {
        fieldCounts[vine.fieldName!] = (fieldCounts[vine.fieldName!] ?? 0) + 1;
      } else {
        fieldCounts['Unknown'] = (fieldCounts['Unknown'] ?? 0) + 1;
      }
    }
    
    print('DEBUG: Calculated field summary for $vineyardName: ${fieldCounts.entries.map((e) => '${e.key}: ${e.value}').join(', ')}');
    
    return fieldCounts;
  }
  
  // Get variety counts for a specific field from local data (fast)
  Future<Map<String, int>> getVarietyCountsForField(String vineyardName, String fieldName, {bool backgroundRefresh = true}) async {
    // Get data from local database immediately (fast)
    final vines = await _repository.getLocalVines();
    final Map<String, int> varietyCounts = {};
    
    // Start background refresh if requested and online
    if (backgroundRefresh && _repository.isOnline && _repository.isAuthenticated) {
      _startBackgroundSyncWithNotification('variety_counts');
    }
    
    for (var vine in vines.where((v) => 
        v.vineyardName == vineyardName && 
        v.fieldName == fieldName)) {
      final variety = vine.variety ?? 'Unknown';
      varietyCounts[variety] = (varietyCounts[variety] ?? 0) + 1;
    }
    
    return varietyCounts;
  }
  
  // Get health summary (count of alive vs dead vines) from local data (fast)
  Future<Map<String, int>> getHealthSummary({bool backgroundRefresh = true}) async {
    // Get data from local database immediately (fast)
    final vines = await _repository.getLocalVines();
    
    // Start background refresh if requested and online
    if (backgroundRefresh && _repository.isOnline && _repository.isAuthenticated) {
      _startBackgroundSyncWithNotification('health_summary');
    }
    int alive = 0;
    int dead = 0;
    
    for (var vine in vines) {
      if (vine.isDead) {
        dead++;
      } else {
        alive++;
      }
    }
    
    final result = {
      'Alive': alive,
      'Dead': dead,
    };
    
    print('DEBUG: Calculated health summary: ${result.entries.map((e) => '${e.key}: ${e.value}').join(', ')}');
    
    return result;
  }
  
  // Get total vine count from local data (fast)
  Future<int> getTotalVineCount({bool backgroundRefresh = true}) async {
    // Get data from local database immediately (fast)
    final vines = await _repository.getLocalVines();
    
    // Start background refresh if requested and online
    if (backgroundRefresh && _repository.isOnline && _repository.isAuthenticated) {
      _startBackgroundSyncWithNotification('total_count');
    }
    
    return vines.length;
  }
}