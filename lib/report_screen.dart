import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'report_service.dart';

class ReportScreen extends ConsumerStatefulWidget {
  final String storeId;

  const ReportScreen({super.key, required this.storeId});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  bool _isLoading = false;

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final initialDate = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = picked;
          if (_startDate.isAfter(_endDate)) {
            _startDate = _endDate;
          }
        }
      });
    }
  }

  Future<void> _exportSales(bool isPdf) async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(reportServiceProvider);
      // Ensure time includes whole end day
      final endOfDay = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);
      final data = await service.fetchSalesReport(_startDate, endOfDay, storeId: widget.storeId);

      if (data.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak ada data penjualan untuk interval ini.')));
        }
        return;
      }

      XFile file;
      if (isPdf) {
        file = await service.generateSalesPDF(data, "Warung Anda"); 
      } else {
        file = await service.generateSalesCSV(data);
      }

      if (mounted) {
        await Share.shareXFiles([file], text: 'Laporan Penjualan');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Laporan & Ekspor')),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Laporan Penjualan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectDate(context, true),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Dari Tanggal', 
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.date_range),
                              ),
                              child: Text('${_startDate.day}/${_startDate.month}/${_startDate.year}'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectDate(context, false),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Sampai Tanggal', 
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.date_range),
                              ),
                              child: Text('${_endDate.day}/${_endDate.month}/${_endDate.year}'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _exportSales(false),
                            icon: const Icon(Icons.table_chart_outlined),
                            label: const Text('Ekspor CSV'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _exportSales(true),
                            icon: const Icon(Icons.picture_as_pdf),
                            label: const Text('Ekspor PDF'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
