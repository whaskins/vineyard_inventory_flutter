class Vine {
  final int? id; // Database ID
  final String alphaNumericID; // QR code identifier
  final int? yearOfPlanting;
  final String? nursery;
  final String? variety;
  final String? rootstock;
  final String? vineyardName;
  final String? fieldName;
  final int? rowNumber;
  final int? spotNumber;
  final bool isDead;
  final DateTime? dateDied;
  final DateTime recordCreated;

  Vine({
    this.id,
    required this.alphaNumericID,
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
    DateTime? recordCreated,
  }) : recordCreated = recordCreated ?? DateTime.now();

  // Create a Vine from a Map (database)
  factory Vine.fromMap(Map<String, dynamic> map) {
    return Vine(
      id: map['id'],
      alphaNumericID: map['alphaNumericID'],
      yearOfPlanting: map['yearOfPlanting'],
      nursery: map['nursery'],
      variety: map['variety'],
      rootstock: map['rootstock'],
      vineyardName: map['vineyardName'],
      fieldName: map['fieldName'],
      rowNumber: map['rowNumber'],
      spotNumber: map['spotNumber'],
      isDead: map['isDead'] == 1,
      dateDied: map['dateDied'] != null ? DateTime.parse(map['dateDied']) : null,
      recordCreated: map['recordCreated'] != null 
        ? DateTime.parse(map['recordCreated']) 
        : DateTime.now(),
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
      'vineyardName': vineyardName,
      'fieldName': fieldName,
      'rowNumber': rowNumber,
      'spotNumber': spotNumber,
      'isDead': isDead ? 1 : 0,
      'dateDied': dateDied?.toIso8601String(),
      'recordCreated': recordCreated.toIso8601String(),
    };
  }

  // Create a copy of this Vine with given fields replaced with new values
  Vine copyWith({
    int? id,
    String? alphaNumericID,
    int? yearOfPlanting,
    String? nursery,
    String? variety,
    String? rootstock,
    String? vineyardName,
    String? fieldName,
    int? rowNumber,
    int? spotNumber,
    bool? isDead,
    DateTime? dateDied,
    DateTime? recordCreated,
  }) {
    return Vine(
      id: id ?? this.id,
      alphaNumericID: alphaNumericID ?? this.alphaNumericID,
      yearOfPlanting: yearOfPlanting ?? this.yearOfPlanting,
      nursery: nursery ?? this.nursery,
      variety: variety ?? this.variety,
      rootstock: rootstock ?? this.rootstock,
      vineyardName: vineyardName ?? this.vineyardName,
      fieldName: fieldName ?? this.fieldName,
      rowNumber: rowNumber ?? this.rowNumber,
      spotNumber: spotNumber ?? this.spotNumber,
      isDead: isDead ?? this.isDead,
      dateDied: dateDied ?? this.dateDied,
      recordCreated: recordCreated ?? this.recordCreated,
    );
  }
}