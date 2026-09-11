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

  Future<List<Category>> getAllCategories() async {
    final database = await _db;
    final rows = await database.query('categories', orderBy: 'name ASC');
    return rows
        .map(
          (r) => Category(
            id: r['id'] as String,
            name: r['name'] as String,
            description: r['description'] as String?,
          ),
        )
        .toList();
  }
}
