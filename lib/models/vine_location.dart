class VineLocation {
  final int? id; // Database ID
  final String? alphaNumericID; // QR code identifier (null for untagged locations)
  final String vineyardName;
  final String fieldName;
  final int rowNumber;
  final int spotNumber;
  final int? yearOfPlanting;
  final int? vineId; // Foreign key to vines table (null for untagged)
  final DateTime recordCreated;
  final DateTime updatedAt;

  VineLocation({
    this.id,
    this.alphaNumericID,
    required this.vineyardName,
    required this.fieldName,
    required this.rowNumber,
    required this.spotNumber,
    this.yearOfPlanting,
    this.vineId,
    DateTime? recordCreated,
    DateTime? updatedAt,
  }) : recordCreated = recordCreated ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  // Create a VineLocation from a Map (database)
  factory VineLocation.fromMap(Map<String, dynamic> map) {
    return VineLocation(
      id: map['id'],
      alphaNumericID: map['alphaNumericID'],
      vineyardName: map['vineyardName'],
      fieldName: map['fieldName'],
      rowNumber: map['rowNumber'],
      spotNumber: map['spotNumber'],
      yearOfPlanting: map['yearOfPlanting'],
      vineId: map['vineId'],
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
      'alphaNumericID': alphaNumericID,
      'vineyardName': vineyardName,
      'fieldName': fieldName,
      'rowNumber': rowNumber,
      'spotNumber': spotNumber,
      'yearOfPlanting': yearOfPlanting,
      'vineId': vineId,
      'recordCreated': recordCreated.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  // Convert to API format
  Map<String, dynamic> toApiMap() {
    return {
      'alpha_numeric_id': alphaNumericID,
      'vineyard_name': vineyardName,
      'field_name': fieldName,
      'row_number': rowNumber,
      'spot_number': spotNumber,
      'year_of_planting': yearOfPlanting,
      'vine_id': vineId,
    };
  }

  // Create a copy of this VineLocation with given fields replaced with new values
  VineLocation copyWith({
    int? id,
    String? alphaNumericID,
    String? vineyardName,
    String? fieldName,
    int? rowNumber,
    int? spotNumber,
    int? yearOfPlanting,
    int? vineId,
    DateTime? recordCreated,
    DateTime? updatedAt,
  }) {
    return VineLocation(
      id: id ?? this.id,
      alphaNumericID: alphaNumericID ?? this.alphaNumericID,
      vineyardName: vineyardName ?? this.vineyardName,
      fieldName: fieldName ?? this.fieldName,
      rowNumber: rowNumber ?? this.rowNumber,
      spotNumber: spotNumber ?? this.spotNumber,
      yearOfPlanting: yearOfPlanting ?? this.yearOfPlanting,
      vineId: vineId ?? this.vineId,
      recordCreated: recordCreated ?? this.recordCreated,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
  
  // Helper method to generate a unique identifier
  String get uniqueIdentifier {
    if (alphaNumericID != null && alphaNumericID!.isNotEmpty) {
      return alphaNumericID!;
    }
    
    // For locations without tags, use location-based identifier
    return '${vineyardName}_${fieldName}_${rowNumber}_$spotNumber';
  }
  
  // Check if this location has a QR tag
  bool get hasTag => alphaNumericID != null && alphaNumericID!.isNotEmpty;
  
  // Check if this location needs a tag to be printed
  bool get needsTag => !hasTag && yearOfPlanting != null;
}