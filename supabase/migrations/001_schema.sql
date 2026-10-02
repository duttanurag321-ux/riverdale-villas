-- Riverdale Villas — Phase 1 / 001: tables, constraints, indexes.
-- Money is ALWAYS bigint paise (1 rupee = 100 paise). Percentages are basis points (10000 = 100%).

create type user_role as enum ('site_manager','salesperson','director');
create type villa_status as enum ('available','reserved','booked','under_construction','completed','handed_over','inactive');
create type booking_status as enum ('draft','confirmed','cancelled','completed');
create type update_status as enum ('not_started','in_progress','delayed','completed');
create type approval_status as enum ('not_required','pending','approved','rejected');
create type milestone_trigger as enum ('booking_confirmed','stage_approved','manual');
create type payment_kind as enum ('receipt','reversal');
create type payment_verification as enum ('pending','verified','rejected');

create table profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  full_name text not null check (length(trim(full_name)) > 0),
  phone text,
  role user_role not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table projects (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  city text, address text, description text,
  created_at timestamptz not null default now()
);

create table construction_stages (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sequence int not null check (sequence > 0),
  requires_approval boolean not null default true,
  target_days int check (target_days is null or target_days >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table villas (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id),
  villa_number text not null,
  plot_details text,
  configuration text,                       -- e.g. '2 BHK'
  land_area numeric(12,2) check (land_area is null or land_area > 0),
  land_unit text not null default 'katha',
  status villa_status not null default 'available',
  current_stage_id uuid references construction_stages(id),
  site_manager_id uuid references profiles(id),
  salesperson_id uuid references profiles(id),
  expected_completion date,
  actual_completion date,
  remarks text,
  created_at timestamptz not null default now(),
  unique (project_id, villa_number)
);

-- Price lives apart from villas so Site Managers (who can read villas) never see money.
create table villa_pricing (
  villa_id uuid primary key references villas(id),
  list_price_paise bigint not null check (list_price_paise > 0)
);

create table customers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (length(trim(full_name)) > 0),
  phone text not null,
  alt_phone text, email text, address text,
  whatsapp_opt_in boolean not null default false,
  whatsapp_opt_in_at timestamptz,
  salesperson_id uuid references profiles(id),
  notes text,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  check (not whatsapp_opt_in or whatsapp_opt_in_at is not null)
);

-- PAN is kept in its own table so RLS can restrict it to the Director only.
create table customer_sensitive (
  customer_id uuid primary key references customers(id),
  pan text check (pan is null or pan ~ '^[A-Z]{5}[0-9]{4}[A-Z]$')
);

create table payment_plan_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  villa_configuration text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table payment_plan_template_milestones (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references payment_plan_templates(id) on delete cascade,
  seq int not null check (seq > 0),
  name text not null,
  kind text not null check (kind in ('percent','fixed')),
  percent_bp int check (percent_bp is null or percent_bp between 1 and 10000),
  fixed_paise bigint check (fixed_paise is null or fixed_paise > 0),
  trigger milestone_trigger not null default 'stage_approved',
  stage_id uuid references construction_stages(id),
  due_days int not null default 0 check (due_days >= 0),
  grace_days int not null default 0 check (grace_days >= 0),
  notify_customer boolean not null default true,
  is_mandatory boolean not null default true,
  unique (template_id, seq),
  check ((kind='percent' and percent_bp is not null and fixed_paise is null)
      or (kind='fixed' and fixed_paise is not null and percent_bp is null)),
  check (trigger <> 'stage_approved' or stage_id is not null)
);

create table bookings (
  id uuid primary key default gen_random_uuid(),
  villa_id uuid not null references villas(id),
  customer_id uuid not null references customers(id),
  salesperson_id uuid references profiles(id),
  status booking_status not null default 'draft',
  booking_date date not null default current_date,
  package_price_paise bigint not null check (package_price_paise > 0),
  extra_charges_paise bigint not null default 0 check (extra_charges_paise >= 0),
  contract_value_paise bigint generated always as (package_price_paise + extra_charges_paise) stored,
  expected_start date, expected_handover date,
  confirmed_at timestamptz, confirmed_by uuid references profiles(id),
  cancelled_at timestamptz, cancel_reason text,
  notes text,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  check (status <> 'cancelled' or (cancelled_at is not null and cancel_reason is not null))
);
-- Only one live booking per villa; cancelled ones stay as history.
create unique index one_live_booking_per_villa on bookings(villa_id) where status in ('draft','confirmed','completed');
create index on bookings(customer_id);
create index on bookings(salesperson_id);

