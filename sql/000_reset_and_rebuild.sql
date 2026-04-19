-- ============================================================
-- WARUNGPINTAR LITE v2.0 — MASTER DATABASE RESET & REBUILD
-- ============================================================
-- PERINGATAN: Script ini MENGHAPUS SEMUA DATA dan membuat ulang
-- seluruh database dari nol. Jalankan di Supabase SQL Editor.
--
-- Urutan: DROP ALL → CREATE TABLES → CREATE RPCs → RLS → AUTH TRIGGER
-- ============================================================

-- ╔══════════════════════════════════════════════════════════╗
-- ║  BAGIAN 0: HAPUS SEMUANYA                               ║
-- ╚══════════════════════════════════════════════════════════╝

-- Drop triggers on auth.users first
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS handle_new_user_trigger ON auth.users;

-- Drop all RLS policies
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN (SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public') LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', r.policyname, r.tablename);
    END LOOP;
END $$;

-- Drop all tables (cascade handles FKs)
DROP TABLE IF EXISTS public.stock_mutations CASCADE;
DROP TABLE IF EXISTS public.sales_log CASCADE;
DROP TABLE IF EXISTS public.debt_payments CASCADE;
DROP TABLE IF EXISTS public.debt_items CASCADE;
DROP TABLE IF EXISTS public.debts CASCADE;
DROP TABLE IF EXISTS public.products CASCADE;
DROP TABLE IF EXISTS public.customers CASCADE;
DROP TABLE IF EXISTS public.store_members CASCADE;
DROP TABLE IF EXISTS public.stores CASCADE;

