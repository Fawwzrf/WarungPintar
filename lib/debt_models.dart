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
  // [FIX] Store as integer cents for exact arithmetic
  final int totalDebtCents;
  final int maxCreditCents;

  const Customer({
    required this.id, required this.storeId, required this.name,
    this.phone, required this.totalDebtCents, required this.maxCreditCents,
  });

  // Convenience getters for display
  double get totalDebt => totalDebtCents / 100;
  double get maxCredit => maxCreditCents / 100;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: json['id'] as String,
    storeId: json['store_id'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String?,
    // [FIX] Convert numeric to cents integer to eliminate double precision issues
    totalDebtCents: ((json['total_debt'] as num) * 100).round(),
    maxCreditCents: ((json['max_credit'] as num) * 100).round(),
  );

  Map<String, dynamic> toJson() => {
    'store_id': storeId,
    'name': name,
    'phone': phone?.isNotEmpty == true ? phone : null,
    'max_credit': maxCreditCents / 100,
  };
}

@immutable
class Debt {
  final String id;
  final String customerId;
  // [FIX] Integer cents representation for all amounts
  final int totalAmountCents;
  final int paidAmountCents;
  final int remainingAmountCents;
  final String status;
  final DateTime createdAt;
  final List<DebtItem>? items;

  const Debt({
    required this.id, required this.customerId,
    required this.totalAmountCents, required this.paidAmountCents,
    required this.remainingAmountCents, required this.status,
    required this.createdAt, this.items,
  });

  // Convenience getters for display
  double get totalAmount => totalAmountCents / 100;
  double get paidAmount => paidAmountCents / 100;
  double get remainingAmount => remainingAmountCents / 100;

  factory Debt.fromJson(Map<String, dynamic> json) => Debt(
    id: json['id'] as String,
    customerId: json['customer_id'] as String,
    totalAmountCents: ((json['total_amount'] as num) * 100).round(),
    paidAmountCents: ((json['paid_amount'] as num) * 100).round(),
    remainingAmountCents: ((json['remaining_amount'] as num) * 100).round(),
    status: json['status'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
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
    if (msg.contains('INSUFFICIENT_STOCK')) return const KasbonException('Stok produk tidak mencukupi.');
    if (msg.contains('CREDIT_LIMIT_EXCEEDED')) return const KasbonException('Limit kredit pelanggan terlampaui.');
    if (msg.contains('PAYMENT_EXCEEDS_REMAINING')) return const KasbonException('Jumlah bayar melebihi sisa hutang.');
    if (msg.contains('DEBT_NOT_FOUND')) return const KasbonException('Data kasbon tidak ditemukan.');
    if (msg.contains('CUSTOMER_NOT_FOUND')) return const KasbonException('Data pelanggan tidak ditemukan.');
    if (msg.contains('UNAUTHORIZED_MEMBER')) return const KasbonException('Anda tidak memiliki akses ke toko ini.');
    if (msg.contains('network') || msg.contains('SocketException')) return const KasbonException('Tidak ada koneksi internet. Silakan coba lagi.');
    return const KasbonException('Terjadi kesalahan. Silakan coba lagi.');
  }
}
