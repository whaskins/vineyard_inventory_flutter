class OrganizationApiModel {
  final int? id;
  final String name;
  final String? inviteCode;
  final String? createdAt;
  final String? updatedAt;

  OrganizationApiModel({
    this.id,
    required this.name,
    this.inviteCode,
    this.createdAt,
    this.updatedAt,
  });

  factory OrganizationApiModel.fromJson(Map<String, dynamic> json) {
    return OrganizationApiModel(
      id: json['id'],
      name: json['name'],
      inviteCode: json['invite_code'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
    };
  }
}
