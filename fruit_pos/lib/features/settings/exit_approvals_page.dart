import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_service.dart';
import '../../api/api_exception.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../shared/widgets/common_widgets.dart';

/// BOS: daftar permintaan keluar karyawan yang menunggu.
/// PIN hanya muncul di sini, lalu BOS yang meneruskan ke karyawan.
class ExitApprovalsPage extends StatefulWidget {
  const ExitApprovalsPage({super.key});

  @override
  State<ExitApprovalsPage> createState() => _ExitApprovalsPageState();
}

class _ExitApprovalsPageState extends State<ExitApprovalsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await context.read<ApiService>().fetchPendingExitOtps();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Gagal mengambil data izin keluar');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Izin Keluar Karyawan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body:
          _loading
              ? const LoadingView()
              : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _items.isEmpty
              ? const EmptyView(message: 'Tidak ada permintaan izin keluar')
              : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final item in _items) _ApprovalCard(item: item),
                  ],
                ),
              ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ApprovalCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final requestedAt = (item['requested_at'] as num?)?.toDouble() ?? 0;
    final expiresAt = (item['expires_at'] as num?)?.toDouble() ?? 0;
    final expiresDto = DateTime.fromMillisecondsSinceEpoch(
      (expiresAt * 1000).round(),
      isUtc: true,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, color: AppColors.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item['requester']?.toString() ?? 'Karyawan',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Diminta ${Formatters.dateTime(DateTime.fromMillisecondsSinceEpoch((requestedAt * 1000).round()))}'
              '  ·  berlaku hingga ${Formatters.time(expiresDto.toLocal())}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'PIN Sekali Pakai:',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryDark,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    item['pin']?.toString() ?? '------',
                    style: const TextStyle(
                      fontSize: 22,
                      letterSpacing: 4,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Sampaikan PIN ini kepada karyawan. Berlaku 5 menit dan hanya bisa dipakai 1 kali.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
