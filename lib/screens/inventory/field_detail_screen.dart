import 'package:flutter/material.dart';
import '../../models/vine.dart';
import '../../services/inventory_service.dart';
import '../../services/repository.dart';
import '../vine_detail_screen.dart';

class FieldDetailScreen extends StatefulWidget {
  final String vineyardName;
  final String fieldName;

  const FieldDetailScreen({
    Key? key,
    required this.vineyardName,
    required this.fieldName,
  }) : super(key: key);

  @override
  _FieldDetailScreenState createState() => _FieldDetailScreenState();
}

class _FieldDetailScreenState extends State<FieldDetailScreen> {
  final InventoryService _inventoryService = InventoryService();
  final Repository _repository = Repository();
  
  bool _isLoading = true;
  List<String> _rows = [];
  Map<String, List<Vine>> _rowVines = {};
  Map<String, int> _varietyCounts = {};
  int _totalVines = 0;
  int _liveVines = 0;
  int _deadVines = 0;

  @override
  void initState() {
    super.initState();
    _loadFieldData();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when the screen is shown again
    _loadFieldData();
  }

  Future<void> _loadFieldData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get all vines directly from repository
      final allVines = await _repository.getAllVines();
      
      // Filter vines for this field
      final fieldVines = allVines.where((v) => 
          v.vineyardName == widget.vineyardName && 
          v.fieldName == widget.fieldName).toList();
      
      // Extract unique row numbers
      final Set<int> rowSet = {};
      for (var vine in fieldVines) {
        if (vine.rowNumber != null) {
          rowSet.add(vine.rowNumber!);
        }
      }
      
      // Convert row numbers to strings and sort naturally
      _rows = rowSet.map((r) => r.toString()).toList();
      _rows.sort((a, b) {
        try {
          return int.parse(a).compareTo(int.parse(b));
        } catch (e) {
          return a.compareTo(b);
        }
      });

      // Group vines by row
      _rowVines = {};
      _varietyCounts = {};
      _totalVines = 0;
      _liveVines = 0;
      _deadVines = 0;

      for (String row in _rows) {
        try {
          final rowNum = int.parse(row);
          final vines = fieldVines.where((v) => v.rowNumber == rowNum).toList();
          
          // Sort by spot number
          vines.sort((a, b) => (a.spotNumber ?? 0).compareTo(b.spotNumber ?? 0));
          
          _rowVines[row] = vines;
          _totalVines += vines.length;
          
          for (var vine in vines) {
            // Count by variety - handle null/empty values
            if (vine.variety != null && vine.variety!.trim().isNotEmpty) {
              final variety = vine.variety!.trim();
              _varietyCounts[variety] = (_varietyCounts[variety] ?? 0) + 1;
            } else {
              // Only add unknown if variety is null or empty
              _varietyCounts['Unknown'] = (_varietyCounts['Unknown'] ?? 0) + 1;
            }
            
            // Count by health status
            if (vine.isDead) {
              _deadVines++;
            } else {
              _liveVines++;
            }
          }
        } catch (e) {
          print('Error processing row $row: $e');
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading field data: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.vineyardName} - ${widget.fieldName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              if (_repository.isOnline && _repository.isAuthenticated) {
                // Show a loading indicator
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Refreshing data from server...'))
                );
                
                // Do a full refresh from API
                await _inventoryService.refreshFromAPI();
                
                // Then reload field data from local database
                _loadFieldData();
              } else {
                // Just reload from local database
                _loadFieldData();
              }
            },
            tooltip: 'Refresh from API',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatisticsCard(),
            const SizedBox(height: 16),
            _buildVarietyBreakdown(),
            const SizedBox(height: 16),
            _buildRowsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Field Statistics',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            _buildStatRow('Total Vines', _totalVines.toString()),
            _buildStatRow('Number of Rows', _rows.length.toString()),
            _buildStatRow('Varieties', _varietyCounts.length.toString()),
            _buildStatRow('Live Vines', '$_liveVines (${_totalVines > 0 ? (_liveVines * 100 / _totalVines).toStringAsFixed(1) : 0}%)'),
            _buildStatRow('Dead Vines', '$_deadVines (${_totalVines > 0 ? (_deadVines * 100 / _totalVines).toStringAsFixed(1) : 0}%)'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(value),
        ],
      ),
    );
  }

  Widget _buildVarietyBreakdown() {
    final sortedVarieties = _varietyCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Varieties',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            ...sortedVarieties.map((entry) {
              final percentage = _totalVines > 0
                  ? (entry.value * 100 / _totalVines).toStringAsFixed(1)
                  : '0';
              
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(entry.key),
                    Text('${entry.value} ($percentage%)'),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildRowsList() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rows',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            ..._rows.map((row) => _buildRowTile(row)),
          ],
        ),
      ),
    );
  }

  Widget _buildRowTile(String row) {
    final vines = _rowVines[row] ?? [];
    final deadCount = vines.where((v) => v.isDead).length;
    final liveCount = vines.length - deadCount;
    final unknownCount = 0; // With isDead property, there are no unknown health states
    
    // Get varieties in this row
    final Map<String, int> rowVarieties = {};
    for (var vine in vines) {
      if (vine.variety != null && vine.variety!.trim().isNotEmpty) {
        final variety = vine.variety!.trim();
        rowVarieties[variety] = (rowVarieties[variety] ?? 0) + 1;
      } else {
        rowVarieties['Unknown'] = (rowVarieties['Unknown'] ?? 0) + 1;
      }
    }
    
    // Get top 3 varieties
    final sortedRowVarieties = rowVarieties.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topVarieties = sortedRowVarieties.take(3).map((e) => e.key).join(', ');
    
    return ListTile(
      title: Text('Row $row'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$liveCount live, $deadCount dead'),
          if (topVarieties.isNotEmpty)
            Text(
              'Varieties: $topVarieties${sortedRowVarieties.length > 3 ? " + ${sortedRowVarieties.length - 3} more" : ""}',
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
      trailing: Text(
        '${vines.length} vines',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      onTap: () => _showRowDetails(row, vines),
    );
  }

  void _showRowDetails(String row, List<Vine> vines) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Row $row',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                Text('${vines.length} vines found'),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: vines.length,
                    itemBuilder: (context, index) {
                      final vine = vines[index];
                      return ListTile(
                        title: Text(
                          'Vine ${vine.spotNumber ?? 'Unknown Position'}',
                          style: TextStyle(
                            color: vine.isDead
                                ? Colors.red
                                : Colors.green.shade700,
                          ),
                        ),
                        subtitle: Text(
                          'Variety: ${(vine.variety != null && vine.variety!.trim().isNotEmpty) ? vine.variety!.trim() : 'Unknown'}, ' +
                          'Status: ${vine.isDead ? 'Dead' : 'Live'}',
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => VineDetailScreen(vineId: vine.uniqueIdentifier),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}