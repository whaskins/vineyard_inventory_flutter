import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vineyard_inventory_flutter/config/api_config.dart';

// Custom auth exception class
class AuthException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  AuthException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() => message;
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  
  // Auth token
  String? _token;

  // Organization ID from JWT token
  int? _orgId;

  // Store credentials for auto-refresh
  String? _lastEmail;
  String? _lastPassword;

  // Token refresh settings
  bool _autoRefreshEnabled = true; // Enable auto-refresh by default
  int _refreshThresholdMinutes = 60; // Refresh token if it expires in less than 60 minutes
  bool _isRefreshing = false; // Flag to prevent multiple simultaneous refresh attempts

  // Secure storage for credentials
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Storage keys
  static const String _tokenKey = 'auth_token';
  static const String _emailKey = 'auth_email';
  static const String _passwordKey = 'auth_password';
  static const String _orgIdKey = 'auth_org_id';

  // Constructor with initialization
  ApiService._internal() {
    _loadFromStorage();
  }
  
  // Load auth data from persistent storage
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedToken = prefs.getString(_tokenKey);

      if (storedToken != null && storedToken.isNotEmpty) {
        print('DEBUG: Loaded auth token from storage');
        _token = storedToken;

        // Check if token needs refresh
        if (_autoRefreshEnabled && _isTokenExpiring()) {
          print('DEBUG: Stored token is expiring soon, will attempt refresh');

          // Load credentials from secure storage for refresh
          _lastEmail = await _secureStorage.read(key: _emailKey);
          _lastPassword = await _secureStorage.read(key: _passwordKey);

          if (_lastEmail != null && _lastPassword != null) {
            _refreshToken();
          } else {
            print('DEBUG: Cannot refresh token - credentials not found');
          }
        }
      } else {
        print('DEBUG: No stored auth token found');
      }

      // Load credentials from secure storage for future refreshes
      _lastEmail = await _secureStorage.read(key: _emailKey);
      _lastPassword = await _secureStorage.read(key: _passwordKey);

      // Migrate: if credentials exist in SharedPreferences, move to secure storage
      final oldEmail = prefs.getString(_emailKey);
      final oldPassword = prefs.getString(_passwordKey);
      if (oldEmail != null || oldPassword != null) {
        if (oldEmail != null && oldPassword != null) {
          await _secureStorage.write(key: _emailKey, value: oldEmail);
          await _secureStorage.write(key: _passwordKey, value: oldPassword);
          _lastEmail = oldEmail;
          _lastPassword = oldPassword;
          print('DEBUG: Migrated credentials from SharedPreferences to secure storage');
        }
        await prefs.remove(_emailKey);
        await prefs.remove(_passwordKey);
      }

      // Load org_id
      if (prefs.containsKey(_orgIdKey)) {
        _orgId = prefs.getInt(_orgIdKey);
        print('DEBUG: Loaded org_id from storage: $_orgId');
      }
    } catch (e) {
      print('DEBUG: Error loading auth data from storage: $e');
    }
  }
  
  // Save token and credentials to persistent storage
  Future<void> _saveAuthDataToStorage({String? token, String? email, String? password}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save token to SharedPreferences (non-sensitive)
      if (token != null) {
        if (token.isNotEmpty) {
          await prefs.setString(_tokenKey, token);
          print('DEBUG: Saved auth token to storage');
        } else {
          await prefs.remove(_tokenKey);
          print('DEBUG: Removed auth token from storage');
        }
      }

      // Save credentials to secure storage (sensitive)
      if (email != null) {
        if (email.isNotEmpty) {
          await _secureStorage.write(key: _emailKey, value: email);
        } else {
          await _secureStorage.delete(key: _emailKey);
        }
      }

      if (password != null) {
        if (password.isNotEmpty) {
          await _secureStorage.write(key: _passwordKey, value: password);
        } else {
          await _secureStorage.delete(key: _passwordKey);
        }
      }
    } catch (e) {
      print('DEBUG: Error saving auth data to storage: $e');
    }
  }
  
  // Convenience method for just saving the token
  Future<void> _saveTokenToStorage(String? token) async {
    return _saveAuthDataToStorage(token: token);
  }

  // Extract org_id from JWT token payload
  void _extractOrgIdFromToken(String token) {
    try {
      final Map<String, dynamic> payload = JwtDecoder.decode(token);
      if (payload.containsKey('org_id')) {
        _orgId = payload['org_id'] as int?;
        print('DEBUG: Extracted org_id from token: $_orgId');
        _saveOrgIdToStorage(_orgId);
      }
    } catch (e) {
      print('DEBUG: Error extracting org_id from token: $e');
    }
  }

  // Save org_id to persistent storage
  Future<void> _saveOrgIdToStorage(int? orgId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (orgId != null) {
        await prefs.setInt(_orgIdKey, orgId);
      } else {
        await prefs.remove(_orgIdKey);
      }
    } catch (e) {
      print('DEBUG: Error saving org_id to storage: $e');
    }
  }
  
  // Getter for authenticated status
  bool get isAuthenticated => _token != null;

  // Getter for current org ID
  int? get currentOrgId => _orgId;

  // Auth token setter
  set token(String? value) {
    _token = value;

    // If token is null/empty, also clear credentials and org_id
    if (value == null || value.isEmpty) {
      _lastEmail = null;
      _lastPassword = null;
      _orgId = null;
      _saveAuthDataToStorage(
        token: '',
        email: '',
        password: '',
      );
      _saveOrgIdToStorage(null);
    } else {
      _saveTokenToStorage(value);
      _extractOrgIdFromToken(value);
    }
  }
  
  // Enable or disable automatic token refresh
  set enableAutoRefresh(bool value) {
    _autoRefreshEnabled = value;
  }
  
  // Check if token is expired
  bool isTokenExpired() {
    if (_token == null) return true;
    
    try {
      return JwtDecoder.isExpired(_token!);
    } catch (e) {
      print('DEBUG: Error checking token expiration: $e');
      return true; // If we can't verify, assume it's expired
    }
  }
  
  // Check if token is expiring within threshold
  bool _isTokenExpiring() {
    if (_token == null) return true;
    
    try {
      // Get expiration time
      final expirationDate = JwtDecoder.getExpirationDate(_token!);
      final now = DateTime.now();
      
      // Calculate minutes until expiration
      final minutesUntilExpiration = expirationDate.difference(now).inMinutes;
      
      // Check if token expires within threshold
      final isExpiring = minutesUntilExpiration <= _refreshThresholdMinutes;
      
      if (isExpiring) {
        print('DEBUG: Token expires in $minutesUntilExpiration minutes, threshold is $_refreshThresholdMinutes minutes');
      }
      
      return isExpiring;
    } catch (e) {
      print('DEBUG: Error checking token expiration: $e');
      return true; // If we can't verify, assume it's expiring
    }
  }
  
  // Get the remaining time (in minutes) before token expiration
  int getTokenRemainingMinutes() {
    if (_token == null) return 0;
    
    try {
      // Get expiration time
      final expirationDate = JwtDecoder.getExpirationDate(_token!);
      final now = DateTime.now();
      
      // Calculate minutes until expiration
      return expirationDate.difference(now).inMinutes;
    } catch (e) {
      print('DEBUG: Error getting token remaining time: $e');
      return 0; // If we can't verify, assume no time left
    }
  }
  
  // Refresh the token using stored credentials
  Future<bool> _refreshToken() async {
    // If already refreshing, skip
    if (_isRefreshing) {
      print('DEBUG: Token refresh already in progress, skipping');
      return false;
    }
    
    // Check if credentials are available
    if (_lastEmail == null || _lastPassword == null) {
      print('DEBUG: Cannot refresh token - credentials not available');
      return false;
    }
    
    _isRefreshing = true;
    
    try {
      print('DEBUG: Attempting to refresh token');
      
      // Use the stored credentials to get a new token
      final response = await login(_lastEmail!, _lastPassword!);
      
      if (response.containsKey('access_token')) {
        print('DEBUG: Token refreshed successfully');
        _isRefreshing = false;
        return true;
      } else {
        print('DEBUG: Token refresh failed - invalid response');
        _isRefreshing = false;
        return false;
      }
    } catch (e) {
      print('DEBUG: Error refreshing token: $e');
      _isRefreshing = false;
      return false;
    }
  }
  
  // Attempt to refresh token if needed
  Future<bool> refreshTokenIfNeeded() async {
    // Skip if auto-refresh is disabled
    if (!_autoRefreshEnabled) return false;
    
    // Check if token is expiring soon
    if (_isTokenExpiring()) {
      return await _refreshToken();
    }
    
    return false;
  }
  
  // Get headers with auth token for external use
  Map<String, String> getAuthHeaders() {
    final headers = <String, String>{};
    
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    
    return headers;
  }
  
  // Parse JSON response for external use
  dynamic parseJsonResponse(String body) {
    if (body.isEmpty) return {};
    return jsonDecode(body);
  }

  // Login function
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      // The FastAPI OAuth2 endpoint expects form data, not JSON
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.authLogin}'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'username': email, // OAuth2 uses 'username', but we're passing the email
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          if (data['access_token'] == null) {
            throw AuthException('Invalid response format: missing access_token',
                statusCode: response.statusCode, responseBody: response.body);
          }
          
          // Save token
          _token = data['access_token'];

          // Extract org_id from JWT token
          _extractOrgIdFromToken(_token!);

          // Store credentials for auto-refresh
          _lastEmail = email;
          _lastPassword = password;

          // Save everything to storage
          _saveAuthDataToStorage(
            token: _token,
            email: email,
            password: password,
          );
          
          // Log token expiration details if parsing is successful
          try {
            if (_token != null) {
              final expirationDate = JwtDecoder.getExpirationDate(_token!);
              final now = DateTime.now();
              final minutesUntilExpiration = expirationDate.difference(now).inMinutes;
              print('DEBUG: Token will expire in $minutesUntilExpiration minutes (${expirationDate.toIso8601String()})');
            }
          } catch (e) {
            print('DEBUG: Could not parse token expiration: $e');
          }
          
          return data;
        } catch (e) {
          if (e is AuthException) rethrow;
          throw AuthException('Invalid response format: ${e.toString()}',
              statusCode: response.statusCode, responseBody: response.body);
        }
      } else if (response.statusCode == 401) {
        throw AuthException('Invalid email or password',
            statusCode: response.statusCode, responseBody: response.body);
      } else if (response.statusCode == 404) {
        throw AuthException('Authentication endpoint not found. Please check server configuration.',
            statusCode: response.statusCode, responseBody: response.body);
      } else if (response.statusCode >= 500) {
        throw AuthException('Server error. Please try again later.',
            statusCode: response.statusCode, responseBody: response.body);
      } else {
        print('Login failed with status: ${response.statusCode}, body: ${response.body}');
        throw AuthException('Authentication failed: ${response.statusCode}',
            statusCode: response.statusCode, responseBody: response.body);
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      if (e is SocketException) {
        throw AuthException(ApiConfig.connectionError);
      }
      print('Login error: $e');
      throw AuthException('Login error: ${e.toString()}');
    }
  }

  // GET request
  Future<dynamic> get(String endpoint) async {
    try {
      // Check if token is expiring and refresh if needed
      if (_autoRefreshEnabled && _isTokenExpiring()) {
        await _refreshToken();
      }
      
      final url = Uri.parse('${ApiConfig.baseUrl}$endpoint');
      final headers = _getHeaders();
      
      print('DEBUG: API GET request to $url');
      print('DEBUG: Headers: $headers');
      
      final response = await http.get(url, headers: headers);
      
      print('DEBUG: Response status: ${response.statusCode}');
      print('DEBUG: Response body: ${response.body}');
      
      // Handle redirect (307) manually
      if (response.statusCode == 307 || response.statusCode == 301 || response.statusCode == 302 || response.statusCode == 303) {
        final redirectUrl = response.headers['location'];
        print('DEBUG: Redirecting to: $redirectUrl');
        
        if (redirectUrl != null) {
          final redirectResponse = await http.get(
            Uri.parse(redirectUrl),
            headers: headers,
          );
          
          print('DEBUG: Redirect response status: ${redirectResponse.statusCode}');
          print('DEBUG: Redirect response body: ${redirectResponse.body}');
          
          return _handleResponse(redirectResponse);
        }
      }
      
      // If unauthorized and we have credentials, try to refresh and retry
      if (response.statusCode == 401 && _autoRefreshEnabled && _lastEmail != null && _lastPassword != null) {
        print('DEBUG: Received 401, attempting to refresh token and retry');
        if (await _refreshToken()) {
          // Retry the request with the new token
          final newHeaders = _getHeaders();
          final retryResponse = await http.get(url, headers: newHeaders);
          return _handleResponse(retryResponse);
        }
      }

      return _handleResponse(response);
    } catch (e) {
      print('DEBUG: GET request error: $e');
      _handleError(e);
    }
  }

  // POST request
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    try {
      // Check if token is expiring and refresh if needed
      if (_autoRefreshEnabled && _isTokenExpiring()) {
        await _refreshToken();
      }
      
      final url = Uri.parse('${ApiConfig.baseUrl}$endpoint');
      final headers = _getHeaders();
      final body = jsonEncode(data);
      
      print('DEBUG: API POST request to $url');
      print('DEBUG: Headers: $headers');
      print('DEBUG: Body: $body');
      
      final response = await http.post(
        url,
        headers: headers,
        body: body,
      );
      
      print('DEBUG: Response status: ${response.statusCode}');
      print('DEBUG: Response body: ${response.body}');
      
      // Handle redirect (307) manually
      if (response.statusCode == 307 || response.statusCode == 301 || response.statusCode == 302 || response.statusCode == 303) {
        final redirectUrl = response.headers['location'];
        print('DEBUG: Redirecting to: $redirectUrl');
        
        if (redirectUrl != null) {
          final redirectResponse = await http.post(
            Uri.parse(redirectUrl),
            headers: headers,
            body: body,
          );
          
          print('DEBUG: Redirect response status: ${redirectResponse.statusCode}');
          print('DEBUG: Redirect response body: ${redirectResponse.body}');
          
          return _handleResponse(redirectResponse);
        }
      }
      
      // If unauthorized and we have credentials, try to refresh and retry
      if (response.statusCode == 401 && _autoRefreshEnabled && _lastEmail != null && _lastPassword != null) {
        print('DEBUG: Received 401, attempting to refresh token and retry');
        if (await _refreshToken()) {
          // Retry the request with the new token
          final newHeaders = _getHeaders();
          final retryResponse = await http.post(
            url,
            headers: newHeaders,
            body: body,
          );
          return _handleResponse(retryResponse);
        }
      }

      return _handleResponse(response);
    } catch (e) {
      print('DEBUG: POST request error: $e');
      _handleError(e);
    }
  }

  // PUT request
  Future<dynamic> put(String endpoint, Map<String, dynamic> data) async {
    try {
      // Check if token is expiring and refresh if needed
      if (_autoRefreshEnabled && _isTokenExpiring()) {
        await _refreshToken();
      }
      
      final url = Uri.parse('${ApiConfig.baseUrl}$endpoint');
      final headers = _getHeaders();
      final body = jsonEncode(data);
      
      print('DEBUG: API PUT request to $url');
      print('DEBUG: Headers: $headers');
      print('DEBUG: Body: $body');
      
      final response = await http.put(
        url,
        headers: headers,
        body: body,
      );
      
      print('DEBUG: Response status: ${response.statusCode}');
      print('DEBUG: Response body: ${response.body}');
      
      // Handle redirect (307) manually
      if (response.statusCode == 307 || response.statusCode == 301 || response.statusCode == 302 || response.statusCode == 303) {
        final redirectUrl = response.headers['location'];
        print('DEBUG: Redirecting to: $redirectUrl');
        
        if (redirectUrl != null) {
          final redirectResponse = await http.put(
            Uri.parse(redirectUrl),
            headers: headers,
            body: body,
          );
          
          print('DEBUG: Redirect response status: ${redirectResponse.statusCode}');
          print('DEBUG: Redirect response body: ${redirectResponse.body}');
          
          return _handleResponse(redirectResponse);
        }
      }
      
      // If unauthorized and we have credentials, try to refresh and retry
      if (response.statusCode == 401 && _autoRefreshEnabled && _lastEmail != null && _lastPassword != null) {
        print('DEBUG: Received 401, attempting to refresh token and retry');
        if (await _refreshToken()) {
          // Retry the request with the new token
          final newHeaders = _getHeaders();
          final retryResponse = await http.put(
            url,
            headers: newHeaders,
            body: body,
          );
          return _handleResponse(retryResponse);
        }
      }

      return _handleResponse(response);
    } catch (e) {
      print('DEBUG: PUT request error: $e');
      _handleError(e);
    }
  }

  // DELETE request
  Future<dynamic> delete(String endpoint) async {
    try {
      // Check if token is expiring and refresh if needed
      if (_autoRefreshEnabled && _isTokenExpiring()) {
        await _refreshToken();
      }
      
      final url = Uri.parse('${ApiConfig.baseUrl}$endpoint');
      final headers = _getHeaders();
      
      print('DEBUG: API DELETE request to $url');
      print('DEBUG: Headers: $headers');
      
      final response = await http.delete(
        url,
        headers: headers,
      );
      
      print('DEBUG: Response status: ${response.statusCode}');
      print('DEBUG: Response body: ${response.body}');
      
      // Handle redirect (307) manually
      if (response.statusCode == 307 || response.statusCode == 301 || response.statusCode == 302 || response.statusCode == 303) {
        final redirectUrl = response.headers['location'];
        print('DEBUG: Redirecting to: $redirectUrl');
        
        if (redirectUrl != null) {
          final redirectResponse = await http.delete(
            Uri.parse(redirectUrl),
            headers: headers,
          );
          
          print('DEBUG: Redirect response status: ${redirectResponse.statusCode}');
          print('DEBUG: Redirect response body: ${redirectResponse.body}');
          
          return _handleResponse(redirectResponse);
        }
      }
      
      // If unauthorized and we have credentials, try to refresh and retry
      if (response.statusCode == 401 && _autoRefreshEnabled && _lastEmail != null && _lastPassword != null) {
        print('DEBUG: Received 401, attempting to refresh token and retry');
        if (await _refreshToken()) {
          // Retry the request with the new token
          final newHeaders = _getHeaders();
          final retryResponse = await http.delete(
            url,
            headers: newHeaders,
          );
          return _handleResponse(retryResponse);
        }
      }

      return _handleResponse(response);
    } catch (e) {
      print('DEBUG: DELETE request error: $e');
      _handleError(e);
    }
  }

  // Response handler
  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body);
    } else if (response.statusCode == 401) {
      // If token refresh is enabled and we already attempted refresh,
      // we should not clear the token, as the request might have failed for other reasons
      if (!_isRefreshing) {
        print('DEBUG: Unauthorized response but not during refresh, clearing token');
        _token = null;
      }
      throw HttpException(ApiConfig.unauthorizedError);
    } else if (response.statusCode == 404) {
      // Not found - indicate this specifically to allow for create fallback
      throw HttpException('Resource not found: 404');
    } else if (response.statusCode == 409) {
      // Conflict - usually means the resource already exists
      throw HttpException('Resource conflict (already exists): 409 - ${response.body}');
    } else if (response.statusCode >= 500) {
      // Server error
      throw HttpException('Server error: ${response.statusCode} - ${response.body}');
    } else {
      // Other client errors
      throw HttpException('Request failed with status: ${response.statusCode} - ${response.body}');
    }
  }

  // Error handler
  void _handleError(dynamic error) {
    if (error is SocketException) {
      throw HttpException(ApiConfig.connectionError);
    } else {
      throw error;
    }
  }

  // Get headers with auth token if available
  Map<String, String> _getHeaders() {
    final headers = {
      'Content-Type': 'application/json',
    };

    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
      print('DEBUG: Using auth token: ${_token?.substring(0, 15)}...');
    } else {
      print('DEBUG: No auth token available');
    }

    return headers;
  }
}