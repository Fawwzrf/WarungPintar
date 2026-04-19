import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dashboard_models.dart';

final dashboardServiceProvider = Provider((ref) => DashboardService());

final dashboardSummaryProvider = StateNotifierProvider<DashboardNotifier, AsyncValue<DashboardSummary>>((ref) {
  final service = ref.watch(dashboardServiceProvider);
  return DashboardNotifier(service);
});

final aiRestockPredictionProvider = FutureProvider.family<AIRestockPrediction?, String>((ref, storeId) async {
  return await ref.watch(dashboardServiceProvider).getAiRestockPrediction(storeId);
});

class DashboardService {
  final SupabaseClient _client;
  // [MED-01 FIX] Support dependency injection for testability
  DashboardService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  static const _cacheKey = 'dashboard_summary';

  Future<DashboardSummary> getSummary(String storeId) async {
    try {
      final res = await _client.rpc('get_dashboard_summary', params: {'p_store_id': storeId});
      final summary = DashboardSummary.fromJson(res);
      
      final box = await Hive.openBox('cache');
      await box.put(_cacheKey, jsonEncode(res));
      
      return summary;
    } catch (e) {
      final box = await Hive.openBox('cache');
      final cachedStr = box.get(_cacheKey);
      if (cachedStr != null) {
        return DashboardSummary.fromJson(jsonDecode(cachedStr));
      }
      rethrow;
    }
  }

  Future<AIRestockPrediction?> getAiRestockPrediction(String storeId) async {
    try {
      final res = await _client.functions.invoke('restock-prediction', body: {'store_id': storeId});
      if (res.status == 200 && res.data != null) {
        return AIRestockPrediction.fromJson(res.data);
      }
      return null;
    } catch (e) {
      // In offline mode or if edge function fails, just return null
      return null;
    }
  }

  // Realtime subscription to key tables to trigger a refresh
  RealtimeChannel subscribeToChanges(String storeId, Function() onUpdate) {
    return _client.channel('public:dashboard')
        .onPostgresChanges(
          event: PostgresChangeEvent.all, 
          schema: 'public', 
          table: 'sales_log', 
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'store_id', value: storeId), 
          callback: (payload) => onUpdate(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all, 
          schema: 'public', 
          table: 'debts', 
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'store_id', value: storeId), 
          callback: (payload) => onUpdate(),
        )
        .subscribe();
  }
}

class DashboardNotifier extends StateNotifier<AsyncValue<DashboardSummary>> {
  final DashboardService _service;
  Timer? _refreshTimer;
  RealtimeChannel? _channel;

  DashboardNotifier(this._service) : super(const AsyncLoading());

  Future<void> init(String storeId) async {
    await load(storeId);
    
    // Auto-refresh logic (10-second polling as per user request for charts)
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => load(storeId, silent: true));
    
    // Realtime invalidation
    _channel?.unsubscribe();
    _channel = _service.subscribeToChanges(storeId, () => load(storeId, silent: true));
  }

  Future<void> load(String storeId, {bool silent = false}) async {
    if (!silent) state = const AsyncLoading();
    try {
      final summary = await _service.getSummary(storeId);
      state = AsyncData(summary);
    } catch (e, st) {
      if (!silent) state = AsyncError(e, st);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }
}
