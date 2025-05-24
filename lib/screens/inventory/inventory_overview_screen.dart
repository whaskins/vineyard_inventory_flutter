import 'package:flutter/material.dart';
import '../../services/inventory_service.dart';
import '../../services/repository.dart';
import 'vineyard_list_screen.dart';
import 'variety_list_screen.dart';

class InventoryOverviewScreen extends StatefulWidget {
  const InventoryOverviewScreen({super.key});

  @override
  State<InventoryOverviewScreen> createState() => _InventoryOverviewScreenState();
}

class _InventoryOverviewScreenState extends State<InventoryOverviewScreen> with SingleTickerProviderStateMixin {
  final InventoryService _inventoryService = InventoryService();
  final Repository _repository = Repository();
  late TabController _tabController;
  bool _isLoading = true;
  int _totalVines = 0;
  Map<String, int> _varietyCounts = {};
  Map<String, int> _vineyardCounts = {};
  Map<String, int> _healthCounts = {};
  List<Map<String, dynamic>> _untaggedVines = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Load data on init
    _loadInventoryData();
    
    // Set up a listener for when tab changes
    _tabController.addListener(_handleTabIndexChanged);
  }
  
  void _handleTabIndexChanged() {
    // Reload data when tab changes to ensure fresh data
    if (_tabController.indexIsChanging) {
      _loadInventoryData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when the screen is shown again
    _loadInventoryData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabIndexChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInventoryData({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Force refresh from API if requested
      if (forceRefresh) {
        final refreshed = await _inventoryService.refreshFromAPI();
        if (refreshed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Data refreshed from server')),
          );
        }
      }
      
      // Load all summary data in parallel
      final results = await Future.wait([
        _inventoryService.getTotalVineCount(),
        _inventoryService.getVarietySummary(),
        _inventoryService.getVineyardSummary(),
        _inventoryService.getHealthSummary(),
        _loadUntaggedVines(),
      ]);

      setState(() {
        _totalVines = results[0] as int;
        _varietyCounts = results[1] as Map<String, int>;
        _vineyardCounts = results[2] as Map<String, int>;
        _healthCounts = results[3] as Map<String, int>;
        _untaggedVines = results[4] as List<Map<String, dynamic>>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading inventory data: $e';
        _isLoading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadUntaggedVines() async {
    try {
      // Get all vines from the repository
      final allVines = await _repository.getAllVines();
      print('DEBUG: Total vines loaded: ${allVines.length}');
      
      // Debug: Check some vine IDs to see the pattern
      if (allVines.isNotEmpty) {
        print('DEBUG: Sample vine IDs: ${allVines.take(5).map((v) => v.alphaNumericID).join(', ')}');
      }
      
      // Filter for untagged vines (those with UNTAGGED_ prefix)
      final untaggedVines = allVines
          .where((vine) => !vine.hasTag)
          .map((vine) => {
            'vineyard': vine.vineyardName ?? 'Unknown',
            'field': vine.fieldName ?? 'Unknown',
            'row': vine.rowNumber ?? 0,
            'spot': vine.spotNumber ?? 0,
            'yearPlanted': vine.yearOfPlanting ?? 0,
            'age': vine.yearOfPlanting != null ? DateTime.now().year - vine.yearOfPlanting! : 0,
          })
          .toList();
      
      print('DEBUG: Found ${untaggedVines.length} untagged vines');
      
      // Sort by vineyard, field, row, then spot
      untaggedVines.sort((a, b) {
        int vineyardCompare = (a['vineyard'] as String).compareTo(b['vineyard'] as String);
        if (vineyardCompare != 0) return vineyardCompare;
        
        int fieldCompare = (a['field'] as String).compareTo(b['field'] as String);
        if (fieldCompare != 0) return fieldCompare;
        
        int rowCompare = (a['row'] as int).compareTo(b['row'] as int);
        if (rowCompare != 0) return rowCompare;
        
        return (a['spot'] as int).compareTo(b['spot'] as int);
      });
      
      return untaggedVines;
    } catch (e) {
      print('Error loading untagged vines: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vineyard Inventory'),
        centerTitle: true,
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        actions: [
          // Sync button (if online)
          if (_repository.isOnline)
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Sync with server',
              onPressed: () async {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Syncing with server...'))
                );
                
                try {
                  await _repository.syncLocalVinesToAPI();
                  await _loadInventoryData();
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Sync completed'))
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Sync error: $e'))
                    );
                  }
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => _loadInventoryData(forceRefresh: true),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.7),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
            Tab(icon: Icon(Icons.wine_bar), text: 'By Variety'),
            Tab(icon: Icon(Icons.eco), text: 'By Vineyard'),
          ],
        ),
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
                        onPressed: _loadInventoryData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    // Overview Tab
                    _buildOverviewTab(),
                    
                    // Variety Tab
                    _buildVarietyTab(),
                    
                    // Vineyard Tab
                    _buildVineyardTab(),
                  ],
                ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total count card
          Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.eco, size: 40, color: Colors.green[700]),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Vines',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _totalVines.toString(),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Health Status
          Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Health Status',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildHealthStatusItem(
                          'Alive', 
                          _healthCounts['Alive'] ?? 0,
                          Colors.green,
                        ),
                      ),
                      Expanded(
                        child: _buildHealthStatusItem(
                          'Dead', 
                          _healthCounts['Dead'] ?? 0,
                          Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Quick stats
          Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick Stats',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickStatItem(
                          'Varieties', 
                          _varietyCounts.length, 
                          Icons.category,
                        ),
                      ),
                      Expanded(
                        child: _buildQuickStatItem(
                          'Vineyards', 
                          _vineyardCounts.length, 
                          Icons.villa,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Untagged Vines section
          if (_untaggedVines.isNotEmpty)
            Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.local_florist, color: Colors.orange[700]),
                        const SizedBox(width: 8),
                        Text(
                          'Untagged Vines (${_untaggedVines.length})',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Vines that exist but need QR tags:',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...(_untaggedVines.take(10).map((vine) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              '${vine['vineyard']} - ${vine['field']}',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Row ${vine['row']}, Spot ${vine['spot']}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              '${vine['age']}y old',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ))),
                    if (_untaggedVines.length > 10)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          '... and ${_untaggedVines.length - 10} more',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const VarietyListScreen(),
                      ),
                    ).then((_) => _loadInventoryData());
                  },
                  icon: const Icon(Icons.wine_bar),
                  label: const Text('View by Variety'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const VineyardListScreen(),
                      ),
                    ).then((_) => _loadInventoryData());
                  },
                  icon: const Icon(Icons.eco),
                  label: const Text('View by Vineyard'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVarietyTab() {
    // Sort varieties by count (descending)
    final sortedVarieties = _varietyCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView.builder(
      itemCount: sortedVarieties.length,
      itemBuilder: (context, index) {
        final variety = sortedVarieties[index];
        final percentage = (_totalVines > 0) 
            ? (variety.value / _totalVines * 100).toStringAsFixed(1) 
            : '0.0';
            
        return ListTile(
          title: Text(variety.key),
          subtitle: Text('${variety.value} vines'),
          trailing: Text('$percentage%'),
          leading: CircleAvatar(
            backgroundColor: Colors.purple[100],
            child: Icon(Icons.wine_bar, color: Colors.purple[700]),
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VarietyListScreen(
                  initialVariety: variety.key,
                ),
              ),
            ).then((_) => _loadInventoryData());
          },
        );
      },
    );
  }

  Widget _buildVineyardTab() {
    // Sort vineyards by count (descending)
    final sortedVineyards = _vineyardCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView.builder(
      itemCount: sortedVineyards.length,
      itemBuilder: (context, index) {
        final vineyard = sortedVineyards[index];
        final percentage = (_totalVines > 0) 
            ? (vineyard.value / _totalVines * 100).toStringAsFixed(1) 
            : '0.0';
            
        return ListTile(
          title: Text(vineyard.key),
          subtitle: Text('${vineyard.value} vines'),
          trailing: Text('$percentage%'),
          leading: CircleAvatar(
            backgroundColor: Colors.green[100],
            child: Icon(Icons.eco, color: Colors.green[700]),
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VineyardListScreen(
                  initialVineyard: vineyard.key,
                ),
              ),
            ).then((_) => _loadInventoryData());
          },
        );
      },
    );
  }

  Widget _buildHealthStatusItem(String label, int count, Color color) {
    final percentage = (_totalVines > 0) 
        ? (count / _totalVines * 100).toStringAsFixed(1) 
        : '0.0';
        
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.circle, color: color, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: const TextStyle(
            fontSize: 18,
          ),
        ),
        Text(
          '$percentage%',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStatItem(String label, int count, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 28, color: Colors.blue[700]),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          count.toString(),
          style: const TextStyle(
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}