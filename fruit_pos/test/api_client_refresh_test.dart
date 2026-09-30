import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fruit_pos/api/api_client.dart';
import 'package:fruit_pos/api/api_exception.dart';
import 'package:fruit_pos/api/api_service.dart';

/// Server tiruan yang meniru perilaku token backend: access token berumur
/// pendek, refresh token me-*rotate* setiap kali dipakai, dan 401 kalau
/// bearer token yang dikirim tidak cocok.
class _FakeAuthServer {
  _FakeAuthServer(this._server);

  final HttpServer _server;
  String validAccess = 'access-2';
  String validRefresh = 'refresh-2';
  bool refreshAllowed = true;

  int dashboardCalls = 0;
  int refreshCalls = 0;
  int loginCalls = 0;

  final List<String?> seenAccessHeaders = [];

  String get baseUrl => 'http://127.0.0.1:${_server.port}/api/v1';

  String? _bearer(HttpRequest req) {
    final h = req.headers.value(HttpHeaders.authorizationHeader);
    if (h == null || !h.startsWith('Bearer ')) return null;
    return h.substring(7);
  }

  Future<void> _json(HttpResponse res, int status, Object body) async {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    await res.close();
  }

  Map<String, dynamic> _tokenBody() => {
        'access_token': validAccess,
        'refresh_token': validRefresh,
        'token_type': 'bearer',
        'user': {
          'id': 'u1',
          'username': 'pytest_bos',
          'full_name': 'Budi',
          'role': 'BOS',
          'is_active': true,
        },
      };

  Future<void> start() async {
    _server.listen((req) async {
      final path = req.uri.path;
      if (path == '/api/v1/reports/dashboard') {
        dashboardCalls++;
        final bearer = _bearer(req);
        seenAccessHeaders.add(bearer);
        if (bearer != validAccess) {
          await _json(req.response, 401, {'detail': 'Token tidak valid atau telah kedaluwarsa'});
          return;
        }
        await _json(req.response, 200, {'revenue': 10, 'total_transactions': 2});
        return;
      }
      if (path == '/api/v1/auth/refresh') {
        refreshCalls++;
        final body = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        if (!refreshAllowed || body['refresh_token'] != validRefresh) {
          await _json(req.response, 401, {'detail': 'Refresh token tidak valid'});
          return;
        }
        // rotasi: token lama langsung tidak berlaku lagi
        validAccess = 'access-${dashboardCalls}-${refreshCalls}';
        validRefresh = 'refresh-${dashboardCalls}-${refreshCalls}';
        await _json(req.response, 200, _tokenBody());
        return;
      }
      if (path == '/api/v1/auth/login') {
        loginCalls++;
        await _json(req.response, 401, {'detail': 'Username atau password salah'});
        return;
      }
      await _json(req.response, 404, {'detail': 'not found'});
    });
  }

  Future<void> stop() => _server.close(force: true);
}

Future<_FakeAuthServer> _startServer() async {
  final server = _FakeAuthServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
  await server.start();
  return server;
}

void main() {
  group('ApiClient 401 auto-refresh', () {
    late _FakeAuthServer server;

    setUp(() async => server = await _startServer());
    tearDown(() async => server.stop());

    test('401 lalu refresh sukses: request yang sama diulang dengan token baru', () async {
      final client = ApiClient(baseUrl: server.baseUrl)
        ..setTokens(access: 'access-1', refresh: 'refresh-1');
      server
        ..validAccess = 'access-2'
        ..validRefresh = 'refresh-1';

      final data = await ApiService(client).fetchDashboard();

      expect(data['revenue'], 10);
      expect(server.dashboardCalls, 2);
      expect(server.refreshCalls, 1);
      expect(client.accessToken, server.validAccess);
      expect(client.refreshToken, server.validRefresh);
    });

    test('token hasil rotasi diteruskan ke storage lewat onTokensRefreshed', () async {
      final client = ApiClient(baseUrl: server.baseUrl)
        ..setTokens(access: 'access-1', refresh: 'refresh-1');
      server
        ..validAccess = 'access-2'
        ..validRefresh = 'refresh-1';

      String? savedAccess;
      String? savedRefresh;
      client.onTokensRefreshed = (a, r) {
        savedAccess = a;
        savedRefresh = r;
      };

      await ApiService(client).fetchDashboard();

      expect(savedAccess, server.validAccess);
      expect(savedRefresh, server.validRefresh);
      expect(savedRefresh, isNot('refresh-1'),
          reason: 'refresh token lama harus diganti, kalau tidak sesi mati di restart');
    });

    test('refresh ditolak: onSessionExpired terpanggil dan 401 diteruskan', () async {
      final client = ApiClient(baseUrl: server.baseUrl)
        ..setTokens(access: 'access-1', refresh: 'refresh-mati');

      var expired = false;
      client.onSessionExpired = () => expired = true;

      await expectLater(
        ApiService(client).fetchDashboard(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
      expect(expired, isTrue, reason: 'user harus diminta login ulang');
      expect(client.accessToken, isNull);
      expect(client.refreshToken, isNull);
      expect(server.dashboardCalls, 1,
          reason: 'tidak mengulang request yang pasti tetap 401');
    });

    test('beberapa 401 paralel hanya memicu satu refresh', () async {
      final client = ApiClient(baseUrl: server.baseUrl)
        ..setTokens(access: 'access-1', refresh: 'refresh-1');
      server
        ..validAccess = 'access-2'
        ..validRefresh = 'refresh-1';

      await Future.wait([
        ApiService(client).fetchDashboard(),
        ApiService(client).fetchDashboard(),
        ApiService(client).fetchDashboard(),
      ]);

      expect(server.refreshCalls, 1, reason: 'refresh harus single-flight');
      expect(server.dashboardCalls, 6);
    });

    test('endpoint auth tidak memicu refresh (tidak ada loop)', () async {
      final client = ApiClient(baseUrl: server.baseUrl)
        ..setTokens(access: 'access-1', refresh: 'refresh-1');

      await expectLater(
        ApiService(client).refresh(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
      expect(server.refreshCalls, 1);
    });

    test('login 401 tidak memicu refresh dan pesannya tetap apa adanya', () async {
      final client = ApiClient(baseUrl: server.baseUrl)
        ..setTokens(access: 'access-1', refresh: 'refresh-1');

      await expectLater(
        ApiService(client).login('salah', 'salah'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', contains('Username atau password salah'))),
      );
      expect(server.refreshCalls, 0, reason: 'kredensial salah bukan masalah token kadaluwarsa');
    });

    test('tanpa refresh token, 401 langsung tanpa menandai sesi expired', () async {
      final client = ApiClient(baseUrl: server.baseUrl);
      var expired = false;
      client.onSessionExpired = () => expired = true;

      await expectLater(
        ApiService(client).fetchDashboard(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
      expect(expired, isFalse);
      expect(server.refreshCalls, 0);
    });

    test('server tidak terjangkau dibedakan sebagai error jaringan', () async {
      final client = ApiClient(baseUrl: 'http://127.0.0.1:1/api/v1')
        ..setTokens(access: 'a', refresh: 'b');

      await expectLater(
        ApiService(client).fetchDashboard(),
        throwsA(isA<ApiException>().having((e) => e.isNetworkError, 'isNetworkError', isTrue)),
      );
    });
  });
}
