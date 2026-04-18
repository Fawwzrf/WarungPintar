import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dashboard_service.dart';
import 'dashboard_models.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  final String storeId;
  const DashboardScreen({super.key, required this.storeId});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(dashboardSummaryProvider.notifier).init(widget.storeId));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardSummaryProvider);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Dashboard Toko'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh), 
            onPressed: () => ref.read(dashboardSummaryProvider.notifier).load(widget.storeId),
          ),
        ],
      ),
      // [MED-03 FIX] RefreshIndicator uses onRefresh, not onPressed
      body: RefreshIndicator(
        onRefresh: () => ref.read(dashboardSummaryProvider.notifier).load(widget.storeId),
        child: state.when(
          data: (summary) => _buildContent(summary),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ),
    );
  }

  Widget _buildContent(DashboardSummary summary) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCards(summary),
          const SizedBox(height: 24),
          _buildSalesChart(summary),
          const SizedBox(height: 24),
          _buildTopProducts(summary),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Terakhir diperbarui: ${DateFormat('HH:mm:ss').format(summary.updatedAt)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(DashboardSummary summary) {
    return LayoutBuilder(builder: (context, constraints) {
      final cardWidth = (constraints.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _SummaryCard(
            title: 'Penjualan Hari Ini',
            value: 'Rp ${NumberFormat('#,###').format(summary.todaySales)}',
            color: Colors.blue,
            icon: Icons.payments,
            width: cardWidth,
          ),
          _SummaryCard(
            title: 'Total Piutang Aktif',
            value: 'Rp ${NumberFormat('#,###').format(summary.activeDebtsTotal)}',
            color: Colors.orange,
            icon: Icons.account_balance_wallet,
            width: cardWidth,
          ),
          _SummaryCard(
            title: 'Stok Menipis',
            value: '${summary.lowStockCount} Produk',
            color: summary.lowStockCount > 0 ? Colors.red : Colors.green,
            icon: Icons.inventory_2,
            width: cardWidth,
          ),
        ],
      );
    });
  }

  Widget _buildSalesChart(DashboardSummary summary) {
    return Container(
      height: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tren Penjualan (7 Hari)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 24),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: summary.salesTrend7d.fold(1.0, (prev, e) => e.revenue > prev ? e.revenue : prev) * 1.2,
                barTouchData: BarTouchData(enabled: true),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        try {
                          final date = summary.salesTrend7d[val.toInt()].date;
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(DateFormat('dd/MM').format(date), style: const TextStyle(fontSize: 10)),
                          );
                        } catch (_) { return const Text(''); }
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: summary.salesTrend7d.asMap().entries.map((e) {
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.revenue,
                        color: Colors.blue[400],
                        width: 16,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopProducts(DashboardSummary summary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('5 Produk Terlaris', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: summary.topProducts.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final p = summary.topProducts[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(backgroundColor: Colors.blue[50], child: Text('${index + 1}')),
                title: Text(p.productName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text('${p.totalQtySold} Terjual'),
                trailing: Text(
                  'Rp ${NumberFormat('#,###').format(p.totalRevenueCents / 100)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
          if (summary.topProducts.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('Belum ada data penjualan.'))),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final double width;

  const _SummaryCard({
    required this.title, required this.value, required this.color, required this.icon, required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}
