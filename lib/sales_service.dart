import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final salesServiceProvider = Provider((ref) => SalesService());

class SalesService {
  final SupabaseClient _client;
  SalesService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;

  // --- Expenses ---
  Future<void> recordExpense({
    required String storeId, required int amountCents, required String description
  }) async {
    await _client.from('expenses').insert({
      'store_id': storeId,
      'amount': amountCents / 100, // DB stores numeric decimal
      'description': description,
      'created_by': _client.auth.currentUser?.id,
    });
  }

  // --- Direct POS Sale ---
  Future<void> recordDirectSale({
    required String storeId, required List<Map<String, dynamic>> items
  }) async {
    await _client.rpc('record_direct_sale', params: {
      'p_store_id': storeId,
      'p_items': items,
    });
  }
}