-- Drop helper functions
DROP FUNCTION IF EXISTS public.update_updated_at() CASCADE;
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.is_member_of(UUID) CASCADE;
DROP FUNCTION IF EXISTS public.is_admin_of(UUID) CASCADE;
DROP FUNCTION IF EXISTS public.get_dashboard_summary(UUID) CASCADE;
DROP FUNCTION IF EXISTS public.adjust_product_stock(UUID, INTEGER, TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.record_debt_payment(UUID, NUMERIC, TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.create_debt_with_items(UUID, UUID, jsonb, TEXT) CASCADE;

-- ╔══════════════════════════════════════════════════════════╗
-- ║  BAGIAN 1: BUAT TABEL (100% SESUAI PRD §5.3)           ║
-- ╚══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

-- 1. stores
CREATE TABLE public.stores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL,
    name TEXT NOT NULL,
    address TEXT,
    phone TEXT,
    max_credit_default NUMERIC(12,2) NOT NULL DEFAULT 500000.00 CHECK (max_credit_default >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_stores_updated BEFORE UPDATE ON public.stores FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- 2. store_members (PRD: role IN ('admin','cashier') — lowercase)
CREATE TABLE public.store_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('admin', 'cashier')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (store_id, user_id)
);
CREATE TRIGGER trg_sm_updated BEFORE UPDATE ON public.store_members FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- 3. products (PRD §5.3 Table 3 — includes unit, barcode)
CREATE TABLE public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT,
    barcode TEXT,
    cost_price NUMERIC(12,2) NOT NULL CHECK (cost_price >= 0),
    selling_price NUMERIC(12,2) NOT NULL CHECK (selling_price >= 0),
    stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    min_stock INTEGER NOT NULL DEFAULT 5 CHECK (min_stock >= 0),
    unit TEXT NOT NULL DEFAULT 'pcs',
    image_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_products_updated BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- 4. customers (PRD §5.3 Table 4 — includes address, credit_label)
CREATE TABLE public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT,
    address TEXT,
    max_credit NUMERIC(12,2) NOT NULL DEFAULT 500000.00 CHECK (max_credit >= 0),
    total_debt NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (total_debt >= 0),
    credit_label TEXT NOT NULL DEFAULT 'normal' CHECK (credit_label IN ('trusted','normal','watch')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (store_id, phone)
);
CREATE TRIGGER trg_customers_updated BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- 5. debts (PRD §5.3 Table 5 — includes store_id, created_by, due_date, notes)
CREATE TABLE public.debts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    created_by UUID,
    status TEXT NOT NULL DEFAULT 'unpaid' CHECK (status IN ('unpaid', 'partial', 'paid')),
    total_amount NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0),
    paid_amount NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (paid_amount >= 0),
    remaining_amount NUMERIC(12,2) GENERATED ALWAYS AS (total_amount - paid_amount) STORED,
    due_date DATE,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_paid_lte_total CHECK (paid_amount <= total_amount)
);
CREATE TRIGGER trg_debts_updated BEFORE UPDATE ON public.debts FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- 6. debt_items (PRD §5.3 Table 6)
CREATE TABLE public.debt_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    debt_id UUID NOT NULL REFERENCES public.debts(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    price_at_time NUMERIC(12,2) NOT NULL CHECK (price_at_time >= 0),
    subtotal NUMERIC(12,2) GENERATED ALWAYS AS (quantity * price_at_time) STORED,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 7. debt_payments (PRD §5.3 Table 7 — includes received_by)
CREATE TABLE public.debt_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    debt_id UUID NOT NULL REFERENCES public.debts(id) ON DELETE CASCADE,
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    received_by UUID,
    payment_method TEXT NOT NULL DEFAULT 'cash',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 8. sales_log (PRD §5.3 Table 8 — includes store_id, cashier_id, cost/selling snapshots)
CREATE TABLE public.sales_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    cashier_id UUID,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    cost_price_at_time NUMERIC(12,2),
    selling_price_at_time NUMERIC(12,2),
    total_price NUMERIC(12,2) NOT NULL CHECK (total_price >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 9. stock_mutations (PRD §5.3 Table 9 — includes actor_id, notes)
CREATE TABLE public.stock_mutations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    change_amount INTEGER NOT NULL,
    reason TEXT NOT NULL CHECK (reason IN ('sale', 'debt', 'restock', 'correction')),
    actor_id UUID,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_products_store ON public.products(store_id);
CREATE INDEX idx_products_category ON public.products(category);
CREATE INDEX idx_customers_store ON public.customers(store_id);
CREATE INDEX idx_debts_customer ON public.debts(customer_id);
CREATE INDEX idx_debts_store ON public.debts(store_id);
CREATE INDEX idx_debts_status ON public.debts(status);
CREATE INDEX idx_debt_items_debt ON public.debt_items(debt_id);
CREATE INDEX idx_debt_payments_debt ON public.debt_payments(debt_id);
CREATE INDEX idx_sales_log_store ON public.sales_log(store_id);
CREATE INDEX idx_sales_log_product ON public.sales_log(product_id);
CREATE INDEX idx_sales_log_created ON public.sales_log(created_at);
CREATE INDEX idx_stock_mut_product ON public.stock_mutations(product_id);
CREATE INDEX idx_store_members_store ON public.store_members(store_id);
CREATE INDEX idx_store_members_user ON public.store_members(user_id);

-- ╔══════════════════════════════════════════════════════════╗
-- ║  BAGIAN 2: RPC FUNCTIONS                                ║
-- ╚══════════════════════════════════════════════════════════╝

-- 2a. Adjust product stock atomically
CREATE OR REPLACE FUNCTION public.adjust_product_stock(
    p_id UUID, p_change INTEGER, p_reason TEXT
) RETURNS void AS $$
BEGIN
    UPDATE public.products SET stock = stock + p_change WHERE id = p_id;
    IF (SELECT stock FROM public.products WHERE id = p_id) < 0 THEN
        RAISE EXCEPTION 'Stok tidak boleh negatif';
    END IF;
    INSERT INTO public.stock_mutations (product_id, change_amount, reason, actor_id)
    VALUES (p_id, p_change, p_reason, auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2b. Record debt payment atomically
CREATE OR REPLACE FUNCTION public.record_debt_payment(
    p_debt_id UUID, p_amount NUMERIC, p_method TEXT DEFAULT 'cash'
) RETURNS void AS $$
DECLARE
    v_debt RECORD;
BEGIN
    SELECT * INTO v_debt FROM public.debts WHERE id = p_debt_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Kasbon tidak ditemukan'; END IF;
    IF v_debt.remaining_amount <= 0 THEN RAISE EXCEPTION 'Kasbon sudah lunas'; END IF;
    IF p_amount > v_debt.remaining_amount THEN RAISE EXCEPTION 'Pembayaran melebihi sisa hutang'; END IF;

    INSERT INTO public.debt_payments (debt_id, amount, payment_method, received_by)
    VALUES (p_debt_id, p_amount, p_method, auth.uid());

    UPDATE public.debts SET
        paid_amount = paid_amount + p_amount,
        status = CASE WHEN paid_amount + p_amount >= total_amount THEN 'paid'
                      WHEN paid_amount + p_amount > 0 THEN 'partial'
                      ELSE 'unpaid' END
    WHERE id = p_debt_id;

    -- Update customer total_debt
    UPDATE public.customers SET total_debt = total_debt - p_amount
    WHERE id = v_debt.customer_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2c. Create debt with items atomically
CREATE OR REPLACE FUNCTION public.create_debt_with_items(
    p_customer_id UUID, p_store_id UUID, p_items jsonb, p_notes TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_debt_id UUID;
    v_total NUMERIC := 0;
    v_item RECORD;
    v_product RECORD;
    v_customer RECORD;
BEGIN
    SELECT * INTO v_customer FROM public.customers WHERE id = p_customer_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Pelanggan tidak ditemukan'; END IF;

    -- Calculate total and validate stock
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id UUID, quantity INTEGER)
    LOOP
        SELECT * INTO v_product FROM public.products WHERE id = v_item.product_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Produk tidak ditemukan: %', v_item.product_id; END IF;
        IF v_product.stock < v_item.quantity THEN
            RAISE EXCEPTION 'Stok % tidak cukup (sisa: %, diminta: %)', v_product.name, v_product.stock, v_item.quantity;
        END IF;
        v_total := v_total + (v_product.selling_price * v_item.quantity);
    END LOOP;

    -- Check credit limit
    IF v_customer.total_debt + v_total > v_customer.max_credit THEN
        RAISE EXCEPTION 'Melebihi batas kredit pelanggan (limit: Rp %, hutang saat ini: Rp %, kasbon baru: Rp %)',
            v_customer.max_credit, v_customer.total_debt, v_total;
    END IF;

    -- Create debt
    INSERT INTO public.debts (store_id, customer_id, created_by, total_amount, notes)
    VALUES (p_store_id, p_customer_id, auth.uid(), v_total, p_notes)
    RETURNING id INTO v_debt_id;

    -- Create items & reduce stock
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id UUID, quantity INTEGER)
    LOOP
        SELECT selling_price INTO v_product FROM public.products WHERE id = v_item.product_id;
        INSERT INTO public.debt_items (debt_id, product_id, quantity, price_at_time)
        VALUES (v_debt_id, v_item.product_id, v_item.quantity, v_product.selling_price);

        UPDATE public.products SET stock = stock - v_item.quantity WHERE id = v_item.product_id;
        INSERT INTO public.stock_mutations (product_id, change_amount, reason, actor_id)
        VALUES (v_item.product_id, -v_item.quantity, 'debt', auth.uid());
    END LOOP;

    -- Update customer total_debt
    UPDATE public.customers SET total_debt = total_debt + v_total WHERE id = p_customer_id;

    RETURN v_debt_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2d. Dashboard summary RPC
CREATE OR REPLACE FUNCTION public.get_dashboard_summary(p_store_id UUID)
RETURNS jsonb AS $$
DECLARE
    v_today_sales NUMERIC;
    v_active_debts NUMERIC;
    v_active_debts_count INTEGER;
    v_low_stock INTEGER;
    v_trend jsonb;
    v_top jsonb;
BEGIN
    -- Today's sales
    SELECT COALESCE(SUM(total_price), 0) INTO v_today_sales
    FROM public.sales_log WHERE store_id = p_store_id AND created_at >= CURRENT_DATE;

    -- Active debts
    SELECT COALESCE(SUM(remaining_amount), 0), COUNT(*) INTO v_active_debts, v_active_debts_count
    FROM public.debts WHERE store_id = p_store_id AND status != 'paid';

    -- Low stock count
    SELECT COUNT(*) INTO v_low_stock
    FROM public.products WHERE store_id = p_store_id AND is_active = TRUE AND stock <= min_stock;

    -- 7-day sales trend
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
        'active_debts_total', v_active_debts,
        'active_debts_count', v_active_debts_count,
        'low_stock_count', v_low_stock,
        'sales_trend_7d', v_trend,
        'top_products', v_top,
        'updated_at', now()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ╔══════════════════════════════════════════════════════════╗
-- ║  BAGIAN 3: ROW LEVEL SECURITY (Non-Recursive)           ║
-- ╚══════════════════════════════════════════════════════════╝

-- Helper functions (SECURITY DEFINER to break recursion)
CREATE OR REPLACE FUNCTION public.is_member_of(p_store_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (SELECT 1 FROM public.store_members WHERE store_id = p_store_id AND user_id = auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.is_admin_of(p_store_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (SELECT 1 FROM public.store_members WHERE store_id = p_store_id AND user_id = auth.uid() AND role = 'admin');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Enable RLS on all tables
ALTER TABLE public.stores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.store_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.debts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.debt_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.debt_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_mutations ENABLE ROW LEVEL SECURITY;

-- store_members: user sees own memberships only
CREATE POLICY "sm_select" ON public.store_members FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "sm_insert" ON public.store_members FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM public.stores WHERE id = store_id AND owner_id = auth.uid()));
CREATE POLICY "sm_update" ON public.store_members FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM public.stores WHERE id = store_id AND owner_id = auth.uid()));
CREATE POLICY "sm_delete" ON public.store_members FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM public.stores WHERE id = store_id AND owner_id = auth.uid()));

