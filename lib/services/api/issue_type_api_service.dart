import '../../models/api/issue_type_api.dart';
import '../../models/issue_type.dart';
import 'api_service.dart';

class IssueTypeApiService {
  final ApiService _apiService = ApiService();
  final String _typesEndpoint = '/issue-types/types';

  // Get all issue types
  Future<List<IssueType>> getAllIssueTypes() async {
    final response = await _apiService.get(_typesEndpoint);
    final List<dynamic> typesJson = response is List ? response : (response['data'] ?? []);
    return typesJson
        .map((json) => IssueTypeApiModel.fromJson(json).toLocalModel())
        .toList();
  }

  // Get issue type by ID
  Future<IssueType> getIssueTypeById(int id) async {
    final response = await _apiService.get('$_typesEndpoint/$id');
    final jsonData = response is Map ? (response['data'] ?? response) : response;
    return IssueTypeApiModel.fromJson(jsonData).toLocalModel();
  }

  // Create an issue type
  Future<IssueType> createIssueType(IssueType type) async {
    final typeApi = IssueTypeApiModel.fromLocalModel(type);
    final response = await _apiService.post(_typesEndpoint, typeApi.toJson());
    final jsonData = response is Map ? (response['data'] ?? response) : response;
    return IssueTypeApiModel.fromJson(jsonData).toLocalModel();
  }

  // Update an issue type
  Future<IssueType> updateIssueType(IssueType type) async {
    if (type.id == null) {
      throw Exception('Issue type ID cannot be null for update operation');
    }

    final typeApi = IssueTypeApiModel.fromLocalModel(type);
    final response = await _apiService.put('$_typesEndpoint/${type.id}', typeApi.toJson());
    final jsonData = response is Map ? (response['data'] ?? response) : response;
    return IssueTypeApiModel.fromJson(jsonData).toLocalModel();
  }

  // Delete an issue type
  Future<void> deleteIssueType(int id) async {
    await _apiService.delete('$_typesEndpoint/$id');
  }
}
