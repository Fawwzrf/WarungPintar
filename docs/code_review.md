# WarungPintar Lite v2.0 — Production Code Review

**Reviewer:** Antigravity AI  
**Date:** 2026-04-19  
**Scope:** Full codebase — 21 source files, 3 test files, 4 SQL migrations, CI/CD pipeline  
**Verdict:** ⛔ **NEEDS FIXES** (3 Critical, 6 Medium, 5 Low)

---

## Executive Summary

WarungPintar Lite v2.0 demonstrates strong architectural decisions for a financial UMKM application: server-side ACID transactions via PostgreSQL RPCs, integer-cents monetary representation, comprehensive RLS policies, and proper double-tap idempotency guards. The Riverpod state management is clean and the offline-first strategy using Hive is well-considered.

However, **3 critical blockers** must be resolved before any production deployment. Two are security issues (hardcoded placeholder credentials that would cause runtime crashes, and a missing `FOR UPDATE` row lock in the RPC that enables a race condition on stock). The third is a data integrity bug (the `remaining_amount` generated column is not updated by `record_payment_v1`). Additionally, test coverage is well below the 80% target.

---

## Critical Issues (Must Fix — Release Blockers)

### CRIT-01: Hardcoded Placeholder Supabase Credentials

**File:** [main.dart](file:///D:/WarungPintar/lib/main.dart#L20-L23)  
**Severity:** 🔴 Critical — Security / App Crash  

The Supabase URL and anon key are literal placeholder strings. The app will crash on launch in any non-dev environment, and if they were accidentally committed as real values, this would be a credential leak.

```dart
// CURRENT — Lines 21-22
url: 'YOUR_SUPABASE_URL',
anonKey: 'YOUR_SUPABASE_ANON_KEY',
```

**Recommended Fix:**
```dart
// Use --dart-define or .env for build-time injection
await Supabase.initialize(
  url: const String.fromEnvironment('SUPABASE_URL'),
  anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
);
```

And in the CI pipeline:
```yaml
- name: Build Release APK
  run: flutter build apk --release \
    --dart-define=SUPABASE_URL=${{ secrets.SUPABASE_URL }} \
    --dart-define=SUPABASE_ANON_KEY=${{ secrets.SUPABASE_ANON_KEY }}
```

> [!CAUTION]
> Also applies to the hardcoded `storeId` on [main.dart:71](file:///D:/WarungPintar/lib/main.dart#L71). This zero-UUID means NO data will load for ANY user. After login, the app must fetch the user's `store_id` from the `store_members` table.

---

### CRIT-02: Missing `FOR UPDATE` Row Lock in `create_debt_v1` — Stock Race Condition

**File:** [002_debt_rpcs.sql](file:///D:/WarungPintar/outputs/migrations/002_debt_rpcs.sql#L33-L38)  
**Severity:** 🔴 Critical — Data Integrity (Financial)

The RPC reads product stock and then updates it in a separate statement. Without `FOR UPDATE`, two concurrent transactions can both read `stock = 1`, both pass validation, and both decrement — resulting in `stock = -1`. This directly violates the PRD requirement that stock **must never go negative**, and the `CHECK (stock >= 0)` constraint will cause one transaction to fail unpredictably rather than gracefully.

```sql
-- CURRENT — Line 34: No row lock
SELECT stock, selling_price INTO v_product_stock, v_product_price
FROM products WHERE id = v_item.product_id AND store_id = p_store_id AND is_active = TRUE;
```

**Recommended Fix:**
```sql
-- Add FOR UPDATE to acquire exclusive row lock
SELECT stock, selling_price INTO v_product_stock, v_product_price
FROM products WHERE id = v_item.product_id AND store_id = p_store_id AND is_active = TRUE
FOR UPDATE;
```

This ensures serialization: the second concurrent transaction waits for the first to commit/rollback before reading the stock value.

---

### CRIT-03: `record_payment_v1` Reads Non-Existent Column `remaining_amount` 

**File:** [002_debt_rpcs.sql](file:///D:/WarungPintar/outputs/migrations/002_debt_rpcs.sql#L87-L89)  
**Severity:** 🔴 Critical — Data Integrity (Financial)

The `debts.remaining_amount` column is defined as `GENERATED ALWAYS AS (total_amount - paid_amount) STORED` in [001_create_schema.sql:78](file:///D:/WarungPintar/outputs/migrations/001_create_schema.sql#L78). Generated columns **cannot** be selected into PL/pgSQL variables via `SELECT ... INTO` in some PostgreSQL versions without explicit casting, and more critically, the RPC compares `p_amount > v_remaining` using the stale pre-update value.

**Recommended Fix:**
```sql
-- Compute remaining dynamically instead of relying on generated column
SELECT customer_id, (total_amount - paid_amount), paid_amount, total_amount
INTO v_customer_id, v_remaining, v_new_paid, v_total
FROM debts WHERE id = p_debt_id
FOR UPDATE;  -- Also add row lock for payment race condition
```

---

## Medium Issues (Should Fix Before Release)

### MED-01: `DashboardService` Does Not Support Dependency Injection

**File:** [dashboard_service.dart](file:///D:/WarungPintar/lib/dashboard_service.dart#L16)  
**Severity:** 🟡 Medium — Testability

Unlike `ProductService` and `DebtService` which accept an optional `SupabaseClient`, `DashboardService` hardcodes `Supabase.instance.client`. This makes it untestable and inconsistent with the rest of the codebase.

```dart
// CURRENT
final _client = Supabase.instance.client;

// FIX
final SupabaseClient _client;
DashboardService({SupabaseClient? client}) : _client = client ?? Supabase.instance.client;
```

---

### MED-02: `ReportService.fetchSalesReport` Has No `store_id` Filter

**File:** [report_service.dart](file:///D:/WarungPintar/lib/report_service.dart#L19-L28)  
**Severity:** 🟡 Medium — Security (Data Isolation)

The `fetchSalesReport` method queries `sales_log` without filtering by `store_id`. While RLS policies should prevent cross-store data access, the query itself is wrong — it fetches ALL sales across ALL stores that the user's RLS allows, rather than the specific store being viewed.

```dart
// CURRENT — No store_id filter
final response = await _supabase
    .from('sales_log')
    .select('*, products(name, cost_price, selling_price)')
    .gte('created_at', start.toIso8601String())
    .lte('created_at', end.toIso8601String())
    ...

// FIX — Add store_id filter via join
.select('*, products!inner(name, cost_price, selling_price, store_id)')
.eq('products.store_id', storeId)
```

Similarly, `fetchDebtReport()` has no `store_id` filter.

---

### MED-03: `dashboard_screen.dart` Uses Wrong API on `RefreshIndicator`

**File:** [dashboard_screen.dart](file:///D:/WarungPintar/lib/dashboard_screen.dart#L39)  
**Severity:** 🟡 Medium — Runtime Crash

`RefreshIndicator` requires `onRefresh` (a `Future<void> Function()`), but the code uses `onPressed` which is not a valid parameter. This will cause a compile error or runtime crash.

```dart
// CURRENT — Wrong parameter name
RefreshIndicator(
  onPressed: () => ref.read(...).load(widget.storeId),
  // ❌ 'onPressed' is not a valid parameter

// FIX
RefreshIndicator(
  onRefresh: () => ref.read(dashboardSummaryProvider.notifier).load(widget.storeId),
```

---

### MED-04: RBAC Not Enforced in Customer INSERT (RLS vs PRD Mismatch)

**File:** [rls_policies.sql](file:///D:/WarungPintar/outputs/rls_policies.sql#L105-L110)  
**Severity:** 🟡 Medium — Security

The RLS policy `admin_can_insert_customers` restricts customer creation to `role = 'Admin'`, but the [customer_list_screen.dart:59-61](file:///D:/WarungPintar/lib/customer_list_screen.dart#L59-L61) allows Cashiers to create customers during kasbon flow (which is functionally correct per PRD). This mismatch means Cashier-created customers will be silently rejected by RLS.

**Resolution:** Either change the RLS policy to `members_can_insert_customers` (recommended, since cashiers need to add customers during kasbon), or add a SECURITY DEFINER RPC for customer creation.

---

### MED-05: `ProductService` Uses Wrong Hive Box Name

**File:** [product_service.dart](file:///D:/WarungPintar/lib/product_service.dart#L65)  
**Severity:** 🟡 Medium — Runtime Crash

`ProductService` references `Hive.box('productsBox')` but [main.dart:17](file:///D:/WarungPintar/lib/main.dart#L17) only opens `Hive.openBox('cache')`. Accessing an unopened box throws `HiveError`.

```dart
// CURRENT — Box name mismatch
Box get _box => Hive.box('productsBox');  // ❌ Never opened

// FIX — Either open it in main.dart:
await Hive.openBox('productsBox');

// OR use the existing 'cache' box:
Box get _box => Hive.box('cache');
```

---

### MED-06: `auth_service.dart` Auth Listener Stream Is Never Cancelled

**File:** [auth_service.dart](file:///D:/WarungPintar/lib/auth_service.dart#L32)  
**Severity:** 🟡 Medium — Memory Leak

The `onAuthStateChange.listen()` subscription is never stored or cancelled. When `AuthStateNotifier` is disposed, the listener continues to fire, potentially causing use-after-dispose crashes.

```dart
// CURRENT — Unmanaged subscription
_client.auth.onAuthStateChange.listen((data) { ... });

// FIX
StreamSubscription<AuthState>? _authSub;

Future<void> _init() async {
  ...
  _authSub = _client.auth.onAuthStateChange.listen((data) { ... });
}

@override
void dispose() {
  _authSub?.cancel();
  _timeoutTimer?.cancel();
  super.dispose();
}
```

---

## Low Issues (Nice to Have)

### LOW-01: Product Model Uses `double` for Prices — Inconsistent with Debt Model Pattern

**File:** [product_service.dart](file:///D:/WarungPintar/lib/product_service.dart#L13-L14)  

`Product` uses `double costPrice` and `double sellingPrice`, while `Debt`, `Customer`, `DebtItem`, and `DebtPayment` all use integer cents. This inconsistency means floating-point errors can still creep in during product-related arithmetic (e.g., cart subtotal calculation in `create_debt_screen.dart:62`).

**Suggestion:** Migrate `Product` to `int costPriceCents` / `int sellingPriceCents` for consistency.

---

### LOW-02: Edge Function CORS Is `*` — Should Be Restricted in Production

**File:** [restock_prediction.ts](file:///D:/WarungPintar/lib/restock_prediction.ts#L5)  

```ts
'Access-Control-Allow-Origin': '*',  // Wide open
```

For production, restrict to your app's domain or use Supabase's built-in CORS configuration.

---

### LOW-03: `LoginScreen` Does Not Dispose Controllers

**File:** [login_screen.dart](file:///D:/WarungPintar/lib/login_screen.dart#L14)  

`_email` and `_pass` `TextEditingController`s are never disposed.

---

### LOW-04: Mixed Language in UI Strings

Several screens use English labels ("Search Products", "Save Product", "Retry") while others use Indonesian ("Kasbon berhasil dibuat", "Stok Menipis"). For the target audience (Ibu Sari, 38, Indonesian warung owner), all UI strings should be in Bahasa Indonesia.

---

### LOW-05: `image_picker` Not Declared in `pubspec.yaml`

**File:** [product_form_screen.dart](file:///D:/WarungPintar/lib/product_form_screen.dart#L4)  

The import `package:image_picker/image_picker.dart` is used but `image_picker` is not listed in `pubspec.yaml` dependencies. This will cause a compile error.

---

## Test Coverage Assessment

| Test File | Tests | Coverage | Verdict |
|-----------|-------|----------|---------|
| `auth_service_test.dart` | 5 | Auth flow only, 2 tests are no-op stubs | ⚠️ ~40% |
| `debt_service_test.dart` | 4 | Model serialization only, no service calls | ⚠️ ~25% |
| `product_service_test.dart` | 2 | Model instantiation, no real service tests | ⚠️ ~15% |
| **Dashboard / Report / Screens** | 0 | No tests whatsoever | ❌ 0% |
| **Estimated Overall** | 11 | **~20%** | ❌ Far below 80% target |

> [!WARNING]
> The test suite significantly under-covers the codebase. Key untested areas include:
> - `ReportService` (CSV/PDF generation)
> - `DashboardService` (RPC + cache fallback)
> - All UI screens (widget tests)
> - `KasbonException.parse` error mapping
> - Offline/online sync transitions
> - Real-time subscription lifecycle

---

## Architecture Strengths ✅

| Area | Assessment |
|------|-----------|
| **Financial Atomicity** | `create_debt_v1` and `record_payment_v1` RPCs handle stock, debt, payments, and customer totals in a single PostgreSQL transaction — exactly right |
| **Integer Cents** | Monetary values use `int` cents in models to avoid IEEE 754 float errors — well-documented |
| **RLS Policies** | Comprehensive coverage across all 9 tables with proper Admin/Cashier role separation |
| **Generated Column** | `remaining_amount` is `GENERATED ALWAYS AS (total_amount - paid_amount) STORED` — eliminates desync |
| **Double-tap Guards** | `_submitted` flag in `CreateDebtScreen` and `PaymentScreen` prevents duplicate transactions |
| **Hive Cache Fallback** | Product list degrades gracefully to cached data on `SocketException` |
| **Error Sanitization** | `KasbonException.parse()` prevents raw PostgreSQL errors from reaching users |
| **Schema Constraints** | `CHECK (stock >= 0)`, `CHECK (paid_amount <= total_amount)`, `CHECK (quantity > 0)` — defense in depth |
| **Controller Disposal** | Consistent disposal of `TextEditingController`, `Timer`, and `ScrollController` across screens |
| **SQL Indexes** | Proper indexes on FK columns, `status`, `created_at`, and `store_id` |

---

## Summary Table

| Severity | Count | Status |
|----------|-------|--------|
| 🔴 **Critical** | 3 | Must fix before release |
| 🟡 **Medium** | 6 | Should fix before release |
| 🟢 **Low** | 5 | Nice to have |
| **Test Coverage** | ~20% | ❌ Below 80% target |

---

## Verdict: ⛔ NEEDS FIXES

The codebase has a **solid architectural foundation** — the financial transaction logic, RLS policies, and state management patterns are production-quality. However, the 3 critical issues (**placeholder credentials**, **missing row lock**, **payment RPC column bug**) are release blockers that would cause crashes or data corruption in production. After those are fixed and test coverage is improved to at least 60%, this codebase would be ready for a staging deployment and final QA pass.
