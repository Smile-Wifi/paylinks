create extension if not exists "pgcrypto";
create type user_role as enum ('merchant','admin');
create type merchant_status as enum ('PENDING_VERIFICATION','VERIFIED','REJECTED','SUSPENDED','FROZEN');
create type charge_status as enum ('PENDING','CLAIMED','PAID','REJECTED','EXPIRED','CANCELLED','DISPUTED','FROZEN');
create type dispute_status as enum ('OPEN','UNDER_REVIEW','RESOLVED','CLOSED');

create table public.profiles (id uuid primary key references auth.users(id) on delete cascade, role user_role not null default 'merchant', created_at timestamptz default now());
create table public.merchants (id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade, business_name text not null, business_category text not null, owner_name text not null, city text not null, province text not null, contact_number text not null, email text not null, gcash_number text not null, gcash_name text not null, qr_image text, logo_url text, slug text unique, verification_status merchant_status not null default 'PENDING_VERIFICATION', status merchant_status not null default 'PENDING_VERIFICATION', flags_count int not null default 0, verified_at timestamptz, verified_by uuid, created_at timestamptz default now(), updated_at timestamptz default now(), unique(user_id));
create table public.merchant_settings (id uuid primary key default gen_random_uuid(), merchant_id uuid not null references public.merchants(id) on delete cascade, payment_method text not null default 'GCASH' check (payment_method in ('GCASH')), payment_account_name text not null, payment_account_number text not null, qr_image text, is_active boolean default true, created_at timestamptz default now(), updated_at timestamptz default now());
create table public.charges (id text primary key, merchant_id uuid not null references public.merchants(id), amount_centavos bigint not null check (amount_centavos > 0), currency text not null default 'PHP', description text not null, reference text not null, public_token_hash text not null, status charge_status not null default 'PENDING', payer_name text, payer_ref text, payer_payment_time timestamptz, proof_image text, checklist jsonb, rejection_reason text, expires_at timestamptz not null, created_at timestamptz default now(), claimed_at timestamptz, confirmed_at timestamptz, confirmed_by uuid, unique(merchant_id, payer_ref));
create index idx_charges_merchant on public.charges(merchant_id);
create table public.charge_audit (id uuid primary key default gen_random_uuid(), charge_id text references public.charges(id), merchant_id uuid references public.merchants(id), actor_id uuid, actor_role text, action text not null, previous_status charge_status, new_status charge_status, metadata jsonb default '{}', ip_address text, created_at timestamptz default now());
revoke update, delete on public.charge_audit from anon, authenticated;
create table public.disputes (id uuid primary key default gen_random_uuid(), charge_id text not null references public.charges(id), merchant_id uuid not null references public.merchants(id), customer_name text, reason text not null, description text, evidence_url text, status dispute_status default 'OPEN', assigned_admin uuid, resolution text, created_at timestamptz default now(), resolved_at timestamptz);

alter table public.profiles enable row level security;
alter table public.merchants enable row level security;
alter table public.charges enable row level security;
alter table public.charge_audit enable row level security;
alter table public.disputes enable row level security;
alter table public.merchant_settings enable row level security;

create or replace function public.is_admin() returns boolean as $$ select exists(select 1 from public.profiles where id = auth.uid() and role='admin'); $$ language sql security definer;
create or replace function public.my_merchant_id() returns uuid as $$ select id from public.merchants where user_id = auth.uid(); $$ language sql security definer;

create policy "merchant own profile" on public.merchants for all using (user_id = auth.uid() or public.is_admin());
create policy "merchant own charges" on public.charges for all using (merchant_id = public.my_merchant_id() or public.is_admin());
create policy "merchant own audit" on public.charge_audit for select using (merchant_id = public.my_merchant_id() or public.is_admin());
create policy "merchant own disputes" on public.disputes for select using (merchant_id = public.my_merchant_id() or public.is_admin());
create policy "merchant own settings" on public.merchant_settings for all using (merchant_id = public.my_merchant_id() or public.is_admin());
create policy "own profile" on public.profiles for select using (id = auth.uid() or public.is_admin());

create or replace function public.create_charge(p_amount_centavos bigint, p_description text) returns public.charges as $$
declare v_merchant uuid; v_charge public.charges; v_count int;
begin
  v_merchant := public.my_merchant_id();
  if v_merchant is null then raise exception 'Merchant not found'; end if;
  if exists(select 1 from merchants where id=v_merchant and status in ('SUSPENDED','FROZEN')) then raise exception 'Merchant frozen/suspended'; end if;
  select count(*) into v_count from charges where merchant_id=v_merchant and created_at > now() - interval '1 hour';
  if v_count >= 10 then raise exception 'Rate limit: 10 charges per hour'; end if;
  insert into charges(id, merchant_id, amount_centavos, description, reference, public_token_hash, expires_at) values ('pl_' || encode(gen_random_bytes(9),'hex'), v_merchant, p_amount_centavos, p_description, upper(substr(encode(gen_random_bytes(6),'hex'),1,8)), encode(digest(encode(gen_random_bytes(16),'hex'),'sha256'),'hex'), now() + interval '24 hours') returning * into v_charge;
  insert into charge_audit(charge_id, merchant_id, actor_id, actor_role, action, new_status) values (v_charge.id, v_merchant, auth.uid(),'merchant','CREATED','PENDING');
  return v_charge;
end; $$ language plpgsql security definer;

create or replace function public.confirm_payment(p_charge_id text, p_checklist jsonb) returns public.charges as $$
declare v_charge public.charges;
begin
  if not (p_checklist->>'checked_history'='true' and p_checklist->>'amount_matches'='true' and p_checklist->>'ref_matches'='true' and p_checklist->>'funds_reflected'='true') then raise exception 'All 4 verification checks are required'; end if;
  update charges set status='PAID', confirmed_at=now(), confirmed_by=auth.uid(), checklist=p_checklist where id=p_charge_id and merchant_id=public.my_merchant_id() and status='CLAIMED' returning * into v_charge;
  if v_charge.id is null then raise exception 'Cannot confirm: not CLAIMED or not yours'; end if;
  insert into charge_audit(charge_id, merchant_id, actor_id, actor_role, action, previous_status, new_status, metadata) values (v_charge.id, v_charge.merchant_id, auth.uid(),'merchant','CONFIRMED','CLAIMED','PAID', p_checklist);
  return v_charge;
end; $$ language plpgsql security definer;
