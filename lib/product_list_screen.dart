import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'product_service.dart';
import 'product_form_screen.dart';
import 'stock_form_screen.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  final String storeId;
  // [K-01 FIX] RBAC: Admin can add/edit/delete, Cashier can only view
  final bool isAdmin;
  const ProductListScreen({super.key, required this.storeId, this.isAdmin = true});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  String? _selectedCategory;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_refresh);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    _hasMore = true;
    await ref.read(productsPrv.notifier).load(
      storeId: widget.storeId,
      search: _searchController.text.isEmpty ? null : _searchController.text,
      category: _selectedCategory,
    );
  }

  void _onScroll() {
    if (_hasMore && _scrollController.position.atEdge && _scrollController.position.pixels != 0) {
      ref.read(productsPrv.notifier).load(
        storeId: widget.storeId,
        search: _searchController.text.isEmpty ? null : _searchController.text,
        category: _selectedCategory,
      );
    }
  }

  // [R-05 FIX] Swipe-to-delete with confirmation dialog (Admin only)
  Future<bool> _confirmDelete(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Produk?'),
        content: Text('Apakah Anda yakin ingin menghapus "${product.name}"?\nProduk akan dinonaktifkan (soft delete).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(productServicePrv).deleteProduct(product.id);
        _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${product.name} telah dihapus.')),
          );
        }
        return true;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menghapus: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(productsPrv);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventaris'),
        actions: [
          // [K-01 FIX] Only Admin can add new products
          if (widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Tambah Produk',
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(storeId: widget.storeId)));
                _refresh();
              },
            ),
        ],
      ),
      // [UI FIX] FAB for quick add (Admin only) — per PRD §8.2
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton(
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(storeId: widget.storeId)));
                _refresh();
              },
              tooltip: 'Tambah Produk Baru',
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Cari Produk',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: ListenableBuilder(
                listenable: _searchController,
                builder: (_, __) => _searchController.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); _refresh(); })
                    : const SizedBox.shrink(),
              ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), _refresh);
            },
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            FilterChip(label: const Text('Semua'), selected: _selectedCategory == null, onSelected: (_) { setState(() => _selectedCategory = null); _refresh(); }),
            const SizedBox(width: 8),
            ...['Makanan', 'Minuman', 'Harian'].map((cat) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(label: Text(cat), selected: _selectedCategory == cat, onSelected: (_) { setState(() => _selectedCategory = cat); _refresh(); }),
            )),
          ]),
        ),
        Expanded(
          child: state.when(
            data: (products) => RefreshIndicator(
              onRefresh: _refresh,
              child: products.isEmpty
                ? const Center(child: Text('Produk tidak ditemukan'))
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final p = products[index];
                      final isLow = p.stock <= p.minStock;

                      // [R-05 FIX] Swipe-to-delete for Admin only
                      Widget tile = ListTile(
                        leading: p.imageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(p.imageUrl!, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                            )
                          : Container(
                              width: 48, height: 48,
                              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(6)),
                              child: const Icon(Icons.image, color: Colors.grey),
                            ),
                        title: Text(p.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Rp ${p.sellingPrice.toStringAsFixed(0)} | Stok: ${p.stock} ${p.unit}'),
                            if (widget.isAdmin && p.costPrice > 0)
                              Text(
                                'Margin: ${((p.sellingPrice - p.costPrice) / p.costPrice * 100).toStringAsFixed(1)}%',
                                style: TextStyle(fontSize: 11, color: Colors.green[700]),
                              ),
                          ],
                        ),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (isLow) const Tooltip(message: 'Stok Menipis', child: Icon(Icons.warning_amber_rounded, color: Colors.orange)),
                          // [K-01 FIX] Only Admin can edit products
                          if (widget.isAdmin)
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Edit Produk',
                              onPressed: () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(storeId: widget.storeId, product: p)));
                                _refresh();
                              },
                            ),
                          // Both Admin and Cashier can adjust stock
                          IconButton(
                            icon: const Icon(Icons.inventory_2_outlined),
                            tooltip: 'Sesuaikan Stok',
                            onPressed: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => StockFormScreen(product: p)));
                              _refresh();
                            },
                          ),
                        ]),
                      );

                      // [R-05 FIX] Wrap with Dismissible for swipe-to-delete (Admin only)
                      if (widget.isAdmin) {
                        return Dismissible(
                          key: Key(p.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          confirmDismiss: (_) => _confirmDelete(p),
                          child: tile,
                        );
                      }
                      return tile;
                    },
                  ),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) {
              final isOffline = e is SocketException;
              return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(isOffline ? Icons.cloud_off : Icons.error_outline, size: 48, color: Colors.grey),
                const SizedBox(height: 8),
                Text(isOffline ? 'Offline — menampilkan data tersimpan' : 'Gagal memuat produk', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton.icon(icon: const Icon(Icons.refresh), label: const Text('Coba Lagi'), onPressed: _refresh),
              ]));
            },
          ),
        ),
      ]),
    );
  }
}
