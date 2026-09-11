import 'package:sqflite/sqflite.dart';

import '../models/sync_entry.dart';
import 'app_database.dart';

class OutboxDao {
  final AppDatabase db;
  OutboxDao(this.db);

  Future<Database> get _db => db.database;

  Future<int> enqueue(String entityType, String entityId, String data) async {
    final database = await _db;
    return database.insert('outbox', {
      'entity_type': entityType,
      'entity_id': entityId,
      'data': data,
      'status': 'PENDING',
      'created_at': DateTime.now().toIso8601String(),
      'retry_count': 0,
    });
  }

  Future<List<SyncEntry>> getPending({int limit = 50}) async {
    final database = await _db;
    final rows = await database.query(
      'outbox',
      where: "status IN ('PENDING','FAILED')",
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(SyncEntry.fromMap).toList();
  }

  Future<int> countPending() async {
    final database = await _db;
    final res = await database.rawQuery(
        "SELECT COUNT(*) as c FROM outbox WHERE status IN ('PENDING','FAILED')");
    return Sqflite.firstIntValue(res) ?? 0;
  }

  Future<void> markSynced(int id) async {
    final database = await _db;
    await database.update('outbox', {'status': 'SYNCED'},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markFailed(int id, {bool increment = true}) async {
    final database = await _db;
    if (increment) {
      await database.rawUpdate(
          'UPDATE outbox SET status = ?, retry_count = retry_count + 1 WHERE id = ?',
          ['FAILED', id]);
    } else {
      await database.update('outbox', {'status': 'FAILED'},
          where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> removeSynced() async {
    final database = await _db;
    await database.delete('outbox', where: "status = 'SYNCED'");
  }

  Future<bool> hasEntity(String entityType, String entityId) async {
    final database = await _db;
    final rows = await database.query('outbox',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [entityType, entityId],
        limit: 1);
    return rows.isNotEmpty;
  }
}