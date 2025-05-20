class MaintenanceType {
  final int? id;
  final String name;
  final String? description;

  MaintenanceType({
    this.id,
    required this.name,
    this.description,
  });

  // Create a MaintenanceType from a Map (database)
  factory MaintenanceType.fromMap(Map<String, dynamic> map) {
    return MaintenanceType(
      id: map['id'],
      name: map['name'],
      description: map['description'],
    );
  }

  // Convert a MaintenanceType to a Map (database)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
    };
  }
}

class MaintenanceActivity {
  final int? id;
  final int vineID;
  final int typeID;
  final DateTime activityDate;
  final String? notes;

  MaintenanceActivity({
    this.id,
    required this.vineID,
    required this.typeID,
    required this.activityDate,
    this.notes,
  });

  // Create a MaintenanceActivity from a Map (database)
  factory MaintenanceActivity.fromMap(Map<String, dynamic> map) {
    return MaintenanceActivity(
      id: map['id'],
      vineID: map['vineID'],
      typeID: map['typeID'],
      activityDate: DateTime.parse(map['activityDate']),
      notes: map['notes'],
    );
  }

  // Convert a MaintenanceActivity to a Map (database)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'vineID': vineID,
      'typeID': typeID,
      'activityDate': activityDate.toIso8601String(),
      'notes': notes,
    };
  }
}