-- Contract-specific schedule: a frozen COPY of the template, never a link to it.
create table booking_payment_milestones (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id),
  seq int not null check (seq > 0),
  name text not null,
  trigger milestone_trigger not null,
  stage_id uuid references construction_stages(id),
  amount_paise bigint not null check (amount_paise > 0),
  source_percent_bp int,
  due_days int not null default 0 check (due_days >= 0),
  grace_days int not null default 0 check (grace_days >= 0),
  notify_customer boolean not null default true,
  is_mandatory boolean not null default true,
  activated_at timestamptz,
  due_date date,
  on_hold boolean not null default false,
  on_hold_reason text,
  cancelled boolean not null default false,
  unique (booking_id, seq),
  check (trigger <> 'stage_approved' or stage_id is not null),
  check ((activated_at is null) = (due_date is null))
);
create unique index one_milestone_per_stage on booking_payment_milestones(booking_id, stage_id) where stage_id is not null;

create table construction_updates (
  id uuid primary key default gen_random_uuid(),
  villa_id uuid not null references villas(id),
  booking_id uuid references bookings(id),
  stage_id uuid not null references construction_stages(id),
  previous_status update_status not null,
  new_status update_status not null,
  remarks text,
  is_issue boolean not null default false,
  submitted_by uuid not null references profiles(id),
  submitted_at timestamptz not null default now(),
  approval approval_status not null,
  approved_by uuid references profiles(id),
  approved_at timestamptz,
  rejection_reason text,
  client_request_id text unique,
  check (approval <> 'rejected' or rejection_reason is not null)
);
create unique index one_pending_update_per_stage on construction_updates(villa_id, stage_id) where approval = 'pending';
create index on construction_updates(villa_id, submitted_at desc);

create table construction_update_photos (
  id uuid primary key default gen_random_uuid(),
  update_id uuid not null references construction_updates(id),
  storage_path text not null,
  created_at timestamptz not null default now()
);

create sequence receipt_number_seq;

-- Immutable ledger. Reversals are separate rows; nothing is edited or deleted.
create table payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id),
  customer_id uuid not null references customers(id),
  kind payment_kind not null default 'receipt',
  amount_paise bigint not null check (amount_paise > 0),
  currency text not null default 'INR' check (currency = 'INR'),
  received_on date not null,
  method text not null check (method in ('upi','bank_transfer','cheque','cash','other')),
  reference text,
  entered_by uuid not null references profiles(id),
  verification payment_verification not null default 'pending',
  verified_by uuid references profiles(id),
  verified_at timestamptz,
  receipt_number text unique,
  receipt_document_path text,
  reverses_payment_id uuid unique references payments(id),
  notes text,
  client_request_id text unique,
  created_at timestamptz not null default now(),
  check (verification <> 'verified' or (verified_by is not null and verified_at is not null)),
  check (kind <> 'receipt' or reverses_payment_id is null),
  check (kind <> 'reversal' or reverses_payment_id is not null),
  check (kind <> 'receipt' or verification <> 'verified' or receipt_number is not null)
);
create index on payments(booking_id);
create index on payments(verification);

create table payment_allocations (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references payments(id),
  milestone_id uuid not null references booking_payment_milestones(id),
  amount_paise bigint not null check (amount_paise <> 0),   -- negative only for reversals
  created_at timestamptz not null default now()
);
create index on payment_allocations(milestone_id);
create index on payment_allocations(payment_id);

create table follow_up_tasks (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings(id),
  milestone_id uuid not null references booking_payment_milestones(id),
  kind text not null default 'payment_due',
  assigned_to uuid references profiles(id),
  status text not null default 'open' check (status in ('open','done','cancelled')),
  priority text not null default 'normal' check (priority in ('low','normal','high')),
  due_date date not null,
  created_at timestamptz not null default now(),
  unique (milestone_id, kind)
);

-- Outbox: the unique event_key is what makes retries idempotent. Phase 5 consumes these.
create table domain_events (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,
  event_type text not null,
  booking_id uuid references bookings(id),
  payload jsonb not null default '{}',
  created_at timestamptz not null default now(),
  processed_at timestamptz
);
create index on domain_events(processed_at) where processed_at is null;

create table audit_logs (
  id bigserial primary key,
  actor uuid,
  action text not null,
  entity text not null,
  entity_id text,
  details jsonb not null default '{}',
  at timestamptz not null default now()
);
