import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:warung_pintar/core/auth/auth_service.dart';
import 'package:warung_pintar/features/onboarding/views/login_screen.dart';
import 'package:warung_pintar/features/debts/views/customer_list_screen.dart';
import 'package:warung_pintar/features/inventory/views/product_list_screen.dart';
import 'package:warung_pintar/features/dashboard/views/dashboard_screen.dart';
import 'package:warung_pintar/features/reports/views/report_screen.dart';
import 'package:warung_pintar/features/settings/views/settings_screen.dart';
import 'package:warung_pintar/features/onboarding/views/onboarding_screen.dart';

// Credentials are injected at build time via --dart-define for security.
// Never hardcode these values in source code.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

// ──────────────────────────────────────────────
// RBAC: Store membership model
// ──────────────────────────────────────────────
class StoreMembership {
  final String storeId;
  final String role; // 'admin' or 'cashier' (always lowercase — matches DB CHECK constraint)
  const StoreMembership({required this.storeId, required this.role});
  bool get isAdmin => role == 'admin';
  bool get isCashier => role == 'cashier';
}

/// Provides the [StoreMembership] for the currently authenticated user.
///
/// Cache is keyed by [User.id] to prevent role data from bleeding between
/// different accounts on the same device. Falls back to cached data when
/// offline. Returns `null` when the user has no store membership, which
/// triggers the onboarding flow.
final storeMembershipProvider = FutureProvider<StoreMembership?>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return null;

  // [RBAC-FIX] Key cache by user.id — prevents role bleeding between accounts
  final cacheKey = 'membership_${user.id}';
  final box = Hive.box('cache');

  try {
    final res = await Supabase.instance.client
        .from('store_members')
        .select('role, store_id')
        .eq('user_id', user.id)
        .order('role', ascending: true) // alphabetical: 'admin' < 'cashier' — always prefers admin role
        .limit(1)
        .maybeSingle();

    if (res != null) {
      final membership = StoreMembership(
        storeId: res['store_id'] as String,
        role: res['role'] as String,
      );
      // Write fresh data to user-specific cache key
      await box.put(cacheKey, {'store_id': membership.storeId, 'role': membership.role});
      return membership;
    }
    // User is authenticated but has no store membership → show Onboarding
    return null;
  } catch (e) {
    debugPrint('storeMembershipProvider: fetch error ($e) — using cached data');
    final cached = box.get(cacheKey);
    if (cached != null) {
      return StoreMembership(
        storeId: cached['store_id'] as String,
        role: cached['role'] as String,
      );
    }
    return null;
  }
});

// Legacy provider for backward compatibility
final storeIdProvider = FutureProvider<String?>((ref) async {
  final membership = await ref.watch(storeMembershipProvider.future);
  return membership?.storeId;
});

// ──────────────────────────────────────────────
// Connectivity status provider
// ──────────────────────────────────────────────
final connectivityProvider = StateProvider<bool>((ref) => true);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

    // Invalidate cached membership whenever a new user logs in to prevent
    // stale role data from persisting across sessions.
    ref.listen(authServiceProvider, (prev, next) {
      final prevUser = prev?.valueOrNull;
      final nextUser = next.valueOrNull;
      if (prevUser == null && nextUser != null) {
        ref.invalidate(storeMembershipProvider);
      }
    });

    return MaterialApp(
      title: 'WarungPintar Lite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4), brightness: Brightness.light),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6750A4), width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          elevation: 0,
          indicatorColor: Color(0xFFEADDFF),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD0BCFF), brightness: Brightness.dark),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: const Color(0xFF1C1B1F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade800),
          ),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade900,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD0BCFF), width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          elevation: 0,
          indicatorColor: Color(0xFF4A4458),
        ),
      ),
      themeMode: ThemeMode.system,
      home: authState.when(
        data: (user) => user == null ? const LoginScreen() : const MainNavigationHub(),
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// MainNavigationHub with full RBAC enforcement
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
      if (mounted) {
        Future.microtask(() {
          if (mounted) ref.read(connectivityProvider.notifier).state = result.isNotEmpty;
        });
      }
    } catch (_) {
      if (mounted) {
        Future.microtask(() {
          if (mounted) ref.read(connectivityProvider.notifier).state = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final membershipAsync = ref.watch(storeMembershipProvider);
    final isOnline = ref.watch(connectivityProvider);

    // New signups always go through onboarding to choose their role,
    // even if a database trigger created a default membership.
    final authNotifier = ref.read(authServiceProvider.notifier);
    if (authNotifier.isNewUser) {
      authNotifier.clearNewUserFlag();
      return const OnboardingScreen();
    }

    return membershipAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Gagal memuat data toko: $e'))),
      data: (membership) {
        // No membership → show Onboarding to let user choose their role
        if (membership == null) {
          return const OnboardingScreen();
        }

        final isAdmin = membership.isAdmin;
        final storeId = membership.storeId;

        final List<Widget> screens = [
          DashboardScreen(storeId: storeId, isAdmin: isAdmin),
          ProductListScreen(storeId: storeId, isAdmin: isAdmin),
          CustomerListScreen(storeId: storeId),
          if (isAdmin) ReportScreen(storeId: storeId, isAdmin: isAdmin),
          const SettingsScreen(),
        ];

        final List<NavigationDestination> destinations = [
          const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Beranda'),
          const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Stok'),
          const NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Kasbon'),
          if (isAdmin) const NavigationDestination(icon: Icon(Icons.analytics_outlined), selectedIcon: Icon(Icons.analytics), label: 'Laporan'),
          const NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Pengaturan'),
        ];

        // Safety guard: reset tab index when the screen list changes length
        // (e.g. when a cashier becomes admin or vice versa mid-session).
        if (_currentIndex >= screens.length) {
          _currentIndex = 0;
        }

        return Scaffold(
          body: Column(children: [
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
