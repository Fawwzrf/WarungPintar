import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final memberServiceProvider = Provider((ref) => MemberService());

class StoreMember {
  final String userId;
  final String email;
  final String role;

  StoreMember({required this.userId, required this.email, required this.role});

  factory StoreMember.fromJson(Map<String, dynamic> json) => StoreMember(
    userId: json['user_id'] as String,
    email: (json['profiles']?['email'] as String?) ?? 'Unknown',
    role: json['role'] as String,
  );
}

class MemberService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<StoreMember>> fetchMembers(String storeId) async {
    final res = await _client
        .from('store_members')
        .select('user_id, role, profiles(email)')
        .eq('store_id', storeId);
    
    return (res as List).map((e) => StoreMember.fromJson(e)).toList();
  }

  Future<void> addMember(String storeId, String email, String role) async {
    await _client.rpc('add_store_member_by_email', params: {
      'p_store_id': storeId,
      'p_email': email,
      'p_role': role,
    });
  }

  Future<void> removeMember(String storeId, String userId) async {
    // Only allow removing if not the owner/self-admin? 
    // The DB RLS handles admin check.
    await _client
        .from('store_members')
        .delete()
        .eq('store_id', storeId)
        .eq('user_id', userId);
  }
}
