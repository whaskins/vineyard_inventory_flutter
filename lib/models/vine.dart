import 'vine_location.dart';

class Vine {
  final int? id; // Database ID (vine_id)
  final String? alphaNumericID; // QR code identifier (nullable for vines without tags)
  final int? yearOfPlanting;
  final String? nursery;
  final String? variety;
  final String? rootstock;
  final bool isDead;
  final DateTime? dateDied;
  final DateTime recordCreated;
  final DateTime? updatedAt;
  final VineLocation? location; // 1:1 relationship with VineLocation

  Vine({
    this.id,
    this.alphaNumericID,
    this.yearOfPlanting,
    this.nursery,
    this.variety,
    this.rootstock,
    this.isDead = false,
    this.dateDied,
    DateTime? recordCreated,
    this.updatedAt,
    this.location,
  }) : recordCreated = recordCreated ?? DateTime.now();


  // Create a Vine from a Map (database)
  factory Vine.fromMap(Map<String, dynamic> map) {
    VineLocation? vineLocation;
    
    // Reconstruct location from flattened fields if any location data exists
    if (map['vineyardName'] != null || map['fieldName'] != null ||
        map['rowNumber'] != null || map['spotNumber'] != null ||
        map['latitude'] != null || map['longitude'] != null) {
      vineLocation = VineLocation(
        alphaNumericId: map['alphaNumericID'],
        vineyardName: map['vineyardName'] ?? '',
        fieldName: map['fieldName'] ?? '',
        rowNumber: map['rowNumber'] ?? 0,
        spotNumber: map['spotNumber'] ?? 0,
        latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : null,
        longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : null,
        gpsAccuracy: map['gpsAccuracy'] != null ? (map['gpsAccuracy'] as num).toDouble() : null,
        recordCreated: map['recordCreated'] != null
          ? DateTime.parse(map['recordCreated'])
          : DateTime.now(),
        updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : DateTime.now(),
      );
    }
    
    return Vine(
      id: map['id'],
      alphaNumericID: map['alphaNumericID'],
      yearOfPlanting: map['yearOfPlanting'],
      nursery: map['nursery'],
      variety: map['variety'],
      rootstock: map['rootstock'],
      isDead: map['isDead'] == 1,
      dateDied: map['dateDied'] != null ? DateTime.parse(map['dateDied']) : null,
      recordCreated: map['recordCreated'] != null 
        ? DateTime.parse(map['recordCreated']) 
        : DateTime.now(),
      updatedAt: map['updatedAt'] != null ? DateTime.parse(map['updatedAt']) : null,
      location: vineLocation,
    );
  }

  // Convert a Vine to a Map (database)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'alphaNumericID': alphaNumericID,
      'yearOfPlanting': yearOfPlanting,
      'nursery': nursery,
      'variety': variety,
      'rootstock': rootstock,
      'isDead': isDead ? 1 : 0,
      'dateDied': dateDied?.toIso8601String(),
      'recordCreated': recordCreated.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      // Flatten location data for database storage
      'vineyardName': location?.vineyardName,
      'fieldName': location?.fieldName,
      'rowNumber': location?.rowNumber,
      'spotNumber': location?.spotNumber,
      'latitude': location?.latitude,
      'longitude': location?.longitude,
      'gpsAccuracy': location?.gpsAccuracy,
    };
  }

  // Convert to API format (for sending to backend)
  Map<String, dynamic> toApiJson() {
    return {
      'alpha_numeric_id': alphaNumericID,
      'year_of_planting': yearOfPlanting,
      'nursery': nursery,
      'variety': variety,
      'rootstock': rootstock,
      'is_dead': isDead,
      'date_died': dateDied?.toIso8601String(),
      'record_created': recordCreated.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  // Create a Vine from API JSON response
  factory Vine.fromApiJson(Map<String, dynamic> json) {
    VineLocation? vineLocation;
    
    // Handle new singular 'location' field (1:1 relationship)
    if (json['location'] != null) {
      vineLocation = VineLocation.fromApiJson(json['location'] as Map<String, dynamic>);
    }
    
    return Vine(
      id: json['id'],
      alphaNumericID: json['alpha_numeric_id'],
      yearOfPlanting: json['year_of_planting'],
      nursery: json['nursery'],
      variety: json['variety'],
      rootstock: json['rootstock'],
      isDead: json['is_dead'] ?? false,
      dateDied: json['date_died'] != null ? DateTime.parse(json['date_died']) : null,
      recordCreated: DateTime.parse(json['record_created']),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
      location: vineLocation,
    );
  }

  // Create a copy of this Vine with given fields replaced with new values
  Vine copyWith({
    int? id,
    String? alphaNumericID,
    int? yearOfPlanting,
    String? nursery,
    String? variety,
    String? rootstock,
    bool? isDead,
    DateTime? dateDied,
    DateTime? recordCreated,
    DateTime? updatedAt,
    VineLocation? location,
  }) {
    return Vine(
      id: id ?? this.id,
      alphaNumericID: alphaNumericID ?? this.alphaNumericID,
      yearOfPlanting: yearOfPlanting ?? this.yearOfPlanting,
      nursery: nursery ?? this.nursery,
      variety: variety ?? this.variety,
      rootstock: rootstock ?? this.rootstock,
      isDead: isDead ?? this.isDead,
      dateDied: dateDied ?? this.dateDied,
      recordCreated: recordCreated ?? this.recordCreated,
      updatedAt: updatedAt ?? this.updatedAt,
      location: location ?? this.location,
    );
  }
  
  // Helper method to generate a unique identifier for vines without tags
  String get uniqueIdentifier {
    if (alphaNumericID != null && alphaNumericID!.isNotEmpty) {
      return alphaNumericID!;
    }
    
    // For vines without tags, use location-based identifier
    if (location != null) {
      return location!.uniqueIdentifier;
    }
    
    // Fallback to ID-based identifier
    return 'vine_${id ?? 'new'}';
  }
  
  // Check if this vine has GPS coordinates
  bool get hasCoordinates => location?.hasCoordinates ?? false;

  // Check if this vine has a QR tag
  bool get hasTag => alphaNumericID != null &&
                     alphaNumericID!.isNotEmpty && 
                     !alphaNumericID!.startsWith('UNTAGGED_');
  
  // Convenience getters for location data
  String? get vineyardName => location?.vineyardName;
  String? get fieldName => location?.fieldName;
  int? get rowNumber => location?.rowNumber;
  int? get spotNumber => location?.spotNumber;
}