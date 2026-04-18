import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'product_service.dart';

class StockFormScreen extends ConsumerStatefulWidget {
  final Product product;
  const StockFormScreen({super.key, required this.product});

  @override
  ConsumerState<StockFormScreen> createState() => _StockFormScreenState();
}

class _StockFormScreenState extends ConsumerState<StockFormScreen> {
  final _amount = TextEditingController();
  String _reason = 'restock';
  bool _isAddition = true;
  bool _loading = false;

  @override
  void dispose() {
    // [FIX] Dispose controller to prevent memory leak
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _amount.text.trim();

    // [FIX] Validate input before parsing — prevents unhandled FormatException
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Masukkan jumlah')));
      return;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Masukkan bilangan bulat positif yang valid')));
      return;
    }

    // Guard: prevent reduction below zero
    if (!_isAddition && parsed > widget.product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tidak dapat mengurangi $parsed — stok saat ini hanya ${widget.product.stock}')),
      );
      return;
    }

    final change = parsed * (_isAddition ? 1 : -1);
    setState(() => _loading = true);
    try {
      await ref.read(productServicePrv).adjustStock(widget.product.id, change, _reason);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Penyesuaian gagal: ${e.toString().replaceAll('Exception: ', '')}'), backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Stok: ${widget.product.name}')),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Stok Saat Ini: ${widget.product.stock}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: ChoiceChip(
                  label: const Text('Tambah Stok'), selected: _isAddition,
                  onSelected: (_) { setState(() { _isAddition = true; if (_reason == 'sale') _reason = 'restock'; }); },
                )),
                const SizedBox(width: 8),
                Expanded(child: ChoiceChip(
                  label: const Text('Kurangi Stok'), selected: !_isAddition,
                  onSelected: (_) { setState(() => _isAddition = false); },
                )),
              ]),
              const SizedBox(height: 24),
              TextField(
                controller: _amount,
                decoration: const InputDecoration(labelText: 'Jumlah', border: OutlineInputBorder(), hintText: 'cth. 10'),
                keyboardType: TextInputType.number,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _reason, decoration: const InputDecoration(labelText: 'Alasan', border: OutlineInputBorder()),
                // [FIX] Filter reason dropdown options based on whether adding or reducing
                items: (_isAddition ? ['restock', 'correction'] : ['sale', 'correction', 'debt'])
                    .map((r) => DropdownMenuItem(value: r, child: Text(r.toUpperCase()))).toList(),
                onChanged: (v) => setState(() => _reason = v!),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: const Text('Konfirmasi Penyesuaian'),
              ),
            ]),
          ),
    );
  }
}
