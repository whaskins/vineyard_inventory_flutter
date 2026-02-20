import 'package:flutter/material.dart';
import '../models/vine.dart';
import '../services/repository.dart';
import 'qr_scanner_screen.dart';
import 'vine_detail_screen.dart';

class ScanTab extends StatefulWidget {
  const ScanTab({super.key});

  @override
  State<ScanTab> createState() => ScanTabState();
}

class ScanTabState extends State<ScanTab> {
  final _repository = Repository();
  bool _isLoading = true;
  List<Vine> _recentVines = [];

  @override
  void initState() {
    super.initState();
    _loadRecentVines();
  }

  Future<void> _loadRecentVines() async {
    setState(() => _isLoading = true);

    try {
      final vines = await _repository.getLocalVines();
      vines.sort((a, b) => b.recordCreated.compareTo(a.recordCreated));

      if (mounted) {
        setState(() {
          _recentVines = vines.take(10).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading recent vines: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    ).then((_) => _loadRecentVines());
  }

  void _navigateToVineDetail(String vineId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => VineDetailScreen(vineId: vineId)),
    ).then((_) => _loadRecentVines());
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadRecentVines,
      child: Column(
        children: [
          // Scan button area
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            child: ElevatedButton.icon(
              onPressed: _navigateToScanner,
              icon: const Icon(Icons.qr_code_scanner, size: 28),
              label: const Text('Scan Vine', style: TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // Section header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  'Recently Scanned',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${_recentVines.length} vines',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Recent vines list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _recentVines.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 60),
                          Center(
                            child: Text(
                              'No vines scanned yet.\nTap "Scan Vine" to get started.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        itemCount: _recentVines.length,
                        itemBuilder: (context, index) {
                          final vine = _recentVines[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: ListTile(
                              title: Text(vine.hasTag ? vine.alphaNumericID! : 'No Tag'),
                              subtitle: Text(
                                [
                                  vine.variety ?? 'Unknown Variety',
                                  if (vine.fieldName != null) 'Field: ${vine.fieldName}',
                                  if (vine.rowNumber != null && vine.spotNumber != null)
                                    'Position: ${vine.rowNumber}-${vine.spotNumber}',
                                ].join(' • '),
                              ),
                              leading: CircleAvatar(
                                backgroundColor:
                                    vine.isDead ? Colors.red[100] : Colors.green[100],
                                child: Icon(
                                  vine.isDead ? Icons.close : Icons.eco,
                                  color: vine.isDead ? Colors.red : Colors.green,
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _navigateToVineDetail(vine.uniqueIdentifier),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
