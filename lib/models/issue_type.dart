class IssueType {
  final int? id;
  final String name;
  final String? description;

  IssueType({
    this.id,
    required this.name,
    this.description,
  });

  // Create an IssueType from a Map (database)
  factory IssueType.fromMap(Map<String, dynamic> map) {
    return IssueType(
      id: map['id'],
      name: map['name'],
      description: map['description'],
    );
  }

  // Convert an IssueType to a Map (database)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
    };
  }
}
