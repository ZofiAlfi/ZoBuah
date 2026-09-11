import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'outbox_dao.dart';
import 'products_dao.dart';
import 'sales_dao.dart';
import 'damage_dao.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._();
  AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = join(dir, 'fruit_pos.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('ALTER TABLE products ADD COLUMN photo_url TEXT');
        }
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT,
        description TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        name TEXT,
        category_id TEXT,
        category_name TEXT,
        unit TEXT,
        modal_price REAL,
        selling_price REAL,
        stock REAL,
        min_stock REAL,
        is_active INTEGER DEFAULT 1,
        description TEXT,
        photo_url TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        transaction_number TEXT,
        employee_id TEXT,
        employee_name TEXT,
        total_amount REAL,
        total_modal REAL,
        total_profit REAL,
        discount REAL DEFAULT 0,
        status TEXT DEFAULT 'COMPLETED',
        created_at TEXT,
        sync_status TEXT DEFAULT 'PENDING'
      )
    ''');

    await db.execute('''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id TEXT,
        product_id TEXT,
        product_name TEXT,
        unit TEXT,
        unit_price REAL,
        modal_price REAL,
        quantity REAL,
        subtotal REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id TEXT,
        method TEXT,
        amount REAL,
        cash_received REAL,
        change_amount REAL,
        reference TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE damage_reports (
        id TEXT PRIMARY KEY,
        product_id TEXT,
        product_name TEXT,
        quantity REAL,
        unit TEXT,
        reason TEXT,
        description TEXT,
        status TEXT DEFAULT 'PENDING',
        employee_id TEXT,
        employee_name TEXT,
        created_at TEXT,
        photos TEXT,
        approved_by TEXT,
        approved_at TEXT,
        rejected_by TEXT,
        rejected_at TEXT,
        rejection_reason TEXT,
        sync_status TEXT DEFAULT 'PENDING'
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_movements (
        id TEXT PRIMARY KEY,
        product_id TEXT,
        product_name TEXT,
        movement_type TEXT,
        quantity REAL,
        stock_before REAL,
        stock_after REAL,
        reference_id TEXT,
        reference_type TEXT,
        notes TEXT,
        user_id TEXT,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT,
        entity_id TEXT,
        data TEXT,
        status TEXT DEFAULT 'PENDING',
        created_at TEXT,
        retry_count INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_outbox_status ON outbox(status)
    ''');
    await db.execute('''
      CREATE INDEX idx_sales_created ON sales(created_at)
    ''');
    await db.execute('''
      CREATE INDEX idx_damage_created ON damage_reports(created_at)
    ''');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

// Convenience getters
extension DatabaseAccess on AppDatabase {
  ProductsDao get products => ProductsDao(this);
  SalesDao get sales => SalesDao(this);
  DamageDao get damage => DamageDao(this);
  OutboxDao get outbox => OutboxDao(this);
}
