import '../../models/api/maintenance_api.dart';
import '../../models/maintenance.dart';
import 'api_service.dart';

class MaintenanceApiService {
  final ApiService _apiService = ApiService();
  final String _typesEndpoint = '/maintenance/types';
  final String _activitiesEndpoint = '/maintenance/activities';

  // Get all maintenance types
  Future<List<MaintenanceType>> getAllMaintenanceTypes() async {
    final response = await _apiService.get(_typesEndpoint);
    final List<dynamic> typesJson = response is List ? response : (response['data'] ?? []);
    return typesJson
        .map((json) => MaintenanceTypeApiModel.fromJson(json).toLocalModel())
        .toList();
  }

  // Get maintenance type by ID
  Future<MaintenanceType> getMaintenanceTypeById(int id) async {
    final response = await _apiService.get('$_typesEndpoint/$id');
    final jsonData = response is Map ? (response['data'] ?? response) : response;
    return MaintenanceTypeApiModel.fromJson(jsonData).toLocalModel();
  }

  // Create a maintenance type
  Future<MaintenanceType> createMaintenanceType(MaintenanceType type) async {
    final typeApi = MaintenanceTypeApiModel.fromLocalModel(type);
    final response = await _apiService.post(_typesEndpoint, typeApi.toJson());
    final jsonData = response is Map ? (response['data'] ?? response) : response;
    return MaintenanceTypeApiModel.fromJson(jsonData).toLocalModel();
  }

  // Update a maintenance type
  Future<MaintenanceType> updateMaintenanceType(MaintenanceType type) async {
    if (type.id == null) {
      throw Exception('Maintenance type ID cannot be null for update operation');
    }
    
    final typeApi = MaintenanceTypeApiModel.fromLocalModel(type);
    final response = await _apiService.put('$_typesEndpoint/${type.id}', typeApi.toJson());
    final jsonData = response is Map ? (response['data'] ?? response) : response;
    return MaintenanceTypeApiModel.fromJson(jsonData).toLocalModel();
  }

  // Delete a maintenance type
  Future<void> deleteMaintenanceType(int id) async {
    await _apiService.delete('$_typesEndpoint/$id');
  }

  // Get all maintenance activities
  Future<List<MaintenanceActivity>> getAllMaintenanceActivities() async {
    final response = await _apiService.get(_activitiesEndpoint);
    final List<dynamic> activitiesJson = response is List ? response : (response['data'] ?? []);
    return activitiesJson
        .map((json) => MaintenanceActivityApiModel.fromJson(json).toLocalModel())
        .toList();
  }

  // Get maintenance activities by vine ID
  Future<List<MaintenanceActivity>> getMaintenanceActivitiesByVineId(int vineId) async {
    final response = await _apiService.get('$_activitiesEndpoint/vine/$vineId');
    final List<dynamic> activitiesJson = response is List ? response : (response['data'] ?? []);
    return activitiesJson
        .map((json) => MaintenanceActivityApiModel.fromJson(json).toLocalModel())
        .toList();
  }

  // Get maintenance activity by ID
  Future<MaintenanceActivity> getMaintenanceActivityById(int id) async {
    final response = await _apiService.get('$_activitiesEndpoint/$id');
    final jsonData = response is Map ? (response['data'] ?? response) : response;
    return MaintenanceActivityApiModel.fromJson(jsonData).toLocalModel();
  }

  // Create a maintenance activity
  Future<MaintenanceActivity> createMaintenanceActivity(MaintenanceActivity activity) async {
    final activityApi = MaintenanceActivityApiModel.fromLocalModel(activity);
    final response = await _apiService.post(_activitiesEndpoint, activityApi.toJson());
    final jsonData = response is Map ? (response['data'] ?? response) : response;
    return MaintenanceActivityApiModel.fromJson(jsonData).toLocalModel();
  }

  // Update a maintenance activity
  Future<MaintenanceActivity> updateMaintenanceActivity(MaintenanceActivity activity) async {
    if (activity.id == null) {
      throw Exception('Maintenance activity ID cannot be null for update operation');
    }
    
    final activityApi = MaintenanceActivityApiModel.fromLocalModel(activity);
    final response = await _apiService.put('$_activitiesEndpoint/${activity.id}', activityApi.toJson());
    final jsonData = response is Map ? (response['data'] ?? response) : response;
    return MaintenanceActivityApiModel.fromJson(jsonData).toLocalModel();
  }

  // Delete a maintenance activity
  Future<void> deleteMaintenanceActivity(int id) async {
    await _apiService.delete('$_activitiesEndpoint/$id');
  }
}