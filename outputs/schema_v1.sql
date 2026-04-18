CREATE TABLE stores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID NOT NULL,
    name TEXT NOT NULL,
    address TEXT,
    phone TEXT,
    max_credit_default NUMERIC(12,2) NOT NULL DEFAULT 500000.00 CHECK (max_credit_default >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT,
    cost_price NUMERIC(12,2) NOT NULL CHECK (cost_price >= 0),
    selling_price NUMERIC(12,2) NOT NULL CHECK (selling_price >= 0),
    stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    min_stock INTEGER NOT NULL DEFAULT 5 CHECK (min_stock >= 0),
    image_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT,
    total_debt NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (total_debt >= 0),
    max_credit NUMERIC(12,2) NOT NULL CHECK (max_credit >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (store_id, phone)
);

CREATE TABLE debts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    total_amount NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0),
    paid_amount NUMERIC(12,2) NOT NULL DEFAULT 0.00 CHECK (paid_amount >= 0),
    remaining_amount NUMERIC(12,2) GENERATED ALWAYS AS (total_amount - paid_amount) STORED,
    status TEXT NOT NULL CHECK (status IN ('unpaid', 'partial', 'paid')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT check_paid_less_total CHECK (paid_amount <= total_amount)
);

CREATE TABLE debt_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    debt_id UUID NOT NULL REFERENCES debts(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    price_at_time NUMERIC(12,2) NOT NULL CHECK (price_at_time >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE debt_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    debt_id UUID NOT NULL REFERENCES debts(id) ON DELETE CASCADE,
    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    payment_method TEXT NOT NULL DEFAULT 'cash',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE sales_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    total_price NUMERIC(12,2) NOT NULL CHECK (total_price >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE stock_mutations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    change_amount INTEGER NOT NULL,
    reason TEXT NOT NULL CHECK (reason IN ('sale', 'debt', 'restock', 'correction')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE store_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id UUID NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('Admin', 'Cashier')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (store_id, user_id)
);

CREATE INDEX idx_stores_created_at ON stores(created_at);

CREATE INDEX idx_products_store_id ON products(store_id);
CREATE INDEX idx_products_category ON products(category);
CREATE INDEX idx_products_created_at ON products(created_at);

CREATE INDEX idx_customers_store_id ON customers(store_id);
CREATE INDEX idx_customers_total_debt ON customers(total_debt);
CREATE INDEX idx_customers_created_at ON customers(created_at);

CREATE INDEX idx_debts_customer_id ON debts(customer_id);
CREATE INDEX idx_debts_status ON debts(status);
CREATE INDEX idx_debts_created_at ON debts(created_at);

CREATE INDEX idx_debt_items_debt_id ON debt_items(debt_id);
CREATE INDEX idx_debt_items_product_id ON debt_items(product_id);
CREATE INDEX idx_debt_items_created_at ON debt_items(created_at);

CREATE INDEX idx_debt_payments_debt_id ON debt_payments(debt_id);
CREATE INDEX idx_debt_payments_created_at ON debt_payments(created_at);

CREATE INDEX idx_sales_log_product_id ON sales_log(product_id);
CREATE INDEX idx_sales_log_created_at ON sales_log(created_at);

CREATE INDEX idx_stock_mutations_product_id ON stock_mutations(product_id);
CREATE INDEX idx_stock_mutations_created_at ON stock_mutations(created_at);

CREATE INDEX idx_store_members_store_id ON store_members(store_id);
CREATE INDEX idx_store_members_user_id ON store_members(user_id);
CREATE INDEX idx_store_members_created_at ON store_members(created_at);

ALTER TABLE stores ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE debts ENABLE ROW LEVEL SECURITY;
ALTER TABLE debt_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE debt_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_mutations ENABLE ROW LEVEL SECURITY;
ALTER TABLE store_members ENABLE ROW LEVEL SECURITY;