import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../models/vine.dart';
import '../models/issue.dart';
import '../models/issue_type.dart';
import '../services/database_service.dart';
import '../services/repository.dart';
import '../services/gps_service.dart';
import 'vine_detail_screen.dart';

enum MapViewMode { vines, problems }

/// A problem item shown on the map: either an unresolved issue, dead vine, or empty spot.
class _ProblemItem {
  final double latitude;
  final double longitude;
  final _ProblemKind kind;
  final VineIssue? issue;
  final Vine? vine;
  final String? vineAlphaNumericID;

  _ProblemItem({
    required this.latitude,
    required this.longitude,
    required this.kind,
    this.issue,
    this.vine,
    this.vineAlphaNumericID,
  });
}

enum _ProblemKind { issue, dead, missingTag, empty }

class MapScreen extends StatefulWidget {
  final bool embedded;

  const MapScreen({super.key, this.embedded = false});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Repository _repository = Repository();
  final DatabaseService _databaseService = DatabaseService();
  final GpsService _gpsService = GpsService();
  final MapController _mapController = MapController();

  // Shared state
  List<Vine> _vinesWithCoords = [];
  List<String> _vineyardNames = [];
  String? _selectedVineyard;
  Position? _currentPosition;
  StreamSubscription<Position>? _gpsSubscription;
  bool _isLoading = true;
  int _lastVineCount = -1;
  double _currentZoom = 19;
  MapViewMode _viewMode = MapViewMode.vines;

  // Vines mode state
  List<String> _varietyNames = [];
  String? _selectedVariety;

