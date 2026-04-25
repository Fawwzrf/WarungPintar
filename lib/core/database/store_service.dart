import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final storeServiceProvider = Provider((ref) => StoreService());

class StoreService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<void> createStore(String name) async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    // 1. Create the store
    final store = await _client.from('stores').insert({
      'owner_id': user.id,
      'name': name,
    }).select().single();

    // 2. Add the user as admin to this store
    await _client.from('store_members').insert({
      'store_id': store['id'],
      'user_id': user.id,
      'role': 'admin',
    });
  }
}
