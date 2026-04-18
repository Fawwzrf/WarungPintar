# WarungPintar Lite v2.0 — Integration Test Scenarios

**Format:** Gherkin BDD (Cucumber-compatible)  
**Target Device:** Vivo Y17 (Helio P35, RAM 4GB)  
**Backend:** Supabase (PostgreSQL + Realtime)  
**Test Environment:** Staging Supabase project with seeded test data

---

## Test Data Seed Requirements

```sql
-- Seed: Admin user
INSERT INTO auth.users (id, email) VALUES ('admin-uuid', 'admin@warung.test');
INSERT INTO store_members (user_id, store_id, role) VALUES ('admin-uuid', 'store-uuid', 'admin');

-- Seed: Cashier user
INSERT INTO auth.users (id, email) VALUES ('cashier-uuid', 'kasir@warung.test');
INSERT INTO store_members (user_id, store_id, role) VALUES ('cashier-uuid', 'store-uuid', 'cashier');

-- Seed: Products
INSERT INTO products (id, store_id, name, stock, selling_price)
VALUES
  ('indomie-uuid', 'store-uuid', 'Indomie Goreng', 10, 3500),
  ('sprite-uuid',  'store-uuid', 'Sprite 250ml',    5, 5000),
  ('gula-uuid',    'store-uuid', 'Gula Pasir 1kg',  0, 15000);

-- Seed: Customer
INSERT INTO customers (id, store_id, name, phone, total_debt, max_credit)
VALUES ('ibu-sari-uuid', 'store-uuid', 'Ibu Sari', '08123456789', 0, 500000);
```

---

## Feature 1: Kasbon Full Lifecycle

```gherkin
Feature: Kasbon Full Lifecycle
  As an Admin user
  I want to create a kasbon, verify stock atomicity, and record a payment
  So that financial records are accurate end-to-end

  Background:
    Given the database is seeded with test data
    And the app is running on a connected device
    And Indomie Goreng has stock = 10
    And Sprite 250ml has stock = 5
    And Ibu Sari has total_debt = 0 and max_credit = 500000

  Scenario: INT-001 Successful kasbon creation with multiple items
    Given I am logged in as Admin (admin@warung.test)
    When I navigate to the "Kasbon" tab
    And I tap "Tambah Kasbon"
    And I select customer "Ibu Sari" from the list
    And I add product "Indomie Goreng" with quantity 2
    And I add product "Sprite 250ml" with quantity 1
    And I tap "Konfirmasi Kasbon"
    Then the RPC "create_debt_v1" is called exactly once
    And the kasbon is created with total_amount = Rp 12.000
    And kasbon status is "unpaid"
    And stock of "Indomie Goreng" is reduced to 8
    And stock of "Sprite 250ml" is reduced to 4
    And a "debt" mutation is recorded in stock_mutations for Indomie with change_amount = -2
    And a "debt" mutation is recorded in stock_mutations for Sprite with change_amount = -1
    And Ibu Sari's total_debt is updated to Rp 12.000
    And UI shows success snackbar "Kasbon berhasil dibuat"

    # Error Handling
    When network drops after I tap "Konfirmasi Kasbon"
    Then the app shows a retry dialog "Koneksi terputus. Coba lagi?"
    And stock is NOT decremented (transaction rolled back atomically by PostgreSQL)
    And no kasbon record exists in the database

  Scenario: INT-002 Recording a partial payment
    Given Ibu Sari has an active kasbon with total_amount = Rp 12.000 and status "unpaid"
    And I am logged in as Admin
    When I navigate to Ibu Sari's kasbon detail
    And I tap "Catat Pembayaran"
    And I enter payment amount Rp 5.000
    And I tap "Simpan Pembayaran"
    Then the RPC "record_payment_v1" is called exactly once
    And a record is created in debt_payments with amount = 5000
    And kasbon paid_amount is updated to Rp 5.000
    And kasbon remaining_amount is Rp 7.000
    And kasbon status changes to "partial"
    And Ibu Sari's total_debt is updated to Rp 7.000

  Scenario: INT-003 Recording a final payment (full settlement)
    Given Ibu Sari has a "partial" kasbon with remaining_amount = Rp 7.000
    And I am logged in as Admin
    When I navigate to Ibu Sari's kasbon detail
    And I tap "Catat Pembayaran"
    And I enter payment amount Rp 7.000
    And I tap "Simpan Pembayaran"
    Then kasbon status changes to "paid"
    And kasbon remaining_amount is Rp 0
    And Ibu Sari's total_debt is updated to Rp 0

  Scenario: INT-004 Double-tap prevention (idempotency guard)
    Given I am logged in as Admin
    And I have filled in a valid kasbon form
    When I rapidly tap "Konfirmasi Kasbon" twice in quick succession
    Then the RPC "create_debt_v1" is called exactly once
    And only one kasbon record is created in the database
    And UI shows a loading indicator after the first tap
    And the second tap is silently ignored (_submitted flag = true)
```