  // Problems mode state
  List<_ProblemItem> _problems = [];
  List<IssueType> _issueTypes = [];
  int? _selectedIssueTypeFilter;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initGps();
    _startDataRefreshTimer();
  }

  Timer? _refreshTimer;

  void _startDataRefreshTimer() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkForNewData();
    });
  }

  Future<void> _checkForNewData() async {
    if (!mounted) return;
    final allVines = await _repository.getLocalVines();
    final count = allVines.where((v) => v.hasCoordinates).length;
    if (count != _lastVineCount) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _gpsSubscription?.cancel();
    _gpsService.stopTracking();
    super.dispose();
  }

  Future<void> _initGps() async {
    _gpsService.startTracking();
    _gpsSubscription = _gpsService.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    });
    final pos = await _gpsService.getCurrentPosition();
    if (pos != null && mounted) {
      setState(() {
        _currentPosition = pos;
      });
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final allVines = await _repository.getLocalVines();
      final withCoords = allVines.where((v) => v.hasCoordinates).toList();

      // Extract unique vineyard names
      final names = withCoords
          .where((v) => v.vineyardName != null && v.vineyardName!.isNotEmpty)
          .map((v) => v.vineyardName!)
          .toSet()
          .toList()
        ..sort();

      // Extract unique variety names
      final varieties = withCoords
          .where((v) => v.variety != null && v.variety!.isNotEmpty)
          .map((v) => v.variety!)
          .toSet()
          .toList()
        ..sort();

      // Load problems data
      final problems = await _loadProblems(allVines, withCoords);

      // Load issue types
      List<IssueType> issueTypes = [];
      try {
        issueTypes = await _repository.getAllIssueTypes();
      } catch (e) {
        debugPrint('Error loading issue types for map: $e');
      }

      setState(() {
        _vinesWithCoords = withCoords;
        _vineyardNames = names;
        _varietyNames = varieties;
        _problems = problems;
        _issueTypes = issueTypes;
        _isLoading = false;
        _lastVineCount = withCoords.length;
      });
    } catch (e) {
      debugPrint('Error loading map data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<List<_ProblemItem>> _loadProblems(List<Vine> allVines, List<Vine> withCoords) async {
    final problems = <_ProblemItem>[];

    // 1. Unresolved issues with vine location
    try {
      final issueRows = await _databaseService.getUnresolvedIssuesWithVineLocation();
      for (final row in issueRows) {
        final issue = VineIssue.fromMap({
          'id': row['id'],
          'vineID': row['vineID'],
          'issueTypeID': row['issueTypeID'],
          'description': row['description'],
          'photoPath': row['photoPath'],
          'photoUrl': row['photoUrl'],
          'dateReported': row['dateReported'],
          'reportedBy': row['reportedBy'],
          'isResolved': row['isResolved'],
          'dateResolved': row['dateResolved'],
          'resolvedBy': row['resolvedBy'],
        });
        problems.add(_ProblemItem(
          latitude: (row['latitude'] as num).toDouble(),
          longitude: (row['longitude'] as num).toDouble(),
          kind: _ProblemKind.issue,
          issue: issue,
          vineAlphaNumericID: row['vineAlphaNumericID'] as String?,
        ));
      }
    } catch (e) {
      debugPrint('Error loading unresolved issues: $e');
    }

    // 2. Dead vines with coordinates
    for (final vine in withCoords) {
      if (vine.isDead) {
        problems.add(_ProblemItem(
          latitude: vine.location!.latitude!,
          longitude: vine.location!.longitude!,
          kind: _ProblemKind.dead,
          vine: vine,
          vineAlphaNumericID: vine.alphaNumericID,
        ));
      }
    }

    // 3. Vines without tags (missing tag vs truly empty spot)
    for (final vine in withCoords) {
      if (!vine.hasTag && !vine.isDead) {
        final kind = vine.yearOfPlanting != null
            ? _ProblemKind.missingTag
            : _ProblemKind.empty;
        problems.add(_ProblemItem(
          latitude: vine.location!.latitude!,
          longitude: vine.location!.longitude!,
          kind: kind,
          vine: vine,
          vineAlphaNumericID: vine.alphaNumericID,
        ));
      }
    }

    return problems;
  }

  List<Vine> get _filteredVines {
    var vines = _vinesWithCoords;
    if (_selectedVineyard != null) {
      vines = vines.where((v) => v.vineyardName == _selectedVineyard).toList();
    }
    if (_selectedVariety != null) {
      vines = vines.where((v) => v.variety == _selectedVariety).toList();
    }
    return vines;
  }

  List<_ProblemItem> get _filteredProblems {
    var problems = _problems;
    if (_selectedVineyard != null) {
      // Filter by vineyard if we have the vine object
      problems = problems.where((p) {
        if (p.vine != null) return p.vine!.vineyardName == _selectedVineyard;
        return true; // Keep issues without vine reference
      }).toList();
    }
    if (_selectedIssueTypeFilter != null) {
      problems = problems.where((p) {
        if (p.kind == _ProblemKind.issue) {
          return p.issue?.issueTypeID == _selectedIssueTypeFilter;
        }
        return false; // Hide non-issue items when filtering by type
      }).toList();
    }
    return problems;
  }

  LatLng? get _mapCenter {
    if (_viewMode == MapViewMode.problems) {
      final problems = _filteredProblems;
      if (problems.isNotEmpty) {
        double sumLat = 0, sumLon = 0;
        for (final p in problems) {
          sumLat += p.latitude;
          sumLon += p.longitude;
        }
        return LatLng(sumLat / problems.length, sumLon / problems.length);
      }
    }

    final vines = _filteredVines;
    if (vines.isEmpty) {
      if (_currentPosition != null) {
        return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      }
      return const LatLng(35.0844, -106.6504);
    }

    double sumLat = 0, sumLon = 0;
    for (final vine in vines) {
      sumLat += vine.location!.latitude!;
      sumLon += vine.location!.longitude!;
    }
    return LatLng(sumLat / vines.length, sumLon / vines.length);
  }

  double get _markerSize {
    if (_currentZoom >= 20) return 30;
    if (_currentZoom >= 19) return 24;
    if (_currentZoom >= 18) return 18;
    if (_currentZoom >= 17) return 12;
    if (_currentZoom >= 16) return 8;
    if (_currentZoom >= 15) return 6;
    return 4;
  }

  double get _borderWidth {
    if (_currentZoom >= 19) return 2;
    if (_currentZoom >= 17) return 1;
    return 0.5;
  }

  bool get _showIcon => _currentZoom >= 19;

  List<Marker> _buildMarkers() {
    if (_viewMode == MapViewMode.problems) {
      return _buildProblemMarkers();
    }
    return _buildVineMarkers();
  }

  List<Marker> _buildVineMarkers() {
    final markers = <Marker>[];
    final size = _markerSize;
    final border = _borderWidth;
    final showIcon = _showIcon;

    for (final vine in _filteredVines) {
      final lat = vine.location!.latitude!;
      final lon = vine.location!.longitude!;
      final isAlive = !vine.isDead;

      markers.add(
        Marker(
          point: LatLng(lat, lon),
          width: size,
          height: size,
          child: GestureDetector(
            onTap: () => _onVineMarkerTap(vine),
            child: Container(
              decoration: BoxDecoration(
                color: isAlive ? Colors.green : Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: border),
                boxShadow: _currentZoom >= 17
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: showIcon
                  ? Icon(
                      isAlive ? Icons.eco : Icons.close,
                      color: Colors.white,
                      size: size * 0.55,
                    )
                  : null,
            ),
          ),
        ),
      );
    }

    _addUserPositionMarker(markers);
    return markers;
  }

  List<Marker> _buildProblemMarkers() {
    final markers = <Marker>[];
    final size = _markerSize;
    final border = _borderWidth;
    final showIcon = _showIcon;

    for (final problem in _filteredProblems) {
      Color color;
      IconData icon;

      switch (problem.kind) {
        case _ProblemKind.issue:
          color = Colors.orange;
          icon = Icons.warning;
          break;
        case _ProblemKind.dead:
          color = Colors.red;
          icon = Icons.close;
          break;
        case _ProblemKind.missingTag:
          color = Colors.purple;
          icon = Icons.label_off;
          break;
        case _ProblemKind.empty:
          color = Colors.grey;
          icon = Icons.circle_outlined;
          break;
      }

      markers.add(
        Marker(
          point: LatLng(problem.latitude, problem.longitude),
          width: size,
          height: size,
          child: GestureDetector(
            onTap: () => _onProblemMarkerTap(problem),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: border),
                boxShadow: _currentZoom >= 17
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: showIcon
                  ? Icon(icon, color: Colors.white, size: size * 0.55)
                  : null,
            ),
          ),
        ),
      );
    }

    _addUserPositionMarker(markers);
    return markers;
  }

  void _addUserPositionMarker(List<Marker> markers) {
    if (_currentPosition != null) {
      markers.add(
        Marker(
          point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          width: 24,
          height: 24,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _onVineMarkerTap(Vine vine) {
    if (vine.alphaNumericID != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VineDetailScreen(vineId: vine.uniqueIdentifier),
        ),
      ).then((_) => _loadData());
    }
  }

  void _onProblemMarkerTap(_ProblemItem problem) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _buildProblemBottomSheet(problem),
    );
  }

  Widget _buildProblemBottomSheet(_ProblemItem problem) {
    String title;
    Color titleColor;
    IconData titleIcon;
    List<Widget> details = [];

    switch (problem.kind) {
      case _ProblemKind.issue:
        title = 'Unresolved Issue';
        titleColor = Colors.orange;
        titleIcon = Icons.warning;
        if (problem.issue != null) {
          final issue = problem.issue!;
          // Issue type name
          if (issue.issueTypeID != null) {
            final typeName = _issueTypes
                .where((t) => t.id == issue.issueTypeID)
                .map((t) => t.name)
                .firstOrNull ?? 'Type #${issue.issueTypeID}';
            details.add(Chip(
              label: Text(typeName),
              backgroundColor: Colors.orange.withValues(alpha: 0.2),
            ));
            details.add(const SizedBox(height: 8));
          }
          details.add(Text(issue.description, style: const TextStyle(fontSize: 16)));
          details.add(const SizedBox(height: 8));
          details.add(Text(
            'Reported: ${DateFormat('yyyy-MM-dd').format(issue.dateReported)}',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ));
        }
        if (problem.vineAlphaNumericID != null) {
          details.add(const SizedBox(height: 4));
          details.add(Text(
            'Vine: ${problem.vineAlphaNumericID}',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ));
        }
        break;

      case _ProblemKind.dead:
        title = 'Dead Vine';
        titleColor = Colors.red;
        titleIcon = Icons.close;
        if (problem.vine != null) {
          final vine = problem.vine!;
          if (vine.alphaNumericID != null) {
            details.add(Text('ID: ${vine.alphaNumericID}', style: const TextStyle(fontSize: 16)));
          }
          if (vine.variety != null) {
            details.add(Text('Variety: ${vine.variety}', style: TextStyle(color: Colors.grey[600])));
          }
          if (vine.dateDied != null) {
            details.add(Text(
              'Died: ${DateFormat('yyyy-MM-dd').format(vine.dateDied!)}',
              style: TextStyle(color: Colors.grey[600]),
            ));
          }
        }
        break;

      case _ProblemKind.missingTag:
        title = 'Missing Tag';
        titleColor = Colors.purple;
        titleIcon = Icons.label_off;
        if (problem.vine != null) {
          final vine = problem.vine!;
          if (vine.vineyardName != null) {
            details.add(Text('Vineyard: ${vine.vineyardName}', style: TextStyle(color: Colors.grey[600])));
          }
          if (vine.rowNumber != null && vine.spotNumber != null) {
            details.add(Text('Row ${vine.rowNumber}, Spot ${vine.spotNumber}',
                style: TextStyle(color: Colors.grey[600])));
          }
          if (vine.variety != null) {
            details.add(Text('Variety: ${vine.variety}', style: TextStyle(color: Colors.grey[600])));
          }
          if (vine.yearOfPlanting != null) {
            details.add(Text('Planted: ${vine.yearOfPlanting}', style: TextStyle(color: Colors.grey[600])));
          }
        }
        details.add(const SizedBox(height: 8));
        details.add(const Text('Vine exists but needs a tag printed.'));
        break;

      case _ProblemKind.empty:
        title = 'Empty Spot';
        titleColor = Colors.grey;
        titleIcon = Icons.circle_outlined;
        if (problem.vine != null) {
          final vine = problem.vine!;
          if (vine.vineyardName != null) {
            details.add(Text('Vineyard: ${vine.vineyardName}', style: TextStyle(color: Colors.grey[600])));
          }
          if (vine.rowNumber != null && vine.spotNumber != null) {
            details.add(Text('Row ${vine.rowNumber}, Spot ${vine.spotNumber}',
                style: TextStyle(color: Colors.grey[600])));
          }
        }
        details.add(const SizedBox(height: 8));
        details.add(const Text('No vine planted at this location.'));
        break;
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: titleColor,
                radius: 16,
                child: Icon(titleIcon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Text(title, style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: titleColor,
              )),
            ],
          ),
          const SizedBox(height: 16),
          ...details,
          if (problem.vineAlphaNumericID != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => VineDetailScreen(vineId: problem.vineAlphaNumericID!),
                    ),
                  ).then((_) => _loadData());
                },
                child: const Text('View Vine Details'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String get _statusText {
    if (_viewMode == MapViewMode.problems) {
      final count = _filteredProblems.length;
      return '$count problem${count == 1 ? '' : 's'}';
    }
    return '${_filteredVines.length} vines';
  }

  Widget _buildMapBody() {
    final center = _mapCenter ?? const LatLng(35.0844, -106.6504);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // View mode toggle + vineyard filter
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey[100],
          child: Row(
            children: [
              // Segmented button for view mode
              SegmentedButton<MapViewMode>(
                segments: const [
                  ButtonSegment(
                    value: MapViewMode.vines,
                    label: Text('Vines'),
                    icon: Icon(Icons.eco, size: 16),
                  ),
                  ButtonSegment(
                    value: MapViewMode.problems,
                    label: Text('Problems'),
                    icon: Icon(Icons.warning, size: 16),
                  ),
                ],
                selected: {_viewMode},
                onSelectionChanged: (selection) {
                  setState(() {
                    _viewMode = selection.first;
                    _selectedIssueTypeFilter = null;
                  });
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 12),
              // Vineyard dropdown (compact)
              if (_vineyardNames.isNotEmpty)
                Expanded(
                  child: DropdownButton<String?>(
                    value: _selectedVineyard,
                    hint: const Text('All', style: TextStyle(fontSize: 13)),
                    isExpanded: true,
                    underline: const SizedBox(),
                    isDense: true,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All Vineyards', style: TextStyle(fontSize: 13)),
                      ),
                      ..._vineyardNames.map((name) => DropdownMenuItem(
                            value: name,
                            child: Text(name, style: const TextStyle(fontSize: 13)),
                          )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedVineyard = value;
                      });
                    },
                  ),
                ),
              if (_vineyardNames.isEmpty)
                const Spacer(),
              Text(
                _statusText,
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
        ),
        // Map
        Expanded(
          child: (_viewMode == MapViewMode.vines
                      ? _filteredVines.isEmpty
                      : _filteredProblems.isEmpty) &&
                  _currentPosition == null
              ? Center(
                  child: Text(
                    _viewMode == MapViewMode.vines
                        ? 'No vines with GPS coordinates yet.\nScan vines to capture their location.'
                        : 'No problems found.\nAll vines are healthy!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 19,
                    minZoom: 5,
                    maxZoom: 22,
                    onPositionChanged: (position, hasGesture) {
                      if (position.zoom != null && position.zoom != _currentZoom) {
                        setState(() {
                          _currentZoom = position.zoom!;
                        });
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName:
                          'com.warrenhaskins.vineyardinventory',
                    ),
                    MarkerLayer(
                      markers: _buildMarkers(),
                    ),
                  ],
                ),
        ),
        // Bottom filter chips
        _viewMode == MapViewMode.vines
            ? _buildVarietyChips()
            : _buildProblemFilterChips(),
      ],
    );
  }

  Widget _buildVarietyChips() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All Varieties'),
                    selected: _selectedVariety == null,
                    onSelected: (_) {
                      setState(() => _selectedVariety = null);
                    },
                  ),
                ),
                ..._varietyNames.map((variety) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(variety),
                        selected: _selectedVariety == variety,
                        onSelected: (_) {
                          setState(() {
                            _selectedVariety =
                                _selectedVariety == variety ? null : variety;
                          });
                        },
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProblemFilterChips() {
    // Count by kind
    final issueCount = _problems.where((p) => p.kind == _ProblemKind.issue).length;
    final deadCount = _problems.where((p) => p.kind == _ProblemKind.dead).length;
    final missingTagCount = _problems.where((p) => p.kind == _ProblemKind.missingTag).length;
    final emptyCount = _problems.where((p) => p.kind == _ProblemKind.empty).length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Problem kind legend
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _legendDot(Colors.orange, 'Issues ($issueCount)'),
                const SizedBox(width: 12),
                _legendDot(Colors.red, 'Dead ($deadCount)'),
                const SizedBox(width: 12),
                _legendDot(Colors.purple, 'No Tag ($missingTagCount)'),
                const SizedBox(width: 12),
                _legendDot(Colors.grey, 'Empty ($emptyCount)'),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Issue type filter chips
          if (_issueTypes.isNotEmpty)
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('All Problems'),
                      selected: _selectedIssueTypeFilter == null,
                      onSelected: (_) {
                        setState(() => _selectedIssueTypeFilter = null);
                      },
                    ),
                  ),
                  ..._issueTypes.map((type) {
                    final count = _problems.where((p) =>
                        p.kind == _ProblemKind.issue &&
                        p.issue?.issueTypeID == type.id).length;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('${type.name} ($count)'),
                        selected: _selectedIssueTypeFilter == type.id,
                        onSelected: (_) {
                          setState(() {
                            _selectedIssueTypeFilter =
                                _selectedIssueTypeFilter == type.id
                                    ? null
                                    : type.id;
                          });
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildMapBody();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vine Map'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        actions: [
          if (_currentPosition != null)
            IconButton(
              icon: const Icon(Icons.my_location),
              tooltip: 'Go to my location',
              onPressed: () {
                _mapController.move(
                  LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                  19,
                );
              },
            ),
        ],
      ),
      body: _buildMapBody(),
    );
  }
}
