import 'package:flutter/material.dart';
import '../../services/inventory_service.dart';
import 'field_detail_screen.dart';

class VineyardListScreen extends StatefulWidget {
  final String? initialVineyard;
  
  const VineyardListScreen({super.key, this.initialVineyard});

  @override
  State<VineyardListScreen> createState() => _VineyardListScreenState();
}

class _VineyardListScreenState extends State<VineyardListScreen> {
  final InventoryService _inventoryService = InventoryService();
  bool _isLoading = true;
  Map<String, int> _vineyardCounts = {};
  List<String> _vineyards = [];
  Map<String, Map<String, int>> _vineyardFields = {};
  String? _selectedVineyard;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedVineyard = widget.initialVineyard;
    _loadVineyardData();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when the screen is shown again
    _loadVineyardData();
  }

  Future<void> _loadVineyardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Load vineyard summary
      final vineyardCounts = await _inventoryService.getVineyardSummary();
      final vineyards = vineyardCounts.keys.toList()..sort();
      
      // Load field details for each vineyard
      final Map<String, Map<String, int>> vineyardFields = {};
      
      for (var vineyard in vineyards) {
        vineyardFields[vineyard] = await _inventoryService.getFieldSummary(vineyard);
      }
      
      setState(() {
        _vineyardCounts = vineyardCounts;
        _vineyards = vineyards;
        _vineyardFields = vineyardFields;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading vineyard data: $e';
        _isLoading = false;
      });
    }
  }

  void _selectVineyard(String vineyard) {
    setState(() {
      _selectedVineyard = vineyard;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedVineyard != null 
            ? 'Vineyard: $_selectedVineyard' 
            : 'Vineyards'),
        centerTitle: true,
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadVineyardData,
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
                        onPressed: _loadVineyardData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _vineyards.isEmpty
                  ? const Center(
                      child: Text('No vineyards found in inventory'),
                    )
                  : ListView.builder(
                      itemCount: _vineyards.length,
                      padding: const EdgeInsets.all(8),
                      itemBuilder: (context, index) {
                        final vineyard = _vineyards[index];
                        final isExpanded = _selectedVineyard == vineyard;
                        final fieldCount = _vineyardFields[vineyard]?.length ?? 0;
                        final vinesCount = _vineyardCounts[vineyard] ?? 0;
                        
                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            children: [
                              // Vineyard header
                              ListTile(
                                title: Text(
                                  vineyard,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Text('$fieldCount fields, $vinesCount vines'),
                                leading: CircleAvatar(
                                  backgroundColor: Colors.green[100],
                                  child: Icon(Icons.eco, color: Colors.green[700]),
                                ),
                                trailing: Icon(
                                  isExpanded ? Icons.expand_less : Icons.expand_more,
                                ),
                                onTap: () {
                                  setState(() {
                                    if (isExpanded) {
                                      _selectedVineyard = null;
                                    } else {
                                      _selectedVineyard = vineyard;
                                    }
                                  });
                                },
                              ),
                              
                              // Fields (if expanded)
                              if (isExpanded)
                                _buildFieldsList(vineyard),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _buildFieldsList(String vineyard) {
    final fields = _vineyardFields[vineyard]?.entries.toList() ?? [];
    fields.sort((a, b) => a.key.compareTo(b.key)); // Sort fields alphabetically
    
    if (fields.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('No fields found in this vineyard'),
      );
    }
    
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          const Divider(height: 1),
          ...fields.map((field) => Column(
            children: [
              ListTile(
                title: Text(field.key),
                subtitle: Text('${field.value} vines'),
                leading: Icon(Icons.grid_on, color: Colors.green[700]),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FieldDetailScreen(
                        vineyardName: vineyard,
                        fieldName: field.key,
                      ),
                    ),
                  ).then((_) => _loadVineyardData());
                },
              ),
              const Divider(height: 1),
            ],
          )),
        ],
      ),
    );
  }
}