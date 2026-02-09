class ApiConfig {
  // API base URL with port - Updated to use deployed AWS server
  // static const String baseUrl = 'http://ec2-3-94-38-168.compute-1.amazonaws.com:8080/api/v1';
  
  // Alternative URLs for testing (comment out above and uncomment one below to test)
  static const String baseUrl = 'http://amdmini01.isleta.abqwebdev.com:8080/api/v1';
  
  // API endpoints
  static const String authLogin = '/login/access-token';
  static const String register = '/users/register';
  static const String vines = '/vines';
  static const String maintenance = '/maintenance';
  static const String issues = '/issues';
  static const String organizations = '/organizations';
  
  // API request timeouts in seconds - Increased for slower connections
  static const int connectionTimeout = 30;
  static const int receiveTimeout = 30;
  
  // Error messages
  static const String connectionError = 'Connection error. Please check your internet connection.';
  static const String serverError = 'Server error. Please try again later.';
  static const String unauthorizedError = 'Unauthorized. Please login again.';
}