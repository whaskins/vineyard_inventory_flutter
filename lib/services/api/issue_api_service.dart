import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as path;

import '../../config/api_config.dart';
import '../../models/api/issue_api.dart';
import '../../models/issue.dart';
import 'api_service.dart';

class IssueApiService {
  final ApiService _apiService = ApiService();
  final String _endpoint = '/issues';

  // Get all issues
  Future<List<VineIssue>> getAllIssues() async {
    final response = await _apiService.get(_endpoint);
    // Direct access to response which is a list, without expecting 'data' field
    final List<dynamic> issuesJson = response is List ? response : [response];
    return issuesJson
        .map((json) => VineIssueApiModel.fromJson(json).toLocalModel())
        .toList();
  }

  // Get issues by vine ID
  Future<List<VineIssue>> getIssuesByVineId(int vineId) async {
    try {
      print('DEBUG: Making API request to $_endpoint/vine/$vineId');
      final response = await _apiService.get('$_endpoint/vine/$vineId');
      print('DEBUG: Received API response type: ${response.runtimeType}');
      
      if (response is List) {
        print('DEBUG: Response is a list of ${response.length} items');
      } else {
        print('DEBUG: Response is not a list: $response');
      }
      
      // Direct access to response which is a list, without expecting 'data' field
      final List<dynamic> issuesJson = response is List ? response : [response];
      
      // Process each issue with error handling
      List<VineIssue> issues = [];
      for (var json in issuesJson) {
        try {
          final model = VineIssueApiModel.fromJson(json);
          final issue = model.toLocalModel();
          issues.add(issue);
        } catch (e) {
          print('DEBUG: Error parsing issue from JSON: $e');
          print('DEBUG: Problematic JSON: $json');
        }
      }
      
      print('DEBUG: Successfully parsed ${issues.length} issues');
      return issues;
    } catch (e) {
      print('DEBUG: Error in getIssuesByVineId: $e');
      rethrow;
    }
  }

  // Get issue by ID
  Future<VineIssue> getIssueById(int id) async {
    final response = await _apiService.get('$_endpoint/$id');
    return VineIssueApiModel.fromJson(response).toLocalModel();
  }

