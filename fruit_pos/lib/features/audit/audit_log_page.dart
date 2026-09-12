import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_service.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../shared/widgets/common_widgets.dart';

class AuditLogPage extends StatefulWidget {
  const AuditLogPage({super.key});

  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _logs = [];
  String? _error;
  String _filterAction = '';
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';

  static const List<String> _actionFilters = [
    '',
    'LOGIN',
    'LOGOUT',
    'PRODUCT_CREATE',
    'PRODUCT_UPDATE',
    'PRODUCT_DELETE',
    'CATEGORY_CREATE',
    'CATEGORY_UPDATE',
    'STOCK_IN',
    'STOCK_ADJUSTMENT',
    'SALE_CREATE',
    'DAMAGE_REPORT',
    'DAMAGE_APPROVE',
    'DAMAGE_REJECT',
    'USER_CREATE',
    'USER_UPDATE',
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

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _logs;
    return _logs.where((l) {
      final hay = [
        l['action']?.toString() ?? '',
        l['username']?.toString() ?? '',
        l['details']?.toString() ?? '',
        l['created_at']?.toString() ?? '',
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<ApiService>();
      _logs = await api.fetchAuditLogs(
        action: _filterAction.isNotEmpty ? _filterAction : null,
      );
    } catch (e) {
      setState(() => _error = 'Gagal memuat audit log: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audit Log')),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _FilterChip(
                              label: 'Semua',
                              selected: _filterAction.isEmpty,
                              onTap: () {
                                _filterAction = '';
                                _load();
                              },
                            ),
                            for (final action in _actionFilters.skip(1))
                              _FilterChip(
                                label: _formatAction(action),
                                selected: _filterAction == action,
                                onTap: () {
                                  _filterAction = action;
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
                          hintText: 'Cari aksi, petugas, detail...',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _filtered.isEmpty
                          ? EmptyView(
                              message: _logs.isEmpty
                                  ? 'Belum ada log aktivitas'
                                  : 'Tidak ada log yang cocok',
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                padding: const EdgeInsets.all(12),
                                itemCount: _filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (ctx, i) =>
                                    _AuditTile(log: _filtered[i]),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  String _formatAction(String action) {
    return action
        .replaceAll('_', ' ')
        .toLowerCase()
        .split(' ')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}

class _AuditTile extends StatelessWidget {
  final Map<String, dynamic> log;
  const _AuditTile({required this.log});

  IconData _iconForAction(String action) {
    if (action.contains('LOGIN')) return Icons.login;
    if (action.contains('LOGOUT')) return Icons.logout;
    if (action.contains('PRODUCT')) return Icons.inventory_2;
    if (action.contains('CATEGORY')) return Icons.category;
    if (action.contains('STOCK')) return Icons.warehouse;
    if (action.contains('SALE')) return Icons.receipt_long;
    if (action.contains('DAMAGE')) return Icons.warning;
    if (action.contains('USER')) return Icons.person;
    return Icons.info;
  }

  Color _colorForAction(String action) {
    if (action.contains('DELETE') || action.contains('REJECT')) {
      return AppColors.danger;
    }
    if (action.contains('CREATE')) return AppColors.success;
    if (action.contains('UPDATE') || action.contains('ADJUSTMENT')) {
      return AppColors.warning;
    }
    if (action.contains('APPROVE')) return AppColors.success;
    return AppColors.info;
  }

  String _formatAction(String action) {
    return action
        .replaceAll('_', ' ')
        .toLowerCase()
        .split(' ')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final action = log['action']?.toString() ?? '';
    final color = _colorForAction(action);

    String? details;
    if (log['details'] != null) {
      try {
        final parsed = jsonDecode(log['details'].toString());
        if (parsed is Map) {
          details = parsed.entries.map((e) => '${e.key}: ${e.value}').join(', ');
        }
      } catch (_) {
        details = log['details'].toString();
      }
    }

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(_iconForAction(action), color: color, size: 22),
        title: Text(
          _formatAction(action),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (log['username'] != null)
              Text(
                'oleh ${log['username']}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            if (details != null && details.isNotEmpty)
              Text(
                details,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: Text(
          Formatters.dateTime(DateTime.tryParse(log['created_at'] ?? '')),
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        isThreeLine: true,
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
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
