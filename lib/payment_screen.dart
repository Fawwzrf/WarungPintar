import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'debt_service.dart';
import 'debt_models.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  final Debt debt;
  const PaymentScreen({super.key, required this.debt});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  final _amount = TextEditingController();
  String _method = 'cash';
  bool _loading = false;
  // [FIX] Prevent double-submission race condition — once submitted, block all further attempts
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill with remaining amount for one-tap full payment
    _amount.text = (widget.debt.remainingAmountCents / 100).toStringAsFixed(0);
  }

  @override
  void dispose() {
    // [FIX] Dispose controller to prevent memory leak
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // [FIX] Hard block on subsequent calls — not re-entrant
    if (_submitted || _loading) return;

    final raw = _amount.text.trim();
    // [FIX] Validate using integer cents to avoid floating-point comparison errors
    final parsedDouble = double.tryParse(raw);
    if (parsedDouble == null || parsedDouble <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Masukkan jumlah bayar yang valid.')));
      return;
    }

    // Convert to cents for exact comparison
    final amountCents = (parsedDouble * 100).round();

    if (amountCents > widget.debt.remainingAmountCents) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Jumlah bayar (Rp $raw) melebihi sisa hutang (Rp ${(widget.debt.remainingAmountCents / 100).toStringAsFixed(0)}).')),
      );
      return;
    }

    // [FIX] Set submitted BEFORE the async gap to prevent double-tap race
    _submitted = true;
    setState(() => _loading = true);

    try {
      await ref.read(debtServiceProvider).recordPayment(
        debtId: widget.debt.id,
        amountCents: amountCents,
        method: _method,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pembayaran berhasil dicatat!')));
        Navigator.pop(context);
      }
    } catch (e) {
      // [FIX] Parse raw Postgres error into user-friendly message
      final kasbonError = KasbonException.parse(e);
      // Reset submission flag only for known client-recoverable errors
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(kasbonError.userMessage), backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remainingStr = 'Rp ${(widget.debt.remainingAmountCents / 100).toStringAsFixed(0)}';

    return Scaffold(
      appBar: AppBar(title: const Text('Catat Pembayaran')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              Text('Sisa Hutang', style: TextStyle(color: Colors.blue[700])),
              const SizedBox(height: 4),
              Text(remainingStr, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            ]),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(labelText: 'Jumlah Bayar (Rp)', border: OutlineInputBorder(), prefixText: 'Rp '),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Metode Pembayaran', border: OutlineInputBorder()),
            items: ['cash', 'transfer', 'qris'].map((m) => DropdownMenuItem(value: m, child: Text(m.toUpperCase()))).toList(),
            onChanged: (v) => setState(() => _method = v!),
          ),
          const Spacer(),
          ElevatedButton(
            // [FIX] Button is permanently disabled after first successful submission
            onPressed: (_loading || _submitted) ? null : _submit,
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
            child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Konfirmasi Pembayaran'),
          ),
        ]),
      ),
    );
  }
}
