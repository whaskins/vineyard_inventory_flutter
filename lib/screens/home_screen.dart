import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import '../models/vine.dart';
import '../services/repository.dart';
import '../services/api/auth_service.dart';
import 'qr_scanner_screen.dart';
import 'vine_detail_screen.dart';
import 'row_scan_screen.dart';
import 'login_screen.dart';
import 'inventory/inventory_overview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repository = Repository();
  final _authService = AuthService();
  bool _isLoading = true;
  bool _isOnline = false;
  bool _isLoggedIn = false;
  List<Vine> _recentVines = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    debugPrint('Home screen initialized');
    _checkConnectionStatus();
    _loadRecentVines();
  }

  void _checkConnectionStatus() {
    setState(() {
      _isOnline = _repository.isOnline;
      _isLoggedIn = _authService.isAuthenticated();
    });
  }
  
  // Refresh only local vines (used after background sync completes)
  Future<void> _refreshLocalVinesOnly() async {
    try {
      final vines = await _repository.getLocalVines();
      debugPrint('Refreshed ${vines.length} local vines after background sync');
      
      if (mounted) {
        setState(() {
          _recentVines = vines.take(10).toList();
        });
      }
    } catch (e) {
      debugPrint('Error refreshing local vines: $e');
    }
  }

  Future<void> _loadRecentVines({bool forceRefresh = false}) async {
    debugPrint('Loading recent vines on home screen');
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check connection status first
      _checkConnectionStatus();
      
      // If forcing refresh and we're online, sync with server first
      if (forceRefresh && _isOnline && _isLoggedIn) {
        debugPrint('Forcing refresh from server');
        try {
          // First sync any local changes to API
          final syncCount = await _repository.syncLocalVinesToAPI();
          debugPrint('Synced $syncCount vines to server');
          
          // Show a brief message that data is refreshing
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Refreshing data from server...'))
            );
          }
        } catch (e) {
          debugPrint('Error syncing with server: $e');
        }
      }
      
      // Get local vines immediately for UI
      final localVines = await _repository.getLocalVines();
      debugPrint('Home screen received ${localVines.length} local vines');
      
      // Start background sync if online (don't await - let it run independently)
      if (_isOnline && _isLoggedIn) {
        debugPrint('Starting background vine sync');
        _repository.startBackgroundVineSync().then((_) {
          debugPrint('Background vine sync completed');
          // Refresh UI after sync completes (only if still on this screen)
          if (mounted) {
            _refreshLocalVinesOnly();
          }
        }).catchError((error) {
          debugPrint('Background vine sync error: $error');
        });
      }
      
      final vines = localVines;
      
      // Log the vines for debugging (sample vines only)
      final sampleVines = vines.take(3).toList();
      for (var vine in sampleVines) {
        debugPrint('Sample vine: ID=${vine.id}, AlphaID=${vine.alphaNumericID}, Field=${vine.fieldName}, Row=${vine.rowNumber}, Spot=${vine.spotNumber}');
      }
      
      vines.sort((a, b) => b.recordCreated.compareTo(a.recordCreated));
      debugPrint('Vines sorted by record creation date');
      
      setState(() {
        // Take the 10 most recent vines
        _recentVines = vines.take(10).toList();
        debugPrint('_recentVines list has ${_recentVines.length} items');
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Error loading recent vines: $e');
      debugPrint('Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Error loading recent vines: $e';
        _isLoading = false;
      });
    }
  }

  void _navigateToScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const QrScannerScreen(),
      ),
    ).then((_) {
      // Refresh recent vines when returning from scanner
      _loadRecentVines();
    });
  }
  
  void _navigateToRowScanMode() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const RowScanScreen(),
      ),
    ).then((_) {
      // Refresh recent vines when returning from row scan mode
      _loadRecentVines();
    });
  }
  
  void _navigateToInventoryOverview() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const InventoryOverviewScreen(),
      ),
    ).then((_) {
      // Refresh recent vines when returning from inventory overview
      _loadRecentVines();
    });
  }
  

  void _navigateToVineDetail(String vineId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VineDetailScreen(vineId: vineId),
      ),
    ).then((_) {
      // Refresh recent vines when returning from detail
      _loadRecentVines();
    });
  }
  
  void _logout() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _repository.logout();
                
                // Navigate to login screen
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              },
              child: const Text('LOGOUT'),
            ),
          ],
        );
      },
    );
  }
  
  void _navigateToLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const LoginScreen(),
      ),
    ).then((_) {
      // Refresh status and vines when returning from login screen
      _checkConnectionStatus();
      _loadRecentVines();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vineyard Inventory'),
        centerTitle: true,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          // Sync button
          if (_isLoggedIn && _isOnline)
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Sync with server',
              onPressed: () async {
                // Show a progress indicator
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Syncing with server...'))
                );
                
                try {
                  // First sync local data to API
                  final syncCount = await _repository.syncLocalVinesToAPI();
                  
                  // Then reload to get the latest data
                  await _loadRecentVines();
                  
                  // Show success message
                  if (syncCount > 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Successfully synced $syncCount vines with server'))
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('All vines are already synced with server'))
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error syncing: $e'))
                  );
                }
              },
            ),
          // Logout or Login button
          _isLoggedIn
              ? IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: _logout,
                )
              : IconButton(
                  icon: const Icon(Icons.login),
                  tooltip: 'Login',
                  onPressed: _navigateToLogin,
                ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadRecentVines,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadRecentVines(forceRefresh: true),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Recently Scanned Vines',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: () => _loadRecentVines(forceRefresh: true),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Refresh'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _isOnline ? Colors.green[100] : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _isOnline ? Icons.cloud_done : Icons.cloud_off,
                                        size: 16,
                                        color: _isOnline ? Colors.green[700] : Colors.grey[700],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _isOnline ? 'Online' : 'Offline',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _isOnline ? Colors.green[700] : Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _isLoggedIn ? Colors.blue[100] : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _isLoggedIn ? Icons.login : Icons.logout,
                                        size: 16,
                                        color: _isLoggedIn ? Colors.blue[700] : Colors.grey[700],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _isLoggedIn ? 'Logged In' : 'Not Logged In',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _isLoggedIn ? Colors.blue[700] : Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Login banner for non-empty vines list
                      if (!_isLoggedIn && _recentVines.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: Colors.blue),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text(
                                      'Not logged in',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Log in to sync your data with the server and access more features.',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: _navigateToLogin,
                                style: TextButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                ),
                                child: const Text(
                                  'LOGIN',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: _recentVines.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      'No vines scanned yet. Start by scanning a QR code.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    // Show login button if not logged in
                                    if (!_isLoggedIn) ...[
                                      const SizedBox(height: 24),
                                      const Text(
                                        'Login to sync your data with the server',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontStyle: FontStyle.italic,
                                          color: Colors.blue,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        onPressed: _navigateToLogin,
                                        icon: const Icon(Icons.login),
                                        label: const Text('Login'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: _recentVines.length,
                                itemBuilder: (context, index) {
                                  final vine = _recentVines[index];
                                  return Card(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 16.0,
                                      vertical: 4.0,
                                    ),
                                    child: ListTile(
                                      title: Text(vine.hasTag ? vine.alphaNumericID! : 'No Tag'),
                                      subtitle: Text(
                                        [
                                          vine.variety ?? 'Unknown Variety',
                                          vine.fieldName != null ? 'Field: ${vine.fieldName}' : null,
                                          vine.rowNumber != null && vine.spotNumber != null
                                              ? 'Position: ${vine.rowNumber}-${vine.spotNumber}'
                                              : null,
                                        ].where((s) => s != null).join(' • '),
                                      ),
                                      leading: CircleAvatar(
                                        backgroundColor: vine.isDead
                                            ? Colors.red[100]
                                            : Colors.green[100],
                                        child: Icon(
                                          vine.isDead ? Icons.close : Icons.eco,
                                          color: vine.isDead ? Colors.red : Colors.green,
                                        ),
                                      ),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () =>
                                          _navigateToVineDetail(vine.uniqueIdentifier),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            onPressed: _navigateToInventoryOverview,
            icon: const Icon(Icons.dashboard),
            label: const Text('View Inventory'),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            heroTag: 'inventory',
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            onPressed: _navigateToRowScanMode,
            icon: const Icon(Icons.format_list_numbered),
            label: const Text('Row Scan Mode'),
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            heroTag: 'rowScan',
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            onPressed: _navigateToScanner,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Single Scan'),
            backgroundColor: Theme.of(context).primaryColor, 
            foregroundColor: Colors.white,
            heroTag: 'singleScan',
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}