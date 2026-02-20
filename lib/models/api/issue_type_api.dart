import '../issue_type.dart';

class IssueTypeApiModel {
  final int? id;
  final String name;
  final String? description;
  final String createdAt;

  IssueTypeApiModel({
    this.id,
    required this.name,
    this.description,
    required this.createdAt,
  });

  // Convert API response to IssueTypeApiModel
  factory IssueTypeApiModel.fromJson(Map<String, dynamic> json) {
    return IssueTypeApiModel(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      createdAt: json['created_at'] ?? DateTime.now().toIso8601String(),
    );
  }

  // Convert IssueTypeApiModel to JSON for API request
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
    };
  }

  // Convert API model to local model
  IssueType toLocalModel() {
    return IssueType(
      id: id,
      name: name,
      description: description,
    );
  }

  // Convert local model to API model
  static IssueTypeApiModel fromLocalModel(IssueType issueType) {
    return IssueTypeApiModel(
      id: issueType.id,
      name: issueType.name,
      description: issueType.description,
      createdAt: DateTime.now().toIso8601String(),
    );
  }
}
