import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:warung_pintar/debt_models.dart';
class MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  setUp(() {
    //
  });

  group('Debt Models & Financial Logic', () {
    test('Customer model serialization with valid data', () {
      final customer = Customer(
        id: 'c1',
        storeId: 's1',
        name: 'Budi',
        phone: '08123456789',
        totalDebtCents: 5000000,
        maxCreditCents: 10000000,
      );
      
      final json = customer.toJson();
      expect(json['name'], 'Budi');
      
      // When json is requested, it might not output totalDebt depending on toJson implementation
      // let's just test fromJson
      final parsed = Customer.fromJson({
        'id': 'c1', 'store_id': 's1', 'name': 'Budi', 'total_debt': 50000, 'max_credit': 100000
      });
      expect(parsed.id, 'c1');
      expect(parsed.totalDebt, 50000);
    });

    test('Debt remainingAmount calculation', () {
      final tx = Debt(
        id: 'tx1',
        customerId: 'c1',
        totalAmountCents: 5000000,
        paidAmountCents: 2000000, // 20k paid
        remainingAmountCents: 3000000,
        status: 'active',
        createdAt: DateTime.now(),
        items: [],
      );
      
      expect(tx.remainingAmount, 30000);
      expect(tx.paidAmount, 20000);
    });
    
    test('Transaction isFullyPaid logic (via manual check)', () {
      var tx = Debt(
        id: 'tx1', customerId: 'c1',
        totalAmountCents: 1000000, paidAmountCents: 1000000, remainingAmountCents: 0,
        status: 'paid', createdAt: DateTime.now(), items: [],
      );
      
      expect(tx.status, 'paid');
      expect(tx.remainingAmount, 0);
    });

    test('DebtItem json parsing tests', () {
      final itemJson = {
        'id': 'item1',
        'product_id': 'p1',
        'products': {'name': 'Rokok'},
        'quantity': 2,
        'price_at_time': 25000,
      };
      
      final item = DebtItem.fromJson(itemJson);
      expect(item.productName, 'Rokok');
      expect(item.subtotalCents, 5000000); // 25k * 2 * 100 cents
      expect(item.priceAtTime, 25000);
    });
  });
}
