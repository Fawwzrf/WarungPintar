import 'package:flutter/foundation.dart';

// --- FINANCIAL PRECISION NOTE ---
// All monetary values are stored as integer CENTS internally (multiply by 100)
// to avoid IEEE 754 floating-point errors. Display converts back: cents / 100.
// The DB backend uses NUMERIC(12,2) — this matches perfectly.

@immutable
class Customer {
  final String id;
  final String storeId;
  final String name;
  final String? phone;
  final String? address;
  final String creditLabel; // 'trusted', 'normal', 'watch'
  final int totalDebtCents;
  final int maxCreditCents;

  const Customer({
    required this.id, required this.storeId, required this.name,
    this.phone, this.address, this.creditLabel = 'normal',
    required this.totalDebtCents, required this.maxCreditCents,
  });

  double get totalDebt => totalDebtCents / 100;
  double get maxCredit => maxCreditCents / 100;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: json['id'] as String,
    storeId: json['store_id'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String?,
    address: json['address'] as String?,
    creditLabel: (json['credit_label'] as String?) ?? 'normal',
    totalDebtCents: ((json['total_debt'] as num) * 100).round(),
    maxCreditCents: ((json['max_credit'] as num) * 100).round(),
  );

  Map<String, dynamic> toJson() => {
    'store_id': storeId,
    'name': name,
    'phone': phone?.isNotEmpty == true ? phone : null,
    'address': address?.isNotEmpty == true ? address : null,
    'max_credit': maxCreditCents / 100,
  };
}

@immutable
class Debt {
  final String id;
  final String customerId;
  final String? storeId;
  final String? createdBy;
  final int totalAmountCents;
  final int paidAmountCents;
  final int remainingAmountCents;
  final String status;
  final DateTime createdAt;
  final DateTime? dueDate;
  final String? notes;
  final List<DebtItem>? items;

  const Debt({
    required this.id, required this.customerId,
    this.storeId, this.createdBy,
    required this.totalAmountCents, required this.paidAmountCents,
    required this.remainingAmountCents, required this.status,
    required this.createdAt, this.dueDate, this.notes, this.items,
  });

  double get totalAmount => totalAmountCents / 100;
  double get paidAmount => paidAmountCents / 100;
  double get remainingAmount => remainingAmountCents / 100;

  factory Debt.fromJson(Map<String, dynamic> json) => Debt(
    id: json['id'] as String,
    customerId: json['customer_id'] as String,
    storeId: json['store_id'] as String?,
    createdBy: json['created_by'] as String?,
    totalAmountCents: ((json['total_amount'] as num) * 100).round(),
    paidAmountCents: ((json['paid_amount'] as num) * 100).round(),
    remainingAmountCents: ((json['remaining_amount'] as num) * 100).round(),
    status: json['status'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    dueDate: json['due_date'] != null ? DateTime.tryParse(json['due_date']) : null,
    notes: json['notes'] as String?,
    items: json['debt_items'] != null
        ? (json['debt_items'] as List).map((i) => DebtItem.fromJson(i)).toList()
        : null,
  );
}

@immutable
class DebtItem {
  final String id;
  final String productId;
  final int quantity;
  // [FIX] Integer cents representation for price
  final int priceAtTimeCents;
  final String? productName;

  const DebtItem({
    required this.id, required this.productId, required this.quantity,
    required this.priceAtTimeCents, this.productName,
  });

  double get priceAtTime => priceAtTimeCents / 100;
  int get subtotalCents => priceAtTimeCents * quantity;

  factory DebtItem.fromJson(Map<String, dynamic> json) => DebtItem(
    id: json['id'] as String,
    productId: json['product_id'] as String,
    quantity: json['quantity'] as int,
    priceAtTimeCents: ((json['price_at_time'] as num) * 100).round(),
    productName: json['products']?['name'] as String?,
  );
}

@immutable
class DebtPayment {
  final String id;
  final String debtId;
  // [FIX] Integer cents representation
  final int amountCents;
  final String paymentMethod;
  final DateTime createdAt;

  const DebtPayment({
    required this.id, required this.debtId, required this.amountCents,
    required this.paymentMethod, required this.createdAt,
  });

  double get amount => amountCents / 100;

  factory DebtPayment.fromJson(Map<String, dynamic> json) => DebtPayment(
    id: json['id'] as String,
    debtId: json['debt_id'] as String,
    amountCents: ((json['amount'] as num) * 100).round(),
    paymentMethod: json['payment_method'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}

/// Parses known RPC exception messages into user-friendly Bahasa Indonesia strings.
/// Prevents internal SQL/constraint details from being shown to users.
class KasbonException {
  final String userMessage;
  const KasbonException(this.userMessage);

  static KasbonException parse(dynamic e) {
    final msg = e.toString();
    if (msg.contains('Stok') && msg.contains('tidak cukup')) return const KasbonException('Stok produk tidak mencukupi.');
    if (msg.contains('batas kredit')) return const KasbonException('Limit kredit pelanggan terlampaui.');
    if (msg.contains('melebihi sisa')) return const KasbonException('Jumlah bayar melebihi sisa hutang.');
    if (msg.contains('tidak ditemukan')) return KasbonException(msg);
    if (msg.contains('network') || msg.contains('SocketException')) return const KasbonException('Tidak ada koneksi internet. Silakan coba lagi.');
    return const KasbonException('Terjadi kesalahan. Silakan coba lagi.');
  }
}
