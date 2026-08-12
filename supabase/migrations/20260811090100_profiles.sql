-- 20260811090100_profiles.sql
-- Replaces api/migrations/001_users.sql and 002_refresh_tokens.sql.
--
-- `users` is gone. Supabase Auth owns identity in auth.users, so this table
-- carries only what the association adds on top: role and approval state.
-- The primary key IS auth.users.id, which makes auth.uid() a direct key lookup
-- in every RLS policy and removes the id-mapping layer entirely.
--
-- `refresh_tokens` is gone with no replacement. GoTrue owns refresh rotation
-- and reuse detection. See docs/SUPABASE_MIGRATION_PLAN.md for what that costs:
-- the `replaced_by` chain that distinguished rotation from logout is not
-- something GoTrue exposes.
--
-- google_sub is not stored. It was the identity key precisely because it is
-- immutable while an email can be reassigned inside a Workspace domain; that
-- reasoning now lives in auth.identities, which GoTrue maintains.

CREATE TABLE public.profiles (
  id            uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email         text        NOT NULL,
  display_name  text        NOT NULL DEFAULT '',
  picture_url   text,
  role          app_role    NOT NULL DEFAULT 'viewer',
  status        app_status  NOT NULL DEFAULT 'pending',
  approved_by   uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  approved_at   timestamptz,
  last_login_at timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_profiles_email UNIQUE (email)
);

CREATE INDEX ix_profiles_status ON public.profiles (status, role);

CREATE TRIGGER trg_profiles_touch
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- New accounts land as viewer/pending, exactly as 001_users.sql defaulted them,
-- so a Google sign-in grants no access until an admin approves it.
--
-- A trigger on auth.users, not a client insert: if the app created its own
-- profile row it could choose its own role, and the anon key is public.
CREATE OR REPLACE FUNCTION public.handle_new_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
  INSERT INTO public.profiles (id, email, display_name, picture_url)
  VALUES (
    NEW.id,
    coalesce(NEW.email, ''),
    coalesce(NEW.raw_user_meta_data ->> 'full_name',
             NEW.raw_user_meta_data ->> 'name',
             split_part(coalesce(NEW.email, ''), '@', 1)),
    NEW.raw_user_meta_data ->> 'avatar_url'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Rule: nobody may promote themselves, and the last admin cannot be demoted or
-- locked out. Both were app-layer checks in api/src/users/routes.ts; with no
-- app layer they have to be here or they do not exist.
CREATE OR REPLACE FUNCTION public.guard_profile_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  -- Self-elevation. current_user is postgres/service_role during seeding and
  -- migrations, where this guard must not apply.
  IF auth.uid() IS NOT NULL AND NEW.id = auth.uid()
     AND (NEW.role IS DISTINCT FROM OLD.role
          OR NEW.status IS DISTINCT FROM OLD.status) THEN
    RAISE EXCEPTION 'FORBIDDEN: cannot change your own role or status'
      USING ERRCODE = 'RUL00';
  END IF;

  -- Last approved admin standing.
  IF (OLD.role = 'admin' AND OLD.status = 'approved')
     AND (NEW.role IS DISTINCT FROM 'admin' OR NEW.status IS DISTINCT FROM 'approved')
     AND (SELECT count(*) FROM public.profiles
           WHERE role = 'admin' AND status = 'approved' AND id <> OLD.id) = 0 THEN
    RAISE EXCEPTION 'FORBIDDEN: the last approved admin cannot be removed'
      USING ERRCODE = 'RUL00';
  END IF;

  RETURN NEW;
END $$;

CREATE TRIGGER trg_profiles_guard
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_change();

-- ── Role resolution ─────────────────────────────────────────────────────────
-- Deferred from 20260811090000 because these read the table above.

-- NULL for an unauthenticated caller, a suspended account, or one still
-- pending approval — so `>=` comparisons against it are NULL, never true.
-- Fail-closed by construction rather than by remembering to check.
CREATE OR REPLACE FUNCTION public.my_role() RETURNS app_role
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT p.role
    FROM public.profiles p
   WHERE p.id = auth.uid()
     AND p.status = 'approved'
$$;

CREATE OR REPLACE FUNCTION public.has_role(minimum app_role) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT coalesce(public.role_rank(public.my_role()) >= public.role_rank(minimum), false)
$$;

-- Raise rather than return false, so an RPC body cannot forget to branch.
CREATE OR REPLACE FUNCTION public.require_role(minimum app_role) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
  IF NOT public.has_role(minimum) THEN
    RAISE EXCEPTION 'FORBIDDEN: requires % or higher', minimum
      USING ERRCODE = 'RUL00';
  END IF;
END $$;
