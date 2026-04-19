-- ============================================================
-- WARUNGPINTAR LITE v2.1 — MEGA UPDATE (SALES, EXPENSES, PROFIT)
-- ============================================================

-- 1. CREATE EXPENSES TABLE
CREATE TABLE IF NOT EXISTS public.expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    created_by UUID,
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_expenses_store ON public.expenses(store_id);

-- Enable RLS on expenses
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

-- Expenses policies
CREATE POLICY "expenses_select" ON public.expenses FOR SELECT TO authenticated USING (public.is_member_of(store_id));
CREATE POLICY "expenses_insert" ON public.expenses FOR INSERT TO authenticated WITH CHECK (public.is_member_of(store_id));
CREATE POLICY "expenses_update" ON public.expenses FOR UPDATE TO authenticated USING (public.is_member_of(store_id));
CREATE POLICY "expenses_delete" ON public.expenses FOR DELETE TO authenticated USING (public.is_admin_of(store_id));


-- 2. CREATE RPC FUNC FOR DIRECT CASH SALES
CREATE OR REPLACE FUNCTION public.record_direct_sale(
    p_store_id UUID, p_items jsonb
) RETURNS void AS $$
DECLARE
    v_item RECORD;
    v_product RECORD;
BEGIN
    -- Loop through items and process sale
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id UUID, quantity INTEGER)
    LOOP
        SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id FOR UPDATE;
        
        IF NOT FOUND THEN RAISE EXCEPTION 'Produk tidak ditemukan: %', v_item.product_id; END IF;
        IF v_product.stock < v_item.quantity THEN
            RAISE EXCEPTION 'Stok % tidak cukup (sisa: %, diminta: %)', v_product.name, v_product.stock, v_item.quantity;
        END IF;

        -- 1. Record to sales_log WITH cost_price to calculate profit
        INSERT INTO public.sales_log (
            store_id, product_id, cashier_id, quantity, 
            cost_price_at_time, selling_price_at_time, total_price
        )
        VALUES (
            p_store_id, v_item.product_id, auth.uid(), v_item.quantity,
            v_product.cost_price, v_product.selling_price, (v_product.selling_price * v_item.quantity)
        );

        -- 2. Reduce stock
        UPDATE public.products SET stock = stock - v_item.quantity WHERE id = v_item.product_id;
        
        -- 3. Record mutation
        INSERT INTO public.stock_mutations (product_id, change_amount, reason, actor_id)
        VALUES (v_item.product_id, -v_item.quantity, 'sale', auth.uid());
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 3. UPDATE DASHBOARD SUMMARY RPC TO INCLUDE PROFIT & EXPENSES
CREATE OR REPLACE FUNCTION public.get_dashboard_summary(p_store_id UUID)
RETURNS jsonb AS $$
DECLARE
    v_today_sales NUMERIC := 0;
    v_today_profit NUMERIC := 0;
    v_today_expenses NUMERIC := 0;
    v_active_debts NUMERIC := 0;
    v_active_debts_count INTEGER := 0;
    v_low_stock INTEGER := 0;
    v_trend jsonb;
    v_top jsonb;
BEGIN
    -- Today's sales (Gross) and Profit (Net Revenue - Cost)
    SELECT 
        COALESCE(SUM(total_price), 0),
        COALESCE(SUM(total_price - (cost_price_at_time * quantity)), 0)
    INTO v_today_sales, v_today_profit
    FROM public.sales_log 
    WHERE store_id = p_store_id AND created_at >= CURRENT_DATE;

    -- Today's Expenses
    SELECT COALESCE(SUM(amount), 0) INTO v_today_expenses
    FROM public.expenses 
    WHERE store_id = p_store_id AND created_at >= CURRENT_DATE;

    -- Net Profit (Laba Bersih) = Profit Margin - Expenses
    v_today_profit := v_today_profit - v_today_expenses;

    -- Active debts
    SELECT COALESCE(SUM(remaining_amount), 0), COUNT(*) INTO v_active_debts, v_active_debts_count
    FROM public.debts WHERE store_id = p_store_id AND status != 'paid';

    -- Low stock count
    SELECT COUNT(*) INTO v_low_stock
    FROM public.products WHERE store_id = p_store_id AND is_active = TRUE AND stock <= min_stock;

    -- 7-day sales trend (Gross)
    SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb) INTO v_trend FROM (
        SELECT d::date AS date, COALESCE(SUM(sl.total_price), 0) AS revenue
        FROM generate_series(CURRENT_DATE - INTERVAL '6 days', CURRENT_DATE, '1 day') d
        LEFT JOIN public.sales_log sl ON sl.created_at::date = d AND sl.store_id = p_store_id
        GROUP BY d ORDER BY d
    ) t;

    -- Top 5 products
    SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb) INTO v_top FROM (
        SELECT p.name AS product_name, SUM(sl.quantity) AS total_qty_sold, SUM(sl.total_price) AS total_revenue
        FROM public.sales_log sl JOIN public.products p ON sl.product_id = p.id
        WHERE sl.store_id = p_store_id AND sl.created_at >= CURRENT_DATE - INTERVAL '7 days'
        GROUP BY p.name ORDER BY total_qty_sold DESC LIMIT 5
    ) t;

    RETURN jsonb_build_object(
        'today_sales', v_today_sales,
        'today_profit', v_today_profit,
        'today_expenses', v_today_expenses,
        'active_debts_total', v_active_debts,
        'active_debts_count', v_active_debts_count,
        'low_stock_count', v_low_stock,
        'sales_trend_7d', v_trend,
        'top_products', v_top,
        'updated_at', now()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;
