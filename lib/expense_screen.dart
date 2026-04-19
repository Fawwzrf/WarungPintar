import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sales_service.dart';

class ExpenseScreen extends ConsumerStatefulWidget {
  final String storeId;
  const ExpenseScreen({super.key, required this.storeId});

  @override
  ConsumerState<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends ConsumerState<ExpenseScreen> {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final rawAmount = _amount.text.replaceAll(RegExp(r'[^0-9]'), '');
    final desc = _description.text.trim();

    if (rawAmount.isEmpty || desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nominal dan deskripsi harus diisi')));
      return;
    }

    final amountNumber = int.tryParse(rawAmount);
    if (amountNumber == null || amountNumber <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nominal tidak valid')));
      return;
    }

    setState(() => _loading = true);
    try {
      // Input is in Rupiah string, so we convert to cents by multiplying by 100
      await ref.read(salesServiceProvider).recordExpense(
        storeId: widget.storeId, 
        amountCents: amountNumber * 100, 
        description: desc
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pengeluaran berhasil dicatat!')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mencatat pengeluaran: $e'), backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catat Pengeluaran Laci')),
      body: _loading 
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Gunakan fitur ini untuk mencatat uang yang diambil dari laci kasir (misal: bayar listrik, beli plastik kantong, uang makan, dsb.)', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 24),
                TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Nominal Pengeluaran (Rp)',
                    prefixText: 'Rp ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _description,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    labelText: 'Keterangan/Untuk Apa?',
                    border: OutlineInputBorder(),
                    hintText: 'Cth: Beli sabun cuci laci'
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  icon: const Icon(Icons.outbound),
                  label: const Text('Simpan Pengeluaran'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                  onPressed: _submit,
                )
              ]
            ),
        )
    );
  }
}
