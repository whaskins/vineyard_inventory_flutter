import '../issue.dart';
import 'dart:io';
import 'dart:convert';
import '../../config/api_config.dart';

class VineIssueApiModel {
  final int? id;
  final int vineId;
  final String description;
  final String? photoPath;  // API's photo_path (relative path on server)
  final String? photoUrl;   // Full URL for the photo
  final String dateReported;
  final int reportedById;
  final bool isResolved;
  final String? dateResolved;
  final int? resolvedById;
  final String createdAt;
  final String updatedAt;

  VineIssueApiModel({
    this.id,
    required this.vineId,
    required this.description,
    this.photoPath,
    this.photoUrl,
    required this.dateReported,
    required this.reportedById,
    this.isResolved = false,
    this.dateResolved,
    this.resolvedById,
    required this.createdAt,
    required this.updatedAt,
  });

  // Convert API response to VineIssueApiModel
  factory VineIssueApiModel.fromJson(Map<String, dynamic> json) {
    // Get the photo_path from the API response
    final String? apiPhotoPath = json['photo_path'];
    
    // Generate the full URL for the photo if available
    String? photoUrl;
    if (json['id'] != null) {
      // Construct the URL for the photo endpoint
      photoUrl = '${ApiConfig.baseUrl}/issues/${json['id']}/photo';
      print('DEBUG: Constructed photo URL: $photoUrl');
    }
    
    // Safely extract the reported_by field, which may be under different names
    int reportedById = 0;
    if (json.containsKey('reported_by_id')) {
      reportedById = json['reported_by_id'] ?? 0;
    } else if (json.containsKey('reported_by')) {
      reportedById = json['reported_by'] ?? 0;
    }
    
    // Safely extract the resolved_by field
    int? resolvedById;
    if (json.containsKey('resolved_by_id')) {
      resolvedById = json['resolved_by_id'];
    } else if (json.containsKey('resolved_by')) {
      resolvedById = json['resolved_by'];
    }
    
    return VineIssueApiModel(
      id: json['id'],
      vineId: json['vine_id'],
      description: json['description'],
      photoPath: apiPhotoPath,
      photoUrl: photoUrl,
      dateReported: json['date_reported'],
      reportedById: reportedById,
      isResolved: json['is_resolved'] ?? false,
      dateResolved: json['date_resolved'],
      resolvedById: resolvedById,
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
    );
  }

  // Convert VineIssueApiModel to JSON for API request
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'vine_id': vineId,
      'description': description,
      'date_reported': dateReported,
      'reported_by_id': reportedById,
      'is_resolved': isResolved,
      'date_resolved': dateResolved,
      'resolved_by_id': resolvedById,
    };
    
    // If there's a photo path, we should convert the image to base64
    // This is only used for backward compatibility with the older API version
    if (photoPath != null && photoPath!.isNotEmpty && photoPath!.startsWith('/')) {
      try {
        final File imageFile = File(photoPath!);
        if (imageFile.existsSync()) {
          final bytes = imageFile.readAsBytesSync();
          final base64Image = base64Encode(bytes);
          json['photo_data_base64'] = base64Image;
          
          // Add MIME type based on file extension
          final extension = photoPath!.split('.').last.toLowerCase();
          String contentType = 'image/jpeg'; // Default
          
          if (extension == 'png') {
            contentType = 'image/png';
          } else if (extension == 'gif') {
            contentType = 'image/gif';
          } else if (extension == 'webp') {
            contentType = 'image/webp';
          } else if (extension == 'heic' || extension == 'heif') {
            contentType = 'image/heic';
          }
          
          json['photo_content_type'] = contentType;
        }
      } catch (e) {
        print('DEBUG: Error encoding image to base64: $e');
      }
    }
    
    return json;
  }

  // Convert API model to local model
  VineIssue toLocalModel() {
    String? localPhotoPath = null;
    if (photoPath != null && photoPath!.startsWith('/')) {
      localPhotoPath = photoPath;
    }
    
    return VineIssue(
      id: id,
      vineID: vineId,
      description: description,
      photoPath: localPhotoPath,  // Only use as local path if it's an absolute path
      photoUrl: photoUrl,
      dateReported: DateTime.parse(dateReported),
      reportedBy: reportedById,
      isResolved: isResolved,
      dateResolved: dateResolved != null ? DateTime.parse(dateResolved!) : null,
      resolvedBy: resolvedById,
    );
  }

  // Convert local model to API model
  static VineIssueApiModel fromLocalModel(VineIssue issue) {
    return VineIssueApiModel(
      id: issue.id,
      vineId: issue.vineID,
      description: issue.description,
      photoPath: issue.photoPath,
      photoUrl: issue.photoUrl,
      dateReported: issue.dateReported.toIso8601String(),
      reportedById: issue.reportedBy,
      isResolved: issue.isResolved,
      dateResolved: issue.dateResolved?.toIso8601String(),
      resolvedById: issue.resolvedBy,
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    );
  }
}