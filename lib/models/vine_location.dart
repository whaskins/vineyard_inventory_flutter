class VineLocation {
  final int? id; // Database ID (location_id)
  final String? alphaNumericId; // Foreign key to vine's alpha_numeric_id (1:1 relationship)
  final String vineyardName;
  final String fieldName;
  final int rowNumber;
  final int spotNumber;
  final double? latitude;
  final double? longitude;
  final double? gpsAccuracy;
  final DateTime recordCreated;
  final DateTime updatedAt;

  VineLocation({
    this.id,
    this.alphaNumericId,
    required this.vineyardName,
    required this.fieldName,
    required this.rowNumber,
    required this.spotNumber,
    this.latitude,
    this.longitude,
    this.gpsAccuracy,
    DateTime? recordCreated,
    DateTime? updatedAt,
  }) : recordCreated = recordCreated ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  bool get hasCoordinates => latitude != null && longitude != null;

  // Create a VineLocation from a Map (database)
  factory VineLocation.fromMap(Map<String, dynamic> map) {
    return VineLocation(
      id: map['id'],
      alphaNumericId: map['alphaNumericId'],
      vineyardName: map['vineyardName'],
      fieldName: map['fieldName'],
      rowNumber: map['rowNumber'],
      spotNumber: map['spotNumber'],
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

  // Convert a VineLocation to a Map (database)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'alphaNumericId': alphaNumericId,
      'vineyardName': vineyardName,
      'fieldName': fieldName,
      'rowNumber': rowNumber,
      'spotNumber': spotNumber,
      'latitude': latitude,
      'longitude': longitude,
      'gpsAccuracy': gpsAccuracy,
      'recordCreated': recordCreated.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // Convert to API format (for sending to backend)
  Map<String, dynamic> toApiJson() {
    return {
      'alpha_numeric_id': alphaNumericId,
      'vineyard_name': vineyardName,
      'field_name': fieldName,
      'row_number': rowNumber,
      'spot_number': spotNumber,
      'latitude': latitude,
      'longitude': longitude,
      'gps_accuracy': gpsAccuracy,
      'record_created': recordCreated.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Legacy method for backward compatibility
  Map<String, dynamic> toApiMap() {
    return {
      'alpha_numeric_id': alphaNumericId,
      'vineyard_name': vineyardName,
      'field_name': fieldName,
      'row_number': rowNumber,
      'spot_number': spotNumber,
      'latitude': latitude,
      'longitude': longitude,
      'gps_accuracy': gpsAccuracy,
    };
  }

  // Create a VineLocation from API JSON response
  factory VineLocation.fromApiJson(Map<String, dynamic> json) {
    return VineLocation(
      id: json['id'] ?? json['location_id'],
      alphaNumericId: json['alpha_numeric_id'],
      vineyardName: json['vineyard_name'] ?? '',
      fieldName: json['field_name'] ?? '',
      rowNumber: json['row_number'] ?? 0,
      spotNumber: json['spot_number'] ?? 0,
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      gpsAccuracy: json['gps_accuracy'] != null ? (json['gps_accuracy'] as num).toDouble() : null,
      recordCreated: DateTime.parse(json['record_created']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  // Create a copy of this VineLocation with given fields replaced with new values
  VineLocation copyWith({
    int? id,
    String? alphaNumericId,
    String? vineyardName,
    String? fieldName,
    int? rowNumber,
    int? spotNumber,
    double? latitude,
    double? longitude,
    double? gpsAccuracy,
    DateTime? recordCreated,
    DateTime? updatedAt,
  }) {
    return VineLocation(
      id: id ?? this.id,
      alphaNumericId: alphaNumericId ?? this.alphaNumericId,
      vineyardName: vineyardName ?? this.vineyardName,
      fieldName: fieldName ?? this.fieldName,
      rowNumber: rowNumber ?? this.rowNumber,
      spotNumber: spotNumber ?? this.spotNumber,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      recordCreated: recordCreated ?? this.recordCreated,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Helper method to generate a unique identifier
  String get uniqueIdentifier {
    if (alphaNumericId != null && alphaNumericId!.isNotEmpty) {
      return alphaNumericId!;
    }

    // For locations without tags, use location-based identifier
    return '${vineyardName}_${fieldName}_${rowNumber}_$spotNumber';
  }

  // Check if this location has a vine with QR tag
  bool get hasVineWithTag => alphaNumericId != null && alphaNumericId!.isNotEmpty;
}
