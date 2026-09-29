import 'package:sqflite/sqflite.dart';

import '../models/product.dart';
import '../models/category.dart';
import 'app_database.dart';

class ProductsDao {
  final AppDatabase db;
  ProductsDao(this.db);

  Future<Database> get _db => db.database;

  Future<void> upsertAllProducts(List<Product> products) async {
    final database = await _db;
    final batch = database.batch();
    for (final p in products) {
      batch.insert(
        'products',
        p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Product>> getAllProducts({
    String search = '',
    bool activeOnly = false,
  }) async {
    final database = await _db;
    String where = '';
    List args = [];
    if (search.isNotEmpty) {
      where = 'name LIKE ?';
      args = ['%$search%'];
    }
    if (activeOnly) {
      where = where.isEmpty ? 'is_active = 1' : '$where AND is_active = 1';
    }
    final rows = await database.query(
      'products',
      where: where.isEmpty ? null : where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name ASC',
    );
    return rows.map((r) => Product.fromJson(_rowToJson(r))).toList();
  }

  Product _productFromRow(Map<String, dynamic> row) {
    return Product(
      id: row['id'],
      name: row['name'],
      categoryId: row['category_id'],
      categoryName: row['category_name'],
      unit: row['unit'],
      modalPrice: (row['modal_price'] as num).toDouble(),
      sellingPrice: (row['selling_price'] as num).toDouble(),
      stock: (row['stock'] as num).toDouble(),
      minStock: (row['min_stock'] as num).toDouble(),
      isActive: row['is_active'] == 1,
      description: row['description'],
      photoUrl: row['photo_url'],
    );
  }

  Map<String, dynamic> _rowToJson(Map<String, dynamic> row) => {
    'id': row['id'],
    'name': row['name'],
    'category_id': row['category_id'],
    'category_name': row['category_name'],
    'unit': row['unit'],
    'modal_price': row['modal_price'],
    'selling_price': row['selling_price'],
    'stock': row['stock'],
    'min_stock': row['min_stock'],
    'is_active': row['is_active'] == 1,
    'description': row['description'],
    'photo_url': row['photo_url'],
  };

  Future<Product?> getProductById(String id) async {
    final database = await _db;
    final rows = await database.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _productFromRow(rows.first);
  }

  Future<void> upsertProduct(Product p) async {
    final database = await _db;
    await database.insert(
      'products',
      p.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateStock(String productId, double newStock) async {
    final database = await _db;
    await database.update(
      'products',
      {'stock': newStock},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<void> upsertAllCategories(List<Category> categories) async {
    final database = await _db;
    final batch = database.batch();
    for (final c in categories) {
      batch.insert(
        'categories',
        c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Nonaktifkan baris lokal yang tidak ada lagi di full dump server.
  ///
  /// Ini catching-up untuk produk yang dihapus keras di server sebelum soft
  /// delete diperbaiki: barisnya hilang dari payload, jadi tidak ada is_active
  /// yang bisa menimpanya lewat upsert. Karena products di-pull sebagai full
  /// dump (tanpa filter last_sync), "tidak ada di payload" memang berarti
  /// "tidak ada lagi di server".
  ///
  /// Sengaja return 0 kalau presentIds kosong: pull yang gagal di tengah jalan
  /// tidak boleh menonaktifkan seluruh katalog lokal.
  Future<int> deactivateMissingProducts(Set<String> presentIds) async {
    final database = await _db;
    if (presentIds.isEmpty) return 0;
    final placeholders = List.filled(presentIds.length, '?').join(',');
    return database.rawUpdate(
      'UPDATE products SET is_active = 0 WHERE is_active = 1 '
      'AND id NOT IN ($placeholders)',
      presentIds.toList(),
    );
  }

  /// Sama seperti [deactivateMissingProducts], untuk kategori.
  Future<int> deactivateMissingCategories(Set<String> presentIds) async {
    final database = await _db;
    if (presentIds.isEmpty) return 0;
    final placeholders = List.filled(presentIds.length, '?').join(',');
    return database.rawUpdate(
      'UPDATE categories SET is_active = 0 WHERE is_active = 1 '
      'AND id NOT IN ($placeholders)',
      presentIds.toList(),
    );
  }

  Future<List<Category>> getAllCategories({bool activeOnly = false}) async {
    final database = await _db;
    final rows = await database.query(
      'categories',
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'name ASC',
    );
    return rows
        .map(
          (r) => Category(
            id: r['id'] as String,
            name: r['name'] as String,
            description: r['description'] as String?,
            isActive: r['is_active'] == 1,
          ),
        )
        .toList();
  }
}
