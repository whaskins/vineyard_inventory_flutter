class VineIssue {
  final int? id;
  final int vineID;
  final int? issueTypeID;
  final String description;
  final String? photoPath;     // Local file path (still needed for offline mode)
  final String? photoUrl;      // Remote server URL for the photo
  final DateTime dateReported;
  final int reportedBy;
  final bool isResolved;
  final DateTime? dateResolved;
  final int? resolvedBy;

  VineIssue({
    this.id,
    required this.vineID,
    this.issueTypeID,
    required this.description,
    this.photoPath,
    this.photoUrl,
    required this.dateReported,
    required this.reportedBy,
    this.isResolved = false,
    this.dateResolved,
    this.resolvedBy,
  });

  // Create a VineIssue from a Map (database)
  factory VineIssue.fromMap(Map<String, dynamic> map) {
    return VineIssue(
      id: map['id'],
      vineID: map['vineID'],
      issueTypeID: map['issueTypeID'],
      description: map['description'],
      photoPath: map['photoPath'],
      photoUrl: map['photoUrl'],
      dateReported: DateTime.parse(map['dateReported']),
      reportedBy: map['reportedBy'],
      isResolved: map['isResolved'] == 1,
      dateResolved: map['dateResolved'] != null
        ? DateTime.parse(map['dateResolved'])
        : null,
      resolvedBy: map['resolvedBy'],
    );
  }

  // Convert a VineIssue to a Map (database)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'vineID': vineID,
      'issueTypeID': issueTypeID,
      'description': description,
      'photoPath': photoPath,
      'photoUrl': photoUrl,
      'dateReported': dateReported.toIso8601String(),
      'reportedBy': reportedBy,
      'isResolved': isResolved ? 1 : 0,
      'dateResolved': dateResolved?.toIso8601String(),
      'resolvedBy': resolvedBy,
    };
  }

  // Get the effective photo source (URL first, then local path)
  String? get effectivePhotoSource => photoUrl ?? photoPath;

  // Check if this issue has a photo (either local or remote)
  bool get hasPhoto => photoPath != null || photoUrl != null;

  // Create a copy of this VineIssue with given fields replaced with new values
  VineIssue copyWith({
    int? id,
    int? vineID,
    int? issueTypeID,
    String? description,
    String? photoPath,
    String? photoUrl,
    DateTime? dateReported,
    int? reportedBy,
    bool? isResolved,
    DateTime? dateResolved,
    int? resolvedBy,
  }) {
    return VineIssue(
      id: id ?? this.id,
      vineID: vineID ?? this.vineID,
      issueTypeID: issueTypeID ?? this.issueTypeID,
      description: description ?? this.description,
      photoPath: photoPath ?? this.photoPath,
      photoUrl: photoUrl ?? this.photoUrl,
      dateReported: dateReported ?? this.dateReported,
      reportedBy: reportedBy ?? this.reportedBy,
      isResolved: isResolved ?? this.isResolved,
      dateResolved: dateResolved ?? this.dateResolved,
      resolvedBy: resolvedBy ?? this.resolvedBy,
    );
  }
}