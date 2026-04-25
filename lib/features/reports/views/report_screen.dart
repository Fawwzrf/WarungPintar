import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:warung_pintar/features/reports/providers/report_service.dart';
import 'package:warung_pintar/features/debts/providers/debt_service.dart';
import 'package:intl/intl.dart';

class ReportScreen extends ConsumerStatefulWidget {
  final String storeId;
  final bool isAdmin;
  const ReportScreen({super.key, required this.storeId, this.isAdmin = true});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // Sales report range
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Load debt report on init
    Future.microtask(() => ref.read(debtListProvider.notifier).load(storeId: widget.storeId));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) _endDate = _startDate;
        } else {
          _endDate = picked;
          if (_startDate.isAfter(_endDate)) _startDate = _endDate;
        }
      });
    }
  }

  Future<void> _exportSales(bool isPdf) async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(reportServiceProvider);
      final endOfDay = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);
      final data = await service.fetchSalesReport(_startDate, endOfDay, storeId: widget.storeId);
      if (data.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak ada data penjualan untuk periode ini.')));
        return;
      }
      final file = isPdf ? await service.generateSalesPDF(data, 'Warung Anda') : await service.generateSalesCSV(data);
      if (mounted) await Share.shareXFiles([file], text: 'Laporan Penjualan');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _exportDebts(bool isPdf) async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(reportServiceProvider);
      final data = await service.fetchDebtReport(storeId: widget.storeId);
      if (data.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak ada kasbon aktif.')));
        return;
      }
      final file = isPdf ? await service.generateDebtPDF(data, 'Warung Anda') : await service.generateDebtCSV(data);
      if (mounted) await Share.shareXFiles([file], text: 'Laporan Kasbon');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _aiReportContent;
  bool _isAILoading = false;

  Future<void> _generateAIReport() async {
    setState(() {
      _isAILoading = true;
      _aiReportContent = null;
    });
    try {
      final service = ref.read(reportServiceProvider);
      final endOfDay = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);
      final report = await service.generateAITrendReport(widget.storeId, _startDate, endOfDay);
      if (mounted) {
        setState(() {
          _aiReportContent = report;
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error AI: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isAILoading = false);
    }
  }

  void _shareAIReport() {
    if (_aiReportContent != null) {
      Share.share('Laporan Cerdas WarungPintar\n\n$_aiReportContent');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan & Ekspor'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.payments_outlined), text: 'Penjualan'),
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Kasbon'),
            Tab(icon: Icon(Icons.auto_awesome), text: 'AI Cerdas'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSalesTab(),
                _buildDebtTab(),
                _buildAITab(),
              ],
            ),
    );
  }

  Widget _buildSalesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Laporan Penjualan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Pilih periode untuk mengekspor data penjualan.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              // Quick Presets
              Row(children: [
                _presetChip('7 Hari', 7),
                const SizedBox(width: 8),
                _presetChip('30 Hari', 30),
                const SizedBox(width: 8),
                _presetChip('Bulan Ini', 0),
              ]),
              const SizedBox(height: 16),
              // Date pickers
              Row(children: [
                Expanded(child: _dateTile('Dari', _startDate, () => _selectDate(context, true))),
                const SizedBox(width: 12),
                Expanded(child: _dateTile('Sampai', _endDate, () => _selectDate(context, false))),
              ]),
              const SizedBox(height: 20),
              // Export buttons
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () => _exportSales(false),
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('CSV'),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton.icon(
                  onPressed: () => _exportSales(true),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF'),
                )),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildDebtTab() {
    final debtState = ref.watch(debtListProvider);
    final currencyFmt = NumberFormat('#,###', 'id_ID');

    return Column(children: [
      // Summary header
      debtState.whenOrNull(
        data: (debts) {
          final activeDebts = debts.where((d) => d.status != 'paid').toList();
          final totalRemaining = activeDebts.fold(0.0, (s, d) => s + d.remainingAmount);
          return Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.shade200)),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Total Piutang Aktif', style: TextStyle(color: Colors.grey, fontSize: 12)),
                Text('Rp ${currencyFmt.format(totalRemaining)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${activeDebts.length}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const Text('Kasbon', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
            ]),
          );
        },
      ) ?? const SizedBox(),

      // Export buttons
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: () => _exportDebts(false),
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Ekspor CSV'),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton.icon(
            onPressed: () => _exportDebts(true),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Ekspor PDF'),
          )),
        ]),
      ),
      const SizedBox(height: 8),
      const Divider(),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Align(alignment: Alignment.centerLeft, child: Text('DAFTAR KASBON AKTIF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey))),
      ),

      // Debt list
      Expanded(
        child: debtState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (debts) {
            final activeDebts = debts.where((d) => d.status != 'paid').toList();
            if (activeDebts.isEmpty) return const Center(child: Text('Tidak ada kasbon aktif. 🎉'));
            return RefreshIndicator(
              onRefresh: () async => ref.read(debtListProvider.notifier).load(storeId: widget.storeId),
              child: ListView.builder(
                itemCount: activeDebts.length,
                itemBuilder: (ctx, i) {
                  final d = activeDebts[i];
                  final color = d.status == 'partial' ? Colors.orange : Colors.red;
                  // Days overdue calculation (assuming created_at as start)
                  final daysOld = DateTime.now().difference(d.createdAt).inDays;
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: color.withAlpha(30), child: Icon(Icons.receipt_long, color: color, size: 18)),
                    title: Text('Rp ${currencyFmt.format(d.remainingAmount)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${DateFormat('dd MMM yy').format(d.createdAt)} · $daysOld hari lalu'),
                    trailing: Chip(
                      label: Text(d.status == 'partial' ? 'Cicilan' : 'Belum Lunas', style: const TextStyle(fontSize: 11, color: Colors.white)),
                      backgroundColor: color,
                      padding: EdgeInsets.zero,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _presetChip(String label, int days) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: () {
        setState(() {
          _endDate = DateTime.now();
          _startDate = days == 0
            ? DateTime(DateTime.now().year, DateTime.now().month, 1)
            : DateTime.now().subtract(Duration(days: days));
        });
      },
    );
  }

  Widget _dateTile(String label, DateTime date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.date_range)),
        child: Text(DateFormat('dd/MM/yyyy').format(date)),
      ),
    );
  }

  Widget _buildAITab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.purple, size: 28),
            const SizedBox(width: 8),
            const Expanded(child: Text('Laporan Tren Otomatis AI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Dapatkan ringkasan bisnis cerdas dari Google Gemini untuk panduan strategi bulan depan.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              // Presets
              Row(children: [
                _presetChip('7 Hari', 7),
                const SizedBox(width: 8),
                _presetChip('30 Hari', 30),
                const SizedBox(width: 8),
                _presetChip('Bulan Ini', 0),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: _dateTile('Dari', _startDate, () => _selectDate(context, true))),
                const SizedBox(width: 12),
                Expanded(child: _dateTile('Sampai', _endDate, () => _selectDate(context, false))),
              ]),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isAILoading ? null : _generateAIReport,
                icon: _isAILoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.auto_awesome),
                label: Text(_isAILoading ? 'Memproses Laporan...' : 'Buat Laporan AI'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        if (_aiReportContent != null) ...[
          Card(
            color: Colors.purple.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.purple.shade200)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MarkdownBody(data: _aiReportContent!, styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(fontSize: 14, height: 1.5),
                    h1: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple),
                    h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  )),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _shareAIReport,
                    icon: const Icon(Icons.share, color: Colors.purple),
                    label: const Text('Bagikan via WhatsApp', style: TextStyle(color: Colors.purple)),
                  ),
                ],
              ),
            ),
          ),
        ]
      ]),
    );
  }
}
