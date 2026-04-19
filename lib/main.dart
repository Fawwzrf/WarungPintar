import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'auth_service.dart';
import 'login_screen.dart';
import 'customer_list_screen.dart';
import 'product_list_screen.dart';
import 'dashboard_screen.dart';
import 'report_screen.dart';

// [CRIT-01 FIX] Credentials injected via --dart-define at build time.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

// ──────────────────────────────────────────────
// [K-01 FIX] RBAC: Fetch user's store membership (storeId + role)
// ──────────────────────────────────────────────
class StoreMembership {
  final String storeId;
  final String role; // 'Admin' or 'Cashier'
  const StoreMembership({required this.storeId, required this.role});
  bool get isAdmin => role == 'Admin';
  bool get isCashier => role == 'Cashier';
}

final storeMembershipProvider = FutureProvider<StoreMembership?>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return null;
  final res = await Supabase.instance.client
      .from('store_members')
      .select('store_id, role')
      .eq('user_id', user.id)
      .limit(1)
      .maybeSingle();
  if (res == null) return null;
  return StoreMembership(
    storeId: res['store_id'] as String,
    role: res['role'] as String,
  );
});

// Legacy provider for backward compatibility
final storeIdProvider = FutureProvider<String?>((ref) async {
  final membership = await ref.watch(storeMembershipProvider.future);
  return membership?.storeId;
});

// ──────────────────────────────────────────────
// [S-03 FIX] Connectivity status provider
// ──────────────────────────────────────────────
final connectivityProvider = StateProvider<bool>((ref) => true);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for offline caching
  await Hive.initFlutter();
  await Hive.openBox('cache');
  await Hive.openBox('productsBox');

  assert(_supabaseUrl.isNotEmpty, 'SUPABASE_URL must be set via --dart-define');
  assert(_supabaseAnonKey.isNotEmpty, 'SUPABASE_ANON_KEY must be set via --dart-define');
  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  runApp(
    const ProviderScope(
      child: WarungPintarApp(),
    ),
  );
}

class WarungPintarApp extends ConsumerWidget {
  const WarungPintarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authServiceProvider);

    return MaterialApp(
      title: 'WarungPintar Lite',
      debugShowCheckedModeBanner: false,
      // [S-01 FIX] Light theme
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.light),
        useMaterial3: true,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      // [S-01 FIX] Dark Mode support
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
        useMaterial3: true,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      themeMode: ThemeMode.system, // Follow Android system setting
      home: authState.when(
        data: (user) => user == null ? const LoginScreen() : const MainNavigationHub(),
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// [K-01 FIX] MainNavigationHub with RBAC enforcement
// ──────────────────────────────────────────────
class MainNavigationHub extends ConsumerStatefulWidget {
  const MainNavigationHub({super.key});

  @override
  ConsumerState<MainNavigationHub> createState() => _MainNavigationHubState();
}

class _MainNavigationHubState extends ConsumerState<MainNavigationHub> {
  int _currentIndex = 0;
  Timer? _connectivityTimer;

  @override
  void initState() {
    super.initState();
    // [S-03 FIX] Periodic connectivity check
    _connectivityTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkConnectivity());
    _checkConnectivity();
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
      if (mounted) ref.read(connectivityProvider.notifier).state = result.isNotEmpty;
    } catch (_) {
      if (mounted) ref.read(connectivityProvider.notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final membershipAsync = ref.watch(storeMembershipProvider);
    final isOnline = ref.watch(connectivityProvider);

    return membershipAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Gagal memuat data toko: $e'))),
      data: (membership) {
        if (membership == null) {
          return Scaffold(
            body: Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.store_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text('Anda belum terdaftar di toko manapun.\nHubungi pemilik toko.', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text('Keluar'),
                  onPressed: () => ref.read(authServiceProvider.notifier).signOut(),
                ),
              ]),
            ),
          );
        }

        final isAdmin = membership.isAdmin;
        final storeId = membership.storeId;

        // [K-01 FIX] Build screens based on role
        // Admin: Dashboard, Stok, Kasbon, Laporan (4 tabs)
        // Cashier: Dashboard, Stok (read-only), Kasbon (3 tabs)
        final List<Widget> screens = [
          DashboardScreen(storeId: storeId),
          ProductListScreen(storeId: storeId, isAdmin: isAdmin),
          CustomerListScreen(storeId: storeId),
          if (isAdmin) ReportScreen(storeId: storeId),
        ];

        final List<NavigationDestination> destinations = [
          const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Beranda'),
          const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Stok'),
          const NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Kasbon'),
          if (isAdmin) const NavigationDestination(icon: Icon(Icons.analytics_outlined), selectedIcon: Icon(Icons.analytics), label: 'Laporan'),
        ];

        // Guard: if Cashier and index is out of bounds
        if (_currentIndex >= screens.length) {
          _currentIndex = 0;
        }

        return Scaffold(
          body: Column(children: [
            // [S-03 FIX] Offline banner
            if (!isOnline)
              Container(
                width: double.infinity,
                color: Colors.orange[700],
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                child: const Row(children: [
                  Icon(Icons.cloud_off, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text('Mode Offline — Data belum tersinkron', style: TextStyle(color: Colors.white, fontSize: 12)),
                ]),
              ),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: screens,
              ),
            ),
          ]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) => setState(() => _currentIndex = index),
            destinations: destinations,
          ),
        );
      },
    );
  }
}
