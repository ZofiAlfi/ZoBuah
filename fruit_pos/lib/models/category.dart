class Category {
  final String id;
  final String name;
  final String? description;
  final bool isActive;

  Category({
    required this.id,
    required this.name,
    this.description,
    this.isActive = true,
  });

  /* Sengaja `== true`, bukan `?? true`. Kategori yang tidak punya field
   * is_active sama sekali (server versi lama) diperlakukan tidak aktif supaya
   * tidak muncul diam-diam tanpa kategori yang bisa dipertanggungjawabkan.
   * Sebaliknya, null di SQLite berarti kolom tidak pernah diisi dan itu
   * kondisi yang perlu diperbaiki, bukan alasan untuk menampilkan kategori
   * basi sebagai aktif. */
  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString(),
        isActive: json['is_active'] == true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'is_active': isActive ? 1 : 0,
      };
}
