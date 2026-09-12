import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_service.dart';
import '../../core/theme.dart';
import '../../models/user.dart';
import '../../shared/widgets/common_widgets.dart';

class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key});

  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  bool _loading = true;
  List<User> _users = [];
  String? _error;

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
      final api = context.read<ApiService>();
      _users = await api.fetchUsers();
    } catch (e) {
      setState(() => _error = 'Gagal memuat data karyawan: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showAddDialog() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _UserFormSheet(),
    );
    if (result == true) _load();
  }

  Future<void> _showEditDialog(User user) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _UserFormSheet(user: user),
    );
    if (result == true) _load();
  }

  Future<void> _toggleActive(User user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(user.isActive ? 'Nonaktifkan akun?' : 'Aktifkan akun?'),
        content: Text(
            '${user.isActive ? 'Nonaktifkan' : 'Aktifkan'} akun ${user.fullName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(user.isActive ? 'Nonaktifkan' : 'Aktifkan'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final api = context.read<ApiService>();
      await api.updateUser(user.id, {'is_active': !user.isActive});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Akun ${user.fullName} ${user.isActive ? 'dinonaktifkan' : 'diaktifkan'}'),
          ),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Karyawan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Tambah Karyawan',
            onPressed: _showAddDialog,
          ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _users.isEmpty
                      ? const EmptyView(message: 'Belum ada karyawan')
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _users.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, i) => _UserTile(
                            user: _users[i],
                            onEdit: () => _showEditDialog(_users[i]),
                            onToggle: () => _toggleActive(_users[i]),
                          ),
                        ),
                ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final User user;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  const _UserTile({
    required this.user,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: user.isActive
              ? AppColors.primary.withOpacity(0.15)
              : AppColors.textSecondary.withOpacity(0.15),
          child: Icon(Icons.person,
              color: user.isActive ? AppColors.primary : AppColors.textSecondary),
        ),
        title: Text(
          user.fullName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: user.isActive ? null : AppColors.textSecondary,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.username,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: user.isBos
                        ? AppColors.accent.withOpacity(0.12)
                        : AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    user.role,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: user.isBos ? AppColors.accent : AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!user.isActive)
                  const StatusBadge(status: 'Nonaktif'),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') onEdit();
            if (v == 'toggle') onToggle();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(user.isActive ? 'Nonaktifkan' : 'Aktifkan'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserFormSheet extends StatefulWidget {
  final User? user;
  const _UserFormSheet({this.user});

  @override
  State<_UserFormSheet> createState() => _UserFormSheetState();
}

class _UserFormSheetState extends State<_UserFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _passwordCtrl;
  String _role = 'KARYAWAN';
  bool _saving = false;

  bool get isEdit => widget.user != null;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.user?.username ?? '');
    _nameCtrl = TextEditingController(text: widget.user?.fullName ?? '');
    _passwordCtrl = TextEditingController();
    _role = widget.user?.role ?? 'KARYAWAN';
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final api = context.read<ApiService>();
      if (isEdit) {
        final body = <String, dynamic>{
          'full_name': _nameCtrl.text.trim(),
          'role': _role,
        };
        if (_passwordCtrl.text.isNotEmpty) {
          body['password'] = _passwordCtrl.text;
        }
        await api.updateUser(widget.user!.id, body);
      } else {
        await api.createUser({
          'username': _usernameCtrl.text.trim(),
          'full_name': _nameCtrl.text.trim(),
          'password': _passwordCtrl.text,
          'role': _role,
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Karyawan diperbarui' : 'Karyawan ditambahkan'),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEdit ? 'Edit Karyawan' : 'Tambah Karyawan',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameCtrl,
              enabled: !isEdit,
              decoration: const InputDecoration(labelText: 'Username'),
              validator: (v) {
                if (v == null || v.trim().length < 3) return 'Minimal 3 karakter';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nama Lengkap'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText:
                    isEdit ? 'Password Baru (kosongkan jika tidak ubah)' : 'Password',
              ),
              validator: (v) {
                if (!isEdit && (v == null || v.length < 4)) return 'Minimal 4 karakter';
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(value: 'KARYAWAN', child: Text('Karyawan')),
                DropdownMenuItem(value: 'BOS', child: Text('Bos')),
              ],
              onChanged: (v) => setState(() => _role = v ?? 'KARYAWAN'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEdit ? 'Simpan Perubahan' : 'Tambah Karyawan'),
            ),
          ],
        ),
      ),
    );
  }
}
