import '../vine.dart';
import '../vine_location.dart';

class VineApiModel {
  final int? id;
  final String? alphaNumericID; // Nullable for vines without tags
  final int? yearOfPlanting;
  final String? nursery;
  final String? variety;
  final String? rootstock;
  final String? vineyardName;
  final String? fieldName;
  final int? rowNumber;
  final int? spotNumber;
  final bool isDead;
  final String? dateDied;
  final String createdAt;
  final String updatedAt;
  final double? latitude;
  final double? longitude;
  final double? gpsAccuracy;

  VineApiModel({
    this.id,
    this.alphaNumericID,
    this.yearOfPlanting,
    this.nursery,
    this.variety,
    this.rootstock,
    this.vineyardName,
    this.fieldName,
    this.rowNumber,
    this.spotNumber,
    this.isDead = false,
    this.dateDied,
    required this.createdAt,
    required this.updatedAt,
    this.latitude,
    this.longitude,
    this.gpsAccuracy,
  });

  // Convert API response to VineApiModel with robust error handling
  factory VineApiModel.fromJson(Map<String, dynamic> json) {
    try {
      print('DEBUG: Parsing VineApiModel from JSON: $json');
      
      // Extract location data from location object (new 1:1 schema)
      String? vineyardName;
      String? fieldName;
      int? rowNumber;
      int? spotNumber;
      double? latitude;
      double? longitude;
      double? gpsAccuracy;

      // First try the new singular 'location' field
      final Map<String, dynamic>? location = json['location'];
      if (location != null) {
        vineyardName = location['vineyard_name']?.toString();
        fieldName = location['field_name']?.toString();
        rowNumber = location['row_number'] is int 
          ? location['row_number'] 
          : int.tryParse(location['row_number']?.toString() ?? '');
        spotNumber = location['spot_number'] is int 
          ? location['spot_number'] 
          : int.tryParse(location['spot_number']?.toString() ?? '');
        
        latitude = location['latitude'] != null ? (location['latitude'] as num).toDouble() : null;
        longitude = location['longitude'] != null ? (location['longitude'] as num).toDouble() : null;
        gpsAccuracy = location['gps_accuracy'] != null ? (location['gps_accuracy'] as num).toDouble() : null;

        print('DEBUG: Extracted vineyard_name: "$vineyardName" from singular location: $location');
      } else {
        // Fallback to old 'locations' array for backward compatibility
        final List<dynamic>? locations = json['locations'];
        if (locations != null && locations.isNotEmpty) {
          final locationData = locations.first as Map<String, dynamic>;
          vineyardName = locationData['vineyard_name']?.toString();
          fieldName = locationData['field_name']?.toString();
          rowNumber = locationData['row_number'] is int 
            ? locationData['row_number'] 
            : int.tryParse(locationData['row_number']?.toString() ?? '');
          spotNumber = locationData['spot_number'] is int 
            ? locationData['spot_number'] 
            : int.tryParse(locationData['spot_number']?.toString() ?? '');
          
          print('DEBUG: Extracted vineyard_name: "$vineyardName" from locations array: $locationData');
        } else {
          print('DEBUG: No location data found in vine JSON: ${json.keys.join(', ')}');
        }
      }
      
      // Ensure all required fields exist, with defaults as needed
      // Use null-aware operators and handle potential type issues
      return VineApiModel(
        id: json['id'] is int ? json['id'] : (int.tryParse(json['id']?.toString() ?? '') ?? json['vine_id']),
        alphaNumericID: json['alpha_numeric_id']?.toString(),
        yearOfPlanting: json['year_of_planting'] is int 
          ? json['year_of_planting'] 
          : int.tryParse(json['year_of_planting']?.toString() ?? ''),
        nursery: json['nursery']?.toString(),
        variety: json['variety']?.toString(),
        rootstock: json['rootstock']?.toString(),
        vineyardName: vineyardName,
        fieldName: fieldName,
        rowNumber: rowNumber,
        spotNumber: spotNumber,
        isDead: json['is_dead'] is bool 
          ? json['is_dead'] 
          : (json['is_dead']?.toString()?.toLowerCase() == 'true' || 
             json['is_dead'] == 1) ?? false,
        dateDied: json['date_died']?.toString(),
        createdAt: json['record_created']?.toString() ??
                  json['created_at']?.toString() ??
                  json['created_date']?.toString() ??
                  DateTime.now().toIso8601String(),
        updatedAt: json['updated_at']?.toString() ??
                  json['updated_date']?.toString() ??
                  DateTime.now().toIso8601String(),
        latitude: latitude,
        longitude: longitude,
        gpsAccuracy: gpsAccuracy,
      );
    } catch (e) {
      print('DEBUG: Error parsing VineApiModel: $e for JSON: $json');
      // Create a minimal valid object as fallback
      return VineApiModel(
        id: null,
        alphaNumericID: json['alpha_numeric_id']?.toString(),
        yearOfPlanting: null,
        nursery: null,
        variety: null,
        rootstock: null,
        vineyardName: null,
        fieldName: null,
        rowNumber: null,
        spotNumber: null,
        isDead: false,
        dateDied: null,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      );
    }
  }

  // Convert VineApiModel to JSON for API request
  Map<String, dynamic> toJson() {
    return {
      'alpha_numeric_id': alphaNumericID,
      'year_of_planting': yearOfPlanting,
      'nursery': nursery,
      'variety': variety,
      'rootstock': rootstock,
      'vineyard_name': vineyardName,
      'field_name': fieldName,
      'row_number': rowNumber,
      'spot_number': spotNumber,
      'is_dead': isDead,
      // Don't send date_died in the request to avoid datetime format issues
      'date_died': null,
    };
  }

  // Convert API model to local model
  Vine toLocalModel() {
    // Create VineLocation from the API data
    VineLocation? location;
    if (vineyardName != null || fieldName != null || rowNumber != null || spotNumber != null) {
      location = VineLocation(
        alphaNumericId: alphaNumericID,
        vineyardName: vineyardName ?? '',
        fieldName: fieldName ?? '',
        rowNumber: rowNumber ?? 0,
        spotNumber: spotNumber ?? 0,
        latitude: latitude,
        longitude: longitude,
        gpsAccuracy: gpsAccuracy,
        recordCreated: DateTime.parse(createdAt),
        updatedAt: DateTime.parse(updatedAt),
      );
    }
    
    return Vine(
      id: id,
      alphaNumericID: alphaNumericID,
      yearOfPlanting: yearOfPlanting,
      nursery: nursery,
      variety: variety,
      rootstock: rootstock,
      isDead: isDead,
      dateDied: dateDied != null ? DateTime.parse(dateDied!) : null,
      recordCreated: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
      location: location,
    );
  }

  // Convert local model to API model
  static VineApiModel fromLocalModel(Vine vine) {
    return VineApiModel(
      id: vine.id,
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
      dateDied: vine.dateDied?.toIso8601String(),
      createdAt: vine.recordCreated.toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
      latitude: vine.location?.latitude,
      longitude: vine.location?.longitude,
      gpsAccuracy: vine.location?.gpsAccuracy,
    );
  }
}