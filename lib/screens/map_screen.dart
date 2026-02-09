import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/vine.dart';
import '../services/repository.dart';
import '../services/gps_service.dart';
import 'vine_detail_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Repository _repository = Repository();
  final GpsService _gpsService = GpsService();
  final MapController _mapController = MapController();

  List<Vine> _vinesWithCoords = [];
  List<String> _vineyardNames = [];
  String? _selectedVineyard;
  Position? _currentPosition;
  StreamSubscription<Position>? _gpsSubscription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initGps();
  }

  @override
  void dispose() {
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

      setState(() {
        _vinesWithCoords = withCoords;
        _vineyardNames = names;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading map data: $e');
      setState(() => _isLoading = false);
    }
  }

  List<Vine> get _filteredVines {
    if (_selectedVineyard == null) return _vinesWithCoords;
    return _vinesWithCoords
        .where((v) => v.vineyardName == _selectedVineyard)
        .toList();
  }

  LatLng? get _mapCenter {
    final vines = _filteredVines;
    if (vines.isEmpty) {
      // If no vines, center on user position or default
      if (_currentPosition != null) {
        return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      }
      return const LatLng(35.0844, -106.6504); // Albuquerque default
    }

    // Calculate centroid of all vine coordinates
    double sumLat = 0, sumLon = 0;
    for (final vine in vines) {
      sumLat += vine.location!.latitude!;
      sumLon += vine.location!.longitude!;
    }
    return LatLng(sumLat / vines.length, sumLon / vines.length);
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    for (final vine in _filteredVines) {
      final lat = vine.location!.latitude!;
      final lon = vine.location!.longitude!;
      final isAlive = !vine.isDead;

      markers.add(
        Marker(
          point: LatLng(lat, lon),
          width: 30,
          height: 30,
          child: GestureDetector(
            onTap: () => _onMarkerTap(vine),
            child: Container(
              decoration: BoxDecoration(
                color: isAlive ? Colors.green : Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                isAlive ? Icons.eco : Icons.close,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
      );
    }

    // Add user position marker
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

    return markers;
  }

  void _onMarkerTap(Vine vine) {
    if (vine.alphaNumericID != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => VineDetailScreen(vineId: vine.uniqueIdentifier),
        ),
      ).then((_) => _loadData());
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = _mapCenter ?? const LatLng(35.0844, -106.6504);

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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Vineyard filter dropdown
                if (_vineyardNames.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Colors.grey[100],
                    child: Row(
                      children: [
                        const Icon(Icons.filter_list, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<String?>(
                            value: _selectedVineyard,
                            hint: const Text('All Vineyards'),
                            isExpanded: true,
                            underline: const SizedBox(),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('All Vineyards'),
                              ),
                              ..._vineyardNames.map((name) => DropdownMenuItem(
                                    value: name,
                                    child: Text(name),
                                  )),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedVineyard = value;
                              });
                            },
                          ),
                        ),
                        Text(
                          '${_filteredVines.length} vines',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                // Map
                Expanded(
                  child: _filteredVines.isEmpty && _currentPosition == null
                      ? const Center(
                          child: Text(
                            'No vines with GPS coordinates yet.\nScan vines to capture their location.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: center,
                            initialZoom: 19,
                            minZoom: 5,
                            maxZoom: 22,
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
              ],
            ),
    );
  }
}
