import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_service.dart';
import 'main.dart';
import 'member_management_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = Supabase.instance.client.auth.currentUser;
    final membershipAsync = ref.watch(storeMembershipProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(children: [
        // ── Profil ──────────────────────────────────────
        const _SectionHeader('Profil Akun'),
        ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.blue.shade100,
            child: Text(
              (user?.email?.isNotEmpty == true ? user!.email![0].toUpperCase() : '?'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(user?.email ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: membershipAsync.whenOrNull(
            data: (m) => Text('Peran: ${m?.role.toUpperCase() ?? '-'} • Toko: ${m?.storeId.substring(0, 8) ?? '-'}...'),
          ),
        ),
        const Divider(),

        // ── Bisnis ──────────────────────────────────────
        if (membershipAsync.value?.isAdmin == true) ...[
          const _SectionHeader('Manajemen Bisnis'),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('Manajemen Karyawan'),
            subtitle: const Text('Tambah kasir atau admin baru'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              final storeId = membershipAsync.value!.storeId;
              Navigator.push(context, MaterialPageRoute(builder: (_) => MemberManagementScreen(storeId: storeId)));
            },
          ),
          const Divider(),
        ],

        // ── Tampilan ────────────────────────────────────
        const _SectionHeader('Tampilan'),
        ListTile(
          leading: const Icon(Icons.dark_mode_outlined),
          title: const Text('Mode Gelap'),
          subtitle: const Text('Ikuti pengaturan sistem HP'),
          trailing: Icon(Icons.check_circle, color: Colors.green.shade600),
        ),
        const Divider(),

        // ── Tentang ─────────────────────────────────────
        const _SectionHeader('Tentang Aplikasi'),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Versi Aplikasi'),
          trailing: const Text('2.0.0', style: TextStyle(color: Colors.grey)),
        ),
        ListTile(
          leading: const Icon(Icons.code),
          title: const Text('Repositori GitHub'),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () async {
            final uri = Uri.parse('https://github.com/Fawwzrf/WarungPintar');
            if (await canLaunchUrl(uri)) launchUrl(uri);
          },
        ),
        ListTile(
          leading: const Icon(Icons.policy_outlined),
          title: const Text('PRD WarungPintar v2.0'),
          subtitle: const Text('dokumen spesifikasi fitur'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showPrdDialog(context),
        ),
        const Divider(),

        // ── Bahaya Zona ──────────────────────────────────
        const _SectionHeader('Akun'),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text('Keluar', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
          subtitle: const Text('Anda akan keluar dari akun ini'),
          onTap: () => _confirmLogout(context, ref),
        ),
        const SizedBox(height: 40),
      ]),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi Keluar'),
        content: const Text('Apakah Anda yakin ingin keluar dari akun?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authServiceProvider.notifier).signOut();
            },
            child: const Text('Keluar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showPrdDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PRD WarungPintar Lite v2.0'),
        content: const SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Fitur Utama:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('• Manajemen inventaris real-time'),
            Text('• Buku kasbon digital multi-item'),
            Text('• Laporan & ekspor CSV/PDF'),
            Text('• RBAC: Admin & Kasir'),
            Text('• Sinkronisasi multi-perangkat'),
            Text('• Mode offline dengan Hive cache'),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1.2),
      ),
    );
  }
}
