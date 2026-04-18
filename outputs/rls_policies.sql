Ran command: `sqlparse --parse outputs/schema_v1.sql`
Ran command: `cat response.sql > prompts/phase1_foundation/responses/01_schema_response.sql`
Viewed schema_v1.sql:1-128

-- ==========================================
-- 1. STORES
-- Policy: Owner only, no delete. 
-- Note: Store members can also view their store.
-- ==========================================
ALTER TABLE stores ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members_can_view_stores"
ON stores FOR SELECT
USING (
  id IN (SELECT store_id FROM store_members WHERE user_id = auth.uid()) 
  OR owner_id = auth.uid()
);

CREATE POLICY "owner_can_insert_stores"
ON stores FOR INSERT
WITH CHECK (owner_id = auth.uid());

CREATE POLICY "owner_can_update_stores"
ON stores FOR UPDATE
USING (owner_id = auth.uid())
WITH CHECK (owner_id = auth.uid());

-- NO DELETE policy for stores

-- ==========================================
-- 2. STORE_MEMBERS
-- Policy: Owner only.
-- ==========================================
ALTER TABLE store_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner_can_view_store_members"
ON store_members FOR SELECT
USING (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()));

CREATE POLICY "owner_can_insert_store_members"
ON store_members FOR INSERT
WITH CHECK (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()));

CREATE POLICY "owner_can_update_store_members"
ON store_members FOR UPDATE
USING (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()))
WITH CHECK (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()));

CREATE POLICY "owner_only_delete_store_members"
ON store_members FOR DELETE
USING (store_id IN (SELECT id FROM stores WHERE owner_id = auth.uid()));

-- ==========================================
-- 3. PRODUCTS
-- Policy: Admin full, Cashier read-only.
-- Threat prevented: Cashier deleting products or changing selling prices.
-- ==========================================
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members_can_view_products"
ON products FOR SELECT
USING (store_id IN (
  SELECT store_id FROM store_members 
  WHERE user_id = auth.uid()
));

CREATE POLICY "admin_can_insert_products"
ON products FOR INSERT
WITH CHECK (store_id IN (
  SELECT store_id FROM store_members
  WHERE user_id = auth.uid() AND role = 'Admin'
));

CREATE POLICY "admin_can_update_products"
ON products FOR UPDATE
USING (store_id IN (
  SELECT store_id FROM store_members
  WHERE user_id = auth.uid() AND role = 'Admin'
))
WITH CHECK (store_id IN (
  SELECT store_id FROM store_members
  WHERE user_id = auth.uid() AND role = 'Admin'
));

CREATE POLICY "admin_only_delete_products"
ON products FOR DELETE
USING (store_id IN (
  SELECT store_id FROM store_members
  WHERE user_id = auth.uid() AND role = 'Admin'
));

-- ==========================================
-- 4. CUSTOMERS
-- Policy: Admin full, Cashier read-only.
-- ==========================================
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members_can_view_customers"
ON customers FOR SELECT
USING (store_id IN (
  SELECT store_id FROM store_members 
  WHERE user_id = auth.uid()
));

-- [MED-04 FIX] Changed from Admin-only to all members.
-- Cashiers need to create customers during kasbon flow (PRD requirement).
CREATE POLICY "members_can_insert_customers"
ON customers FOR INSERT
WITH CHECK (store_id IN (
  SELECT store_id FROM store_members
  WHERE user_id = auth.uid()
));

CREATE POLICY "admin_can_update_customers"
ON customers FOR UPDATE
USING (store_id IN (
  SELECT store_id FROM store_members
  WHERE user_id = auth.uid() AND role = 'Admin'
))
WITH CHECK (store_id IN (
  SELECT store_id FROM store_members
  WHERE user_id = auth.uid() AND role = 'Admin'
));

CREATE POLICY "admin_only_delete_customers"
ON customers FOR DELETE
USING (store_id IN (
  SELECT store_id FROM store_members
  WHERE user_id = auth.uid() AND role = 'Admin'
));

-- ==========================================
-- 5. DEBTS
-- Policy: Admin full, Cashier can create/update status.
-- ==========================================
ALTER TABLE debts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members_can_view_debts"
ON debts FOR SELECT
USING (customer_id IN (
  SELECT id FROM customers WHERE store_id IN (
    SELECT store_id FROM store_members WHERE user_id = auth.uid()
  )
));

CREATE POLICY "members_can_insert_debts"
ON debts FOR INSERT
WITH CHECK (customer_id IN (
  SELECT id FROM customers WHERE store_id IN (
    SELECT store_id FROM store_members WHERE user_id = auth.uid()
  )
));

CREATE POLICY "members_can_update_debts"
ON debts FOR UPDATE
USING (customer_id IN (
  SELECT id FROM customers WHERE store_id IN (
    SELECT store_id FROM store_members WHERE user_id = auth.uid()
  )
))
WITH CHECK (customer_id IN (
  SELECT id FROM customers WHERE store_id IN (
    SELECT store_id FROM store_members WHERE user_id = auth.uid()
  )
));

