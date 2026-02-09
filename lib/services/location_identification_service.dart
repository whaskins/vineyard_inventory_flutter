import 'dart:math';
import '../models/vine.dart';

class LocationEstimate {
  final String vineyardName;
  final String fieldName;
  final int rowNumber;
  final double distanceMeters;
  final double confidence; // 0.0 to 1.0

  LocationEstimate({
    required this.vineyardName,
    required this.fieldName,
    required this.rowNumber,
    required this.distanceMeters,
    required this.confidence,
  });
}

class LocationIdentificationService {
  /// Identify the user's location based on nearby vines with GPS coordinates.
  /// Uses nearest-neighbor with majority vote on vineyard/field/row.
  static LocationEstimate? identifyLocation(
    double lat,
    double lon,
    List<Vine> vines,
  ) {
    // Filter vines that have coordinates
    final vinesWithCoords = vines.where((v) => v.hasCoordinates).toList();
    if (vinesWithCoords.isEmpty) return null;

    // Calculate distance to each vine and sort by distance
    final distances = vinesWithCoords.map((vine) {
      final d = _haversineDistance(
        lat, lon,
        vine.location!.latitude!, vine.location!.longitude!,
      );
      return _VineDistance(vine: vine, distance: d);
    }).toList();

    distances.sort((a, b) => a.distance.compareTo(b.distance));

    // Take the 10 nearest (or fewer if less available)
    final nearest = distances.take(10).toList();
    if (nearest.isEmpty) return null;

    // If the closest vine is very far (>200m), don't estimate
    if (nearest.first.distance > 200) return null;

    // Majority vote on vineyard name
    final vineyardVotes = <String, int>{};
    final fieldVotes = <String, int>{};
    final rowVotes = <int, int>{};

    for (final nd in nearest) {
      final loc = nd.vine.location!;
      vineyardVotes[loc.vineyardName] = (vineyardVotes[loc.vineyardName] ?? 0) + 1;
      fieldVotes[loc.fieldName] = (fieldVotes[loc.fieldName] ?? 0) + 1;
      rowVotes[loc.rowNumber] = (rowVotes[loc.rowNumber] ?? 0) + 1;
    }

    final bestVineyard = _topVote(vineyardVotes);
    final bestField = _topVote(fieldVotes);
    final bestRow = _topVote(rowVotes);

    if (bestVineyard == null || bestField == null || bestRow == null) return null;

    // Confidence based on vote proportion and distance
    final totalVotes = nearest.length;
    final vineyardConfidence = vineyardVotes[bestVineyard]! / totalVotes;
    final fieldConfidence = fieldVotes[bestField]! / totalVotes;
    final rowConfidence = rowVotes[bestRow]! / totalVotes;
    final avgConfidence = (vineyardConfidence + fieldConfidence + rowConfidence) / 3;

    // Reduce confidence based on distance (>50m starts reducing)
    final distancePenalty = nearest.first.distance > 50
        ? max(0.0, 1.0 - (nearest.first.distance - 50) / 150)
        : 1.0;

    return LocationEstimate(
      vineyardName: bestVineyard,
      fieldName: bestField,
      rowNumber: bestRow,
      distanceMeters: nearest.first.distance,
      confidence: avgConfidence * distancePenalty,
    );
  }

  static T? _topVote<T>(Map<T, int> votes) {
    if (votes.isEmpty) return null;
    return votes.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  /// Haversine distance in meters between two lat/lon points.
  static double _haversineDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const R = 6371000.0; // Earth radius in meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;
}

class _VineDistance {
  final Vine vine;
  final double distance;

  _VineDistance({required this.vine, required this.distance});
}
