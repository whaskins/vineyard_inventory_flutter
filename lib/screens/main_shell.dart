import 'package:flutter/material.dart';
import '../services/repository.dart';
import '../services/api/auth_service.dart';
import 'inventory/inventory_overview_screen.dart';
import 'scan_tab.dart';
import 'map_screen.dart';
import 'more_tab.dart';
import 'login_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _repository = Repository();
  final _authService = AuthService();

  int _currentIndex = 0;
  bool _isOnline = false;
  bool _isLoggedIn = false;
  bool _isAdmin = false;
  String? _orgName;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isOnline = _repository.isOnline;
      _isLoggedIn = _authService.isAuthenticated();
    });

    if (_isLoggedIn && _isOnline) {
      try {
        final org = await _authService.getMyOrganization();
        final user = await _authService.getCurrentUser();
        if (mounted) {
          setState(() {
            _orgName = org.name;
            _isAdmin = user.isAdmin;
          });
        }
      } catch (e) {
        debugPrint('Error loading org/user info: $e');
      }
    }
  }

  Future<void> _syncData() async {
    setState(() => _isSyncing = true);

    try {
      final syncCount = await _repository.syncWithDeltaMethod();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(syncCount > 0
                ? 'Synced $syncCount vines with server'
                : 'All vines are already synced'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _onLogout() {
    _repository.logout();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _orgName ?? 'Vineyard Inventory',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
        ),
        centerTitle: true,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/grape_leaves.jpg'),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                Colors.black38,
                BlendMode.darken,
              ),
            ),
          ),
        ),
        actions: [
          if (_isLoggedIn && _isOnline)
            IconButton(
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync),
              tooltip: 'Sync with server',
              onPressed: _isSyncing ? null : _syncData,
            ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _isOnline
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.red.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isOnline ? Icons.cloud_done : Icons.cloud_off,
                  size: 14,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  _isOnline ? 'Online' : 'Offline',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const InventoryOverviewScreen(embedded: true),
          const ScanTab(),
          const MapScreen(embedded: true),
          MoreTab(
            isLoggedIn: _isLoggedIn,
            isAdmin: _isAdmin,
            onLogout: _onLogout,
            onStatusChanged: _loadStatus,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Inventory',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
