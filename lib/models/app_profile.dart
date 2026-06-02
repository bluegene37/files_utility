class AppProfile {
  final String id;
  final String name;
  final String description;

  AppProfile({
    required this.id,
    required this.name,
    this.description = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
    };
  }

  factory AppProfile.fromJson(Map<String, dynamic> json) {
    return AppProfile(
      id: json['id'] as String? ?? 'default',
      name: json['name'] as String? ?? 'Default Profile',
      description: json['description'] as String? ?? '',
    );
  }
}
