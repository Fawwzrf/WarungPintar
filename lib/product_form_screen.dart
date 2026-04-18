import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'product_service.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  final String storeId;
  final Product? product;
  const ProductFormScreen({super.key, required this.storeId, this.product});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  // [FIX] All controllers are now individually declared for clear disposal
  late final TextEditingController _name;
  late final TextEditingController _cost;
  late final TextEditingController _selling;
  late final TextEditingController _stock;
  late final TextEditingController _minStock;
  // [FIX] ImagePicker as a class field — not re-instantiated on every call
  final _picker = ImagePicker();
  String? _category;
  File? _imageFile;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.product?.name);
    _cost = TextEditingController(text: widget.product?.costPrice.toStringAsFixed(0));
    _selling = TextEditingController(text: widget.product?.sellingPrice.toStringAsFixed(0));
    _stock = TextEditingController(text: widget.product?.stock.toString() ?? '0');
    _minStock = TextEditingController(text: widget.product?.minStock.toString() ?? '5');
    _category = widget.product?.category;
  }

  @override
  void dispose() {
    // [FIX] Dispose all TextEditingControllers to prevent memory leaks
    _name.dispose();
    _cost.dispose();
    _selling.dispose();
    _stock.dispose();
    _minStock.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null && mounted) setState(() => _imageFile = File(picked.path));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final service = ref.read(productServicePrv);
      String? imageUrl = widget.product?.imageUrl;

      if (_imageFile != null) {
        imageUrl = await service.uploadImage(_imageFile!, widget.storeId);
      }

      final p = Product(
        id: widget.product?.id ?? '',
        storeId: widget.storeId,
        name: _name.text.trim(),
        category: _category,
        // [FIX] parse() is safe here because validators guarantee valid numeric input, multiplied by 100 for cents
        costPriceCents: (double.parse(_cost.text) * 100).round(),
        sellingPriceCents: (double.parse(_selling.text) * 100).round(),
        stock: int.parse(_stock.text),
        minStock: int.parse(_minStock.text),
        imageUrl: imageUrl,
      );

      await service.saveProduct(p);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan: ${e.toString().replaceAll('Exception: ', '')}'), backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.product == null ? 'Produk Baru' : 'Edit Produk')),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                // Image Picker
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 150, width: double.infinity,
                    decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _imageFile != null
                        ? Image.file(_imageFile!, fit: BoxFit.cover)
                        : (widget.product?.imageUrl != null
                          ? Image.network(widget.product!.imageUrl!, fit: BoxFit.cover)
                          : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.add_a_photo, size: 40, color: Colors.grey),
                              SizedBox(height: 4),
                              Text('Ketuk untuk tambah foto', style: TextStyle(color: Colors.grey)),
                            ])),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Product Name
                TextFormField(
                  controller: _name, decoration: const InputDecoration(labelText: 'Nama Produk *', border: OutlineInputBorder()),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Nama produk wajib diisi' : null,
                ),
                const SizedBox(height: 12),
                // Category
                DropdownButtonFormField<String>(
                  initialValue: _category, decoration: const InputDecoration(labelText: 'Kategori', border: OutlineInputBorder()),
                  items: ['Makanan', 'Minuman', 'Harian'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() => _category = v),
                ),
                const SizedBox(height: 12),
                // Prices
                Row(children: [
                  Expanded(child: TextFormField(
                    controller: _cost,
                    decoration: const InputDecoration(labelText: 'Harga Modal (Rp) *', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    // [FIX] Validator prevents FormatException crash on parse()
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Wajib diisi';
                      if (double.tryParse(v) == null) return 'Masukkan angka yang valid';
                      if (double.parse(v) < 0) return 'Harus ≥ 0';
                      return null;
                    },
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(
                    controller: _selling,
                    decoration: const InputDecoration(labelText: 'Harga Jual (Rp) *', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    // [FIX] Also validates selling >= cost
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Wajib diisi';
                      final sell = double.tryParse(v);
                      if (sell == null) return 'Masukkan angka yang valid';
                      if (sell < 0) return 'Harus ≥ 0';
                      final cost = double.tryParse(_cost.text) ?? 0;
                      if (sell < cost) return 'Harus ≥ harga modal';
                      return null;
                    },
                  )),
                ]),
                const SizedBox(height: 12),
                // Stock
                Row(children: [
                  Expanded(child: TextFormField(
                    controller: _stock,
                    decoration: const InputDecoration(labelText: 'Stok Awal *', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Wajib diisi';
                      if (int.tryParse(v) == null) return 'Masukkan bilangan bulat';
                      if (int.parse(v) < 0) return 'Harus ≥ 0';
                      return null;
                    },
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(
                    controller: _minStock,
                    decoration: const InputDecoration(labelText: 'Batas Stok Menipis *', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Wajib diisi';
                      if (int.tryParse(v) == null) return 'Masukkan bilangan bulat';
                      if (int.parse(v) < 0) return 'Harus ≥ 0';
                      return null;
                    },
                  )),
                ]),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                  child: const Text('Simpan Produk'),
                ),
              ]),
            ),
          ),
    );
  }
}
