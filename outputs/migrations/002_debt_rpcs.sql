-- Migration: 002_debt_rpcs
-- Description: RPC functions for atomic debt creation and payment management

-- =========== UP ===========

-- CREATE DEBT RPC
CREATE OR REPLACE FUNCTION create_debt_v1(
    p_customer_id UUID,
    p_store_id UUID,
    p_items JSONB -- [{product_id, quantity}]
) RETURNS UUID AS $$
DECLARE
    v_debt_id UUID;
    v_total NUMERIC(12,2) := 0;
    v_item RECORD;
    v_customer_debt NUMERIC(12,2);
    v_customer_limit NUMERIC(12,2);
    v_product_stock INTEGER;
    v_product_price NUMERIC(12,2);
BEGIN
    -- 1. Verify membership
    IF NOT EXISTS (SELECT 1 FROM store_members WHERE store_id = p_store_id AND user_id = auth.uid()) THEN
        RAISE EXCEPTION 'UNAUTHORIZED_MEMBER';
    END IF;

    -- 2. Validate customer & Credit limit
    SELECT total_debt, max_credit INTO v_customer_debt, v_customer_limit
    FROM customers WHERE id = p_customer_id AND store_id = p_store_id;
    
    IF NOT FOUND THEN RAISE EXCEPTION 'CUSTOMER_NOT_FOUND'; END IF;

    -- 3. Pre-calculate total and validate items (Stock & Price)
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id UUID, quantity INTEGER) LOOP
        SELECT stock, selling_price INTO v_product_stock, v_product_price
        FROM products WHERE id = v_item.product_id AND store_id = p_store_id AND is_active = TRUE;
        
        IF NOT FOUND THEN RAISE EXCEPTION 'PRODUCT_NOT_FOUND %', v_item.product_id; END IF;
        IF v_product_stock < v_item.quantity THEN RAISE EXCEPTION 'INSUFFICIENT_STOCK %', v_item.product_id; END IF;
        
        v_total := v_total + (v_product_price * v_item.quantity);
    END LOOP;

    -- 4. Check Credit Limit
    IF (v_customer_debt + v_total) > v_customer_limit THEN
        RAISE EXCEPTION 'CREDIT_LIMIT_EXCEEDED';
    END IF;

    -- 5. Insert Debt Header
    INSERT INTO debts (customer_id, total_amount, paid_amount, status)
    VALUES (p_customer_id, v_total, 0, 'unpaid')
    RETURNING id INTO v_debt_id;

    -- 6. Process Items, Stock & Mutations
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id UUID, quantity INTEGER) LOOP
        SELECT selling_price INTO v_product_price FROM products WHERE id = v_item.product_id;
        
        INSERT INTO debt_items (debt_id, product_id, quantity, price_at_time)
        VALUES (v_debt_id, v_item.product_id, v_item.quantity, v_product_price);

        UPDATE products SET stock = stock - v_item.quantity WHERE id = v_item.product_id;

        INSERT INTO stock_mutations (product_id, change_amount, reason)
        VALUES (v_item.product_id, -v_item.quantity, 'debt');
    END LOOP;

    -- 7. Update Customer
    UPDATE customers SET total_debt = total_debt + v_total WHERE id = p_customer_id;

    RETURN v_debt_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RECORD PAYMENT RPC
CREATE OR REPLACE FUNCTION record_payment_v1(
    p_debt_id UUID,
    p_amount NUMERIC(12,2),
    p_method TEXT
) RETURNS VOID AS $$
DECLARE
    v_customer_id UUID;
    v_remaining NUMERIC(12,2);
    v_new_paid NUMERIC(12,2);
    v_total NUMERIC(12,2);
    v_status TEXT;
BEGIN
    -- 1. Get Debt Details
    SELECT customer_id, remaining_amount, paid_amount, total_amount 
    INTO v_customer_id, v_remaining, v_new_paid, v_total
    FROM debts WHERE id = p_debt_id;

    IF NOT FOUND THEN RAISE EXCEPTION 'DEBT_NOT_FOUND'; END IF;
    IF p_amount > v_remaining THEN RAISE EXCEPTION 'PAYMENT_EXCEEDS_REMAINING'; END IF;

    -- 2. Insert Payment
    INSERT INTO debt_payments (debt_id, amount, payment_method)
    VALUES (p_debt_id, p_amount, p_method);

    -- 3. Calculate New Status
    v_new_paid := v_new_paid + p_amount;
    IF v_new_paid >= v_total THEN v_status := 'paid';
    ELSE v_status := 'partial';
    END IF;

    -- 4. Update Debt
    UPDATE debts SET 
        paid_amount = v_new_paid,
        status = v_status
    WHERE id = p_debt_id;

    -- 5. Update Customer
    UPDATE customers SET total_debt = total_debt - p_amount WHERE id = v_customer_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =========== DOWN ===========
DROP FUNCTION IF EXISTS create_debt_v1(UUID, UUID, JSONB);
DROP FUNCTION IF EXISTS record_payment_v1(UUID, NUMERIC, TEXT);