CREATE POLICY "admin_only_delete_debts"
ON debts FOR DELETE
USING (customer_id IN (
  SELECT id FROM customers WHERE store_id IN (
    SELECT store_id FROM store_members WHERE user_id = auth.uid() AND role = 'Admin'
  )
));

-- ==========================================
-- 6. DEBT_ITEMS
-- Policy: Inherit from debts (Admin full, Cashier create/read).
-- ==========================================
ALTER TABLE debt_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members_can_view_debt_items"
ON debt_items FOR SELECT
USING (debt_id IN (
  SELECT id FROM debts WHERE customer_id IN (
    SELECT id FROM customers WHERE store_id IN (
      SELECT store_id FROM store_members WHERE user_id = auth.uid()
    )
  )
));

CREATE POLICY "members_can_insert_debt_items"
ON debt_items FOR INSERT
WITH CHECK (debt_id IN (
  SELECT id FROM debts WHERE customer_id IN (
    SELECT id FROM customers WHERE store_id IN (
      SELECT store_id FROM store_members WHERE user_id = auth.uid()
    )
  )
));

CREATE POLICY "admin_can_update_debt_items"
ON debt_items FOR UPDATE
USING (debt_id IN (
  SELECT id FROM debts WHERE customer_id IN (
    SELECT id FROM customers WHERE store_id IN (
      SELECT store_id FROM store_members WHERE user_id = auth.uid() AND role = 'Admin'
    )
  )
));

CREATE POLICY "admin_only_delete_debt_items"
ON debt_items FOR DELETE
USING (debt_id IN (
  SELECT id FROM debts WHERE customer_id IN (
    SELECT id FROM customers WHERE store_id IN (
      SELECT store_id FROM store_members WHERE user_id = auth.uid() AND role = 'Admin'
    )
  )
));

-- ==========================================
-- 7. DEBT_PAYMENTS
-- Policy: Admin full, Cashier can create (only).
-- Threat prevented: Unauthorized modification of financial records.
-- ==========================================
ALTER TABLE debt_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members_can_view_debt_payments"
ON debt_payments FOR SELECT
USING (debt_id IN (
  SELECT id FROM debts WHERE customer_id IN (
    SELECT id FROM customers WHERE store_id IN (
      SELECT store_id FROM store_members WHERE user_id = auth.uid()
    )
  )
));

CREATE POLICY "members_can_insert_debt_payments"
ON debt_payments FOR INSERT
WITH CHECK (debt_id IN (
  SELECT id FROM debts WHERE customer_id IN (
    SELECT id FROM customers WHERE store_id IN (
      SELECT store_id FROM store_members WHERE user_id = auth.uid()
    )
  )
));

CREATE POLICY "admin_can_update_debt_payments"
ON debt_payments FOR UPDATE
USING (debt_id IN (
  SELECT id FROM debts WHERE customer_id IN (
    SELECT id FROM customers WHERE store_id IN (
      SELECT store_id FROM store_members WHERE user_id = auth.uid() AND role = 'Admin'
    )
  )
));

CREATE POLICY "admin_only_delete_debt_payments"
ON debt_payments FOR DELETE
USING (debt_id IN (
  SELECT id FROM debts WHERE customer_id IN (
    SELECT id FROM customers WHERE store_id IN (
      SELECT store_id FROM store_members WHERE user_id = auth.uid() AND role = 'Admin'
    )
  )
));

-- ==========================================
-- 8. SALES_LOG
-- Policy: Admin full, Cashier create-only (and read).
-- ==========================================
ALTER TABLE sales_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members_can_view_sales_log"
ON sales_log FOR SELECT
USING (product_id IN (
  SELECT id FROM products WHERE store_id IN (
    SELECT store_id FROM store_members WHERE user_id = auth.uid()
  )
));

CREATE POLICY "members_can_insert_sales_log"
ON sales_log FOR INSERT
WITH CHECK (product_id IN (
  SELECT id FROM products WHERE store_id IN (
    SELECT store_id FROM store_members WHERE user_id = auth.uid()
  )
));

CREATE POLICY "admin_can_update_sales_log"
ON sales_log FOR UPDATE
USING (product_id IN (
  SELECT id FROM products WHERE store_id IN (
    SELECT store_id FROM store_members WHERE user_id = auth.uid() AND role = 'Admin'
  )
));

CREATE POLICY "admin_only_delete_sales_log"
ON sales_log FOR DELETE
USING (product_id IN (
  SELECT id FROM products WHERE store_id IN (
    SELECT store_id FROM store_members WHERE user_id = auth.uid() AND role = 'Admin'
  )
));

-- ==========================================
-- 9. STOCK_MUTATIONS
-- Policy: Audit only (Admin can read; no manual INSERT/UPDATE/DELETE).
-- Note: Mutations should be recorded by background triggers or secure functions.
-- ==========================================
ALTER TABLE stock_mutations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_can_view_stock_mutations"
ON stock_mutations FOR SELECT
USING (product_id IN (
  SELECT id FROM products WHERE store_id IN (
    SELECT store_id FROM store_members WHERE user_id = auth.uid() AND role = 'Admin'
  )
));

-- NO INSERT, UPDATE, DELETE policies for stock_mutations