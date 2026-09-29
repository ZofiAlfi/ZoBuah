import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_service.dart';
import '../core/constants.dart';
import '../database/outbox_dao.dart';
import '../database/products_dao.dart';
import '../database/sales_dao.dart';
import '../database/damage_dao.dart';
import '../models/category.dart';
import '../models/broadcast_notice.dart';
import '../models/damage_report.dart';
import '../models/product.dart';
import '../models/sale.dart' show Sale;

class SyncManager extends ChangeNotifier {
  final ApiService apiService;
  final OutboxDao outboxDao;
  final ProductsDao productsDao;
  final SalesDao salesDao;
  final DamageDao damageDao;
  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);
  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  /// Bertambah setiap sinkronisasi yang benar-benar mengubah data lokal
  /// (produk/kategori/penjualan/laporan rusak masuk, atau status outbox
  /// berubah).
  ///
  /// Halaman yang membaca DB lokal perlu listen ke sini. Nilai ini yang
  /// membuat daftar produk kasir ikut terisi sendiri setelah sync startup
  /// selesai: sebelumnya halaman hanya memuat sekali di initState, jadi
  /// produk baru dari server tidak pernah tampil sampai pengguna menekan
  /// tombol sync secara manual.
  final ValueNotifier<int> dataRevision = ValueNotifier<int>(0);

  /// Pengumuman owner yang aktif, urutan dari paling mendesak.
  ///
  /// Disimpan di SharedPreferences, bukan hanya di memori, supaya pengumuman
  /// tetap tampil saat app dibuka dalam keadaan offline.
  final ValueNotifier<List<BroadcastNotice>> notices =
      ValueNotifier<List<BroadcastNotice>>([]);

  Timer? _timer;
  String? _deviceId;

  SyncManager({
    required this.apiService,
    required this.outboxDao,
    required this.productsDao,
    required this.salesDao,
    required this.damageDao,
  });

  Future<String?> getDeviceId() async {
    if (_deviceId != null) return _deviceId;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(AppConstants.prefDeviceId);
    if (id == null) {
      id = await _generateAndroidDeviceId();
      await prefs.setString(AppConstants.prefDeviceId, id);
    }
    _deviceId = id;
    return id;
  }

  Future<String> _generateAndroidDeviceId() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return '${info.model}-${info.id}';
    } catch (e) {
      return 'd-${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  Future<void> startPeriodicSync({Duration interval = const Duration(seconds: 30)}) async {
    await syncNow(forcePull: true);
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => syncNow());
  }

  Future<void> syncNow({bool forcePull = false}) async {
    if (isSyncing.value) return;
    isSyncing.value = true;
    try {
      final deviceId = await getDeviceId();
      final prefs = await SharedPreferences.getInstance();
      final lastSync = prefs.getString(AppConstants.prefLastSync);
      var dataChanged = await _push();
      if (await _pull(deviceId ?? '', forcePull ? null : lastSync)) {
        dataChanged = true;
      }
      await prefs.setString(
          AppConstants.prefLastSync, DateTime.now().toUtc().toIso8601String());
      await outboxDao.removeSynced();
      if (dataChanged) _bumpDataRevision();
    } catch (e) {
      debugPrint('Sync gagal: $e');
    } finally {
      await refreshPendingCount();
      isSyncing.value = false;
      notifyListeners();
    }
  }

  void _bumpDataRevision() {
    dataRevision.value = dataRevision.value + 1;
  }

  /// Mengembalikan true kalau ada entri outbox yang berubah statusnya.
  Future<bool> _push() async {
    final entries = await outboxDao.getPending(limit: 50);
    if (entries.isEmpty) return false;

    final items = entries
        .map((e) => SyncPushEntity(
              entityType: e.entityType,
              entityId: e.entityId,
              data: jsonDecode(e.data) as Map<String, dynamic>,
            ))
        .toList();

    var changed = false;
    try {
      final result = await apiService.syncPush({
        'device_id': _deviceId,
        'items': items.map((e) => e.toJson()).toList(),
      });

      final results = result['results'] as List;
      for (final r in results) {
        final entityId = r['entity_id']?.toString();
        final status = r['status']?.toString();
        if (entityId == null) continue;
        final entry = entries.firstWhere(
            (e) => e.entityId == entityId,
            orElse: () => throw StateError('not found in list'));
        if (status == 'ok') {
          await outboxDao.markSynced(entry.id!);
          changed = true;
        } else if (status == 'duplicate') {
          await outboxDao.markSynced(entry.id!);
          changed = true;
        } else {
          await outboxDao.markFailed(entry.id!);
          changed = true;
        }
      }
    } catch (e) {
      debugPrint('Push gagal: $e');
    }
    return changed;
  }

  /// Mengembalikan true kalau ada tabel lokal yang ditulis hasil pull.
  Future<bool> _pull(String deviceId, String? lastSync) async {
    var changed = false;
    try {
      final data = await apiService.syncPull(
        deviceId: deviceId,
        lastSync: lastSync,
      );

      final products = data['products'] as List;
      if (products.isNotEmpty) {
        final parsed = products
            .map((p) => Product.fromJson(p as Map<String, dynamic>))
            .toList();
        await productsDao.upsertAllProducts(parsed);
        // Rekonsiliasi setelah upsert. Soft delete sudah sampai lewat
        // is_active, tapi produk yang dihapus keras sebelum migrasi 006 tidak
        // ada lagi di payload, jadi baris lamanya harus dinonaktifkan
        // manual. Kalau tidak, produk itu tetap tampil dan bisa dijual
        // selamanya di perangkat ini.
        await productsDao.deactivateMissingProducts(
          parsed.map((p) => p.id).toSet(),
        );
        changed = true;
      }

      final categories = data['categories'] as List;
      if (categories.isNotEmpty) {
        final parsed = categories
            .map((c) => Category.fromJson(c as Map<String, dynamic>))
            .toList();
        await productsDao.upsertAllCategories(parsed);
        await productsDao.deactivateMissingCategories(
          parsed.map((c) => c.id).toSet(),
        );
        changed = true;
      }

      final damages = data['damage_reports'] as List;
      if (damages.isNotEmpty) {
        final parsed = damages
            .map((d) => DamageReport.fromJson(d as Map<String, dynamic>))
            .toList();
        await damageDao.upsertAll(parsed);
        changed = true;
      }

      final sales = data['sales'] as List? ?? [];
      if (sales.isNotEmpty) {
        final parsed = sales
            .map((s) => Sale.fromJson(s as Map<String, dynamic>))
            .toList();
        await salesDao.upsertFromServer(parsed);
        changed = true;
      }

      await _applyNotices(data['app_settings']);
    } catch (e) {
      debugPrint('Pull gagal: $e');
    }
    return changed;
  }

  /// Baca pengumuman owner dari hasil pull.
  ///
  /// Field `app_settings` masih opsional di server supaya POS versi lama tidak
  /// error, jadi di sini wajib/absen keduanya ditangani diam-diam.
  Future<void> _applyNotices(dynamic raw) async {
    final prefs = await SharedPreferences.getInstance();

    // Field-nya tidak ada sama sekali: server terlalu tua untuk tahu soal
    // pengumuman. Yang tersimpan di perangkat yang dipakai, bukan dihapus.
    if (raw is! Map) {
      await _restoreNotices(prefs);
      return;
    }

    final parsed = <String, BroadcastNotice>{};
    raw.forEach((key, value) {
      if (value is Map) {
        parsed[key.toString()] =
            BroadcastNotice.fromJson(key.toString(), Map<String, dynamic>.from(value));
      }
    });

    // Server hanya mengirim yang belum kedaluwarsa, jadi daftar hasil pull
    // adalah daftar lengkap, bukan tambahan. Kalau owner sudah mencabut semua
    // pengumuman, hasil pull akan kosong dan yang harus dilakukan adalah
    // Membersihkan cache. Kalau cache lama justru dipulihkan di sini,
    // pengumuman yang sudah dicabut owner akan tetap nempel di layar POS.
    await prefs.remove(AppConstants.prefNotices);
    if (parsed.isEmpty) {
      _publish(const []);
      return;
    }

    await prefs.setString(AppConstants.prefNotices, jsonEncode({
      for (final entry in parsed.entries) entry.key: entry.value.toMap(),
    }));
    _publish(parsed.values);
  }

  /// Muat pengumuman tersimpan dari perangkat.
  ///
  /// Dipanggil sekali saat aplikasi start supaya pengumuman tetap tampil walau
  /// perangkat sedang offline dan pull belum pernah berhasil.
  Future<void> restoreNotices() async {
    await _restoreNotices(await SharedPreferences.getInstance());
  }

  Future<void> _restoreNotices(SharedPreferences prefs) async {
    final saved = prefs.getString(AppConstants.prefNotices);
    if (saved == null) {
      _publish(const []);
      return;
    }
    try {
      final decoded = jsonDecode(saved);
      if (decoded is! Map) {
        _publish(const []);
        return;
      }
      final parsed = <String, BroadcastNotice>{};
      decoded.forEach((key, value) {
        if (value is Map) {
          parsed[key.toString()] =
              BroadcastNotice.fromMap(key.toString(), Map<String, dynamic>.from(value));
        }
      });
      _publish(parsed.values);
    } catch (e) {
      // Payload rusak tidak boleh halt seluruh sync.
      debugPrint('Notifikasi owner gagal dibaca: $e');
      _publish(const []);
    }
  }

  void _publish(Iterable<BroadcastNotice> items) {
    final now = DateTime.now();
    final alive = items
        .where((n) => n.expiresAt == null || n.expiresAt!.isAfter(now))
        .toList()
      ..sort((a, b) {
        if (a.isUrgent != b.isUrgent) return a.isUrgent ? -1 : 1;
        final aAt = a.startsAt ?? DateTime(1970);
        final bAt = b.startsAt ?? DateTime(1970);
        return bAt.compareTo(aAt);
      });
    notices.value = alive;
  }

  Future<void> refreshPendingCount() async {
    pendingCount.value = await outboxDao.countPending();
  }

  Future<void> enqueueSale(String saleId, Map<String, dynamic> data) async {
    final exists = await outboxDao.hasEntity('sale', saleId);
    if (!exists) {
      await outboxDao.enqueue('sale', saleId, jsonEncode(data));
    }
    await refreshPendingCount();
  }

  Future<void> enqueueDamage(String reportId, Map<String, dynamic> data) async {
    final exists = await outboxDao.hasEntity('damage_report', reportId);
    if (!exists) {
      await outboxDao.enqueue('damage_report', reportId, jsonEncode(data));
    }
    await refreshPendingCount();
  }

  @override
  void dispose() {
    _timer?.cancel();
    isSyncing.dispose();
    pendingCount.dispose();
    notices.dispose();
    dataRevision.dispose();
    super.dispose();
  }
}

class SyncPushEntity {
  final String entityType;
  final String entityId;
  final Map<String, dynamic> data;

  SyncPushEntity({required this.entityType, required this.entityId, required this.data});

  Map<String, dynamic> toJson() => {
        'entity_type': entityType,
        'entity_id': entityId,
        'data': data,
      };
}