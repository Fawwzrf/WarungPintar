-- ============================================================
-- [K-02 FIX] Non-Recursive RLS Policies for WarungPintar Lite v2.0
-- ============================================================
-- PENTING: Jalankan file ini di Supabase SQL Editor SETELAH
-- menjalankan 001_create_schema.sql dan 002_debt_rpcs.sql
--
-- Kebijakan ini menghindari recursive loop antara stores ↔ store_members
-- dengan menggunakan auth.uid() langsung tanpa cross-table subquery.
-- ============================================================

-- ──────────────────────────────────────────────
-- 0. RESET: Matikan dan bersihkan semua policy lama
-- ──────────────────────────────────────────────
ALTER TABLE public.stores DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.store_members DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.products DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.debts DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.debt_items DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.debt_payments DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_log DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_mutations DISABLE ROW LEVEL SECURITY;

-- Drop semua policy yang mungkin tersisa
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT policyname, tablename 
        FROM pg_policies 
        WHERE schemaname = 'public'
    ) LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', r.policyname, r.tablename);
    END LOOP;
END $$;

-- ──────────────────────────────────────────────
-- 1. STORE_MEMBERS — Kunci utama, TIDAK BOLEH query tabel lain
-- ──────────────────────────────────────────────
ALTER TABLE public.store_members ENABLE ROW LEVEL SECURITY;

-- User hanya bisa melihat keanggotaan DIRI SENDIRI (tanpa subquery!)
CREATE POLICY "sm_select_own"
ON public.store_members FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- Hanya pemilik toko (owner) yang bisa menambah anggota baru
-- Mengecek ke tabel stores (bukan store_members → aman, tidak recursive)
CREATE POLICY "sm_insert_owner"
ON public.store_members FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (SELECT 1 FROM public.stores WHERE id = store_id AND owner_id = auth.uid())
);

-- Hanya pemilik toko yang bisa update/delete anggota
CREATE POLICY "sm_modify_owner"
ON public.store_members FOR UPDATE
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.stores WHERE id = store_id AND owner_id = auth.uid())
);

CREATE POLICY "sm_delete_owner"
ON public.store_members FOR DELETE
TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.stores WHERE id = store_id AND owner_id = auth.uid())
);

-- ──────────────────────────────────────────────
-- 2. STORES — Pemilik bisa lihat tokonya, anggota juga bisa
-- ──────────────────────────────────────────────
ALTER TABLE public.stores ENABLE ROW LEVEL SECURITY;

-- Pemilik OR anggota bisa melihat toko
-- Mengecek ke store_members (aman karena store_members policy hanya cek auth.uid())
CREATE POLICY "stores_select"
ON public.stores FOR SELECT
TO authenticated
USING (
    owner_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.store_members WHERE store_id = id AND user_id = auth.uid())
);

-- Hanya pemilik yang bisa update toko
CREATE POLICY "stores_update"
ON public.stores FOR UPDATE
TO authenticated
USING (owner_id = auth.uid());

-- Hanya pemilik yang bisa buat toko baru (owner_id harus diri sendiri)
CREATE POLICY "stores_insert"
ON public.stores FOR INSERT
TO authenticated
WITH CHECK (owner_id = auth.uid());

-- ──────────────────────────────────────────────
-- Helper: Function to check store membership (untuk tabel data)
-- Ini AMAN karena store_members RLS hanya cek user_id = auth.uid()
-- ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_member_of(p_store_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.store_members 
        WHERE store_id = p_store_id AND user_id = auth.uid()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Helper: Check if user is Admin of a store
CREATE OR REPLACE FUNCTION public.is_admin_of(p_store_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.store_members 
        WHERE store_id = p_store_id AND user_id = auth.uid() AND role = 'Admin'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ──────────────────────────────────────────────
-- 3. PRODUCTS — Semua anggota bisa lihat, hanya Admin bisa CRUD
-- ──────────────────────────────────────────────
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "products_select"
ON public.products FOR SELECT
TO authenticated
USING (public.is_member_of(store_id));

CREATE POLICY "products_insert"
ON public.products FOR INSERT
TO authenticated
WITH CHECK (public.is_admin_of(store_id));

CREATE POLICY "products_update"
ON public.products FOR UPDATE
TO authenticated
USING (public.is_admin_of(store_id));

CREATE POLICY "products_delete"
ON public.products FOR DELETE
TO authenticated
USING (public.is_admin_of(store_id));

-- ──────────────────────────────────────────────
-- 4. CUSTOMERS — Semua anggota bisa lihat & tambah
-- ──────────────────────────────────────────────
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "customers_select"
ON public.customers FOR SELECT
TO authenticated
USING (public.is_member_of(store_id));

CREATE POLICY "customers_insert"
ON public.customers FOR INSERT
TO authenticated
WITH CHECK (public.is_member_of(store_id));

CREATE POLICY "customers_update"
ON public.customers FOR UPDATE
TO authenticated
USING (public.is_member_of(store_id));

CREATE POLICY "customers_delete"
ON public.customers FOR DELETE
TO authenticated
USING (public.is_admin_of(store_id));

-- ──────────────────────────────────────────────
-- 5. DEBTS — Semua anggota toko bisa CRUD via customer → store_id
-- ──────────────────────────────────────────────
ALTER TABLE public.debts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "debts_select"
ON public.debts FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.customers c
        WHERE c.id = customer_id AND public.is_member_of(c.store_id)
    )
);

