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
      final pendingCountBefore = await outboxDao.countPending();

      if (pendingCountBefore > 0 || forcePull || lastSync == null) {
        await _push();
        await _pull(deviceId ?? '', lastSync);
        await prefs.setString(AppConstants.prefLastSync, DateTime.now().toUtc().toIso8601String());
        await outboxDao.removeSynced();
      }
    } catch (e) {
      debugPrint('Sync gagal: $e');
    } finally {
      await refreshPendingCount();
      isSyncing.value = false;
      notifyListeners();
    }
  }

  Future<void> _push() async {
    final entries = await outboxDao.getPending(limit: 50);
    if (entries.isEmpty) return;

    final items = entries
        .map((e) => SyncPushEntity(
              entityType: e.entityType,
              entityId: e.entityId,
              data: jsonDecode(e.data) as Map<String, dynamic>,
            ))
        .toList();

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
        } else if (status == 'duplicate') {
          await outboxDao.markSynced(entry.id!);
        } else {
          await outboxDao.markFailed(entry.id!);
        }
      }
    } catch (e) {
      debugPrint('Push gagal: $e');
    }
  }

  Future<void> _pull(String deviceId, String? lastSync) async {
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
      }

      final categories = data['categories'] as List;
      if (categories.isNotEmpty) {
        final parsed = categories
            .map((c) => Category.fromJson(c as Map<String, dynamic>))
            .toList();
        await productsDao.upsertAllCategories(parsed);
      }

      final damages = data['damage_reports'] as List;
      if (damages.isNotEmpty) {
        final parsed = damages
            .map((d) => DamageReport.fromJson(d as Map<String, dynamic>))
            .toList();
        await damageDao.upsertAll(parsed);
      }

      final sales = data['sales'] as List? ?? [];
      if (sales.isNotEmpty) {
        final parsed = sales
            .map((s) => Sale.fromJson(s as Map<String, dynamic>))
            .toList();
        await salesDao.upsertFromServer(parsed);
      }

      final from = lastSync;
      if (from != null) {
        // Putuskan di server; di sini update saja data yang ada
      }
    } catch (e) {
      debugPrint('Pull gagal: $e');
    }
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