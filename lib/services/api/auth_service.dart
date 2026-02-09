import '../../models/api/user_api.dart';
import '../../models/api/organization_api.dart';
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

  // Register a new user (joining an existing org via invite code)
  Future<UserApiModel> register(String email, String password, String fullName, {required String inviteCode}) async {
    try {
      final response = await _apiService.post(_registerEndpoint, {
        'email': email,
        'password': password,
        'full_name': fullName,
        'invite_code': inviteCode,
      });

      print('Registration response: $response');
      return UserApiModel.fromJson(response);
    } catch (e) {
      print('Registration error: $e');
      rethrow;
    }
  }

  // Register a new user and create a new organization
  // Returns a map with user data plus 'inviteCode'
  Future<Map<String, dynamic>> registerWithOrg(String email, String password, String fullName, String orgName) async {
    try {
      final response = await _apiService.post('/users/register-with-org', {
        'email': email,
        'password': password,
        'full_name': fullName,
        'org_name': orgName,
      });

      print('Register with org response: $response');
      return {
        'user': UserApiModel.fromJson(response),
        'orgId': response['org_id'],
        'inviteCode': response['invite_code'],
      };
    } catch (e) {
      print('Register with org error: $e');
      rethrow;
    }
  }

  // Get current user profile
  Future<UserApiModel> getCurrentUser() async {
    final response = await _apiService.get(_userEndpoint);
    // The FastAPI backend returns the user data directly, not wrapped in a 'data' field
    return UserApiModel.fromJson(response);
  }

  // Get current user's organization
  Future<OrganizationApiModel> getMyOrganization() async {
    final response = await _apiService.get('${ApiConfig.organizations}/me');
    return OrganizationApiModel.fromJson(response);
  }

  // --- Member management (admin) ---

  // Get all members in the current organization
  Future<List<UserApiModel>> getMembers() async {
    try {
      final response = await _apiService.get('${ApiConfig.organizations}/members');
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => UserApiModel.fromJson(json)).toList();
    } catch (e) {
      print('Get members error: $e');
      rethrow;
    }
  }

  // Deactivate a member
  Future<UserApiModel> deactivateMember(int userId) async {
    try {
      final response = await _apiService.put(
        '${ApiConfig.organizations}/members/$userId/deactivate',
        {},
      );
      return UserApiModel.fromJson(response);
    } catch (e) {
      print('Deactivate member error: $e');
      rethrow;
    }
  }

  // Activate a member
  Future<UserApiModel> activateMember(int userId) async {
    try {
      final response = await _apiService.put(
        '${ApiConfig.organizations}/members/$userId/activate',
        {},
      );
      return UserApiModel.fromJson(response);
    } catch (e) {
      print('Activate member error: $e');
      rethrow;
    }
  }

  // Get the current invite code
  Future<String> getInviteCode() async {
    try {
      final response = await _apiService.get('${ApiConfig.organizations}/invite-code');
      return response['invite_code'] as String;
    } catch (e) {
      print('Get invite code error: $e');
      rethrow;
    }
  }

  // Regenerate the invite code (invalidates old one)
  Future<String> regenerateInviteCode() async {
    try {
      final response = await _apiService.post(
        '${ApiConfig.organizations}/regenerate-invite-code',
        {},
      );
      return response['invite_code'] as String;
    } catch (e) {
      print('Regenerate invite code error: $e');
      rethrow;
    }
  }

  // Get current org_id from token
  int? get currentOrgId => _apiService.currentOrgId;

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