import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_service.dart';
import '../../auth/auth_state.dart';
import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../database/app_database.dart';
import '../../models/damage_report.dart';
import '../../shared/widgets/common_widgets.dart';

class DamageListPage extends StatefulWidget {
  const DamageListPage({super.key});

  @override
  State<DamageListPage> createState() => _DamageListPageState();
}

class _DamageListPageState extends State<DamageListPage> {
  bool _loading = true;
  List<DamageReport> _reports = [];
  String _filterStatus = '';
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  String _period = 'all'; // 'all' | 'today' | '7d' | '30d'

  static const List<({String value, String label})> _periodFilters = [
    (value: 'all', label: 'Semua'),
    (value: 'today', label: 'Hari Ini'),
    (value: '7d', label: '7 Hari'),
    (value: '30d', label: '30 Hari'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<DamageReport> get _filtered {
    final q = _search.trim().toLowerCase();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _reports.where((r) {
      if (_period == 'today') {
        final d = DateTime.tryParse(r.createdAt ?? '');
        if (d == null) return false;
        if (!DateTime(d.year, d.month, d.day).isAtSameMomentAs(today)) {
          return false;
        }
      } else if (_period == '7d') {
        final d = DateTime.tryParse(r.createdAt ?? '');
        if (d == null || d.isBefore(today.subtract(const Duration(days: 6)))) {
          return false;
        }
      } else if (_period == '30d') {
        final d = DateTime.tryParse(r.createdAt ?? '');
        if (d == null || d.isBefore(today.subtract(const Duration(days: 29)))) {
          return false;
        }
      }
      if (q.isEmpty) return true;
      final hay = [
        r.productName ?? '',
        r.reason,
        r.description ?? '',
        r.employeeName ?? '',
        r.status,
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final api = context.read<ApiService>();
    final auth = context.read<AuthState>();
    final db = AppDatabase.instance;
    try {
      if (auth.user?.isBos == true) {
        _reports = await api.fetchDamageReports(status: _filterStatus);
      } else {
        _reports = await db.damage.getDamageReports(status: _filterStatus);
      }
    } catch (e) {
      _reports = await db.damage.getDamageReports(status: _filterStatus);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onApprove(DamageReport report) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Setujui laporan?'),
        content: Text(
            'Setujui ${Formatters.quantity(report.quantity)} ${report.unit} ${report.productName ?? ''}. Stok akan dikurangi otomatis.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Setujui'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await context.read<ApiService>().approveDamage(report.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Laporan disetujui. Stok dikurangi.')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyetujui: $e')),
        );
      }
    }
  }

  Future<void> _onReject(DamageReport report) async {
    final reasonCtrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: reasonCtrl,
        builder: (context, value, _) => AlertDialog(
          title: const Text('Tolak laporan'),
          content: TextField(
            controller: reasonCtrl,
            autofocus: true,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Alasan penolakan'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal')),
            ElevatedButton(
              onPressed: value.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, value.text.trim()),
              child: const Text('Tolak'),
            ),
          ],
        ),
      ),
    );
    if (reason == null || reason.isEmpty) return;

    try {
      await context.read<ApiService>().rejectDamage(report.id!, reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Laporan ditolak')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menolak: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final isBos = auth.user?.isBos ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Laporan Produk Rusak')),
      body: _loading
          ? const LoadingView()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'Semua',
                          selected: _filterStatus.isEmpty,
                          onTap: () {
                            _filterStatus = '';
                            _load();
                          },
                        ),
                        _FilterChip(
                          label: 'Pending',
                          selected: _filterStatus == 'PENDING',
                          onTap: () {
                            _filterStatus = 'PENDING';
                            _load();
                          },
                        ),
                        _FilterChip(
                          label: 'Disetujui',
                          selected: _filterStatus == 'APPROVED',
                          onTap: () {
                            _filterStatus = 'APPROVED';
                            _load();
                          },
                        ),
                        _FilterChip(
                          label: 'Ditolak',
                          selected: _filterStatus == 'REJECTED',
                          onTap: () {
                            _filterStatus = 'REJECTED';
                            _load();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _search = v),
                    decoration: const InputDecoration(
                      hintText: 'Cari produk, alasan, petugas...',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final f in _periodFilters)
                          _FilterChip(
                            label: f.label,
                            selected: _period == f.value,
                            onTap: () => setState(() => _period = f.value),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _filtered.isEmpty
                      ? EmptyView(
                          message: _reports.isEmpty
                              ? 'Belum ada laporan'
                              : 'Tidak ada laporan yang cocok',
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (ctx, i) => _DamageTile(
                              report: _filtered[i],
                              isBos: isBos,
                              onApprove: () => _onApprove(_filtered[i]),
                              onReject: () => _onReject(_filtered[i]),
                              onTap: () => _showDetail(_filtered[i]),
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  void _showDetail(DamageReport report) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(report.productName ?? 'Laporan'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Jumlah', '${Formatters.quantity(report.quantity)} ${report.unit}'),
              _row('Alasan', report.reason),
              _row('Status', report.status),
              _row('Dilaporkan', report.employeeName ?? '-'),
              _row('Waktu', Formatters.dateTime(DateTime.tryParse(report.createdAt ?? ''))),
              if (report.description?.isNotEmpty == true)
                _row('Keterangan', report.description!),
              if (report.rejectionReason?.isNotEmpty == true)
                _row('Alasan ditolak', report.rejectionReason!),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup')),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _DamageTile extends StatelessWidget {
  final DamageReport report;
  final bool isBos;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onTap;

  const _DamageTile({
    required this.report,
    required this.isBos,
    required this.onApprove,
    required this.onReject,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      report.productName ?? 'Produk',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  StatusBadge(status: report.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${Formatters.quantity(report.quantity)} ${report.unit} - ${report.reason}',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'oleh ${report.employeeName ?? "-"} · ${Formatters.dateTime(DateTime.tryParse(report.createdAt ?? ""))}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              if (report.photos.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: report.photos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (ctx, i) => Thumb(image: report.photos[i]),
                  ),
                ),
              ],
              if (isBos && report.isPending) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                        ),
                        onPressed: onReject,
                        icon: const Icon(Icons.close),
                        label: const Text('Tolak'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onApprove,
                        icon: const Icon(Icons.check),
                        label: const Text('Setujui'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class Thumb extends StatelessWidget {
  final String image;
  const Thumb({required this.image});

  @override
  Widget build(BuildContext context) {
    if (_isUrl(image)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          _absolute(image),
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }

    Uint8List? bytes;
    try {
      String b64 = image;
      if (b64.startsWith('data:image')) {
        b64 = b64.split(',').last;
      }
      bytes = base64Decode(b64);
    } catch (_) {}

    if (bytes == null || bytes.isEmpty) {
      return _placeholder();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        bytes,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      ),
    );
  }

  bool _isUrl(String s) =>
      s.startsWith('http://') || s.startsWith('https://') || s.startsWith('/');

  String _absolute(String s) =>
      s.startsWith('/') ? '${AppConstants.baseUrl}$s' : s;

  Widget _placeholder() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.photo, color: AppColors.textSecondary),
    );
  }
}