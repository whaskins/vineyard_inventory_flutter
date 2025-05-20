import '../maintenance.dart';

class MaintenanceTypeApiModel {
  final int? id;
  final String name;
  final String? description;
  final String createdAt;
  final String updatedAt;

  MaintenanceTypeApiModel({
    this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  // Convert API response to MaintenanceTypeApiModel
  factory MaintenanceTypeApiModel.fromJson(Map<String, dynamic> json) {
    return MaintenanceTypeApiModel(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
    );
  }

  // Convert MaintenanceTypeApiModel to JSON for API request
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
    };
  }

  // Convert API model to local model
  MaintenanceType toLocalModel() {
    return MaintenanceType(
      id: id,
      name: name,
      description: description,
    );
  }

  // Convert local model to API model
  static MaintenanceTypeApiModel fromLocalModel(MaintenanceType maintenanceType) {
    return MaintenanceTypeApiModel(
      id: maintenanceType.id,
      name: maintenanceType.name,
      description: maintenanceType.description,
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    );
  }
}

class MaintenanceActivityApiModel {
  final int? id;
  final int vineId;
  final int typeId;
  final String activityDate;
  final String? notes;
  final String createdAt;
  final String updatedAt;

  MaintenanceActivityApiModel({
    this.id,
    required this.vineId,
    required this.typeId,
    required this.activityDate,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  // Convert API response to MaintenanceActivityApiModel
  factory MaintenanceActivityApiModel.fromJson(Map<String, dynamic> json) {
    return MaintenanceActivityApiModel(
      id: json['id'],
      vineId: json['vine_id'],
      typeId: json['type_id'],
      activityDate: json['activity_date'],
      notes: json['notes'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
    );
  }

  // Convert MaintenanceActivityApiModel to JSON for API request
  Map<String, dynamic> toJson() {
    return {
      'vine_id': vineId,
      'type_id': typeId,
      'activity_date': activityDate,
      'notes': notes,
    };
  }

  // Convert API model to local model
  MaintenanceActivity toLocalModel() {
    return MaintenanceActivity(
      id: id,
      vineID: vineId,
      typeID: typeId,
      activityDate: DateTime.parse(activityDate),
      notes: notes,
    );
  }

  // Convert local model to API model
  static MaintenanceActivityApiModel fromLocalModel(MaintenanceActivity activity) {
    return MaintenanceActivityApiModel(
      id: activity.id,
      vineId: activity.vineID,
      typeId: activity.typeID,
      activityDate: activity.activityDate.toIso8601String(),
      notes: activity.notes,
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    );
  }
}