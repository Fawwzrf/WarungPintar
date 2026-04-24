import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'debt_models.dart';
import 'debt_service.dart';
import 'debt_detail_screen.dart';
import 'create_debt_screen.dart';

class CustomerDetailScreen extends ConsumerStatefulWidget {
  final Customer customer;
  final String storeId;
  const CustomerDetailScreen({super.key, required this.customer, required this.storeId});

  @override
  ConsumerState<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    Future.microtask(() => ref.read(debtListProvider.notifier).load(
      storeId: widget.storeId, 
      customerId: widget.customer.id
    ));
    // Also refresh customer object to get latest debt
    ref.read(customerListProvider.notifier).load(storeId: widget.storeId);
  }

  @override
  Widget build(BuildContext context) {
    final debtState = ref.watch(debtListProvider);
    // Find latest customer data from list provider to reflect payment changes
    final currentCustomer = ref.watch(customerListProvider).whenOrNull(
      data: (list) => list.where((c) => c.id == widget.customer.id).firstOrNull
    ) ?? widget.customer;

    return Scaffold(
      appBar: AppBar(title: Text(currentCustomer.name)),
      body: Column(children: [
        // Summary Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.blue.withValues(alpha: 0.1) 
                : Colors.blue[50],
          ),
          child: Row(children: [
            Expanded(child: _infoTile(context, 'Total Hutang', 'Rp ${currentCustomer.totalDebt.toStringAsFixed(0)}', Colors.red)),
            const VerticalDivider(),
            Expanded(child: _infoTile(context, 'Sisa Limit', 'Rp ${(currentCustomer.maxCredit - currentCustomer.totalDebt).toStringAsFixed(0)}', Colors.green)),
          ]),
        ),
        
        // Actions
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Buat Kasbon Baru'),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => CreateDebtScreen(storeId: widget.storeId, customer: currentCustomer)));
              _refresh();
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
          ),
        ),

        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft, 
            child: Text(
              'RIWAYAT KASBON', 
              style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).hintColor),
            ),
          ),
        ),

        // Debt List
        Expanded(
          child: debtState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Gagal memuat riwayat: $e')),
            data: (debts) {
              if (debts.isEmpty) return const Center(child: Text('Belum ada riwayat kasbon.'));
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  itemCount: debts.length,
                  itemBuilder: (context, index) {
                    final d = debts[index];
                    final color = d.status == 'paid' ? Colors.green : (d.status == 'partial' ? Colors.orange : Colors.red);
                    return ListTile(
                      leading: Icon(Icons.receipt_long_outlined, color: color),
                      title: Text('Rp ${d.totalAmount.toStringAsFixed(0)}'),
                      subtitle: Text(DateFormat('dd MMM yyyy').format(d.createdAt)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(d.status.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
                          if (d.status != 'paid') Text('Sisa: Rp ${d.remainingAmount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => DebtDetailScreen(debtId: d.id)));
                        _refresh();
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _infoTile(BuildContext context, String label, String value, Color color) {
    return Column(children: [
      Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
    ]);
  }
}
