import '../models/vine.dart';
import 'repository.dart';

class InventoryService {
  static final InventoryService _instance = InventoryService._internal();
  factory InventoryService() => _instance;
  
  InventoryService._internal();
  
  final Repository _repository = Repository();
  
  // Force a full refresh of data from API
  Future<bool> refreshFromAPI() async {
    if (_repository.isOnline && _repository.isAuthenticated) {
      try {
        // First sync any local changes to API
        await _repository.syncLocalVinesToAPI();
        
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
  
  // Get all vineyards from the vines data - always gets fresh data
  Future<List<String>> getVineyards() async {
    // Force refresh from repository to get latest data
    final vines = await _repository.getAllVines();
    final vineyards = vines
        .where((v) => v.vineyardName != null && v.vineyardName!.isNotEmpty)
        .map((v) => v.vineyardName!)
        .toSet()
        .toList();
    
    return vineyards..sort();
  }
  
  // Get all fields for a specific vineyard
  Future<List<String>> getFieldsForVineyard(String vineyardName) async {
    final vines = await _repository.getAllVines();
    final fields = vines
        .where((v) => v.vineyardName == vineyardName && 
                     v.fieldName != null && 
                     v.fieldName!.isNotEmpty)
        .map((v) => v.fieldName!)
        .toSet()
        .toList();
    
    return fields..sort();
  }
  
  // Get all rows for a specific field in a vineyard
  Future<List<String>> getRowsForField(String vineyardName, String fieldName) async {
    final vines = await _repository.getAllVines();
    final rows = vines
        .where((v) => v.vineyardName == vineyardName && 
                     v.fieldName == fieldName && 
                     v.rowNumber != null)
        .map((v) => v.rowNumber!.toString())
        .toSet()
        .toList();
    
    return rows..sort();
  }
  
  // Get all vines for a specific row in a field
  Future<List<Vine>> getVinesForRow(String vineyardName, String fieldName, String row) async {
    // Convert row string to integer
    int? rowNumber;
    try {
      rowNumber = int.parse(row);
    } catch (e) {
      print('Failed to parse row number: $row');
      return [];
    }
    
    final vines = await _repository.getAllVines();
    final rowVines = vines
        .where((v) => v.vineyardName == vineyardName && 
                     v.fieldName == fieldName && 
                     v.rowNumber == rowNumber)
        .toList();
    
    // Sort by spot number
    rowVines.sort((a, b) => 
      (a.spotNumber ?? 0).compareTo(b.spotNumber ?? 0)
    );
    
    return rowVines;
  }
  
  // Get variety summary (counts by variety)
  Future<Map<String, int>> getVarietySummary({bool forceRefresh = false}) async {
    // Only force refresh if explicitly requested
    if (forceRefresh && _repository.isOnline && _repository.isAuthenticated) {
      await _repository.syncLocalVinesToAPI();
      
      // After syncing, force a fresh fetch to ensure we have the latest data
      await _repository.getAllVines();
    }
    
    // Get fresh data from repository
    final vines = await _repository.getAllVines();
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
  
  // Get vineyard summary (counts by vineyard)
  Future<Map<String, int>> getVineyardSummary({bool forceRefresh = false}) async {
    // Only force refresh if explicitly requested
    if (forceRefresh && _repository.isOnline && _repository.isAuthenticated) {
      await _repository.syncLocalVinesToAPI();
    }
    
    // Get fresh data from repository
    final vines = await _repository.getAllVines();
    final Map<String, int> vineyardCounts = {};
    
    for (var vine in vines) {
      if (vine.vineyardName != null && vine.vineyardName!.isNotEmpty) {
        vineyardCounts[vine.vineyardName!] = (vineyardCounts[vine.vineyardName!] ?? 0) + 1;
      } else {
        vineyardCounts['Unknown'] = (vineyardCounts['Unknown'] ?? 0) + 1;
      }
    }
    
    print('DEBUG: Calculated vineyard summary: ${vineyardCounts.entries.map((e) => '${e.key}: ${e.value}').join(', ')}');
    
    return vineyardCounts;
  }
  
  // Get field summary for a vineyard (counts by field)
  Future<Map<String, int>> getFieldSummary(String vineyardName, {bool forceRefresh = false}) async {
    // Only force refresh if explicitly requested
    if (forceRefresh && _repository.isOnline && _repository.isAuthenticated) {
      await _repository.syncLocalVinesToAPI();
    }
    
    // Get fresh data from repository
    final vines = await _repository.getAllVines();
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
  
  // Get variety counts for a specific field
  Future<Map<String, int>> getVarietyCountsForField(String vineyardName, String fieldName) async {
    final vines = await _repository.getAllVines();
    final Map<String, int> varietyCounts = {};
    
    for (var vine in vines.where((v) => 
        v.vineyardName == vineyardName && 
        v.fieldName == fieldName)) {
      final variety = vine.variety ?? 'Unknown';
      varietyCounts[variety] = (varietyCounts[variety] ?? 0) + 1;
    }
    
    return varietyCounts;
  }
  
  // Get health summary (count of alive vs dead vines)
  Future<Map<String, int>> getHealthSummary({bool forceRefresh = false}) async {
    // Only force refresh if explicitly requested
    if (forceRefresh && _repository.isOnline && _repository.isAuthenticated) {
      await _repository.syncLocalVinesToAPI();
    }
    
    // Get fresh data from repository
    final vines = await _repository.getAllVines();
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
  
  // Get total vine count
  Future<int> getTotalVineCount() async {
    final vines = await _repository.getAllVines();
    return vines.length;
  }
}