---

## Feature 2: Offline Sync

```gherkin
Feature: Offline-First Kasbon Sync
  As a store owner on an unstable 4G connection
  I want browsing to work offline with Hive-cached data
  So that the app never crashes without connectivity

  Background:
    Given the app has been opened at least once while online
    And customer data and product catalog are cached in local Hive storage

  Scenario: INT-005 View cached data while offline
    Given I am logged in as Admin
    And the device is currently offline (airplane mode ON)
    When I navigate to the "Kasbon" tab
    And I navigate to the "Stok" tab
    Then I see the previously cached customer list from Hive
    And I see the previously cached product list from Hive
    And a banner "Mode Offline" is displayed at the top

  Scenario: INT-006 Kasbon creation is blocked offline (financial safety)
    Given I am logged in as Admin
    And the device is currently offline (airplane mode ON)
    When I navigate to "Tambah Kasbon"
    And I select customer "Ibu Sari"
    And I add product "Indomie Goreng" with quantity 1
    And I tap "Konfirmasi Kasbon"
    Then the system shows error dialog about offline state
    And no kasbon record is created
    And stock is NOT modified

  Scenario: INT-007 Auto-refresh when connectivity is restored
    Given I am on the Dashboard while offline
    And the dashboard shows cached metrics from last sync
    When I disable airplane mode (connectivity is restored)
    Then the app detects network restoration within 5 seconds
    And the dashboard automatically refreshes data from Supabase
    And the "Mode Offline" banner disappears
    And the Realtime WebSocket subscription is re-established
```

---

## Feature 3: RBAC — Role-Based Access Control

```gherkin
Feature: Role-Based Access Control (Admin vs Cashier)
  As a store owner
  I want to restrict cashiers from modifying or deleting financial records
  So that only admins can perform sensitive operations

  Background:
    Given there is an existing kasbon with id = "debt-001" and status = "unpaid"

  Scenario: INT-008 Admin CAN delete a kasbon
    Given I am logged in as Admin (admin@warung.test)
    When I navigate to the kasbon detail for "debt-001"
    Then I see a "Hapus Kasbon" button
    When I tap "Hapus Kasbon" and confirm deletion
    Then the kasbon is removed from the active debt list
    And Ibu Sari's total_debt is reverted accordingly

  Scenario: INT-009 Cashier CANNOT delete a kasbon (UI blocked)
    Given I am logged in as Cashier (kasir@warung.test)
    When I navigate to the kasbon detail for "debt-001"
    Then the "Hapus Kasbon" button is NOT visible in the UI

  Scenario: INT-010 Cashier CANNOT delete via direct API call (RLS enforced)
    Given I am authenticated as Cashier with a Cashier JWT token
    When I send a DELETE request to /rest/v1/debts?id=eq.debt-001
    Then the server returns HTTP 403 Forbidden
    And no record is deleted from the database

  Scenario: INT-011 Cashier CAN create a kasbon (permitted action)
    Given I am logged in as Cashier (kasir@warung.test)
    When I navigate to "Tambah Kasbon"
    And I select customer "Ibu Sari"
    And I add product "Indomie Goreng" with quantity 1
    And I tap "Konfirmasi Kasbon"
    Then the kasbon is created successfully
    And UI shows success snackbar "Kasbon berhasil dibuat"

  Scenario: INT-012 Cashier CANNOT modify debt total_amount via PATCH (RLS blocked)
    Given I am authenticated as Cashier with a Cashier JWT token
    When I send PATCH /rest/v1/debts?id=eq.debt-001 with body total_amount=1
    Then the server returns HTTP 403 Forbidden
    And total_amount remains unchanged in the database
```

---

## Feature 4: Real-time Multi-Device Sync

