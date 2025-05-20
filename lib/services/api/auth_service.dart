import '../../models/api/user_api.dart';
import '../../config/api_config.dart';
import 'api_service.dart';

class AuthService {
  final ApiService _apiService = ApiService();
  // Using endpoints from ApiConfig for consistency
  final String _loginEndpoint = ApiConfig.authLogin;
  final String _registerEndpoint = ApiConfig.register;
  final String _userEndpoint = '/users/me';

  // Login with email and password
  Future<LoginResponse> login(String email, String password) async {
    print('DEBUG: Attempting login for email: $email');
    
    try {
      final response = await _apiService.login(email, password);
      print('DEBUG: Login response received');
      
      final loginResponse = LoginResponse.fromJson(response);
      print('DEBUG: Access token received: ${loginResponse.accessToken?.substring(0, 15)}...');
      
      // If user info is not included in the token response, fetch it separately
      if (loginResponse.user == null) {
        print('DEBUG: User info not included in login response, fetching separately');
        try {
          final userResponse = await getCurrentUser();
          print('DEBUG: User info fetched: ${userResponse.email}');
          return LoginResponse(
            accessToken: loginResponse.accessToken,
            tokenType: loginResponse.tokenType,
            user: userResponse,
          );
        } catch (e) {
          // If we can't get the user, just return the login response without user info
          print('DEBUG: Error fetching user after login: $e');
          return loginResponse;
        }
      }
      
      print('DEBUG: Login completed successfully with user info');
      return loginResponse;
    } catch (e) {
      print('DEBUG: Login error: $e');
      rethrow;
    }
  }

  // Register a new user
  Future<UserApiModel> register(String email, String password, String fullName) async {
    try {
      final response = await _apiService.post(_registerEndpoint, {
        'email': email,
        'password': password,
        'full_name': fullName,
      });
      
      // Debug print to see the response structure
      print('Registration response: $response');
      
      // The FastAPI backend returns the user data directly, not wrapped in a 'data' field
      return UserApiModel.fromJson(response);
    } catch (e) {
      print('Registration error: $e');
      rethrow;
    }
  }

  // Get current user profile
  Future<UserApiModel> getCurrentUser() async {
    final response = await _apiService.get(_userEndpoint);
    // The FastAPI backend returns the user data directly, not wrapped in a 'data' field
    return UserApiModel.fromJson(response);
  }

  // Check if user is authenticated
  bool isAuthenticated() {
    final authenticated = _apiService.isAuthenticated;
    print('DEBUG: Authentication check: $authenticated');
    return authenticated;
  }

  // Logout (clear token)
  void logout() {
    print('DEBUG: Logging out, clearing authentication token');
    _apiService.token = null;
  }
}