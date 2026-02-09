import 'vine.dart';
import 'vine_location.dart';

/// Request model for batch sync operations
class VineSyncRequest {
  final List<Vine> vines;
  final List<VineLocation> vineLocations;
  final DateTime? since;

  VineSyncRequest({
    this.vines = const [],
    this.vineLocations = const [],
    this.since,
  });

  Map<String, dynamic> toJson() {
    return {
      'vines': vines.map((v) => v.toApiJson()).toList(),
      'vine_locations': vineLocations.map((vl) => vl.toApiJson()).toList(),
      'since': since?.toIso8601String(),
    };
  }
}

/// Response model for batch sync operations
class VineSyncResponse {
  final List<Vine> updatedVines;
  final List<VineLocation> updatedVineLocations;
  final List<VineConflict> conflicts;
  final DateTime lastSync;

  VineSyncResponse({
    required this.updatedVines,
    required this.updatedVineLocations,
    required this.conflicts,
    required this.lastSync,
  });

  factory VineSyncResponse.fromJson(Map<String, dynamic> json) {
    return VineSyncResponse(
      updatedVines: (json['updated_vines'] as List<dynamic>?)
          ?.map((v) => Vine.fromApiJson(v))
          .toList() ?? [],
      updatedVineLocations: (json['updated_vine_locations'] as List<dynamic>?)
          ?.map((vl) => VineLocation.fromApiJson(vl))
          .toList() ?? [],
      conflicts: (json['conflicts'] as List<dynamic>?)
          ?.map((c) => VineConflict.fromJson(c))
          .toList() ?? [],
      lastSync: DateTime.parse(json['last_sync']),
    );
  }
}

/// Model for sync conflicts
class VineConflict {
  final String type; // 'vine' or 'vine_location'
  final String id;
  final Map<String, dynamic> clientData;
  final Map<String, dynamic> serverData;
  final String conflictReason;
  final DateTime timestamp;

  VineConflict({
    required this.type,
    required this.id,
    required this.clientData,
    required this.serverData,
    required this.conflictReason,
    required this.timestamp,
  });

  factory VineConflict.fromJson(Map<String, dynamic> json) {
    return VineConflict(
      type: json['type'],
      id: json['id'],
      clientData: Map<String, dynamic>.from(json['client_data']),
      serverData: Map<String, dynamic>.from(json['server_data']),
      conflictReason: json['conflict_reason'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

/// Request model for delta sync operations
class DeltaSyncRequest {
  final DateTime since;
  final int limit;

  DeltaSyncRequest({
    required this.since,
    this.limit = 1000,
  });

  Map<String, dynamic> toQueryParams() {
    return {
      'since': since.toIso8601String(),
      'limit': limit.toString(),
    };
  }
}

/// Response model for delta sync operations
class DeltaSyncResponse {
  final List<Vine> vines;
  final List<VineLocation> vineLocations;
  final bool hasMore;
  final DateTime? nextPageSince;
  final DateTime currentTime;

  DeltaSyncResponse({
    required this.vines,
    required this.vineLocations,
    required this.hasMore,
    this.nextPageSince,
    required this.currentTime,
  });

  factory DeltaSyncResponse.fromJson(Map<String, dynamic> json) {
    return DeltaSyncResponse(
      vines: (json['vines'] as List<dynamic>?)
          ?.map((v) => Vine.fromApiJson(v))
          .toList() ?? [],
      vineLocations: (json['vine_locations'] as List<dynamic>?)
          ?.map((vl) => VineLocation.fromApiJson(vl))
          .toList() ?? [],
      hasMore: json['has_more'] ?? false,
      nextPageSince: json['next_page_since'] != null 
          ? DateTime.parse(json['next_page_since'])
          : null,
      currentTime: DateTime.parse(json['current_time']),
    );
  }
}

/// Response model for sync status
class SyncStatus {
  final DateTime serverTime;
  final int totalVines;
  final int totalVineLocations;
  final String syncVersion;

  SyncStatus({
    required this.serverTime,
    required this.totalVines,
    required this.totalVineLocations,
    required this.syncVersion,
  });

  factory SyncStatus.fromJson(Map<String, dynamic> json) {
    return SyncStatus(
      serverTime: DateTime.parse(json['server_time']),
      totalVines: json['total_vines'],
      totalVineLocations: json['total_vine_locations'],
      syncVersion: json['sync_version'],
    );
  }
}