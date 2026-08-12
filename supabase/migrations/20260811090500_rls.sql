-- 20260811090500_rls.sql — the security boundary.
--
-- This file is what replaces `api/src/auth/middleware.ts` and every per-route
-- role guard. Read it as the answer to one question: "a hostile client holds the
-- anon key and can call anything — what stops it?"
--
-- The shape is deliberate and it is not the obvious one:
--
--   READS  go direct to tables and views, gated by RLS on role.
--   WRITES do not exist. anon and authenticated hold NO INSERT, UPDATE or
--          DELETE privilege on any table, and no table carries a write policy.
--          Every mutation goes through a SECURITY DEFINER function that checks
--          the caller's role and enforces the rule before touching a row.
--
-- Why withhold writes entirely rather than write careful per-table policies: a
-- policy can only judge the row in front of it. It cannot see that this INSERT
-- into payment_allocations is the third of five that must all land or none, nor
-- that receivables.paid must move by exactly the same amount. The nine
-- transactional endpoints were transactional for a reason, and a policy has no
-- way to express it. Funnelling writes through functions keeps the transaction
-- boundary that the API owned.

-- ── Baseline privileges ──────────────────────────────────────────────────────
-- Supabase grants ALL on new objects in public to anon and authenticated via
-- default privileges. Revoke first, then grant back only SELECT.
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE ALL ON TABLES FROM anon, authenticated;

GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- ── RLS on, everywhere, with no exceptions ───────────────────────────────────
-- A table with RLS enabled and no matching policy denies. Enabling it on every
-- table means a table added later without a policy fails closed, not open.
ALTER TABLE public.profiles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.association_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.families             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.members              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receivables          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receivable_lines     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_allocations  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cash_movements       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log            ENABLE ROW LEVEL SECURITY;

-- ── SELECT: viewer and above ─────────────────────────────────────────────────
-- has_role() returns false for anon, for a suspended account, and for one still
-- pending admin approval, because my_role() returns NULL unless status =
-- 'approved'. The prototype's "sign in and you are in" becomes "sign in and wait
-- to be let in", which is the behaviour api/src/auth/middleware.ts had.

GRANT SELECT ON
  public.association_settings, public.families, public.members,
  public.receivables, public.receivable_lines, public.payments,
  public.payment_allocations, public.cash_movements
TO authenticated;

CREATE POLICY read_settings ON public.association_settings
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_families ON public.families
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_members ON public.members
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_receivables ON public.receivables
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_receivable_lines ON public.receivable_lines
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_payments ON public.payments
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_allocations ON public.payment_allocations
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_cash ON public.cash_movements
  FOR SELECT TO authenticated USING (public.has_role('viewer'));

-- ── audit_log: financeManager and above ──────────────────────────────────────
-- Endpoint 29 was financeManager-gated. A treasurer seeing who cancelled what
-- is an oversight function, not a collection function.
GRANT SELECT ON public.audit_log TO authenticated;
CREATE POLICY read_audit ON public.audit_log
  FOR SELECT TO authenticated USING (public.has_role('financeManager'));

-- ── profiles ─────────────────────────────────────────────────────────────────
-- Own row always readable, otherwise admin only — a pending user must be able
-- to load /auth/me and see that they are pending, which is how the app renders
-- the waiting-for-approval screen. That read must NOT go through has_role(),
-- since has_role() is false for exactly those users.
GRANT SELECT ON public.profiles TO authenticated;
CREATE POLICY read_own_profile ON public.profiles
  FOR SELECT TO authenticated USING (id = auth.uid());
CREATE POLICY read_all_profiles ON public.profiles
  FOR SELECT TO authenticated USING (public.has_role('admin'));

-- Deliberately absent: any INSERT, UPDATE or DELETE policy on any table.
-- If you are about to add one, the write belongs in an RPC instead.

-- ── Function execution ───────────────────────────────────────────────────────
-- Handled in 20260811090800_lockdown.sql, not here, and NOT with
-- ALTER DEFAULT PRIVILEGES.
--
-- The obvious approach is to set a default-privilege rule now so that every
-- function created by later migrations comes out locked. It does not work:
-- issued as the superuser that owns these objects,
--     ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
-- is a silent no-op on PostgreSQL 16.4 — nothing lands in pg_default_acl and the
-- next function created still carries PUBLIC=EXECUTE. Verified directly; see the
-- header of the lockdown migration. Supabase runs migrations as that same kind of
-- role, so this is not a local artefact.
--
-- The privileges the read policies above depend on are granted there too, so that
-- one file holds the complete answer to "what can a client call?".
