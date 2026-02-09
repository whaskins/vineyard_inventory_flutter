import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class GpsService {
  static final GpsService _instance = GpsService._internal();
  factory GpsService() => _instance;
  GpsService._internal();

  Position? _lastPosition;
  StreamSubscription<Position>? _positionSubscription;
  final StreamController<Position> _positionController =
      StreamController<Position>.broadcast();

  Position? get lastPosition => _lastPosition;
  Stream<Position> get positionStream => _positionController.stream;

  /// Check and request location permissions. Returns true if granted.
  Future<bool> ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('GPS: Location services are disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('GPS: Location permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('GPS: Location permission permanently denied');
      return false;
    }

    return true;
  }

  /// Get current position (one-shot).
  Future<Position?> getCurrentPosition() async {
    final hasPermission = await ensurePermission();
    if (!hasPermission) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _lastPosition = position;
      return position;
    } catch (e) {
      debugPrint('GPS: Error getting current position: $e');
      return null;
    }
  }

  /// Start continuous position tracking.
  void startTracking() {
    if (_positionSubscription != null) return; // Already tracking

    _ensurePermissionAndTrack();
  }

  Future<void> _ensurePermissionAndTrack() async {
    final hasPermission = await ensurePermission();
    if (!hasPermission) return;

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 2, // Update every 2 meters
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen(
      (Position position) {
        _lastPosition = position;
        _positionController.add(position);
      },
      onError: (error) {
        debugPrint('GPS: Position stream error: $error');
      },
    );
  }

  /// Stop continuous position tracking.
  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Dispose the service (call on app shutdown if needed).
  void dispose() {
    stopTracking();
    _positionController.close();
  }
}