```gherkin
Feature: Real-time Sync Across Devices
  As a store owner with multiple devices
  I want kasbon and stock changes to appear on all devices in real-time
  So that I and my cashier always see the same data

  Background:
    Given Phone A is logged in as Admin (admin@warung.test)
    And Phone B is logged in as Cashier (kasir@warung.test)
    And both phones are connected to the same store ("store-uuid")
    And both phones have an active Supabase Realtime WebSocket connection
    And Indomie Goreng has stock = 10 on both devices

  Scenario: INT-013 New kasbon appears on Phone B within 2 seconds
    Given Phone B is on the "Kasbon" tab showing Ibu Sari total_debt = 0
    When on Phone A, I create a kasbon for Ibu Sari with total_amount = Rp 12.000
    Then within 2 seconds, Phone B shows Ibu Sari's total_debt updated to Rp 12.000
    And stock of Indomie Goreng on Phone B reduces from 10 to 8
    And no manual refresh is needed on Phone B

    # Error Handling
    When the Realtime WebSocket subscription drops on Phone B
    Then Phone B shows a reconnecting indicator
    And within 10 seconds, Realtime reconnects automatically

  Scenario: INT-014 Stock restock propagates to all devices
    Given Phone B is on the "Stok" tab showing Indomie Goreng stock = 10
    When on Phone A, Admin adds +20 stock (reason: restock)
    Then within 2 seconds, Phone B shows Indomie Goreng stock updated to 30

  Scenario: INT-015 Payment update propagates to all devices
    Given Ibu Sari has an active kasbon on both phones showing status = "unpaid"
    When on Phone A, Admin records partial payment of Rp 5.000
    Then within 2 seconds on Phone B:
      - kasbon status changes to "partial"
      - paid_amount shows Rp 5.000
      - remaining_amount shows Rp 7.000
      - customer total_debt shows Rp 7.000
```

---

## Feature 5: Edge Cases & Validation

```gherkin
Feature: Edge Cases — Stock, Credit, and Payment Validation
  As the system
  I want to enforce financial constraints at both the UI and RPC level
  So that inventory accuracy and financial integrity are always maintained

  Background:
    Given I am logged in as Admin
    And Gula Pasir 1kg has stock = 0
    And Indomie Goreng has stock = 3
    And Ibu Sari has total_debt = 0 and max_credit = 500000

  Scenario: INT-016 Kasbon fails with out-of-stock product
    When I navigate to "Tambah Kasbon" and add "Gula Pasir 1kg" qty 1
    Then the "Konfirmasi Kasbon" button is DISABLED
    And an inline warning shows "Stok Gula Pasir 1kg habis"
    When I bypass UI and call create_debt_v1 RPC with gula-uuid qty=1
    Then the RPC raises exception containing "INSUFFICIENT_STOCK"
    And no kasbon record is created
    And Gula Pasir 1kg stock remains at 0

  Scenario: INT-017 Quantity input is capped at current stock
    When I add product "Indomie Goreng" and enter quantity 5 (stock is 3)
    Then the quantity input is automatically capped to 3
    When I force qty=5 via create_debt_v1 RPC
    Then the RPC raises exception containing "INSUFFICIENT_STOCK"

  Scenario: INT-018 Kasbon rejected when customer exceeds credit limit
    Given Ibu Sari has total_debt = Rp 480.000 and max_credit = Rp 500.000
    When I add products totaling Rp 30.000 and tap "Konfirmasi Kasbon"
    Then the system shows error "Limit kredit pelanggan terlampaui."
    And no kasbon is created and no stock is reduced
    When I call create_debt_v1 RPC directly with exceeding total
    Then the RPC raises exception containing "CREDIT_LIMIT_EXCEEDED"

  Scenario: INT-019 Overpayment is rejected
    Given Ibu Sari has a kasbon with remaining_amount = Rp 7.000
    When I navigate to the payment screen and enter Rp 100.000
    Then the "Simpan Pembayaran" button is DISABLED
    And inline validation shows "Jumlah bayar melebihi sisa hutang (Rp 7.000)"
    When I call record_payment_v1('debt-001', 100000) via RPC
    Then the RPC raises exception containing "PAYMENT_EXCEEDS_REMAINING"

  Scenario: INT-020 Concurrent race condition — stock contention resolved by DB lock
    Given Indomie Goreng has stock = 1
    And Phone A and Phone B simultaneously submit kasbon for 1x Indomie Goreng
    When both "create_debt_v1" calls hit the database concurrently
    Then exactly ONE kasbon succeeds (PostgreSQL FOR UPDATE row lock)
    And the second RPC raises exception "INSUFFICIENT_STOCK"
    And Indomie Goreng stock is exactly 0, never negative
    And exactly one stock_mutations record exists with change_amount = -1

  Scenario: INT-021 Empty cart is rejected before submission
    When I navigate to "Tambah Kasbon" and select "Ibu Sari" but add no items
    Then the "Konfirmasi Kasbon" button is DISABLED
    And UI shows "Tambahkan produk untuk membuat kasbon"
```

