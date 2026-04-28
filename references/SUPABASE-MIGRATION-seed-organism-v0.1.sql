-- CursiveOS Seed Organism schema v0.1
-- Stores Phase 0 seed bundles and fake payout reports uploaded by Linux test hosts.

create table if not exists seed_bundles (
  id bigserial primary key,
  bundle_hash text not null unique,
  variant_id text not null,
  cycle_id text,
  decision text not null,
  reason text,
  machine_id text,
  contributor_id text,
  commit_ref text,
  fitness_score double precision,
  confidence double precision,
  sensor_result_hash text,
  regression_result_hash text,
  result_bundle jsonb not null,
  source text not null default 'seed_organism.py',
  created_at timestamptz not null default now(),
  uploaded_at timestamptz not null default now()
);

create index if not exists seed_bundles_variant_idx on seed_bundles (variant_id, created_at desc);
create index if not exists seed_bundles_machine_idx on seed_bundles (machine_id, created_at desc);
create index if not exists seed_bundles_decision_idx on seed_bundles (decision, created_at desc);
create index if not exists seed_bundles_bundle_gin_idx on seed_bundles using gin (result_bundle);

create table if not exists seed_payout_reports (
  id bigserial primary key,
  payout_report_hash text not null unique,
  cycle_id text not null,
  simulated_revenue_sats bigint,
  contributor_count integer,
  report jsonb not null,
  source text not null default 'seed_organism.py',
  created_at timestamptz not null default now(),
  uploaded_at timestamptz not null default now()
);

create index if not exists seed_payout_reports_cycle_idx on seed_payout_reports (cycle_id, created_at desc);
create index if not exists seed_payout_reports_report_gin_idx on seed_payout_reports using gin (report);

alter table seed_bundles enable row level security;
alter table seed_payout_reports enable row level security;

drop policy if exists seed_bundles_anon_insert on seed_bundles;
create policy seed_bundles_anon_insert on seed_bundles
  for insert to anon
  with check (true);

drop policy if exists seed_bundles_anon_select on seed_bundles;
create policy seed_bundles_anon_select on seed_bundles
  for select to anon
  using (true);

drop policy if exists seed_payout_reports_anon_insert on seed_payout_reports;
create policy seed_payout_reports_anon_insert on seed_payout_reports
  for insert to anon
  with check (true);

drop policy if exists seed_payout_reports_anon_select on seed_payout_reports;
create policy seed_payout_reports_anon_select on seed_payout_reports
  for select to anon
  using (true);

grant usage on schema public to anon;
grant select, insert on seed_bundles to anon;
grant select, insert on seed_payout_reports to anon;
grant usage, select on sequence seed_bundles_id_seq to anon;
grant usage, select on sequence seed_payout_reports_id_seq to anon;
