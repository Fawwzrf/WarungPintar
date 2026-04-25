import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:warung_pintar/features/debts/providers/debt_service.dart';
import 'package:warung_pintar/features/debts/models/debt_models.dart';
import 'package:warung_pintar/features/debts/views/payment_screen.dart';

class DebtDetailScreen extends ConsumerStatefulWidget {
  final String debtId;
  const DebtDetailScreen({super.key, required this.debtId});

  @override
  ConsumerState<DebtDetailScreen> createState() => _DebtDetailScreenState();
}

class _DebtDetailScreenState extends ConsumerState<DebtDetailScreen> {
  late Future<Debt> _detailFuture;
  // [FIX] Cache payments Future to prevent re-fetching on every build
  Future<List<DebtPayment>>? _paymentsFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _detailFuture = ref.read(debtServiceProvider).getDebtDetail(widget.debtId);
      // Future is reset so it re-fetches payment list when detail is refreshed
      _paymentsFuture = null;
    });
  }

  String _buildNota(Debt debt) {
    final df = DateFormat('dd MMM yyyy, HH:mm');
    final buffer = StringBuffer();
    buffer.writeln('--- NOTA KASBON ---');
    buffer.writeln('Tanggal: ${df.format(debt.createdAt)}');
    buffer.writeln('Status  : ${debt.status.toUpperCase()}');
    buffer.writeln('\nDetail Barang:');
    for (var item in debt.items!) {
      final subtotal = (item.subtotalCents / 100).toStringAsFixed(0);
      buffer.writeln('- ${item.productName ?? 'Produk'}: ${item.quantity} x Rp ${(item.priceAtTimeCents / 100).toStringAsFixed(0)} = Rp $subtotal');
    }
    buffer.writeln('\nTOTAL   : Rp ${debt.totalAmount.toStringAsFixed(0)}');
    buffer.writeln('DIBAYAR : Rp ${debt.paidAmount.toStringAsFixed(0)}');
    buffer.writeln('SISA    : Rp ${debt.remainingAmount.toStringAsFixed(0)}');
    buffer.writeln('\nTerima kasih! 🙏');
    return buffer.toString();
  }

  void _share(Debt debt) {
    if (debt.items == null || debt.items!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invoice tidak tersedia.')));
      return;
    }
    final nota = _buildNota(debt);
    // Show bottom sheet: generic share OR WhatsApp deeplink
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Bagikan Nota', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFF25D366), child: Icon(Icons.message, color: Colors.white, size: 20)),
            title: const Text('Kirim via WhatsApp'),
            subtitle: const Text('Buka WhatsApp langsung'),
            onTap: () async {
              Navigator.pop(ctx);
              // PRD §4.3.3: deeplink to WhatsApp with pre-filled message
              final encoded = Uri.encodeComponent(nota);
              final uri = Uri.parse('https://wa.me/?text=$encoded');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WhatsApp tidak ditemukan.')));
              }
            },
          ),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.share, color: Colors.white, size: 20)),
            title: const Text('Bagikan ke Aplikasi Lain'),
            onTap: () {
              Navigator.pop(ctx);
              Share.share(nota);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Kasbon'),
        actions: [
          FutureBuilder<Debt>(
            future: _detailFuture,
            builder: (context, snapshot) => snapshot.hasData
                ? IconButton(icon: const Icon(Icons.share), onPressed: () => _share(snapshot.data!))
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: FutureBuilder<Debt>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) {
            // [FIX] Don't expose raw error to user
            return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 8),
              const Text('Gagal memuat data kasbon.'),
              ElevatedButton.icon(icon: const Icon(Icons.refresh), label: const Text('Coba Lagi'), onPressed: _refresh),
            ]));
          }
          final debt = snapshot.data!;

          // [FIX] Init payments future exactly once per refresh cycle
          _paymentsFuture ??= ref.read(debtServiceProvider).getPayments(debt.id);

          final statusColor = debt.status == 'paid' ? Colors.green : (debt.status == 'partial' ? Colors.orange : Colors.red);

          return Column(children: [
            Container(
              padding: const EdgeInsets.all(24), width: double.infinity, color: statusColor.withAlpha(25),
              child: Column(children: [
                Chip(label: Text(debt.status.toUpperCase()), backgroundColor: statusColor, labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Rp ${debt.remainingAmount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                const Text('Sisa Hutang'),
              ]),
            ),
            Expanded(
              child: ListView(children: [
                const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('ITEMS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1))),
                // [FIX] Safe null guard on items
                if (debt.items == null || debt.items!.isEmpty)
                  const Padding(padding: EdgeInsets.all(16), child: Text('Tidak ada item.', style: TextStyle(color: Colors.grey)))
                else
                  ...debt.items!.map((i) => ListTile(
                    title: Text(i.productName ?? 'Produk'),
                    subtitle: Text('${i.quantity} x Rp ${(i.priceAtTimeCents / 100).toStringAsFixed(0)}'),
                    trailing: Text('Rp ${(i.subtotalCents / 100).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  )),
                const Divider(),
                const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('RIWAYAT PEMBAYARAN', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1))),
                // [FIX] Use cached _paymentsFuture — not re-fetched on every build
                FutureBuilder<List<DebtPayment>>(
                  future: _paymentsFuture,
                  builder: (context, snap) {
                    if (!snap.hasData) return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
                    if (snap.data!.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Belum ada pembayaran.', style: TextStyle(color: Colors.grey)));
                    return Column(children: snap.data!.map((p) => ListTile(
                      leading: const Icon(Icons.check_circle, color: Colors.green),
                      title: Text('Rp ${p.amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(p.paymentMethod.toUpperCase()),
                      trailing: Text(DateFormat('dd/MM/yy').format(p.createdAt)),
                    )).toList());
                  },
                ),
                const SizedBox(height: 80), // Bottom padding for button
              ]),
            ),
            // RBAC note: Cashiers ARE authorized to record payments per RLS policy
            if (debt.status != 'paid')
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Catat Pembayaran'),
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentScreen(debt: debt)));
                    _refresh();
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
