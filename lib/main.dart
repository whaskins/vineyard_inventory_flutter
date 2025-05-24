import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'services/repository.dart';
import 'package:http/http.dart' as http;
import 'config/api_config.dart';
import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize for web if needed
  if (kIsWeb) {
    // Initialize FFI for web support
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  // Set preferred orientations (skip on web)
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  
  // Test API endpoints 
  await _testApiEndpoints();
  
  // Initialize the repository (handles both local and API data)
  await Repository().initialize();
  
  runApp(const MyApp());
}

// Function to test API endpoints directly
Future<void> _testApiEndpoints() async {
  try {
    print('DEBUG: Testing API connectivity to ${ApiConfig.baseUrl}');
    
    // Test health endpoint (common in FastAPI apps)
    try {
      final healthResponse = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/health'),
        headers: {'Content-Type': 'application/json'}
      ).timeout(const Duration(seconds: 5));
      print('DEBUG: Health endpoint status: ${healthResponse.statusCode}');
      print('DEBUG: Health endpoint response: ${healthResponse.body}');
    } catch (e) {
      print('DEBUG: Health endpoint not available: $e');
    }
    
    // Test OpenAPI documentation
    try {
      final docsResponse = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/docs'),
        headers: {'Content-Type': 'application/json'}
      ).timeout(const Duration(seconds: 5));
      print('DEBUG: API docs status: ${docsResponse.statusCode}');
    } catch (e) {
      print('DEBUG: API docs not available: $e');
    }
    
    // Test vines endpoint (requires auth)
    try {
      final vinesResponse = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.vines}'),
        headers: {'Content-Type': 'application/json'}
      ).timeout(const Duration(seconds: 5));
      print('DEBUG: Vines endpoint status: ${vinesResponse.statusCode}');
      if (vinesResponse.statusCode >= 200 && vinesResponse.statusCode < 300) {
        print('DEBUG: Vines endpoint response: ${vinesResponse.body}');
      }
    } catch (e) {
      print('DEBUG: Vines endpoint error: $e');
    }
    
    // Try a direct test POST to the vines endpoint (will fail without auth, but good to try)
    try {
      print('DEBUG: Testing direct POST to vines endpoint');
      final sampleVine = {
        'alpha_numeric_id': 'TEST-${DateTime.now().millisecondsSinceEpoch}',
        'year_of_planting': 2023,
        'nursery': 'Test Nursery',
        'variety': 'Test Variety',
        'rootstock': 'Test Rootstock',
        'vineyard_name': 'Test Vineyard',
        'field_name': 'Test Field',
        'row_number': 1,
        'spot_number': 1,
        'is_dead': false
      };
      
      final postResponse = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.vines}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(sampleVine)
      ).timeout(const Duration(seconds: 10));
      
      print('DEBUG: Direct POST status: ${postResponse.statusCode}');
      print('DEBUG: Direct POST response: ${postResponse.body}');
    } catch (e) {
      print('DEBUG: Direct POST error: $e');
    }
    
  } catch (e) {
    print('DEBUG: API connectivity test failed: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = Repository();
    final isAuthenticated = repository.isAuthenticated;
    final initialScreen = isAuthenticated ? const HomeScreen() : const LoginScreen();
    
    return MaterialApp(
      title: 'Vineyard Inventory',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green[700] ?? Colors.green,
          primary: Colors.green[700] ?? Colors.green,
        ),
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.green[700],
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      home: initialScreen,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        FormBuilderLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', ''),
      ],
    );
  }
}