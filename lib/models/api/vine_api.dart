import '../vine.dart';

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
  });

  // Convert API response to VineApiModel with robust error handling
  factory VineApiModel.fromJson(Map<String, dynamic> json) {
    try {
      print('DEBUG: Parsing VineApiModel from JSON: $json');
      
      // Extract location data from locations array (new schema)
      String? vineyardName;
      String? fieldName;
      int? rowNumber;
      int? spotNumber;
      
      final List<dynamic>? locations = json['locations'];
      if (locations != null && locations.isNotEmpty) {
        // Use the first location if available
        final location = locations.first as Map<String, dynamic>;
        vineyardName = location['vineyard_name']?.toString();
        fieldName = location['field_name']?.toString();
        rowNumber = location['row_number'] is int 
          ? location['row_number'] 
          : int.tryParse(location['row_number']?.toString() ?? '');
        spotNumber = location['spot_number'] is int 
          ? location['spot_number'] 
          : int.tryParse(location['spot_number']?.toString() ?? '');
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
        createdAt: json['created_at']?.toString() ?? 
                  json['created_date']?.toString() ?? 
                  DateTime.now().toIso8601String(),
        updatedAt: json['updated_at']?.toString() ?? 
                  json['updated_date']?.toString() ?? 
                  DateTime.now().toIso8601String(),
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
    return Vine(
      id: id,
      alphaNumericID: alphaNumericID,
      yearOfPlanting: yearOfPlanting,
      nursery: nursery,
      variety: variety,
      rootstock: rootstock,
      vineyardName: vineyardName,
      fieldName: fieldName,
      rowNumber: rowNumber,
      spotNumber: spotNumber,
      isDead: isDead,
      dateDied: dateDied != null ? DateTime.parse(dateDied!) : null,
      recordCreated: DateTime.parse(createdAt),
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
    );
  }
}