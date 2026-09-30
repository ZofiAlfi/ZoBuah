import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fruit_pos/database/app_database.dart';
import 'package:fruit_pos/models/sale.dart';

/// Regresi untuk dua bug sinkronisasi yang membuat riwayat transaksi kosong
/// dan koreksi owner tidak pernah sampai ke perangkat.
///
/// Bug 1: `upsertFromServer` hanya menulis kolom `status` dan langsung
///        `continue` kalau status-nya sama. `total_amount` dan `sale_items`
///        tidak pernah ditulis ulang, jadi owner yang mengubah 0,8 kg jadi
///        0,7 kg di Owner Console tidak mengubah apa pun di kasir.
///
/// Bug 2: `sale_items` di-insert dengan `ConflictAlgorithm.ignore` sehingga
///        baris lama tidak pernah tergantikan, dan item yang dihapus owner
///        tetap tampil.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    await deleteDatabase('fruit_pos.db');
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  Sale buildSale({
    String id = 'sale-1',
    String transactionNumber = 'TRX-20260930-77A',
    double totalAmount = 14400,
    double totalModal = 10400,
    double totalProfit = 4000,
    String status = 'COMPLETED',
    double quantity = 0.8,
    double subtotal = 14400,
    String productName = 'Pisang Balangan',
    String createdAt = '2026-09-30T05:24:45.469840Z',
  }) {
    return Sale(
      id: id,
      transactionNumber: transactionNumber,
      employeeId: 'emp-1',
      employeeName: 'Erlina',
      totalAmount: totalAmount,
      totalModal: totalModal,
      totalProfit: totalProfit,
      status: status,
      createdAt: createdAt,
      items: [
        SaleItem(
          productId: 'prod-1',
          productName: productName,
          unit: 'kg',
          unitPrice: 18000,
          modalPrice: 13000,
          quantity: quantity,
          subtotal: subtotal,
        ),
      ],
      payment: Payment(method: 'CASH', amount: totalAmount),
    );
  }

  test('koreksi owner 0,8 -> 0,7 kg menulis ulang nominal di DB lokal', () async {
    final db = AppDatabase.instance;
    final database = await db.database;

    // First pull: server mengirim angka lama.
    await db.sales.upsertFromServer([buildSale()]);

    var row = (await database.query('sales', where: 'id = ?', whereArgs: ['sale-1']))
        .single;
    expect(row['total_amount'], 14400);
    var item = (await database
            .query('sale_items', where: 'sale_id = ?', whereArgs: ['sale-1']))
        .single;
    expect(item['quantity'], 0.8);
    expect(item['subtotal'], 14400);

    // Owner mengoreksi di Owner Console: 0,7 kg, total 12.600.
    // Status TIDAK berubah -- justru ini yang dulu membuat app meloloskan
    // baris itu tanpa menulis ulang apa pun.
    await db.sales.upsertFromServer([
      buildSale(
        totalAmount: 12600,
        totalModal: 9100,
        totalProfit: 3500,
        quantity: 0.7,
        subtotal: 12600,
      ),
    ]);

    row = (await database.query('sales', where: 'id = ?', whereArgs: ['sale-1']))
        .single;
    expect(row['total_amount'], 12600,
        reason: 'total_amount harus mengikuti koreksi owner');
    expect(row['total_modal'], 9100);
    expect(row['total_profit'], 3500);

    item = (await database
            .query('sale_items', where: 'sale_id = ?', whereArgs: ['sale-1']))
        .single;
    expect(item['quantity'], 0.7,
        reason: 'berat item harus mengikuti koreksi owner');
    expect(item['subtotal'], 12600);
  });

  test('baris sale_items lama tidak menumpuk setelah koreksi', () async {
    final db = AppDatabase.instance;
    final database = await db.database;

    await db.sales.upsertFromServer([buildSale()]);
    await db.sales.upsertFromServer([
      buildSale(
        totalAmount: 12600,
        totalModal: 9100,
        totalProfit: 3500,
        quantity: 0.7,
        subtotal: 12600,
      ),
    ]);

    final items = await database
        .query('sale_items', where: 'sale_id = ?', whereArgs: ['sale-1']);
    expect(items.length, 1,
        reason: 'hanya boleh ada satu baris item per transaksi');
  });

  test('item yang dihapus owner ikut hilang dari perangkat', () async {
    final db = AppDatabase.instance;
    final database = await db.database;

    await db.sales.upsertFromServer([buildSale()]);
    expect(
      await database
          .query('sale_items', where: 'sale_id = ?', whereArgs: ['sale-1']),
      hasLength(1),
    );

    // Owner menghapus seluruh item dari baris penjualan.
    final tanpaItem = Sale(
      id: 'sale-1',
      transactionNumber: 'TRX-20260930-77A',
      employeeId: 'emp-1',
      employeeName: 'Erlina',
      totalAmount: 0,
      totalModal: 0,
      totalProfit: 0,
      status: 'COMPLETED',
      createdAt: '2026-09-30T05:24:45.469840Z',
    );
    await db.sales.upsertFromServer([tanpaItem]);

    expect(
      await database
          .query('sale_items', where: 'sale_id = ?', whereArgs: ['sale-1']),
      isEmpty,
      reason: 'item yang dihapus owner tidak boleh tetap tampil di kasir',
    );
  });

  test('perubahan status tetap diteruskan seperti sebelumnya', () async {
    final db = AppDatabase.instance;
    final database = await db.database;

    await db.sales.upsertFromServer([buildSale()]);
    await db.sales.upsertFromServer([
      buildSale(totalAmount: 14400, totalModal: 10400, totalProfit: 4000,
          status: 'CANCELLED'),
    ]);

    final row = (await database.query('sales', where: 'id = ?', whereArgs: ['sale-1']))
        .single;
    expect(row['status'], 'CANCELLED',
        reason: 'regresi: pembatalan oleh owner harus tetap masuk ke kasir');
  });

  test('penjualan lokal yang masih PENDING tidak ditimpa server', () async {
    final db = AppDatabase.instance;
    final database = await db.database;

    // Transaksi dibuat di perangkat ini dan belum sempat terkirim.
    await database.insert('sales', {
      'id': 'sale-pending',
      'transaction_number': 'TRX-LOKAL-1',
      'total_amount': 5000,
      'total_modal': 3000,
      'total_profit': 2000,
      'status': 'COMPLETED',
      'sync_status': 'PENDING',
    });

    await db.sales.upsertFromServer([
      buildSale(
        id: 'sale-pending',
        transactionNumber: 'TRX-LOKAL-1',
        totalAmount: 9999,
        totalModal: 9999,
        totalProfit: 0,
      ),
    ]);

    final row = (await database
            .query('sales', where: 'id = ?', whereArgs: ['sale-pending']))
        .single;
    expect(row['total_amount'], 5000,
        reason: 'transaksi PENDING belum ada di server, tidak boleh ditimpa');
    expect(row['sync_status'], 'PENDING');
  });

  test('koreksi jam di server ikut diterima walau nominal tidak berubah', () async {
    // `created_at` ikut dibandingkan supaya koreksi jam di server diterima
    // walau nominalnya sama persis. Transaksi offline pernah masuk dengan jam
    // LOKAL perangkat lalu dilabeli `Z` server, jadi tampil meleset 7 jam di
    // Owner Console. Kalau perbandingan ini tidak ada, tanggal salahnya
    // menempel selamanya di HP.
    final db = AppDatabase.instance;
    await db.sales.upsertFromServer([
      buildSale(
        createdAt: '2026-09-30T23:45:06.869018Z',
        totalAmount: 36000,
        totalModal: 29850,
        totalProfit: 6150,
        quantity: 0.75,
        subtotal: 36000,
        productName: 'Anggur Hijau',
      ),
    ]);
    var tersimpan = (await db.sales.getSales(limit: 10))
        .firstWhere((s) => s.id == 'sale-1');
    expect(tersimpan.createdAt, '2026-09-30T23:45:06.869018Z');

    await db.sales.upsertFromServer([
      buildSale(
        // 16:45 UTC = 23:45 WIB: waktu yang benar untuk sale yang sama.
        createdAt: '2026-09-30T16:45:06.869018Z',
        totalAmount: 36000,
        totalModal: 29850,
        totalProfit: 6150,
        quantity: 0.75,
        subtotal: 36000,
        productName: 'Anggur Hijau',
      ),
    ]);
    tersimpan = (await db.sales.getSales(limit: 10))
        .firstWhere((s) => s.id == 'sale-1');
    expect(tersimpan.createdAt, '2026-09-30T16:45:06.869018Z');
    expect(tersimpan.totalAmount, 36000);
  });

  test('waktu yang sama tidak memicu tulis ulang berulang', () async {
    // Kalau perbandingan created_at tidak stabil, setiap pull akan menulis ulang
    // baris yang sama dan `changed` selalu true -- daftar di HP lalu berkedip
    // tiap 30 detik.
    final db = AppDatabase.instance;
    final sale = buildSale(
      totalAmount: 36000,
      totalModal: 29850,
      totalProfit: 6150,
      quantity: 0.75,
      subtotal: 36000,
      productName: 'Anggur Hijau',
    );
    await db.sales.upsertFromServer([sale]);
    await db.sales.upsertFromServer([buildSale(
      totalAmount: 36000,
      totalModal: 29850,
      totalProfit: 6150,
      quantity: 0.75,
      subtotal: 36000,
      productName: 'Anggur Hijau',
    )]);
    final semua = await db.sales.getSales(limit: 10);
    expect(semua.length, 1, reason: 'tidak boleh membuat baris ganda');
  });

  test('perbedaan pembulatan float tidak memicu tulis ulang', () async {
    final db = AppDatabase.instance;
    final database = await db.database;

    await db.sales.upsertFromServer([buildSale()]);
    final before = (await database
            .query('sales', where: 'id = ?', whereArgs: ['sale-1']))
        .single;
    final itemCountBefore = (await database
            .query('sale_items', where: 'sale_id = ?', whereArgs: ['sale-1']))
        .length;

    // Nilai sama secara riil, representasi REAL sedikit berbeda.
    await db.sales.upsertFromServer([
      buildSale(totalAmount: 14400.0, totalModal: 10400.0, totalProfit: 4000.0),
    ]);

    final after = (await database
            .query('sales', where: 'id = ?', whereArgs: ['sale-1']))
        .single;
    expect(after['total_amount'], before['total_amount']);
    expect(
      (await database
              .query('sale_items', where: 'sale_id = ?', whereArgs: ['sale-1']))
          .length,
      itemCountBefore,
    );
  });
}