  // Create a new issue using multipart form upload for the image
  Future<VineIssue> createIssueWithFormUpload(VineIssue issue) async {
    try {
      print('DEBUG: Creating issue for vine ${issue.vineID} with form upload');
      
      // Create a multipart request
      final url = Uri.parse('${ApiConfig.baseUrl}$_endpoint/upload');
      final request = http.MultipartRequest('POST', url);
      
      // Add authorization header
      final headers = _apiService.getAuthHeaders();
      if (headers.isNotEmpty) {
        request.headers.addAll(headers);
      }
      
      // Add the text fields
      request.fields['vine_id'] = issue.vineID.toString();
      request.fields['description'] = issue.description;
      request.fields['date_reported'] = issue.dateReported.toIso8601String();
      request.fields['reported_by_id'] = issue.reportedBy.toString();
      request.fields['is_resolved'] = issue.isResolved.toString();
      
      if (issue.dateResolved != null) {
        request.fields['date_resolved'] = issue.dateResolved!.toIso8601String();
      }
      
      if (issue.resolvedBy != null) {
        request.fields['resolved_by_id'] = issue.resolvedBy.toString();
      }
      
      // Add the photo file if available
      if (issue.photoPath != null && issue.photoPath!.isNotEmpty) {
        final photoFile = File(issue.photoPath!);
        
        if (await photoFile.exists()) {
          final fileName = path.basename(photoFile.path);
          final extension = path.extension(fileName).toLowerCase().replaceFirst('.', '');
          
          // Determine content type
          String contentType = 'image/jpeg';
          if (extension == 'png') {
            contentType = 'image/png';
          } else if (extension == 'gif') {
            contentType = 'image/gif';
          } else if (extension == 'webp') {
            contentType = 'image/webp';
          } else if (extension == 'heic' || extension == 'heif') {
            contentType = 'image/heic';
          }
          
          // Add file to request
          final photoStream = http.ByteStream(photoFile.openRead());
          final photoLength = await photoFile.length();
          
          final photoUpload = http.MultipartFile(
            'photo',
            photoStream,
            photoLength,
            filename: fileName,
            contentType: MediaType.parse(contentType)
          );
          
          request.files.add(photoUpload);
          print('DEBUG: Added photo file to request: $fileName, type: $contentType, size: $photoLength bytes');
        } else {
          print('DEBUG: Photo file does not exist: ${issue.photoPath}');
        }
      }
      
      // Send the request
      print('DEBUG: Sending multipart request to $url');
      final streamedResponse = await request.send();
      
      // Convert to a regular response
      final response = await http.Response.fromStream(streamedResponse);
      
      print('DEBUG: Form upload response status: ${response.statusCode}');
      print('DEBUG: Form upload response body: ${response.body}');
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Parse the response
        final responseJson = _apiService.parseJsonResponse(response.body);
        
        // Convert API response to local model
        final apiIssue = VineIssueApiModel.fromJson(responseJson).toLocalModel();
        
        // Keep the local photo path for offline access
        return apiIssue.copyWith(photoPath: issue.photoPath);
      } else {
        throw HttpException('Error creating issue: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('DEBUG: Error creating issue with form upload: $e');
      // If API call fails, return the original issue - it will still be saved locally
      return issue;
    }
  }

  // Create a new issue (uses new method with form upload if there's a photo, otherwise uses JSON)
  Future<VineIssue> createIssue(VineIssue issue) async {
    if (issue.photoPath != null && issue.photoPath!.isNotEmpty) {
      // Use form upload for issues with photos
      return createIssueWithFormUpload(issue);
    }
    
    // For issues without photos, use the traditional JSON approach
    try {
      print('DEBUG: Creating issue for vine ${issue.vineID} (no photo)');
      final issueApi = VineIssueApiModel.fromLocalModel(issue);
      
      // Convert to API format
      final apiPayload = issueApi.toJson();
      print('DEBUG: API payload has ${apiPayload.length} fields, keys: ${apiPayload.keys.join(', ')}');
      
      final response = await _apiService.post(_endpoint, apiPayload);
      print('DEBUG: Issue created successfully in API');
      
      // Convert API response to local model
      final apiIssue = VineIssueApiModel.fromJson(response).toLocalModel();
      return apiIssue;
    } catch (e) {
      print('DEBUG: Error creating issue in API: $e');
      // If API call fails, return the original issue - it will still be saved locally
      return issue;
    }
  }

  // Update an issue using multipart form upload for the image
  Future<VineIssue> updateIssueWithFormUpload(VineIssue issue) async {
    if (issue.id == null) {
      throw Exception('Issue ID cannot be null for update operation');
    }
    
    try {
      print('DEBUG: Updating issue for vine ${issue.vineID} with form upload');
      
      // Create a multipart request
      final url = Uri.parse('${ApiConfig.baseUrl}$_endpoint/${issue.id}/upload');
      final request = http.MultipartRequest('PUT', url);
      
      // Add authorization header
      final headers = _apiService.getAuthHeaders();
      if (headers.isNotEmpty) {
        request.headers.addAll(headers);
      }
      
      // Add the text fields
      request.fields['vine_id'] = issue.vineID.toString();
      request.fields['description'] = issue.description;
      request.fields['date_reported'] = issue.dateReported.toIso8601String();
      request.fields['reported_by_id'] = issue.reportedBy.toString();
      request.fields['is_resolved'] = issue.isResolved.toString();
      
      if (issue.dateResolved != null) {
        request.fields['date_resolved'] = issue.dateResolved!.toIso8601String();
      }
      
      if (issue.resolvedBy != null) {
        request.fields['resolved_by_id'] = issue.resolvedBy.toString();
      }
      
      // Add the photo file if available
      if (issue.photoPath != null && issue.photoPath!.isNotEmpty) {
        final photoFile = File(issue.photoPath!);
        
        if (await photoFile.exists()) {
          final fileName = path.basename(photoFile.path);
          final extension = path.extension(fileName).toLowerCase().replaceFirst('.', '');
          
          // Determine content type
          String contentType = 'image/jpeg';
          if (extension == 'png') {
            contentType = 'image/png';
          } else if (extension == 'gif') {
            contentType = 'image/gif';
          } else if (extension == 'webp') {
            contentType = 'image/webp';
          } else if (extension == 'heic' || extension == 'heif') {
            contentType = 'image/heic';
          }
          
          // Add file to request
          final photoStream = http.ByteStream(photoFile.openRead());
          final photoLength = await photoFile.length();
          
          final photoUpload = http.MultipartFile(
            'photo',
            photoStream,
            photoLength,
            filename: fileName,
            contentType: MediaType.parse(contentType)
          );
          
          request.files.add(photoUpload);
          print('DEBUG: Added photo file to request: $fileName, type: $contentType, size: $photoLength bytes');
        } else {
          print('DEBUG: Photo file does not exist: ${issue.photoPath}');
        }
      }
      
      // Send the request
      print('DEBUG: Sending multipart request to $url');
      final streamedResponse = await request.send();
      
      // Convert to a regular response
      final response = await http.Response.fromStream(streamedResponse);
      
      print('DEBUG: Form upload response status: ${response.statusCode}');
      print('DEBUG: Form upload response body: ${response.body}');
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Parse the response
        final responseJson = _apiService.parseJsonResponse(response.body);
        
        // Convert API response to local model
        final apiIssue = VineIssueApiModel.fromJson(responseJson).toLocalModel();
        
        // Keep the local photo path for offline access
        return apiIssue.copyWith(photoPath: issue.photoPath);
      } else {
        throw HttpException('Error updating issue: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('DEBUG: Error updating issue with form upload: $e');
      // If API call fails, return the original issue - it will still be saved locally
      return issue;
    }
  }

  // Update an issue (uses new method with form upload if there's a photo, otherwise uses JSON)
  Future<VineIssue> updateIssue(VineIssue issue) async {
    if (issue.id == null) {
      throw Exception('Issue ID cannot be null for update operation');
    }
    
    if (issue.photoPath != null && issue.photoPath!.isNotEmpty) {
      // Use form upload for issues with photos
      return updateIssueWithFormUpload(issue);
    }
    
    // For issues without photos, use the traditional JSON approach
    try {
      print('DEBUG: Updating issue for vine ${issue.vineID} (no photo)');
      final issueApi = VineIssueApiModel.fromLocalModel(issue);
      
      // Convert to API format
      final apiPayload = issueApi.toJson();
      print('DEBUG: API payload has ${apiPayload.length} fields, keys: ${apiPayload.keys.join(', ')}');
      
      final response = await _apiService.put('$_endpoint/${issue.id}', apiPayload);
      print('DEBUG: Issue updated successfully in API');
      
      // Convert API response to local model
      final apiIssue = VineIssueApiModel.fromJson(response).toLocalModel();
      return apiIssue;
    } catch (e) {
      print('DEBUG: Error updating issue in API: $e');
      // If API call fails, return the original issue - it will still be saved locally
      return issue;
    }
  }

  // Mark issue as resolved
  Future<VineIssue> resolveIssue(int id, int resolvedById) async {
    final response = await _apiService.put('$_endpoint/$id/resolve', {
      'resolved_by_id': resolvedById,
    });
    return VineIssueApiModel.fromJson(response).toLocalModel();
  }

  // Delete an issue
  Future<void> deleteIssue(int id) async {
    await _apiService.delete('$_endpoint/$id');
  }
}