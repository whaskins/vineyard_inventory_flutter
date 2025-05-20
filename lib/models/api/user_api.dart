class UserApiModel {
  final int? id;
  final String email;
  final String? fullName;
  final bool isActive;
  final bool isAdmin;
  final String createdAt;
  final String updatedAt;

  UserApiModel({
    this.id,
    required this.email,
    this.fullName,
    this.isActive = true,
    this.isAdmin = false,
    required this.createdAt,
    required this.updatedAt,
  });

  // Convert API response to UserApiModel
  factory UserApiModel.fromJson(Map<String, dynamic> json) {
    return UserApiModel(
      id: json['id'],
      email: json['email'],
      fullName: json['full_name'],
      isActive: json['is_active'] ?? true,
      isAdmin: json['is_superuser'] ?? false, // Backend uses is_superuser instead of is_admin
      createdAt: json['created_at'] ?? DateTime.now().toIso8601String(),
      updatedAt: json['updated_at'] ?? DateTime.now().toIso8601String(),
    );
  }

  // Convert UserApiModel to JSON for API request
  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'full_name': fullName,
      'is_active': isActive,
      'is_admin': isAdmin,
    };
  }
}

class LoginResponse {
  final String accessToken;
  final String tokenType;
  final UserApiModel? user; // Make user optional since it might not be in the response

  LoginResponse({
    required this.accessToken,
    required this.tokenType,
    this.user,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      accessToken: json['access_token'],
      tokenType: json['token_type'] ?? 'bearer',
      // The user might not be included in the token response if the backend doesn't return it
      user: json.containsKey('user') ? UserApiModel.fromJson(json['user']) : null,
    );
  }
}