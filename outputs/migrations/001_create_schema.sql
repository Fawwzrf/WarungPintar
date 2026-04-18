-- Migration: 20250715_001_create_warungpintar_schema.sql
-- =========== UP ===========

-- Helper function for updated_at triggers
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
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

CREATE TRIGGER trigger_stores_updated_at
    BEFORE UPDATE ON public.stores
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

ALTER TABLE public.stores ENABLE ROW LEVEL SECURITY;

-- 2. customers
CREATE TABLE public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT,
    total_debt NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (total_debt >= 0),
    max_credit NUMERIC(12,2) NOT NULL CHECK (max_credit >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (store_id, phone)
);

CREATE TRIGGER trigger_customers_updated_at
    BEFORE UPDATE ON public.customers
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

-- 3. products
CREATE TABLE public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT,
    cost_price NUMERIC(12,2) NOT NULL CHECK (cost_price >= 0),
    selling_price NUMERIC(12,2) NOT NULL CHECK (selling_price >= 0),
    stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    min_stock INTEGER NOT NULL DEFAULT 5 CHECK (min_stock >= 0),
    image_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trigger_products_updated_at
    BEFORE UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- 4. debts
CREATE TABLE public.debts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    total_amount NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0),
    paid_amount NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (paid_amount >= 0),
    remaining_amount NUMERIC(12,2) GENERATED ALWAYS AS (total_amount - paid_amount) STORED,
    status TEXT NOT NULL CHECK (status IN ('unpaid', 'partial', 'paid')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT check_paid_less_total CHECK (paid_amount <= total_amount)
);

CREATE TRIGGER trigger_debts_updated_at
    BEFORE UPDATE ON public.debts
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

ALTER TABLE public.debts ENABLE ROW LEVEL SECURITY;

-- 5. debt_items
CREATE TABLE public.debt_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    debt_id UUID NOT NULL REFERENCES public.debts(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    price_at_time NUMERIC(12,2) NOT NULL CHECK (price_at_time >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    -- No updated_at for append-only items
);

ALTER TABLE public.debt_items ENABLE ROW LEVEL SECURITY;

-- 6. debt_payments
CREATE TABLE public.debt_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    debt_id UUID NOT NULL REFERENCES public.debts(id) ON DELETE CASCADE,
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    payment_method TEXT NOT NULL DEFAULT 'cash',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    -- No updated_at for append-only log
);

ALTER TABLE public.debt_payments ENABLE ROW LEVEL SECURITY;

-- 7. sales_log
CREATE TABLE public.sales_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    total_price NUMERIC(12,2) NOT NULL CHECK (total_price >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.sales_log ENABLE ROW LEVEL SECURITY;

-- 8. stock_mutations
CREATE TABLE public.stock_mutations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    change_amount INTEGER NOT NULL,
    reason TEXT NOT NULL CHECK (reason IN ('sale', 'debt', 'restock', 'correction')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.stock_mutations ENABLE ROW LEVEL SECURITY;

-- 9. store_members
CREATE TABLE public.store_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('Admin', 'Cashier')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (store_id, user_id)
);

CREATE TRIGGER trigger_store_members_updated_at
    BEFORE UPDATE ON public.store_members
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

ALTER TABLE public.store_members ENABLE ROW LEVEL SECURITY;

-- Indexes for performance
CREATE INDEX idx_stores_created_at ON public.stores(created_at);
CREATE INDEX idx_products_store_id ON public.products(store_id);
CREATE INDEX idx_products_category ON public.products(category);
CREATE INDEX idx_products_created_at ON public.products(created_at);
CREATE INDEX idx_customers_store_id ON public.customers(store_id);
CREATE INDEX idx_customers_total_debt ON public.customers(total_debt);
CREATE INDEX idx_customers_created_at ON public.customers(created_at);
CREATE INDEX idx_debts_customer_id ON public.debts(customer_id);
CREATE INDEX idx_debts_status ON public.debts(status);
CREATE INDEX idx_debts_created_at ON public.debts(created_at);
CREATE INDEX idx_debt_items_debt_id ON public.debt_items(debt_id);
CREATE INDEX idx_debt_items_product_id ON public.debt_items(product_id);
CREATE INDEX idx_debt_payments_debt_id ON public.debt_payments(debt_id);
CREATE INDEX idx_sales_log_product_id ON public.sales_log(product_id);
CREATE INDEX idx_sales_log_created_at ON public.sales_log(created_at);
CREATE INDEX idx_stock_mutations_product_id ON public.stock_mutations(product_id);
CREATE INDEX idx_stock_mutations_created_at ON public.stock_mutations(created_at);
CREATE INDEX idx_store_members_store_id ON public.store_members(store_id);
CREATE INDEX idx_store_members_user_id ON public.store_members(user_id);

-- End of schema creation