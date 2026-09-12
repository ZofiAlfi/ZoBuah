import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_state.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';

import '../../sync/sync_manager.dart';

class SettingsPage extends StatelessWidget {
  final bool isHome;
  const SettingsPage({super.key, this.isHome = false});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.user;
    final isBos = user?.isBos ?? false;
    final sync = context.watch<SyncManager>();

    return Scaffold(
      appBar: isHome ? null : AppBar(title: const Text('Menu & Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.primaryLight.withOpacity(0.18),
                    child: Text(
                      (user?.fullName ?? 'P').substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.fullName ?? 'Pengguna',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          user?.username ?? '',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            user?.role ?? '',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<int>(
            valueListenable: sync.pendingCount,
            builder: (_, count, __) {
              if (count == 0) return const SizedBox.shrink();
              return Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.cloud_upload,
                    color: AppColors.warning,
                  ),
                  title: const Text('Antrian sinkronisasi'),
                  subtitle: Text('$count data menunggu dikirim'),
                  trailing: const Icon(Icons.sync, color: AppColors.warning),
                  onTap: () => sync.syncNow(forcePull: true),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          if (isBos) ...[
            const _MenuTile(
              icon: Icons.group,
              title: 'Kelola Karyawan',
              subtitle: 'Tambah / ubah akun karyawan',
              route: '/employees',
            ),
            const _MenuTile(
              icon: Icons.apps,
              title: 'Kelola Produk',
              subtitle: 'Produk, harga, kategori, stok',
              route: '/products',
            ),
            const _MenuTile(
              icon: Icons.inventory_2,
              title: 'Stok Masuk',
              subtitle: 'Record stok masuk / adjustment',
              route: '/stock',
            ),
            const _MenuTile(
              icon: Icons.report_problem,
              title: 'Approval Produk Rusak',
              subtitle: 'Setujui / tolak laporan',
              route: '/damage/list',
            ),
            const _MenuTile(
              icon: Icons.assessment,
              title: 'Laporan',
              subtitle: 'Penjualan, stok, laba, kerugian',
              route: '/reports',
            ),
            const _MenuTile(
              icon: Icons.history_edu,
              title: 'Audit Log',
              subtitle: 'Riwayat aktivitas penting',
              route: '/audit',
            ),
            const SizedBox(height: 8),
          ] else ...[
            const _MenuTile(
              icon: Icons.point_of_sale,
              title: 'Kasir Penjualan',
              route: '/sales',
            ),
            const _MenuTile(
              icon: Icons.report_problem,
              title: 'Lapor Produk Rusak',
              route: '/damage/new',
            ),
            const _MenuTile(
              icon: Icons.history,
              title: 'Riwayat Transaksi',
              route: '/transactions',
            ),
            const _MenuTile(
              icon: Icons.error_outline,
              title: 'Laporan Rusak Saya',
              route: '/damage/list',
            ),
          ],
          const Divider(height: 32),
          Card(
            color: AppColors.danger.withOpacity(0.05),
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppColors.danger),
              title: const Text(
                'Keluar',
                style: TextStyle(color: AppColors.danger),
              ),
              onTap: () async {
                final shouldExit = await showDialog<bool>(
                  context: context,
                  builder:
                      (ctx) => AlertDialog(
                        title: const Text('Keluar aplikasi?'),
                        content: const Text(
                          'Data yang belum tersinkronisasi akan tetap aman.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Batal'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Keluar'),
                          ),
                        ],
                      ),
                );
                if (shouldExit == true && context.mounted) {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  await context.read<AuthState>().logout();
                }
              },
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(
              Icons.info_outline,
              color: AppColors.textSecondary,
            ),
            title: Text(
              AppConstants.appName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('Versi ${AppConstants.appVersion}'),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                AppConstants.appCredit,
                style: TextStyle(
                  color: AppColors.textSecondary.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String route;
  const _MenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.pushNamed(context, route),
      ),
    );
  }
}
