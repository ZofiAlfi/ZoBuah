import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../api/api_service.dart';
import '../../core/theme.dart';

/// Dialog keluar (karyawan): wajib memasukkan PIN keluar.
/// PIN default 123456 (bisa diubah BOS). Alternatif: minta PIN sekali pakai
/// ke BOS. Berhasil => pop(true) sebagai tanda diizinkan keluar.
class ExitPinDialog extends StatefulWidget {
  const ExitPinDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ExitPinDialog(),
    );
    return result ?? false;
  }

  @override
  State<ExitPinDialog> createState() => _ExitPinDialogState();
}

class _ExitPinDialogState extends State<ExitPinDialog> {
  final _pinCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _otpRequested = false;
  String? _requestMessage;

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _verifyPin() async {
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty || pin.length < 4) {
      setState(() => _error = 'PIN minimal 4 karakter');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<ApiService>().verifyExitPin(pin);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Gagal verifikasi PIN');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestOtp() async {
    if (_otpRequested) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await context.read<ApiService>().requestExitOtp();
      setState(() {
        _requestMessage =
            res['message']?.toString() ??
            'PIN sekali pakai dikirim ke BOS. Masukkan PIN dari BOS untuk keluar.';
        _otpRequested = true;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Gagal meminta PIN ke server');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_loading) return;
        Navigator.of(context).pop(false);
      },
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock_outline, color: AppColors.primary),
            SizedBox(width: 10),
            Text('Keluar Aplikasi'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Masukkan PIN keluar untuk izin keluar dari aplikasi kasir.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('exit_pin_field'),
              controller: _pinCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
              style: const TextStyle(fontSize: 20, letterSpacing: 6),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'PIN (default 123456)',
                counterText: '',
                prefixIcon: const Icon(Icons.pin, size: 18),
                errorText: _error,
              ),
              onSubmitted: _loading ? null : (_) => _verifyPin(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 46,
              child: ElevatedButton(
                key: const Key('exit_confirm'),
                onPressed: _loading ? null : _verifyPin,
                child: const Text('KELUAR'),
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'atau',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _loading || _otpRequested ? null : _requestOtp,
                icon: const Icon(Icons.send, size: 18),
                label: const Text(
                  'Minta PIN ke BOS',
                  style: TextStyle(fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primary),
                  foregroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (_otpRequested && _requestMessage != null) ...[
              const SizedBox(height: 10),
              Container(
                key: const Key('otp_sent_note'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppColors.primary,
                          size: 18,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'PIN dikirim ke BOS',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _requestMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
  }
}
