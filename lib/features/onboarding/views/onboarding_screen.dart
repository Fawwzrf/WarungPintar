import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:warung_pintar/core/database/store_service.dart';
import 'package:warung_pintar/main.dart';
import 'package:warung_pintar/core/auth/auth_service.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _loading = false;
  final _storeNameController = TextEditingController();

  Future<void> _handleCreateStore() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nama Toko Baru'),
        content: TextField(
          controller: _storeNameController,
          decoration: const InputDecoration(hintText: 'Contoh: Toko Berkah Jaya'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, _storeNameController.text),
            child: const Text('Buat Toko'),
          ),
        ],
      ),
    );

    if (name == null || name.trim().isEmpty) return;

    setState(() => _loading = true);
    try {
      await ref.read(storeServiceProvider).createStore(name.trim());
      // Refresh membership to enter the app
      ref.invalidate(storeMembershipProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat toko: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.store_outlined, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            const Text(
              'Selamat Datang di WarungPintar',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Silakan pilih peran Anda untuk melanjutkan',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            
            // OPTION 1: ADMIN
            _RoleCard(
              title: 'Saya Pemilik Toko',
              subtitle: 'Kelola stok, hutang, dan laporan bisnis Anda',
              icon: Icons.admin_panel_settings,
              color: Colors.blue,
              onTap: _loading ? null : _handleCreateStore,
            ),
            
            const SizedBox(height: 16),
            
            // OPTION 2: CASHIER
            _RoleCard(
              title: 'Saya Karyawan / Kasir',
              subtitle: 'Tunggu admin mengundang email Anda ke toko',
              icon: Icons.point_of_sale,
              color: Colors.orange,
              onTap: _loading ? null : () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Menunggu Undangan'),
                    content: const Text(
                      'Silakan berikan email Anda ke Pemilik Toko agar bisa ditambahkan sebagai kasir.\n\nKlik tombol Segarkan jika sudah ditambahkan.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Tutup'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          ref.invalidate(storeMembershipProvider);
                        },
                        child: const Text('Segarkan'),
                      ),
                    ],
                  ),
                );
              },
            ),
            
            const SizedBox(height: 40),
            TextButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Keluar Akun'),
              onPressed: () => ref.read(authServiceProvider.notifier).signOut(),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(16),
          color: color.withValues(alpha: 0.05),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
