import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'debt_service.dart';
import 'debt_models.dart';
import 'product_service.dart';

class CreateDebtScreen extends ConsumerStatefulWidget {
  final String storeId;
  final Customer customer;
  const CreateDebtScreen({super.key, required this.storeId, required this.customer});

  @override
  ConsumerState<CreateDebtScreen> createState() => _CreateDebtScreenState();
}

// Cart item uses integer cents for all price calculations
class _CartItem {
  final String productId;
  final String name;
  final int priceCents;
  final int maxStock;
  int qty;
  _CartItem({required this.productId, required this.name, required this.priceCents, required this.maxStock, this.qty = 1});
  int get subtotalCents => priceCents * qty;
}

class _CreateDebtScreenState extends ConsumerState<CreateDebtScreen> {
  final List<_CartItem> _cart = [];
  bool _loading = false;
  // [FIX] Guard against double-tap submission
  bool _submitted = false;

  // [FIX] Integer cents arithmetic — no floating-point errors
  int get _totalCents => _cart.fold(0, (sum, item) => sum + item.subtotalCents);
  int get _availableCreditCents => widget.customer.maxCreditCents - widget.customer.totalDebtCents;

  // [NOTE] Client-side check is UX hint only. Server RPC enforces the real limit with fresh data.
  bool get _exceedsLimit => (_totalCents + widget.customer.totalDebtCents) > widget.customer.maxCreditCents;

  void _addProduct() async {
    final product = await showSearch<Product?>(
      context: context,
      delegate: ProductSearchDelegate(widget.storeId, ref),
    );
    if (product == null) return;

    setState(() {
      // [FIX] Merge duplicate products instead of creating two line items
      final existing = _cart.where((i) => i.productId == product.id).firstOrNull;
      if (existing != null) {
        if (existing.qty < existing.maxStock) {
          existing.qty++;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Stok ${product.name} tidak mencukupi (max: ${product.stock})')),
          );
        }
      } else {
        _cart.add(_CartItem(
          productId: product.id,
          name: product.name,
          priceCents: (product.sellingPrice * 100).round(),
          maxStock: product.stock,
        ));
      }
    });
  }

  Future<void> _submit() async {
    if (_cart.isEmpty || _submitted) return;

    // UX-only pre-flight check (server is authoritative)
    if (_exceedsLimit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Limit kredit pelanggan tidak mencukupi.')),
      );
      return;
    }

    // [FIX] Set submitted flag BEFORE async gap to prevent double-tap race
    _submitted = true;
    setState(() => _loading = true);

    try {
      final items = _cart.map((e) => {'product_id': e.productId, 'quantity': e.qty}).toList();
      await ref.read(debtServiceProvider).createDebt(
        customerId: widget.customer.id, storeId: widget.storeId, items: items,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kasbon berhasil dibuat!')));
        Navigator.pop(context);
      }
    } catch (e) {
      // [FIX] Parse error — never show raw Postgres messages to users
      final kasbonError = KasbonException.parse(e);
      // [FIX] Reset submitted on error so user can retry after fixing the issue
      _submitted = false;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(kasbonError.userMessage), backgroundColor: Colors.red[700]),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableStr = 'Rp ${(_availableCreditCents / 100).toStringAsFixed(0)}';
    final totalStr = 'Rp ${(_totalCents / 100).toStringAsFixed(0)}';
    final isOverLimit = _exceedsLimit;

    return Scaffold(
      appBar: AppBar(title: Text('Kasbon: ${widget.customer.name}')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Limit Tersedia:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(availableStr, style: TextStyle(color: isOverLimit ? Colors.red : Colors.green)),
          ]),
        ),
        const Divider(),
        Expanded(
          child: _cart.isEmpty
            ? const Center(child: Text('Belum ada produk.\nTambahkan produk di bawah.', textAlign: TextAlign.center))
            : ListView.builder(
                itemCount: _cart.length,
                itemBuilder: (context, index) {
                  final item = _cart[index];
                  return ListTile(
                    title: Text(item.name),
                    // [FIX] Show stock limit in subtitle
                    subtitle: Text('Rp ${(item.priceCents / 100).toStringAsFixed(0)} x ${item.qty} (stok: ${item.maxStock})'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: () => setState(() { if (item.qty > 1) item.qty--; }),
                      ),
                      Text('${item.qty}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add),
                        // [FIX] Bounded by maxStock — prevent client-side over-ordering
                        onPressed: item.qty < item.maxStock ? () => setState(() => item.qty++) : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => setState(() => _cart.removeAt(index)),
                      ),
                    ]),
                  );
                },
              ),
        ),
        Container(
          padding: const EdgeInsets.all(16), color: Colors.grey[100],
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('TOTAL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(totalStr, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isOverLimit ? Colors.red : Colors.blue)),
            ]),
            if (isOverLimit) const Text('Melebihi limit kredit!', style: TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.add_shopping_cart), label: const Text('Tambah Produk'),
                onPressed: _addProduct,
              )),
              const SizedBox(width: 16),
              Expanded(child: ElevatedButton(
                onPressed: (_loading || _cart.isEmpty) ? null : _submit,
                child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Konfirmasi'),
              )),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class ProductSearchDelegate extends SearchDelegate<Product?> {
  final String storeId;
  final WidgetRef ref;
  ProductSearchDelegate(this.storeId, this.ref);

  @override
  List<Widget>? buildActions(BuildContext context) => [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _buildProductList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildProductList(context);

  Widget _buildProductList(BuildContext context) {
    return FutureBuilder<List<Product>>(
      future: ref.read(productServicePrv).fetchProducts(storeId: storeId, search: query.isEmpty ? null : query),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.isEmpty) return const Center(child: Text('Produk tidak ditemukan.'));
        return ListView(children: snap.data!.map((p) => ListTile(
          title: Text(p.name),
          subtitle: Text('Rp ${p.sellingPrice.toStringAsFixed(0)} | Stok: ${p.stock}'),
          enabled: p.stock > 0,
          onTap: p.stock > 0 ? () => close(context, p) : null,
        )).toList());
      },
    );
  }
}