-- stores
CREATE POLICY "stores_select" ON public.stores FOR SELECT TO authenticated USING (owner_id = auth.uid() OR EXISTS (SELECT 1 FROM public.store_members WHERE store_id = id AND user_id = auth.uid()));
CREATE POLICY "stores_insert" ON public.stores FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid());
CREATE POLICY "stores_update" ON public.stores FOR UPDATE TO authenticated USING (owner_id = auth.uid());

-- products
CREATE POLICY "products_select" ON public.products FOR SELECT TO authenticated USING (public.is_member_of(store_id));
CREATE POLICY "products_insert" ON public.products FOR INSERT TO authenticated WITH CHECK (public.is_admin_of(store_id));
CREATE POLICY "products_update" ON public.products FOR UPDATE TO authenticated USING (public.is_member_of(store_id));
CREATE POLICY "products_delete" ON public.products FOR DELETE TO authenticated USING (public.is_admin_of(store_id));

-- customers
CREATE POLICY "customers_select" ON public.customers FOR SELECT TO authenticated USING (public.is_member_of(store_id));
CREATE POLICY "customers_insert" ON public.customers FOR INSERT TO authenticated WITH CHECK (public.is_member_of(store_id));
CREATE POLICY "customers_update" ON public.customers FOR UPDATE TO authenticated USING (public.is_member_of(store_id));
CREATE POLICY "customers_delete" ON public.customers FOR DELETE TO authenticated USING (public.is_admin_of(store_id));

