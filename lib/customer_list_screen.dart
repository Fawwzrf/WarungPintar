import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'debt_service.dart';
import 'debt_models.dart';
import 'create_debt_screen.dart';

class CustomerListScreen extends ConsumerStatefulWidget {
  final String storeId;
  final bool selectMode;
  const CustomerListScreen({super.key, required this.storeId, this.selectMode = false});

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(customerListProvider.notifier).load(storeId: widget.storeId));
  }

  @override
  void dispose() {
    // [FIX] Dispose controller and cancel timer to prevent memory leaks
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _addCustomer() async {
    // [FIX] Wrap in StatefulWidget form — controllers are disposed when dialog closes
    final result = await showDialog<Customer?>(context: context, builder: (ctx) => _AddCustomerDialog(storeId: widget.storeId));
    if (result != null) {
      try {
        await ref.read(debtServiceProvider).saveCustomer(result);
        ref.read(customerListProvider.notifier).load(storeId: widget.storeId);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menyimpan: ${KasbonException.parse(e).userMessage}')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerListProvider);

    return Scaffold(
      // [FIX] Corrected: was `app_appBar:` (compile error typo)
      appBar: AppBar(
        title: Text(widget.selectMode ? 'Pilih Pelanggan' : 'Pelanggan'),
        actions: [
          // [FIX] Add Customer is available to all roles (Cashier needs it during new kasbon)
          // If Admin-only is required, inject role from a provider and check here
          IconButton(icon: const Icon(Icons.person_add_outlined), onPressed: _addCustomer),
        ],
      ),
      // [UI FIX] FAB for quick add customer — per PRD §8.2
      floatingActionButton: widget.selectMode ? null : FloatingActionButton(
        onPressed: _addCustomer,
        tooltip: 'Tambah Pelanggan Baru',
        child: const Icon(Icons.person_add),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'Cari Pelanggan', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(),
            ),
            onChanged: (val) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () {
                ref.read(customerListProvider.notifier).load(storeId: widget.storeId, search: val.isEmpty ? null : val);
              });
            },
          ),
        ),
        Expanded(
          child: state.when(
            data: (customers) {
              if (customers.isEmpty) return const Center(child: Text('Belum ada pelanggan.'));
              return ListView.builder(
                itemCount: customers.length,
                itemBuilder: (context, index) {
                  final c = customers[index];
                  final isNearLimit = c.totalDebtCents > (c.maxCreditCents * 0.8).round();
                  return ListTile(
                    leading: CircleAvatar(
                      // [FIX] Guard against empty name
                      child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?'),
                    ),
                    title: Text(c.name),
                    subtitle: Text('Hutang: Rp ${c.totalDebt.toStringAsFixed(0)} / Limit: Rp ${c.maxCredit.toStringAsFixed(0)}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (isNearLimit) const Tooltip(message: 'Mendekati limit kredit', child: Icon(Icons.warning_amber, color: Colors.orange, size: 18)),
                      const Icon(Icons.chevron_right),
                    ]),
                    onTap: () {
                      if (widget.selectMode) {
                        Navigator.pop(context, c);
                      } else {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(storeId: widget.storeId, customer: c)));
                      }
                    },
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 8),
              Text(KasbonException.parse(e).userMessage),
              ElevatedButton(onPressed: () => ref.read(customerListProvider.notifier).load(storeId: widget.storeId), child: const Text('Coba Lagi')),
            ])),
          ),
        ),
      ]),
    );
  }
}

/// Isolated StatefulWidget dialog for Add Customer.
/// Controllers are owned by this widget's state and auto-disposed when it's removed.
class _AddCustomerDialog extends StatefulWidget {
  final String storeId;
  const _AddCustomerDialog({required this.storeId});

  @override
  State<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<_AddCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _limit = TextEditingController(text: '500000');

  @override
  void dispose() {
    // [FIX] All controllers properly disposed when dialog closes
    _name.dispose();
    _phone.dispose();
    _limit.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final limitVal = double.tryParse(_limit.text);
    if (limitVal == null || limitVal < 0) return;

    Navigator.pop(context, Customer(
      id: '',
      storeId: widget.storeId,
      name: _name.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      totalDebtCents: 0,
      maxCreditCents: (limitVal * 100).round(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tambah Pelanggan'),
      content: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Nama *'),
          textCapitalization: TextCapitalization.words,
          // [FIX] Validate non-empty name
          validator: (v) => (v?.trim().isEmpty ?? true) ? 'Nama wajib diisi' : null,
        ),
        TextFormField(controller: _phone, decoration: const InputDecoration(labelText: 'No. HP'), keyboardType: TextInputType.phone),
        TextFormField(
          controller: _limit,
          decoration: const InputDecoration(labelText: 'Limit Kredit (Rp) *', prefixText: 'Rp '),
          keyboardType: TextInputType.number,
          // [FIX] Validate numeric limit — prevents FormatException crash
          validator: (v) {
            if (v == null || v.isEmpty) return 'Wajib diisi';
            final val = double.tryParse(v);
            if (val == null || val < 0) return 'Masukkan angka yang valid';
            return null;
          },
        ),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: _save, child: const Text('Simpan')),
      ],
    );
  }
}