CREATE POLICY "debts_insert"
ON public.debts FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.customers c
        WHERE c.id = customer_id AND public.is_member_of(c.store_id)
    )
);

CREATE POLICY "debts_update"
ON public.debts FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.customers c
        WHERE c.id = customer_id AND public.is_member_of(c.store_id)
    )
);

-- ──────────────────────────────────────────────
-- 6. DEBT_ITEMS — Akses via debt → customer → store
-- ──────────────────────────────────────────────
ALTER TABLE public.debt_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "debt_items_select"
ON public.debt_items FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.debts d
        JOIN public.customers c ON d.customer_id = c.id
        WHERE d.id = debt_id AND public.is_member_of(c.store_id)
    )
);

CREATE POLICY "debt_items_insert"
ON public.debt_items FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.debts d
        JOIN public.customers c ON d.customer_id = c.id
        WHERE d.id = debt_id AND public.is_member_of(c.store_id)
    )
);

-- ──────────────────────────────────────────────
-- 7. DEBT_PAYMENTS — Akses via debt → customer → store
-- ──────────────────────────────────────────────
ALTER TABLE public.debt_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "debt_payments_select"
ON public.debt_payments FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.debts d
        JOIN public.customers c ON d.customer_id = c.id
        WHERE d.id = debt_id AND public.is_member_of(c.store_id)
    )
);

CREATE POLICY "debt_payments_insert"
ON public.debt_payments FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.debts d
        JOIN public.customers c ON d.customer_id = c.id
        WHERE d.id = debt_id AND public.is_member_of(c.store_id)
    )
);

-- ──────────────────────────────────────────────
-- 8. SALES_LOG — Akses via product → store
-- ──────────────────────────────────────────────
ALTER TABLE public.sales_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sales_log_select"
ON public.sales_log FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.products p
        WHERE p.id = product_id AND public.is_member_of(p.store_id)
    )
);

CREATE POLICY "sales_log_insert"
ON public.sales_log FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.products p
        WHERE p.id = product_id AND public.is_member_of(p.store_id)
    )
);

-- ──────────────────────────────────────────────
-- 9. STOCK_MUTATIONS — Akses via product → store
-- ──────────────────────────────────────────────
ALTER TABLE public.stock_mutations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "stock_mutations_select"
ON public.stock_mutations FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.products p
        WHERE p.id = product_id AND public.is_member_of(p.store_id)
    )
);

CREATE POLICY "stock_mutations_insert"
ON public.stock_mutations FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.products p
        WHERE p.id = product_id AND public.is_member_of(p.store_id)
    )
);

-- ──────────────────────────────────────────────
-- 10. STORAGE POLICIES — Foto produk
-- ──────────────────────────────────────────────
-- Izinkan semua user yang terautentikasi untuk membaca foto produk
DROP POLICY IF EXISTS "Public Access" ON storage.objects;
CREATE POLICY "storage_public_read"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'products');

-- Izinkan upload foto oleh user terautentikasi
CREATE POLICY "storage_auth_upload"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'products');

-- Izinkan update foto oleh user terautentikasi
CREATE POLICY "storage_auth_update"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'products');

-- ============================================================
-- SELESAI! RLS kini aktif dengan aman tanpa infinite recursion.
-- ============================================================
