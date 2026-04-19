import 'dart:io';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reportServiceProvider = Provider<ReportService>((ref) => ReportService());

class ReportService {
  final SupabaseClient _supabase;

  ReportService([SupabaseClient? client]) : _supabase = client ?? Supabase.instance.client;

  /// Fetches sales data for a specific date range.
  Future<List<Map<String, dynamic>>> fetchSalesReport(DateTime start, DateTime end, {required String storeId}) async {
    final response = await _supabase
        .from('sales_log')
        .select('*, products(name, cost_price, selling_price)')
        .eq('store_id', storeId)
        .gte('created_at', start.toIso8601String())
        .lte('created_at', end.toIso8601String())
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Fetches active debt data for export.
  Future<List<Map<String, dynamic>>> fetchDebtReport({required String storeId}) async {
    final response = await _supabase
        .from('debts')
        .select('*, customers(name, phone)')
        .eq('store_id', storeId)
        .neq('status', 'paid')
        .order('remaining_amount', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }




  /// Generates a CSV file for sales data.
  Future<XFile> generateSalesCSV(List<Map<String, dynamic>> data) async {
    List<List<dynamic>> rows = [];

    // Header
    rows.add([
      "Tanggal",
      "Produk",
      "Jumlah",
      "Total Harga (Rp)",
      "Estimasi Modal (Rp)",
      "Estimasi Profit (Rp)"
    ]);

    for (var item in data) {
      final product = item['products'] as Map<String, dynamic>;
      final qty = item['quantity'] as int;
      final totalPrice = item['total_price'] as num;
      final costPrice = product['cost_price'] as num;
      final totalCost = costPrice * qty;
      final profit = totalPrice - totalCost;

      rows.add([
        item['created_at'],
        product['name'],
        qty,
        totalPrice,
        totalCost,
        profit
      ]);
    }

    String csvData = const ListToCsvConverter().convert(rows);
    final directory = await getTemporaryDirectory();
    final path = "${directory.path}/sales_report_${DateTime.now().millisecondsSinceEpoch}.csv";
    final file = File(path);
    await file.writeAsString(csvData);

    return XFile(path);
  }

  /// Generates a PDF report for sales data.
  Future<XFile> generateSalesPDF(List<Map<String, dynamic>> data, String storeName) async {
    final pdf = pw.Document();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Laporan Penjualan - $storeName", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
                pw.Text(dateFormat.format(DateTime.now())),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: ['Tanggal', 'Produk', 'Qty', 'Total', 'Profit'],
            data: data.map((item) {
              final product = item['products'] as Map<String, dynamic>;
              final qty = item['quantity'] as int;
              final total = item['total_price'] as num;
              final cost = (product['cost_price'] as num) * qty;
              return [
                dateFormat.format(DateTime.parse(item['created_at'])),
                product['name'],
                qty.toString(),
                currencyFormat.format(total),
                currencyFormat.format(total - cost),
              ];
            }).toList(),
          ),
        ],
      ),
    );

    final directory = await getTemporaryDirectory();
    final path = "${directory.path}/sales_report_${DateTime.now().millisecondsSinceEpoch}.pdf";
    final file = File(path);
    await file.writeAsBytes(await pdf.save());

    return XFile(path);
  }

  /// Generates a CSV for active debt report.
  Future<XFile> generateDebtCSV(List<Map<String, dynamic>> data) async {
    List<List<dynamic>> rows = [
      ['Nama Pelanggan', 'Total Kasbon (Rp)', 'Sudah Dibayar (Rp)', 'Sisa Hutang (Rp)', 'Status', 'Tanggal'],
    ];
    for (var item in data) {
      final customer = item['customers'] as Map<String, dynamic>? ?? {};
      rows.add([
        customer['name'] ?? '-',
        item['total_amount'],
        item['paid_amount'],
        item['remaining_amount'],
        item['status'],
        item['created_at'],
      ]);
    }
    final csvData = const ListToCsvConverter().convert(rows);
    final directory = await getTemporaryDirectory();
    final path = "${directory.path}/debt_report_${DateTime.now().millisecondsSinceEpoch}.csv";
    final file = File(path);
    await file.writeAsString(csvData);
    return XFile(path);
  }

  /// Generates a PDF for active debt report.
  Future<XFile> generateDebtPDF(List<Map<String, dynamic>> data, String storeName) async {
    final pdf = pw.Document();
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text("Laporan Kasbon - $storeName", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
              pw.Text(dateFormat.format(DateTime.now())),
            ]),
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: ['Pelanggan', 'Total', 'Dibayar', 'Sisa', 'Status'],
            data: data.map((item) {
              final customer = item['customers'] as Map<String, dynamic>? ?? {};
              return [
                customer['name'] ?? '-',
                currencyFormat.format(item['total_amount'] ?? 0),
                currencyFormat.format(item['paid_amount'] ?? 0),
                currencyFormat.format(item['remaining_amount'] ?? 0),
                item['status'] ?? '-',
              ];
            }).toList(),
          ),
        ],
      ),
    );

    final directory = await getTemporaryDirectory();
    final path = "${directory.path}/debt_report_${DateTime.now().millisecondsSinceEpoch}.pdf";
    final file = File(path);
    await file.writeAsBytes(await pdf.save());
    return XFile(path);
  }
}
