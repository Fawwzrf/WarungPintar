import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'debt_models.dart';

final debtServiceProvider = Provider((ref) => DebtService());

final customerListProvider =
    StateNotifierProvider<CustomerNotifier, AsyncValue<List<Customer>>>(
        (ref) => CustomerNotifier(ref.watch(debtServiceProvider)));

final debtListProvider =
    StateNotifierProvider<DebtNotifier, AsyncValue<List<Debt>>>(
        (ref) => DebtNotifier(ref.watch(debtServiceProvider)));

class DebtService {
  final SupabaseClient _client;
  DebtService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  // --- Customers ---
  Future<List<Customer>> getCustomers({required String storeId, String? search}) async {
    var query = _client.from('customers').select().eq('store_id', storeId);
    if (search != null && search.isNotEmpty) query = query.ilike('name', '%$search%');
    final res = await query.order('name');
    return (res as List).map((e) => Customer.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> saveCustomer(Customer customer) async {
    if (customer.id.isEmpty) {
      await _client.from('customers').insert(customer.toJson());
    } else {
      await _client.from('customers').update(customer.toJson()).eq('id', customer.id);
    }
  }

  // --- Debts (new schema: debts has store_id directly) ---
  Future<List<Debt>> getDebts({
    required String storeId, String? customerId, String? status, int page = 0,
  }) async {
    var query = _client.from('debts').select().eq('store_id', storeId);
    if (customerId != null) query = query.eq('customer_id', customerId);
    if (status != null) query = query.eq('status', status);
    final res = await query.range(page * 20, (page + 1) * 20 - 1).order('created_at', ascending: false);
    return (res as List).map((e) => Debt.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<Debt> getDebtDetail(String id) async {
    final res = await _client.from('debts').select('*, debt_items(*, products(name))').eq('id', id).single();
    return Debt.fromJson(Map<String, dynamic>.from(res));
  }

  // --- RPC: Create debt with items (matches new SQL function name) ---
  Future<String> createDebt({
    required String customerId, required String storeId,
    required List<Map<String, dynamic>> items, String? notes,
  }) async {
    final res = await _client.rpc('create_debt_with_items', params: {
      'p_customer_id': customerId,
      'p_store_id': storeId,
      'p_items': items,
      'p_notes': notes,
    });
    return res as String;
  }

  // --- RPC: Record payment (matches new SQL function name) ---
  Future<void> recordPayment({required String debtId, required int amountCents, required String method}) async {
    await _client.rpc('record_debt_payment', params: {
      'p_debt_id': debtId,
      'p_amount': amountCents / 100,
      'p_method': method,
    });
  }

  Future<List<DebtPayment>> getPayments(String debtId) async {
    final res = await _client.from('debt_payments').select().eq('debt_id', debtId).order('created_at', ascending: false);
    return (res as List).map((e) => DebtPayment.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  // --- Fetch debt report (for report export) ---
  Future<List<Map<String, dynamic>>> fetchDebtReport({required String storeId}) async {
    final res = await _client.from('debts')
        .select('*, customers(name, phone)')
        .eq('store_id', storeId)
        .neq('status', 'paid')
        .order('remaining_amount', ascending: false);
    return (res as List).map((e) => Map<String, dynamic>.from(e)).toList();
  }
}

// --- Notifiers ---
class CustomerNotifier extends StateNotifier<AsyncValue<List<Customer>>> {
  final DebtService _service;
  CustomerNotifier(this._service) : super(const AsyncLoading());

  Future<void> load({required String storeId, String? search}) async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await _service.getCustomers(storeId: storeId, search: search));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

class DebtNotifier extends StateNotifier<AsyncValue<List<Debt>>> {
  final DebtService _service;
  DebtNotifier(this._service) : super(const AsyncLoading());

  Future<void> load({required String storeId, String? customerId, String? status}) async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await _service.getDebts(storeId: storeId, customerId: customerId, status: status));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
