import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- MODEL ---
class Product {
  final String id;
  final String storeId;
  final String name;
  final String? category;
  final int costPriceCents;
  final int sellingPriceCents;
  final int stock;
  final int minStock;
  final String? imageUrl;
  final bool isActive;

  double get costPrice => costPriceCents / 100;
  double get sellingPrice => sellingPriceCents / 100;

  const Product({
    required this.id, required this.storeId, required this.name, this.category,
    required this.costPriceCents, required this.sellingPriceCents, required this.stock,
    required this.minStock, this.imageUrl, this.isActive = true,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as String,
    storeId: json['store_id'] as String,
    name: json['name'] as String,
    category: json['category'] as String?,
    costPriceCents: ((json['cost_price'] as num) * 100).round(),
    sellingPriceCents: ((json['selling_price'] as num) * 100).round(),
    stock: json['stock'] as int,
    minStock: json['min_stock'] as int,
    imageUrl: json['image_url'] as String?,
    isActive: (json['is_active'] as bool?) ?? true,
  );

  Map<String, dynamic> toJson() => {
    'store_id': storeId, 'name': name, 'category': category,
    'cost_price': costPriceCents / 100, 'selling_price': sellingPriceCents / 100,
    'stock': stock, 'min_stock': minStock,
    'image_url': imageUrl, 'is_active': isActive,
  };

  Product copyWith({int? stock, String? imageUrl, String? id}) => Product(
    id: id ?? this.id, storeId: storeId, name: name, category: category,
    costPriceCents: costPriceCents, sellingPriceCents: sellingPriceCents,
    stock: stock ?? this.stock, minStock: minStock,
    imageUrl: imageUrl ?? this.imageUrl, isActive: isActive,
  );
}

// --- PROVIDERS ---
final productServicePrv = Provider((ref) => ProductService());
final productsPrv = StateNotifierProvider<ProductsNotifier, AsyncValue<List<Product>>>((ref) {
  return ProductsNotifier(ref.watch(productServicePrv));
});

// --- SERVICE ---
class ProductService {
  final SupabaseClient _client;
  ProductService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
  // [FIX] Lazy getter: box is only accessed after guaranteed initialization
  Box get _box => Hive.box('productsBox');

  Future<List<Product>> fetchProducts({
    int page = 0,
    String? search,
    String? category,
    // [FIX] storeId is now required and non-nullable — no more force-unwrap crash
    required String storeId,
  }) async {
    try {
      var query = _client.from('products').select()
          .eq('is_active', true)
          .eq('store_id', storeId);
      if (search != null && search.isNotEmpty) query = query.ilike('name', '%$search%');
      if (category != null) query = query.eq('category', category);

      final res = await query.range(page * 20, (page + 1) * 20 - 1).order('name');
      final products = (res as List).map((e) => Product.fromJson(Map<String, dynamic>.from(e))).toList();

      if (page == 0 && search == null && category == null) {
        await _box.put('cached_products', products.map((e) => e.toJson()).toList());
      }
      return products;
    } on SocketException {
      // [FIX] Only fall back to cache on connectivity errors, not auth/server errors
      final cached = _box.get('cached_products') as List?;
      if (cached != null) {
        return cached.map((e) => Product.fromJson(Map<String, dynamic>.from(e))).toList();
      }
      throw const SocketException('No internet connection and no cache available.');
    } catch (e) {
      // Re-throw auth errors (401), server errors (500), etc. so UI can handle them
      rethrow;
    }
  }

  Future<String?> uploadImage(File file, String storeId) async {
    // [FIX] Validate file size (PRD: max 2MB)
    final bytes = await file.length();
    if (bytes > 2 * 1024 * 1024) throw Exception('Image exceeds 2MB limit.');

    final path = '$storeId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('products').upload(path, file);
    return _client.storage.from('products').getPublicUrl(path);
  }

  // [FIX] Returns created Product with server-assigned id
  Future<Product> saveProduct(Product product) async {
    if (product.id.isEmpty) {
      final res = await _client.from('products').insert(product.toJson()).select().single();
      return Product.fromJson(Map<String, dynamic>.from(res));
    } else {
      await _client.from('products').update(product.toJson()).eq('id', product.id);
      return product;
    }
  }

  Future<void> adjustStock(String productId, int change, String reason) async {
    await _client.rpc('adjust_product_stock', params: {
      'p_id': productId, 'p_change': change, 'p_reason': reason,
    });
  }

  // [S-07 FIX] Soft delete: set is_active=false instead of hard delete (PRD §5.4)
  Future<void> deleteProduct(String productId) async {
    await _client.from('products').update({'is_active': false}).eq('id', productId);
  }

  RealtimeChannel subscribe({
    required void Function(Product) onUpdate,
    required void Function(String deletedId) onDelete,
  }) {
    // [FIX] Unique channel name to prevent duplicate subscriptions during navigation
    final channelName = 'products:${DateTime.now().millisecondsSinceEpoch}';
    return _client.channel(channelName)
      .onPostgresChanges(
        event: PostgresChangeEvent.insert, schema: 'public', table: 'products',
        callback: (payload) {
          if (payload.newRecord.isNotEmpty) onUpdate(Product.fromJson(Map<String, dynamic>.from(payload.newRecord)));
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.update, schema: 'public', table: 'products',
        callback: (payload) {
          if (payload.newRecord.isNotEmpty) onUpdate(Product.fromJson(Map<String, dynamic>.from(payload.newRecord)));
        },
      )
      .onPostgresChanges(
        // [FIX] Handle DELETE events safely — newRecord is empty on delete
        event: PostgresChangeEvent.delete, schema: 'public', table: 'products',
        callback: (payload) {
          final deletedId = payload.oldRecord['id'] as String?;
          if (deletedId != null) onDelete(deletedId);
        },
      )
      .subscribe();
  }
}

// --- NOTIFIER ---
class ProductsNotifier extends StateNotifier<AsyncValue<List<Product>>> {
  final ProductService _service;
  RealtimeChannel? _subscription;

  ProductsNotifier(this._service) : super(const AsyncLoading());

  Future<void> load({required String storeId, String? search, String? category}) async {
    state = const AsyncLoading();
    try {
      // [FIX] Await unsubscribe to prevent race conditions during rapid filter changes
      await _subscription?.unsubscribe();
      _subscription = null;

      final list = await _service.fetchProducts(storeId: storeId, search: search, category: category);
      state = AsyncData(list);

      _subscription = _service.subscribe(
        onUpdate: (updated) {
          state.whenData((current) {
            final index = current.indexWhere((p) => p.id == updated.id);
            if (index != -1) {
              state = AsyncData(List<Product>.from(current)..[index] = updated);
            } else {
              // INSERT: prepend new product
              state = AsyncData([updated, ...current]);
            }
          });
        },
        onDelete: (deletedId) {
          state.whenData((current) {
            state = AsyncData(current.where((p) => p.id != deletedId).toList());
          });
        },
      );
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    super.dispose();
  }
}
