import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:warung_pintar/features/dashboard/providers/dashboard_service.dart';
import 'package:warung_pintar/features/dashboard/models/dashboard_models.dart';
import 'package:warung_pintar/features/sales/views/create_sale_screen.dart';
import 'package:warung_pintar/features/settings/views/expense_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  final String storeId;
  final bool isAdmin;
  const DashboardScreen({super.key, required this.storeId, required this.isAdmin});

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
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? null : Colors.grey[50],
      appBar: AppBar(
        title: const Text('Dashboard Toko'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh), 
            onPressed: () => ref.read(dashboardSummaryProvider.notifier).load(widget.storeId),
          ),
        ],
      ),
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
          _buildFastActionButtons(context),
          const SizedBox(height: 24),
          if (widget.isAdmin) ...[
            _buildAiPredictionList(),
            const SizedBox(height: 24),
          ],
          _buildSalesChart(summary),
          const SizedBox(height: 24),
          _buildTopProducts(summary),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Terakhir diperbarui: ${DateFormat('HH:mm:ss').format(summary.updatedAt)}',
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
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
          if (widget.isAdmin)
            _SummaryCard(
              title: 'Laba Bersih Hari Ini',
              value: 'Rp ${NumberFormat('#,###').format(summary.todayProfit)}',
              color: summary.todayProfit >= 0 ? Colors.green : Colors.red,
              icon: Icons.monetization_on,
              width: cardWidth,
            ),
          _SummaryCard(
            title: 'Omzet Penjualan',
            value: 'Rp ${NumberFormat('#,###').format(summary.todaySales)}',
            color: Colors.blue,
            icon: Icons.storefront,
            width: cardWidth,
          ),
          if (widget.isAdmin)
            _SummaryCard(
              title: 'Pengeluaran Laci',
              value: 'Rp ${NumberFormat('#,###').format(summary.todayExpenses)}',
              color: Colors.orange,
              icon: Icons.outbound,
              width: cardWidth,
            ),
          _SummaryCard(
            title: 'Total Piutang Aktif',
            value: 'Rp ${NumberFormat('#,###').format(summary.activeDebtsTotal)}',
            color: Colors.purple,
            icon: Icons.account_balance_wallet,
            width: cardWidth,
          ),
        ],
      );
    });
  }

  Widget _buildFastActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.point_of_sale, size: 24),
            label: const Text('Kasir Penjualan', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 20),
            ),
            onPressed: () => Navigator.push(
              context, 
              MaterialPageRoute(builder: (_) => CreateSaleScreen(storeId: widget.storeId))
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 24),
            label: const Text('Pengeluaran', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 20),
            ),
            onPressed: () => Navigator.push(
              context, 
              MaterialPageRoute(builder: (_) => ExpenseScreen(storeId: widget.storeId))
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSalesChart(DashboardSummary summary) {
    return Container(
      height: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor, 
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
      ),
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
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor, 
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
      ),
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
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.withValues(alpha: 0.1), 
                  child: Text('${index + 1}', style: const TextStyle(color: Colors.blue)),
                ),
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

  Widget _buildAiPredictionList() {
    final aiState = ref.watch(aiRestockPredictionProvider(widget.storeId));
    
    return aiState.when(
      data: (prediction) {
        if (prediction == null || prediction.recommendations.isEmpty) return const SizedBox.shrink();
        
        final isFallback = prediction.summary.contains('Sistem Dasar') || prediction.summary.contains('Sistem AI sedang sibuk');
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isFallback 
                  ? (isDarkMode ? [Colors.orange.withValues(alpha: 0.2), Colors.brown.withValues(alpha: 0.2)] : [Colors.orange[50]!, Colors.yellow[50]!])
                  : (isDarkMode ? [Colors.purple.withValues(alpha: 0.2), Colors.blue.withValues(alpha: 0.2)] : [Colors.purple[50]!, Colors.blue[50]!])
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isFallback ? Colors.orange.withValues(alpha: 0.3) : Colors.purple.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isFallback ? Icons.warning_amber_rounded : Icons.auto_awesome, 
                    color: isFallback ? Colors.orange[700] : Colors.purple[700]
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isFallback ? '⚠️ Rekomendasi Restock (Sistem Dasar)' : '✨ Rekomendasi Restock (AI Powered)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 16, 
                        color: isFallback 
                            ? (isDarkMode ? Colors.orange[200] : Colors.orange[900])
                            : (isDarkMode ? Colors.purple[200] : Colors.purple[900]),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                prediction.summary, 
                style: TextStyle(
                  fontSize: 12, 
                  color: isFallback ? Colors.orange[800] : Colors.purple[800]
                )
              ),
              const SizedBox(height: 16),
              ...prediction.recommendations.map((rec) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor, 
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        rec.urgency == 'critical' ? Icons.warning_amber_rounded 
                            : (rec.urgency == 'soon' ? Icons.access_time : Icons.info_outline),
                        color: rec.urgency == 'critical' ? Colors.red : (rec.urgency == 'soon' ? Colors.orange : Colors.blue),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(rec.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(rec.reason, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('+${rec.suggestedRestockQty}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          const Text('Saran Beli', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      )
                    ],
                  ),
                ),
              )),
            ],
          ),
        );
      },
      loading: () => const Center(child: Padding(
        padding: EdgeInsets.all(16.0),
        child: CircularProgressIndicator(),
      )),
      error: (_, __) => const SizedBox.shrink(),
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
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor, 
        borderRadius: BorderRadius.circular(12), 
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
      ),
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
