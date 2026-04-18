import 'package:flutter/foundation.dart';

@immutable
class DashboardSummary {
  final int todaySalesCents;
  final int activeDebtsTotalCents;
  final int lowStockCount;
  final List<DailySalesTrend> salesTrend7d;
  final List<TopProduct> topProducts;
  final DateTime updatedAt;

  const DashboardSummary({
    required this.todaySalesCents,
    required this.activeDebtsTotalCents,
    required this.lowStockCount,
    required this.salesTrend7d,
    required this.topProducts,
    required this.updatedAt,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) => DashboardSummary(
    todaySalesCents: ((json['total_sales_today'] ?? 0) as num * 100).round(),
    activeDebtsTotalCents: ((json['active_debts_total'] ?? 0) as num * 100).round(),
    lowStockCount: (json['low_stock_count'] ?? 0) as int,
    salesTrend7d: (json['sales_chart_7d'] as List? ?? [])
        .map((e) => DailySalesTrend.fromJson(e))
        .toList(),
    topProducts: (json['top_products_7d'] as List? ?? [])
        .map((e) => TopProduct.fromJson(e))
        .toList(),
    updatedAt: DateTime.now(),
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
    date: DateTime.parse(json['date']),
    revenueCents: ((json['revenue'] ?? 0) as num * 100).round(),
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
    productName: json['product_name'] ?? 'Unknown',
    totalQtySold: (json['total_qty_sold'] ?? 0) as int,
    totalRevenueCents: ((json['total_revenue'] ?? 0) as num * 100).round(),
  );
}
