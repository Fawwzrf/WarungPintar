import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'product_service.dart';
import 'sales_service.dart';

class CreateSaleScreen extends ConsumerStatefulWidget {
  final String storeId;
  const CreateSaleScreen({super.key, required this.storeId});

  @override
  ConsumerState<CreateSaleScreen> createState() => _CreateSaleScreenState();
}

class _CartItem {
  final String productId;
  final String name;
  final int priceCents;
  final int maxStock;
  int qty = 1;

  _CartItem({required this.productId, required this.name, required this.priceCents, required this.maxStock});
  int get subtotalCents => priceCents * qty;
}

class _CreateSaleScreenState extends ConsumerState<CreateSaleScreen> {
  final List<_CartItem> _cart = [];
  bool _loading = false;
  bool _submitted = false;

  int get _totalCents => _cart.fold(0, (sum, item) => sum + item.subtotalCents);

  void _addProduct() async {
    final product = await showSearch<Product?>(
      context: context,
      delegate: ProductSearchDelegate(widget.storeId, ref),
    );
    if (product == null) return;

    setState(() {
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

  void _showCheckoutDialog() {
    final currencyFormat = NumberFormat('#,###');
    final totalRp = _totalCents / 100;
    
    final cashController = TextEditingController();
    int cashAmount = 0;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final change = cashAmount - totalRp;
            return AlertDialog(
              title: const Text('Pembayaran Tunai'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total Belanja: Rp ${currencyFormat.format(totalRp)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: cashController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Uang Tunai dari Pembeli (Rp)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      final raw = val.replaceAll(RegExp(r'[^0-9]'), '');
                      setStateDialog(() {
                        cashAmount = int.tryParse(raw) ?? 0;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  if (cashAmount > 0)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: change >= 0 
                            ? (Theme.of(context).brightness == Brightness.dark ? Colors.green.withValues(alpha: 0.2) : Colors.green[50])
                            : (Theme.of(context).brightness == Brightness.dark ? Colors.red.withValues(alpha: 0.2) : Colors.red[50]),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('KEMBALIAN:', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            change >= 0 ? 'Rp ${currencyFormat.format(change)}' : 'Uang Kurang!',
                            style: TextStyle(
                              fontWeight: FontWeight.bold, 
                              fontSize: 18, 
                              color: change >= 0 
                                  ? (Theme.of(context).brightness == Brightness.dark ? Colors.green[300] : Colors.green[800])
                                  : (Theme.of(context).brightness == Brightness.dark ? Colors.red[300] : Colors.red)
                            ),
                          )
                        ],
                      ),
                    )
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                ElevatedButton(
                  onPressed: change >= 0 ? () {
                    Navigator.pop(ctx);
                    _submitSale();
                  } : null,
                  child: const Text('Simpan Transaksi'),
                )
              ],
            );
          }
        );
      }
    );
  }

  Future<void> _submitSale() async {
    if (_cart.isEmpty || _submitted) return;

    _submitted = true;
    setState(() => _loading = true);

    try {
      final items = _cart.map((e) => {'product_id': e.productId, 'quantity': e.qty}).toList();
      await ref.read(salesServiceProvider).recordDirectSale(storeId: widget.storeId, items: items);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Penjualan Tunai Berhasil!')));
        Navigator.pop(context);
      }
    } catch (e) {
      _submitted = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mencatat penjualan: $e'), backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalStr = 'Rp ${NumberFormat('#,###').format(_totalCents / 100)}';

    return Scaffold(
      appBar: AppBar(title: const Text('Kasir Penjualan Tunai')),
      body: Column(children: [
        Expanded(
          child: _cart.isEmpty
            ? const Center(child: Text('Keranjang kosong.\nTambahkan produk di bawah.', textAlign: TextAlign.center))
            : ListView.builder(
                itemCount: _cart.length,
                itemBuilder: (context, index) {
                  final item = _cart[index];
                  return ListTile(
                    title: Text(item.name),
                    subtitle: Text('Rp ${(item.priceCents / 100).toStringAsFixed(0)} x ${item.qty}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: () => setState(() { if (item.qty > 1) item.qty--; }),
                      ),
                      Text('${item.qty}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add),
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
          padding: const EdgeInsets.all(16), 
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1))),
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('TOTAL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(totalStr, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                icon: const Icon(Icons.add_shopping_cart), label: const Text('Tambah Produk'),
                onPressed: _addProduct,
              )),
              const SizedBox(width: 16),
              Expanded(child: ElevatedButton(
                onPressed: (_loading || _cart.isEmpty) ? null : _showCheckoutDialog,
                child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Bayar Tunai'),
              )),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// Reuse the search delegate from kasbon
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
