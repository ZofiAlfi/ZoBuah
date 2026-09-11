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

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    try {
      final res = await http
          .get(_uri(path, query), headers: _authHeaders())
          .timeout(const Duration(seconds: 15));
      return _handle(res);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw NetworkException('Tidak dapat terhubung ke server', cause: e);
    }
  }

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) async {
    try {
      final res = await http
          .post(_uri(path, query),
              headers: _authHeaders(), body: jsonEncode(body ?? {}))
          .timeout(const Duration(seconds: 20));
      return _handle(res);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw NetworkException('Tidak dapat terhubung ke server', cause: e);
    }
  }

  Future<dynamic> put(String path, {Object? body}) async {
    try {
      final res = await http
          .put(_uri(path), headers: _authHeaders(), body: jsonEncode(body ?? {}))
          .timeout(const Duration(seconds: 20));
      return _handle(res);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw NetworkException('Tidak dapat terhubung ke server', cause: e);
    }
  }

  Future<dynamic> delete(String path) async {
    try {
      final res = await http
          .delete(_uri(path), headers: _authHeaders())
          .timeout(const Duration(seconds: 20));
      return _handle(res);
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