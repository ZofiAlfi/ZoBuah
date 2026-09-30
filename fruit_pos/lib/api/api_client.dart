import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient({String? baseUrl}) : _baseUrl = baseUrl ?? AppConstants.apiV1;

  final String _baseUrl;
  String? accessToken;
  String? refreshToken;

  /// Dipanggil saat sesi benar-benar habis: refresh token juga ditolak
  /// server (dicabut, atau akun dinonaktifkan). Lapisan auth yang
  /// memutuskan apa yang terjadi selanjutnya, bukan lapisan HTTP.
  void Function()? onSessionExpired;

  /// Dipanggil setiap kali server memberi token baru. Backend me-*rotate*
  /// refresh token, jadi token yang baru harus segera ditulis ke storage;
  /// kalau tidak, sesi akan mati lagi di restart berikutnya.
  void Function(String access, String refresh)? onTokensRefreshed;

  /// Refresh yang sedang berjalan. Beberapa request bisa 401 bersamaan
  /// (sync + dashboard + pull_notices), jadi perpanjangan dikunci supaya
  /// hanya satu yang menembak server.
  Future<bool>? _refreshing;

  final Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  void setTokens({String? access, String? refresh}) {
    accessToken = access;
    refreshToken = refresh;
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final uri = Uri.parse('$_baseUrl$path');
    if (query != null && query.isNotEmpty) {
      return uri.replace(queryParameters: query.map((k, v) => MapEntry(k, '$v')));
    }
    return uri;
  }

  Map<String, String> _authHeaders() {
    final h = Map<String, String>.from(_headers);
    if (accessToken != null && accessToken!.isNotEmpty) {
      h['Authorization'] = 'Bearer $accessToken';
    }
    return h;
  }

  /// Perpanjang sesi dengan refresh token.
  ///
  /// Balas false BUKAN berarti sesi sudah invalid: kalau request-nya gagal
  /// karena jaringan, pemanggil sebaiknya tetap memperlakukan device sebagai
  /// offline, bukan memaksa user login ulang.
  Future<bool> _refreshSession() {
    _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
    return _refreshing!;
  }

  Future<bool> _doRefresh() async {
    final token = refreshToken;
    if (token == null || token.isEmpty) return false;
    try {
      final res = await http
          .post(
            _uri('/auth/refresh'),
            headers: _headers,
            body: jsonEncode({'refresh_token': token}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        _expireSession();
        return false;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final access = body['access_token'] as String?;
      if (access == null || access.isEmpty) {
        _expireSession();
        return false;
      }
      accessToken = access;
      refreshToken = body['refresh_token'] as String? ?? refreshToken;
      onTokensRefreshed?.call(accessToken!, refreshToken!);
      return true;
    } catch (_) {
      // Gagal jaringan saat refresh: biarkan token apa adanya, pemanggil
      // yang akan jatuh ke mode offline.
      return false;
    }
  }

  void _expireSession() {
    accessToken = null;
    refreshToken = null;
    onSessionExpired?.call();
  }

  /// Kirim request; kalau server membalas 401 dan masih ada refresh token,
  /// perpanjang sesi sekali lalu ulangi request yang sama.
  ///
  /// Endpoint auth tidak ikut di-refresh: `/auth/login` 401 artinya kredensial
  /// salah, dan `/auth/refresh` yang 401 justru causes yang sedang dicari.
  Future<dynamic> _send(
    String path,
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    var res = await request(_authHeaders());
    final canRefresh = !path.startsWith('/auth/login') && !path.startsWith('/auth/refresh');
    if (res.statusCode == 401 && canRefresh) {
      if (refreshToken != null && refreshToken!.isNotEmpty && await _refreshSession()) {
        res = await request(_authHeaders());
      }
    }
    return _handle(res);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    try {
      return await _send(
        path,
        (headers) =>
            http.get(_uri(path, query), headers: headers).timeout(const Duration(seconds: 15)),
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw NetworkException('Tidak dapat terhubung ke server', cause: e);
    }
  }

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) async {
    try {
      return await _send(
        path,
        (headers) => http
            .post(_uri(path, query),
                headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 20)),
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw NetworkException('Tidak dapat terhubung ke server', cause: e);
    }
  }

  Future<dynamic> put(String path, {Object? body}) async {
    try {
      return await _send(
        path,
        (headers) => http
            .put(_uri(path), headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 20)),
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw NetworkException('Tidak dapat terhubung ke server', cause: e);
    }
  }

  Future<dynamic> delete(String path) async {
    try {
      return await _send(
        path,
        (headers) =>
            http.delete(_uri(path), headers: headers).timeout(const Duration(seconds: 20)),
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw NetworkException('Tidak dapat terhubung ke server', cause: e);
    }
  }

  Future<dynamic> postFormData(String path, Map<String, dynamic> fields,
      {Map<String, http.MultipartFile>? files}) async {
    try {
      final request = http.MultipartRequest('POST', _uri(path));
      request.headers.addAll(_authHeaders());
      fields.forEach((k, v) => request.fields[k] = '$v');
      files?.forEach((k, v) => request.files.add(v));
      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final res = await http.Response.fromStream(streamed);
      return _handle(res);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw NetworkException('Tidak dapat terhubung ke server', cause: e);
    }
  }

  dynamic _handle(http.Response res) {
    final body = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }
    String message = 'Terjadi kesalahan pada server';
    if (body is Map && body['detail'] != null) {
      message = body['detail'].toString();
    }
    throw ApiException(res.statusCode, message);
  }
}
