-- ============================================================
-- WARUNGPINTAR LITE v2.2 — USER PROFILES & MEMBER MANAGEMENT
-- ============================================================

-- 1. Create Profiles Table (Publicly searchable to link members)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Policies for Profiles
DROP POLICY IF EXISTS "profiles_select_all" ON public.profiles;
CREATE POLICY "profiles_select_all" ON public.profiles FOR SELECT TO authenticated USING (true);

-- 1.5 Fix: Add Foreign Key to store_members to enable relationship joining
ALTER TABLE public.store_members
DROP CONSTRAINT IF EXISTS store_members_user_id_fkey;

ALTER TABLE public.store_members
ADD CONSTRAINT store_members_user_id_fkey
FOREIGN KEY (user_id) REFERENCES public.profiles(id);

-- 2. Trigger to Sync Auth Users to Profiles
CREATE OR REPLACE FUNCTION public.handle_new_profile()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email)
    VALUES (NEW.id, NEW.email);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_profile_created ON auth.users;
CREATE TRIGGER on_auth_user_profile_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_profile();

-- Backfill profiles for existing users
INSERT INTO public.profiles (id, email)
SELECT id, email FROM auth.users
ON CONFLICT (id) DO NOTHING;

-- 3. RPC to Add Member by Email
CREATE OR REPLACE FUNCTION public.add_store_member_by_email(
    p_store_id UUID,
    p_email TEXT,
    p_role TEXT
) RETURNS VOID AS $$
DECLARE
    v_user_id UUID;
BEGIN
    -- 1. Check if the executor is an admin of the store
    IF NOT public.is_admin_of(p_store_id) THEN
        RAISE EXCEPTION 'Hanya Admin yang dapat menambah karyawan.';
    END IF;

    -- 2. Find the user ID by email
    SELECT id INTO v_user_id FROM public.profiles WHERE email = p_email;
    
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User dengan email % tidak ditemukan. Pastikan kasir sudah mendaftar akun.', p_email;
    END IF;

    -- 3. Add to store_members
    INSERT INTO public.store_members (store_id, user_id, role)
    VALUES (p_store_id, v_user_id, p_role)
    ON CONFLICT (store_id, user_id) DO UPDATE SET role = EXCLUDED.role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
