class User {
  final String id;
  final String username;
  final String fullName;
  final String role;
  final bool isActive;
  final String? createdAt;

  User({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    this.isActive = true,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        fullName: json['full_name']?.toString() ?? '',
        role: json['role']?.toString() ?? 'KARYAWAN',
        isActive: json['is_active'] ?? true,
        createdAt: json['created_at']?.toString(),
      );

  bool get isBos => role == 'BOS';
  bool get isKaryawan => role == 'KARYAWAN';
}