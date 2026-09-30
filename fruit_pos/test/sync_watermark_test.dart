import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../lib/api/api_client.dart';
import '../lib/api/api_service.dart';
import '../lib/core/constants.dart';
import '../lib/database/app_database.dart';
import '../lib/sync/connectivity_service.dart';
import '../lib/sync/sync_manager.dart';

/// Regresi untuk bug watermark sinkronisasi.
///
/// `last_sync_at` pernah ditulis ulang ke SharedPreferences SEBUNYA pull,
/// dengan nilai jam perangkat. Satu pull yang gagal -- misalnya 401 saat app
/// start sebelum login -- sudah cukup untuk membuat `last_sync_at` melompat ke
/// "sekarang". Server menyaring dengan `updated_at >= last_sync_at`, jadi
/// seluruh riwayat transaksi yang lebih lama langsung tersaring dan tidak
/// pernah dikirim lagi, selamanya di perangkat itu.
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

  /// Server tiruan dengan kendali penuh atas isi respons /sync/pull.
  Future<HttpServer> startServer({
    required int Function() pullHandler,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final path = req.uri.path;
      if (path.endsWith('/sync/pull')) {
        final status = pullHandler();
        req.response.statusCode = status;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'detail': 'gagal'}));
        await req.response.close();
        return;
      }
      if (path.endsWith('/sync/push')) {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'results': []}));
        await req.response.close();
        return;
      }
      req.response.statusCode = 404;
      req.response.headers.contentType = ContentType.json;
      req.response.write('{}');
      await req.response.close();
    });
    return server;
  }

  SyncManager buildManager(int port) {
    final api = ApiService(ApiClient(baseUrl: 'http://127.0.0.1:$port/api/v1'));
    final db = AppDatabase.instance;
    final connectivity = ConnectivityService();
    connectivity.isOnline.value = true;
    return SyncManager(
      apiService: api,
      outboxDao: db.outbox,
      productsDao: db.products,
      salesDao: db.sales,
      damageDao: db.damage,
      connectivity: connectivity,
    );
  }

  test('pull GAGAL tidak boleh memajukan last_sync_at', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.prefLastSync: '2026-09-30T00:00:00.000Z',
    });

    final server = await startServer(pullHandler: () => 500);
    addTearDown(() async => server.close(force: true));

    final sync = buildManager(server.port);
    addTearDown(sync.dispose);
    await sync.syncNow(forcePull: true);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(AppConstants.prefLastSync),
      '2026-09-30T00:00:00.000Z',
      reason: 'watermark hanya boleh maju kalau pull benar-benar sukses',
    );
  });

  test('pull 401 sebelum login tidak boleh mengunci watermark', () async {
    SharedPreferences.setMockInitialValues({});

    final server = await startServer(pullHandler: () => 401);
    addTearDown(() async => server.close(force: true));

    final sync = buildManager(server.port);
    addTearDown(sync.dispose);
    // Skenario nyata: app start -> sync jalan sebelum token ada.
    await sync.syncNow(forcePull: true);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(AppConstants.prefLastSync),
      isNull,
      reason: 'gagal 401 saat startup tidak boleh mengunci data selamanya',
    );
  });

  test('pull sukses memakai server_time, bukan jam perangkat', () async {
    SharedPreferences.setMockInitialValues({});

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));
    const serverTime = '2026-09-30T05:24:45.469840Z';
    server.listen((req) async {
      if (req.uri.path.endsWith('/sync/pull')) {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'products': <dynamic>[],
          'categories': <dynamic>[],
          'damage_reports': <dynamic>[],
          'stock_movements': <dynamic>[],
          'sales': <dynamic>[],
          'sales_complete': true,
          'app_settings': <dynamic>[],
          'server_time': serverTime,
        }));
        await req.response.close();
        return;
      }
      if (req.uri.path.endsWith('/sync/push')) {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'results': []}));
        await req.response.close();
        return;
      }
      req.response.statusCode = 404;
      req.response.headers.contentType = ContentType.json;
      req.response.write('{}');
      await req.response.close();
    });

    final sync = buildManager(server.port);
    addTearDown(sync.dispose);
    await sync.syncNow(forcePull: true);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(AppConstants.prefLastSync),
      serverTime,
      reason: 'jam perangkat bisa meleset dan harus dipakai jam server',
    );
  });

  test('forcePull saat sync lain jalan tetap dijalankan', () async {
    SharedPreferences.setMockInitialValues({});

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async => server.close(force: true));
    var pullCount = 0;
    server.listen((req) async {
      if (req.uri.path.endsWith('/sync/pull')) {
        pullCount++;
        // Slowdown supaya sync kedua sempat datang saat yang pertama jalan.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'products': <dynamic>[],
          'categories': <dynamic>[],
          'damage_reports': <dynamic>[],
          'stock_movements': <dynamic>[],
          'sales': <dynamic>[],
          'sales_complete': true,
          'app_settings': <dynamic>[],
          'server_time': '2026-09-30T05:24:45.469840Z',
        }));
        await req.response.close();
        return;
      }
      if (req.uri.path.endsWith('/sync/push')) {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'results': []}));
        await req.response.close();
        return;
      }
      req.response.statusCode = 404;
      req.response.headers.contentType = ContentType.json;
      req.response.write('{}');
      await req.response.close();
    });

    final sync = buildManager(server.port);
    addTearDown(sync.dispose);

    final first = sync.syncNow(forcePull: true);
    // Selagi sync pertama jalan, login memanggil forcePull lagi.
    final second = sync.syncNow(forcePull: true);
    await Future.wait([first, second]);
    // Beri waktu queued forcePull selesai.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(
      pullCount,
      greaterThanOrEqualTo(2),
      reason: 'forcePull tidak boleh dibuang diam-diam saat sync lain jalan',
    );
  });
}
