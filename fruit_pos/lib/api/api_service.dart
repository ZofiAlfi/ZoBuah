import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/category.dart';
import '../models/damage_report.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/stock_movement.dart';
import '../models/user.dart';
import 'api_client.dart';

MediaType _photoMediaType(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return MediaType('image', 'jpeg');
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return MediaType('image', 'png');
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return MediaType('image', 'gif');
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return MediaType('image', 'webp');
  }
  return MediaType('image', 'jpeg');
}

class AuthResult {
  final String accessToken;
  final String refreshToken;
  final User user;

  AuthResult({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });
}

class ApiService {
  final ApiClient client;

  ApiService(this.client);

  Future<AuthResult> login(String username, String password) async {
    final res = await client.post(
      '/auth/login',
      body: {'username': username, 'password': password},
    );
    final access = res['access_token'] as String;
    final refresh = res['refresh_token'] as String;
    client.setTokens(access: access, refresh: refresh);
    return AuthResult(
      accessToken: access,
      refreshToken: refresh,
      user: User.fromJson(res['user'] as Map<String, dynamic>),
    );
  }

  Future<AuthResult> refresh() async {
    final res = await client.post(
      '/auth/refresh',
      body: {'refresh_token': client.refreshToken ?? ''},
    );
    final access = res['access_token'] as String;
    final refresh = res['refresh_token'] as String;
    client.setTokens(access: access, refresh: refresh);
    return AuthResult(
      accessToken: access,
      refreshToken: refresh,
      user: User.fromJson(res['user'] as Map<String, dynamic>),
    );
  }

