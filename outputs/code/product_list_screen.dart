import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'product_service.dart';
import 'product_form_screen.dart';
import 'stock_form_screen.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  final String storeId;
  const ProductListScreen({super.key, required this.storeId});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  String? _selectedCategory;
  int _currentPage = 0;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_refresh);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    // [FIX] Dispose all controllers to prevent memory leaks
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // [FIX] Returns Future<void> so RefreshIndicator can await it properly
  Future<void> _refresh() async {
    _currentPage = 0;
    _hasMore = true;
    await ref.read(productsPrv.notifier).load(
      storeId: widget.storeId,
      search: _searchController.text.isEmpty ? null : _searchController.text,
      category: _selectedCategory,
    );
  }

  void _onScroll() {
    if (_hasMore && _scrollController.position.atEdge && _scrollController.position.pixels != 0) {
      _currentPage++;
      ref.read(productsPrv.notifier).load(
        storeId: widget.storeId,
        search: _searchController.text.isEmpty ? null : _searchController.text,
        category: _selectedCategory,
        // page: _currentPage  // Enable when notifier supports append pagination
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(productsPrv);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(storeId: widget.storeId)));
              _refresh();
            },
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search Products',
              prefixIcon: const Icon(Icons.search),
              // [FIX] suffixIcon now rebuilds correctly via ListenableBuilder
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
            FilterChip(label: const Text('All'), selected: _selectedCategory == null, onSelected: (_) { setState(() => _selectedCategory = null); _refresh(); }),
            const SizedBox(width: 8),
            // [FIX] Categories sourced from shared constants (hardcoded here as placeholder)
            ...['Food', 'Drink', 'Daily'].map((cat) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(label: Text(cat), selected: _selectedCategory == cat, onSelected: (_) { setState(() => _selectedCategory = cat); _refresh(); }),
            )),
          ]),
        ),
        Expanded(
          child: state.when(
            data: (products) => RefreshIndicator(
              // [FIX] RefreshIndicator now properly awaits the refresh
              onRefresh: _refresh,
              child: products.isEmpty
                ? const Center(child: Text('No products found'))
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final p = products[index];
                      final isLow = p.stock <= p.minStock;
                      return ListTile(
                        leading: p.imageUrl != null
                          ? Image.network(p.imageUrl!, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image))
                          : const Icon(Icons.image),
                        title: Text(p.name),
                        // [FIX] Format price as Indonesian Rupiah (no floating point display)
                        subtitle: Text('Rp ${p.sellingPrice.toStringAsFixed(0)} | Stok: ${p.stock}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (isLow) const Tooltip(message: 'Low Stock', child: Icon(Icons.warning_amber_rounded, color: Colors.orange)),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(storeId: widget.storeId, product: p)));
                              _refresh();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.inventory_2_outlined),
                            onPressed: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => StockFormScreen(product: p)));
                              _refresh();
                            },
                          ),
                        ]),
                      );
                    },
                  ),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) {
              final isOffline = e is SocketException;
              return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(isOffline ? Icons.cloud_off : Icons.error_outline, size: 48, color: Colors.grey),
                const SizedBox(height: 8),
                Text(isOffline ? 'Offline — showing cached data' : 'Failed to load products', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton.icon(icon: const Icon(Icons.refresh), label: const Text('Retry'), onPressed: _refresh),
              ]));
            },
          ),
        ),
      ]),
    );
  }
}