---

## Performance Benchmarks (Non-Functional)

```gherkin
Feature: Performance Benchmarks
  These are validated via integration test timers against PRD targets.

  Scenario: INT-022 Kasbon creation round-trip under 500ms
    Given a valid kasbon form with 3 items is ready
    When I tap "Konfirmasi Kasbon"
    Then the success confirmation appears within 500ms (PRD: sync_latency < 500ms)

  Scenario: INT-023 Real-time event delivery under 2 seconds
    Given Phone B has an active Realtime WebSocket subscription
    When a kasbon is created on Phone A
    Then Phone B receives the Postgres Change event within 2000ms

  Scenario: INT-024 Product list renders in under 800ms
    Given the product catalog has 200 items
    When I navigate to the "Stok" tab
    Then the first page of 20 products renders within 800ms (PRD target)

  Scenario: INT-025 Cold start under 3 seconds
    Given the app is freshly installed with no local cache
    When I launch the app for the first time
    Then the Login screen is fully rendered within 3 seconds (PRD target)
```

---

## Execution Priority Matrix

| ID      | Test Flow                         | Priority | Environment | Method |
|---------|-----------------------------------|----------|-------------|--------|
| INT-001 | Kasbon creation (multi-item)      | **P0**   | Staging     | Auto   |
| INT-002 | Partial payment                   | **P0**   | Staging     | Auto   |
| INT-003 | Full settlement payment           | **P0**   | Staging     | Auto   |
| INT-004 | Double-tap idempotency guard      | P1       | Staging     | Auto   |
| INT-005 | Offline: view cached data         | P1       | Device      | Manual |
| INT-006 | Offline: kasbon creation blocked  | **P0**   | Device      | Manual |
| INT-007 | Auto-refresh on reconnect         | P1       | Device      | Manual |
| INT-008 | Admin can delete kasbon           | **P0**   | Staging     | Auto   |
| INT-009 | Cashier: delete button hidden     | **P0**   | Staging     | Auto   |
| INT-010 | Cashier: RLS blocks direct DELETE | **P0**   | Staging     | Auto   |
| INT-011 | Cashier can create kasbon         | P1       | Staging     | Auto   |
| INT-012 | Cashier: RLS blocks PATCH         | **P0**   | Staging     | Auto   |
| INT-013 | Real-time: kasbon on Phone B      | **P0**   | 2x Device   | Manual |
| INT-014 | Real-time: stock restock          | P1       | 2x Device   | Manual |
| INT-015 | Real-time: payment update         | P1       | 2x Device   | Manual |
| INT-016 | Out-of-stock rejection            | **P0**   | Staging     | Auto   |
| INT-017 | Quantity capped at stock limit    | **P0**   | Staging     | Auto   |
| INT-018 | Credit limit exceeded             | **P0**   | Staging     | Auto   |
| INT-019 | Overpayment guard                 | **P0**   | Staging     | Auto   |
| INT-020 | Race condition: stock contention  | **P0**   | Staging     | Auto   |
| INT-021 | Empty cart rejected               | P1       | Staging     | Auto   |
| INT-022 | Perf: kasbon RTT < 500ms          | P1       | Staging     | Auto   |
| INT-023 | Perf: real-time < 2s              | P1       | 2x Device   | Manual |
| INT-024 | Perf: product list < 800ms        | P2       | Staging     | Auto   |
| INT-025 | Perf: cold start < 3s             | P2       | Device      | Manual |

> **P0** = Blocker — must pass before release  
> **P1** = High — should pass before release  
> **P2** = Medium — nice-to-have before final release
