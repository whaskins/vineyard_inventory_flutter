import 'package:flutter/material.dart';
import '../models/vine.dart';
import '../services/repository.dart';

class _ReplacementEntry {
  final String variety;
  final String rootstock;
  int count;
  final List<String> locations; // "Vineyard > Field > Row X"

  _ReplacementEntry({
    required this.variety,
    required this.rootstock,
    required this.count,
    List<String>? locations,
  }) : locations = locations ?? [];
}

class ReplacementReportScreen extends StatefulWidget {
  const ReplacementReportScreen({super.key});

  @override
  State<ReplacementReportScreen> createState() => _ReplacementReportScreenState();
}

class _ReplacementReportScreenState extends State<ReplacementReportScreen> {
  bool _isLoading = true;
  List<_ReplacementEntry> _entries = [];
  int _totalReplacements = 0;
  int _unknownVariety = 0;

  @override
  void initState() {
    super.initState();
    _generateReport();
  }

  Future<void> _generateReport() async {
    setState(() => _isLoading = true);

    final allVines = await Repository().getLocalVines();

    // Group vines by row: "vineyard|field|row"
    final rowGroups = <String, List<Vine>>{};
    for (final vine in allVines) {
      final loc = vine.location;
      if (loc == null) continue;
      final rowKey = '${loc.vineyardName}|${loc.fieldName}|${loc.rowNumber}';
      rowGroups.putIfAbsent(rowKey, () => []).add(vine);
    }

    // For each row, find dead/empty vines and determine variety from living neighbors
    final replacements = <String, _ReplacementEntry>{};
    var unknownCount = 0;

    for (final entry in rowGroups.entries) {
      final parts = entry.key.split('|');
      final vineyardName = parts[0];
      final fieldName = parts[1];
      final rowNumber = parts[2];
      final vines = entry.value;

      // Find the predominant variety + rootstock in this row from living, tagged vines
      final livingVines = vines.where((v) => !v.isDead && v.hasTag).toList();
      final varietyCounts = <String, int>{};
      final rootstockByVariety = <String, String>{};

      for (final v in livingVines) {
        if (v.variety != null && v.variety!.isNotEmpty) {
          varietyCounts[v.variety!] = (varietyCounts[v.variety!] ?? 0) + 1;
          if (v.rootstock != null && v.rootstock!.isNotEmpty) {
            rootstockByVariety[v.variety!] = v.rootstock!;
          }
        }
      }

      // Predominant variety in this row
      String? rowVariety;
      if (varietyCounts.isNotEmpty) {
        rowVariety = varietyCounts.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key;
      }
      final rowRootstock = rowVariety != null
          ? (rootstockByVariety[rowVariety] ?? 'Unknown')
          : 'Unknown';

      // Count dead vines and empty spots that need replacement
      final needsReplacement = vines.where((v) =>
          v.isDead || (!v.hasTag && v.yearOfPlanting == null));

      final replCount = needsReplacement.length;
      if (replCount == 0) continue;

      final locationLabel = '$vineyardName > $fieldName > Row $rowNumber';

      if (rowVariety != null) {
        final key = '$rowVariety|$rowRootstock';
        final existing = replacements.putIfAbsent(
          key,
          () => _ReplacementEntry(variety: rowVariety!, rootstock: rowRootstock, count: 0),
        );
        existing.count += replCount;
        existing.locations.add('$locationLabel ($replCount)');
      } else {
        unknownCount += replCount;
      }
    }

    // Sort by count descending
    final sorted = replacements.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    setState(() {
      _entries = sorted;
      _totalReplacements = sorted.fold(0, (sum, e) => sum + e.count) + unknownCount;
      _unknownVariety = unknownCount;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vine Replacement Report'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _totalReplacements == 0
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No dead vines or empty spots found.',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  children: [
                    // Summary header
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.green[50],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order Summary',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$_totalReplacements total vines needed',
                            style: TextStyle(fontSize: 16, color: Colors.green[700]),
                          ),
                          if (_unknownVariety > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '$_unknownVariety in rows with unknown variety',
                                style: TextStyle(fontSize: 14, color: Colors.orange[700]),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // Variety breakdown
                    ..._entries.map((entry) => ExpansionTile(
                          leading: const Icon(Icons.local_florist, color: Colors.green),
                          title: Text(
                            '${entry.variety} (${entry.count})',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('Rootstock: ${entry.rootstock}'),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: entry.locations
                                    .map((loc) => Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 2),
                                          child: Row(
                                            children: [
                                              Icon(Icons.location_on,
                                                  size: 16, color: Colors.grey[600]),
                                              const SizedBox(width: 4),
                                              Expanded(child: Text(loc)),
                                            ],
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ),
                          ],
                        )),

                    if (_unknownVariety > 0) ...[
                      const Divider(),
                      ListTile(
                        leading: Icon(Icons.help_outline, color: Colors.orange[700]),
                        title: Text(
                          'Unknown Variety ($_unknownVariety)',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'Rows with no tagged vines to determine variety',
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}
