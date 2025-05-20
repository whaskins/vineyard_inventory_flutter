import 'package:flutter/material.dart';
import '../../models/vine.dart';
import '../../services/inventory_service.dart';
import '../../services/repository.dart';
import '../vine_detail_screen.dart';

class VarietyListScreen extends StatefulWidget {
  final String? initialVariety;
  
  const VarietyListScreen({super.key, this.initialVariety});

  @override
  State<VarietyListScreen> createState() => _VarietyListScreenState();
}

class _VarietyListScreenState extends State<VarietyListScreen> {
  final InventoryService _inventoryService = InventoryService();
  final Repository _repository = Repository();
  bool _isLoading = true;
  Map<String, int> _varietyCounts = {};
  List<Vine> _vines = [];
  String? _selectedVariety;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedVariety = widget.initialVariety;
    _loadVarietyData();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when the screen is shown again
    _loadVarietyData();
  }

  Future<void> _loadVarietyData({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Only force refresh when explicitly requested (like when refresh button is clicked)
      if (forceRefresh && _repository.isOnline && _repository.isAuthenticated) {
        await _inventoryService.refreshFromAPI();
      }
      
      // Load all vines directly from the repository
      final allVines = await _repository.getAllVines();
      
      // Calculate variety statistics directly from the vines
      Map<String, int> varietyCounts = {};
      
      print('DEBUG: Calculating variety counts from ${allVines.length} vines');
      
      // Count vines by variety, handling null and empty strings
      for (var vine in allVines) {
        if (vine.variety != null && vine.variety!.trim().isNotEmpty) {
          final variety = vine.variety!.trim();
          varietyCounts[variety] = (varietyCounts[variety] ?? 0) + 1;
        } else {
          varietyCounts['Unknown'] = (varietyCounts['Unknown'] ?? 0) + 1;
        }
      }
      
      print('DEBUG: Found ${varietyCounts.length} varieties: ${varietyCounts.keys.join(', ')}');
      
      setState(() {
        _varietyCounts = varietyCounts;
        
        // If a variety is selected, filter vines
        if (_selectedVariety != null) {
          if (_selectedVariety == 'Unknown') {
            // Handle "Unknown" variety case specially
            _vines = allVines
                .where((v) => v.variety == null || v.variety!.trim().isEmpty)
                .toList();
          } else {
            // Normal variety filtering - use exact match on trimmed value
            _vines = allVines
                .where((v) => v.variety != null && v.variety!.trim() == _selectedVariety)
                .toList();
          }
          
          // Sort by vineyard, field, row, spot
          _vines.sort((a, b) {
            // First by vineyard name
            final vineyardCompare = (a.vineyardName ?? '')
                .compareTo(b.vineyardName ?? '');
            if (vineyardCompare != 0) return vineyardCompare;
            
            // Then by field name
            final fieldCompare = (a.fieldName ?? '')
                .compareTo(b.fieldName ?? '');
            if (fieldCompare != 0) return fieldCompare;
            
            // Then by row number
            final rowCompare = (a.rowNumber ?? 0)
                .compareTo(b.rowNumber ?? 0);
            if (rowCompare != 0) return rowCompare;
            
            // Finally by spot number
            return (a.spotNumber ?? 0).compareTo(b.spotNumber ?? 0);
          });
          
          print('DEBUG: Found ${_vines.length} vines for variety "$_selectedVariety"');
          
          // Log sample vines for debugging
          if (_vines.isNotEmpty && _vines.length <= 5) {
            for (var vine in _vines) {
              print('DEBUG: Variety "$_selectedVariety" vine: ${vine.alphaNumericID}, '
                  'actual variety: "${vine.variety ?? 'null'}"');
            }
          } else if (_vines.isNotEmpty) {
            for (var vine in _vines.take(5)) {
              print('DEBUG: Variety "$_selectedVariety" sample vine: ${vine.alphaNumericID}, '
                  'actual variety: "${vine.variety ?? 'null'}"');
            }
          }
        } else {
          _vines = [];
        }
        
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading variety data: $e';
        _isLoading = false;
      });
    }
  }

  void _selectVariety(String variety) {
    setState(() {
      _selectedVariety = variety;
    });
    _loadVarietyData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedVariety != null 
            ? 'Variety: $_selectedVariety' 
            : 'Varieties'),
        centerTitle: true,
        backgroundColor: Colors.purple[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh from API',
            onPressed: () => _loadVarietyData(forceRefresh: true),
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
                        onPressed: _loadVarietyData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _selectedVariety == null
                  ? _buildVarietyListView()
                  : _buildVineListView(),
    );
  }

  Widget _buildVarietyListView() {
    // Sort varieties by count (descending)
    final sortedVarieties = _varietyCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView.builder(
      itemCount: sortedVarieties.length,
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, index) {
        final variety = sortedVarieties[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
          child: ListTile(
            title: Text(
              variety.key,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text('${variety.value} vines'),
            leading: CircleAvatar(
              backgroundColor: Colors.purple[100],
              child: Icon(Icons.wine_bar, color: Colors.purple[700]),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _selectVariety(variety.key),
          ),
        );
      },
    );
  }

  Widget _buildVineListView() {
    if (_vines.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning, size: 48, color: Colors.orange[700]),
            const SizedBox(height: 16),
            const Text(
              'No vines found with this variety',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _selectedVariety = null;
                });
                _loadVarietyData();
              },
              child: const Text('Back to Varieties'),
            ),
          ],
        ),
      );
    }

    // Group vines by vineyard and field
    final Map<String, Map<String, List<Vine>>> groupedVines = {};
    
    for (var vine in _vines) {
      final vineyard = vine.vineyardName ?? 'Unknown';
      final field = vine.fieldName ?? 'Unknown';
      
      groupedVines[vineyard] ??= {};
      groupedVines[vineyard]![field] ??= [];
      groupedVines[vineyard]![field]!.add(vine);
    }

    // Convert to list of sections
    final sections = groupedVines.entries.toList();

    return ListView.builder(
      itemCount: sections.length,
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, vineyardIndex) {
        final vineyardEntry = sections[vineyardIndex];
        final vineyardName = vineyardEntry.key;
        final fields = vineyardEntry.value.entries.toList();
        
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Vineyard header
              Container(
                color: Colors.green[700],
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                child: Text(
                  vineyardName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              
              // Fields
              for (var fieldIndex = 0; fieldIndex < fields.length; fieldIndex++)
                _buildFieldSection(fields[fieldIndex]),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFieldSection(MapEntry<String, List<Vine>> fieldEntry) {
    final fieldName = fieldEntry.key;
    final vines = fieldEntry.value;
    
    // Group vines by row
    final Map<int, List<Vine>> rowVines = {};
    for (var vine in vines) {
      final row = vine.rowNumber ?? 0;
      rowVines[row] ??= [];
      rowVines[row]!.add(vine);
    }
    
    // Sort rows
    final rows = rowVines.keys.toList()..sort();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Field header
        Container(
          color: Colors.green[100],
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          child: Text(
            'Field: $fieldName',
            style: TextStyle(
              color: Colors.green[800],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        
        // Row summaries
        for (var row in rows)
          ListTile(
            title: Text('Row $row'),
            subtitle: Text('${rowVines[row]!.length} vines'),
            leading: Icon(Icons.format_list_numbered, color: Colors.green[700]),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // Show vines in this row
              _showVinesInRow(fieldName, row, rowVines[row]!);
            },
          ),
      ],
    );
  }

  void _showVinesInRow(String fieldName, int row, List<Vine> rowVines) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Row $row in $fieldName',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${rowVines.length} vines, variety: $_selectedVariety',
                    style: TextStyle(
                      color: Colors.grey[600],
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: rowVines.length,
                      itemBuilder: (context, index) {
                        final vine = rowVines[index];
                        return ListTile(
                          title: Text('Spot: ${vine.spotNumber ?? "Unknown"}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ID: ${vine.alphaNumericID}'),
                              if (vine.isDead)
                                Text(
                                  'Status: Dead',
                                  style: TextStyle(color: Colors.red[700]),
                                ),
                            ],
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => VineDetailScreen(
                                  vineId: vine.alphaNumericID,
                                ),
                              ),
                            ).then((_) => _loadVarietyData());
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}