-- debts
CREATE POLICY "debts_select" ON public.debts FOR SELECT TO authenticated USING (public.is_member_of(store_id));
CREATE POLICY "debts_insert" ON public.debts FOR INSERT TO authenticated WITH CHECK (public.is_member_of(store_id));
CREATE POLICY "debts_update" ON public.debts FOR UPDATE TO authenticated USING (public.is_member_of(store_id));

-- debt_items (via debt.store_id)
CREATE POLICY "di_select" ON public.debt_items FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.debts d WHERE d.id = debt_id AND public.is_member_of(d.store_id)));
CREATE POLICY "di_insert" ON public.debt_items FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM public.debts d WHERE d.id = debt_id AND public.is_member_of(d.store_id)));

-- debt_payments
CREATE POLICY "dp_select" ON public.debt_payments FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.debts d WHERE d.id = debt_id AND public.is_member_of(d.store_id)));
CREATE POLICY "dp_insert" ON public.debt_payments FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM public.debts d WHERE d.id = debt_id AND public.is_member_of(d.store_id)));

-- sales_log
CREATE POLICY "sl_select" ON public.sales_log FOR SELECT TO authenticated USING (public.is_member_of(store_id));
CREATE POLICY "sl_insert" ON public.sales_log FOR INSERT TO authenticated WITH CHECK (public.is_member_of(store_id));

-- stock_mutations
CREATE POLICY "stm_select" ON public.stock_mutations FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.products p WHERE p.id = product_id AND public.is_member_of(p.store_id)));
CREATE POLICY "stm_insert" ON public.stock_mutations FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM public.products p WHERE p.id = product_id AND public.is_member_of(p.store_id)));

-- Storage policies for products bucket
DO $$ BEGIN
    INSERT INTO storage.buckets (id, name, public) VALUES ('products', 'products', true) ON CONFLICT DO NOTHING;
END $$;

-- ╔══════════════════════════════════════════════════════════╗
-- ║  BAGIAN 4: AUTH TRIGGER (1 akun baru = 1 toko baru)     ║
-- ╚══════════════════════════════════════════════════════════╝

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE new_store_id UUID;
BEGIN
    INSERT INTO public.stores (owner_id, name)
    VALUES (NEW.id, 'Toko ' || split_part(NEW.email, '@', 1))
    RETURNING id INTO new_store_id;

    INSERT INTO public.store_members (store_id, user_id, role)
    VALUES (new_store_id, NEW.id, 'admin');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- SELESAI! Database siap digunakan.
-- Setiap user baru yang mendaftar akan mendapat toko kosong.
-- ============================================================