  Future<List<Product>> fetchProducts({String search = ''}) async {
    final res = await client.get('/products', query: {'search': search});
    return (res as List)
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Category>> fetchCategories() async {
    final res = await client.get('/products/categories');
    return (res as List)
        .map((e) => Category.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> body) async {
    return await client.post('/products', body: body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateProduct(
    String id,
    Map<String, dynamic> body,
  ) async {
    return await client.put('/products/$id', body: body)
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createCategory(Map<String, dynamic> body) async {
    return await client.post('/products/categories', body: body)
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createSale(Map<String, dynamic> body) async {
    return await client.post('/sales', body: body) as Map<String, dynamic>;
  }

  Future<List<Sale>> fetchSales({String? from, String? to}) async {
    final res = await client.get(
      '/sales',
      query: {
        if (from != null) 'date_from': from,
        if (to != null) 'date_to': to,
      },
    );
    return (res as List)
        .map((e) => Sale.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> fetchSale(String id) async {
    final res = await client.get('/sales/$id');
    return res as Map<String, dynamic>;
  }

  Future<List<Product>> fetchStock(String search) async {
    final res = await client.get('/stock');
    return (res as List)
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> stockIn(Map<String, dynamic> body) async {
    return await client.post('/stock/in', body: body) as Map<String, dynamic>;
  }

  Future<List<StockMovement>> fetchStockMovements({String? productId}) async {
    final res = await client.get(
      '/stock/movements',
      query: {if (productId != null) 'product_id': productId, 'limit': '200'},
    );
    return (res as List)
        .map((e) => StockMovement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> createDamageReport(
    Map<String, dynamic> body,
  ) async {
    return await client.post('/damage-reports', body: body)
        as Map<String, dynamic>;
  }

  Future<List<DamageReport>> fetchDamageReports({
    String? status,
    String? from,
    String? to,
  }) async {
    final res = await client.get(
      '/damage-reports',
      query: {
        if (status != null && status.isNotEmpty) 'status_filter': status,
        if (from != null) 'date_from': from,
        if (to != null) 'date_to': to,
      },
    );
    return (res as List)
        .map((e) => DamageReport.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> approveDamage(String id) async {
    return await client.post('/damage-reports/$id/approve', body: {})
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> rejectDamage(String id, String reason) async {
    return await client.post(
          '/damage-reports/$id/reject',
          body: {'reason': reason},
        )
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchDashboard() async {
    return await client.get('/reports/dashboard') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> syncPush(Map<String, dynamic> body) async {
    return await client.post('/sync/push', body: body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> syncPull({
    String? deviceId,
    String? lastSync,
  }) async {
    return await client.post(
          '/sync/pull',
          body: {'device_id': deviceId, 'last_sync_at': lastSync},
        )
        as Map<String, dynamic>;
  }

  Future<List<User>> fetchUsers() async {
    final res = await client.get('/auth/users');
    return (res as List)
        .map((e) => User.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> createUser(Map<String, dynamic> body) async {
    return await client.post('/auth/users', body: body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateUser(
    String id,
    Map<String, dynamic> body,
  ) async {
    return await client.put('/auth/users/$id', body: body)
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateCategory(
    String id,
    Map<String, dynamic> body,
  ) async {
    return await client.put('/products/categories/$id', body: body)
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deleteProduct(String id) async {
    return await client.delete('/products/$id') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> uploadProductPhoto(
    String id,
    Uint8List bytes,
    String filename,
  ) async {
    final file = http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: _photoMediaType(bytes),
    );
    return await client.postFormData(
          '/products/$id/photo',
          {},
          files: {'file': file},
        )
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deleteProductPhoto(String id) async {
    return await client.delete('/products/$id/photo') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> stockAdjustment(
    Map<String, dynamic> body,
  ) async {
    return await client.post('/stock/adjustment', body: body)
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchStockReport({
    String? from,
    String? to,
  }) async {
    final res = await client.get(
      '/reports/stock',
      query: {
        if (from != null) 'date_from': from,
        if (to != null) 'date_to': to,
      },
    );
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchProfitReport({
    String? from,
    String? to,
  }) async {
    final res = await client.get(
      '/reports/profit',
      query: {
        if (from != null) 'date_from': from,
        if (to != null) 'date_to': to,
      },
    );
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchReport(
    String endpoint, {
    String? dateStr,
    String? month,
  }) async {
    final res = await client.get(
      '/reports/$endpoint',
      query: {
        if (dateStr != null) 'date_str': dateStr,
        if (month != null) 'month': month,
      },
    );
    return res as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> fetchTopProducts({int limit = 10}) async {
    final res = await client.get(
      '/reports/top-products',
      query: {'limit': '$limit'},
    );
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchSalesByEmployee({
    String? from,
    String? to,
  }) async {
    final res = await client.get(
      '/reports/by-employee',
      query: {
        if (from != null) 'date_from': from,
        if (to != null) 'date_to': to,
      },
    );
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchAuditLogs({
    String? userId,
    String? action,
    String? from,
    String? to,
  }) async {
    final res = await client.get(
      '/audit/logs',
      query: {
        if (userId != null) 'user_id': userId,
        if (action != null) 'action': action,
        if (from != null) 'date_from': from,
        if (to != null) 'date_to': to,
      },
    );
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> fetchDamageReportSummary({
    String? from,
    String? to,
  }) async {
    final res = await client.get(
      '/reports/damage',
      query: {
        if (from != null) 'date_from': from,
        if (to != null) 'date_to': to,
      },
    );
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deleteCategory(String id) async {
    return await client.delete('/products/categories/$id')
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> requestExitOtp() async {
    return await client.post('/auth/exit/request', body: {})
        as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> fetchPendingExitOtps() async {
    final res = await client.get('/auth/exit/pending') as Map<String, dynamic>;
    final items = (res['items'] as List<dynamic>?) ?? const [];
    return items.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<Map<String, dynamic>> verifyExitPin(String pin) async {
    return await client.post('/auth/exit/verify', body: {'pin': pin})
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchSettings() async {
    return await client.get('/auth/settings') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateSettings({String? exitPin}) async {
    return await client.put(
          '/auth/settings',
          body: {if (exitPin != null) 'exit_pin': exitPin},
        )
        as Map<String, dynamic>;
  }
}
