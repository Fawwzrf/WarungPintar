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
// Usage: flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

// [CRIT-01 FIX] Dynamic storeId fetched from store_members after login
final storeIdProvider = FutureProvider<String?>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return null;
  final res = await Supabase.instance.client
      .from('store_members')
      .select('store_id')
      .eq('user_id', user.id)
      .limit(1)
      .maybeSingle();
  return res?['store_id'] as String?;
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive for offline caching
  await Hive.initFlutter();
  await Hive.openBox('cache');
  // [MED-05 FIX] Open productsBox used by ProductService
  await Hive.openBox('productsBox');

  // [CRIT-01 FIX] Credentials from --dart-define, never hardcoded
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
      home: authState.when(
        data: (user) => user == null ? const LoginScreen() : const MainNavigationHub(),
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      ),
    );
  }
}

// [CRIT-01 FIX] MainNavigationHub now fetches storeId dynamically from store_members
class MainNavigationHub extends ConsumerStatefulWidget {
  const MainNavigationHub({super.key});

  @override
  ConsumerState<MainNavigationHub> createState() => _MainNavigationHubState();
}

class _MainNavigationHubState extends ConsumerState<MainNavigationHub> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final storeIdAsync = ref.watch(storeIdProvider);

    return storeIdAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Gagal memuat data toko: $e'))),
      data: (storeId) {
        if (storeId == null) {
          return const Scaffold(body: Center(child: Text('Anda belum terdaftar di toko manapun.\nHubungi pemilik toko.', textAlign: TextAlign.center)));
        }

        final List<Widget> screens = [
          DashboardScreen(storeId: storeId),
          ProductListScreen(storeId: storeId),
          CustomerListScreen(storeId: storeId),
          ReportScreen(storeId: storeId),
        ];

        return Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: screens,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) => setState(() => _currentIndex = index),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Beranda'),
              NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Stok'),
              NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Kasbon'),
              NavigationDestination(icon: Icon(Icons.analytics_outlined), selectedIcon: Icon(Icons.analytics), label: 'Laporan'),
            ],
          ),
        );
      },
    );
  }
}
