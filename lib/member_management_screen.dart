import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'member_service.dart';

class MemberManagementScreen extends ConsumerStatefulWidget {
  final String storeId;
  const MemberManagementScreen({super.key, required this.storeId});

  @override
  ConsumerState<MemberManagementScreen> createState() => _MemberManagementScreenState();
}

class _MemberManagementScreenState extends ConsumerState<MemberManagementScreen> {
  late Future<List<StoreMember>> _membersFuture;

  @override
  void initState() {
    super.initState();
    _refreshMembers();
  }

  void _refreshMembers() {
    setState(() {
      _membersFuture = ref.read(memberServiceProvider).fetchMembers(widget.storeId);
    });
  }

  void _showAddMemberDialog() {
    final emailController = TextEditingController();
    String selectedRole = 'cashier';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Karyawan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Masukkan email kasir yang sudah mendaftar di aplikasi.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email Kasir', border: OutlineInputBorder()),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: selectedRole,
              decoration: const InputDecoration(labelText: 'Peran', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'admin', child: Text('Admin (Akses Penuh)')),
                DropdownMenuItem(value: 'cashier', child: Text('Kasir (Penjualan Only)')),
              ],
              onChanged: (val) => selectedRole = val!,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) return;
              
              Navigator.pop(ctx);
              try {
                await ref.read(memberServiceProvider).addMember(widget.storeId, email, selectedRole);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Berhasil menambahkan karyawan!')));
                  _refreshMembers();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: ${e.toString().replaceAll('Exception: ', '')}'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manajemen Karyawan')),
      body: FutureBuilder<List<StoreMember>>(
        future: _membersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final members = snapshot.data ?? [];
          if (members.isEmpty) return const Center(child: Text('Belum ada karyawan.'));

          return ListView.builder(
            itemCount: members.length,
            itemBuilder: (context, index) {
              final member = members[index];
              return ListTile(
                leading: CircleAvatar(child: Text(member.email[0].toUpperCase())),
                title: Text(member.email),
                subtitle: Text('Peran: ${member.role.toUpperCase()}'),
                trailing: member.role == 'admin' 
                  ? null // Don't allow removing admins easily for now
                  : IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Hapus Karyawan?'),
                            content: Text('Hapus ${member.email} dari toko ini?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus', style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await ref.read(memberServiceProvider).removeMember(widget.storeId, member.userId);
                          _refreshMembers();
                        }
                      },
                    ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddMemberDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Tambah Kasir'),
      ),
    );
  }
}
