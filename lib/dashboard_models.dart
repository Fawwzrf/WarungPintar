import 'package:flutter/foundation.dart';

@immutable
class DashboardSummary {
  final int todaySalesCents;
  final int activeDebtsTotalCents;
  final int activeDebtsCount;
  final int lowStockCount;
  final List<DailySalesTrend> salesTrend7d;
  final List<TopProduct> topProducts;
  final DateTime updatedAt;

  const DashboardSummary({
    required this.todaySalesCents,
    required this.activeDebtsTotalCents,
    this.activeDebtsCount = 0,
    required this.lowStockCount,
    required this.salesTrend7d,
    required this.topProducts,
    required this.updatedAt,
  });

  // Keys match new RPC: get_dashboard_summary
  factory DashboardSummary.fromJson(Map<String, dynamic> json) => DashboardSummary(
    todaySalesCents: (((json['today_sales'] ?? json['total_sales_today'] ?? 0) as num) * 100).round(),
    activeDebtsTotalCents: (((json['active_debts_total'] ?? 0) as num) * 100).round(),
    activeDebtsCount: (json['active_debts_count'] ?? 0) as int,
    lowStockCount: (json['low_stock_count'] ?? 0) as int,
    salesTrend7d: (json['sales_trend_7d'] as List? ?? json['sales_chart_7d'] as List? ?? [])
        .map((e) => DailySalesTrend.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    topProducts: (json['top_products'] as List? ?? json['top_products_7d'] as List? ?? [])
        .map((e) => TopProduct.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'].toString()) : DateTime.now(),
  );

  double get todaySales => todaySalesCents / 100;
  double get activeDebtsTotal => activeDebtsTotalCents / 100;
}

@immutable
class DailySalesTrend {
  final DateTime date;
  final int revenueCents;

  const DailySalesTrend({required this.date, required this.revenueCents});

  factory DailySalesTrend.fromJson(Map<String, dynamic> json) => DailySalesTrend(
    date: DateTime.parse(json['date'].toString()),
    revenueCents: (((json['revenue'] ?? 0) as num) * 100).round(),
  );

  double get revenue => revenueCents / 100;
}

@immutable
class TopProduct {
  final String productName;
  final int totalQtySold;
  final int totalRevenueCents;

  const TopProduct({
    required this.productName,
    required this.totalQtySold,
    required this.totalRevenueCents,
  });

  factory TopProduct.fromJson(Map<String, dynamic> json) => TopProduct(
    productName: (json['product_name'] ?? 'Unknown') as String,
    totalQtySold: ((json['total_qty_sold'] ?? 0) as num).toInt(),
    totalRevenueCents: (((json['total_revenue'] ?? 0) as num) * 100).round(),
  );
}

// --- AI Models ---

@immutable
class AIRestockPrediction {
  final List<AIRecommendation> recommendations;
  final String summary;
  final String topSelling;

  const AIRestockPrediction({
    required this.recommendations,
    required this.summary,
    required this.topSelling,
  });

  factory AIRestockPrediction.fromJson(Map<String, dynamic> json) => AIRestockPrediction(
    recommendations: (json['recommendations'] as List? ?? [])
        .map((e) => AIRecommendation.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    summary: json['summary'] as String? ?? 'Gagal menganalisis data.',
    topSelling: json['top_selling'] as String? ?? 'Belum ada data',
  );
}

@immutable
class AIRecommendation {
  final String productName;
  final int currentStock;
  final double dailyAvgSales;
  final int daysUntilEmpty;
  final int suggestedRestockQty;
  final String urgency;
  final String reason;

  const AIRecommendation({
    required this.productName,
    required this.currentStock,
    required this.dailyAvgSales,
    required this.daysUntilEmpty,
    required this.suggestedRestockQty,
    required this.urgency,
    required this.reason,
  });

  factory AIRecommendation.fromJson(Map<String, dynamic> json) => AIRecommendation(
    productName: json['product_name'] as String? ?? 'Unknown',
    currentStock: (json['current_stock'] as num?)?.toInt() ?? 0,
    dailyAvgSales: (json['daily_avg_sales'] as num?)?.toDouble() ?? 0.0,
    daysUntilEmpty: (json['days_until_empty'] as num?)?.toInt() ?? 0,
    suggestedRestockQty: (json['suggested_restock_qty'] as num?)?.toInt() ?? 0,
    urgency: json['urgency'] as String? ?? 'normal',
    reason: json['reason'] as String? ?? '',
  );
}
