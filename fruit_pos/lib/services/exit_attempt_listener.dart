import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth/auth_state.dart';

/// Mendengarkan event native "pengguna mencoba keluar" (klik Home / notifikasi
/// / pintasan sistem). Menyimpan tanda agar CashierHome menampilkan dialog PIN
/// keluar ketika aplikasi kembali ke foreground.
/// Jika PIN benar -> keluar (logout). Jika dibatalkan -> tetap terkunci.
class ExitAttemptListener extends StatefulWidget {
  const ExitAttemptListener({super.key, required this.child});

  final Widget child;

  /// Naik saat ada usaha keluar (Home, dll.) dipicu native; dibaca oleh
  /// CashierHome ketika aplikasi kembali ke foreground agar menampilkan
  /// dialog PIN sebelum melanjutkan.
  static bool pendingExitGate = false;

  @override
  State<ExitAttemptListener> createState() => _ExitAttemptListenerState();
}

class _ExitAttemptListenerState extends State<ExitAttemptListener> {
  static const MethodChannel _channel = MethodChannel('com.fruitpos/locktask');

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_onMethodCall);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method != 'leaveAttempted') return null;
    debugPrint(
      '[ExitAttemptListener] leaveAttempted '
      'karyawan=${context.read<AuthState>().user?.isKaryawan}',
    );
    if (!mounted) return null;
    if (context.read<AuthState>().user?.isKaryawan != true) return null;
    ExitAttemptListener.pendingExitGate = true;
    return null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
