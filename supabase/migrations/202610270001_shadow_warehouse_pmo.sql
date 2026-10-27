-- SHADOW warehouse control expansion v1.1
-- Additive migration: preserves the existing core schema and existing records.
begin;

alter table public.shadow_items
  add column if not exists color_code text,
  add column if not exists color_name text,
  add column if not exists family_code text references public.shadow_production_families(family_code),
  add column if not exists finished_item_code text references public.shadow_items(code),
  add column if not exists approval_status text not null default 'pending'
    check (approval_status in ('pending','approved','rejected')),
  add column if not exists approved_by uuid references auth.users(id),
  add column if not exists approved_at timestamptz,
  add column if not exists archived_at timestamptz;

-- A family may produce more than one finished item; an item may be used by multiple families.
create table if not exists public.shadow_family_products (
  id uuid primary key default gen_random_uuid(),
  family_code text not null references public.shadow_production_families(family_code) on update cascade on delete restrict,
  finished_item_code text not null references public.shadow_items(code) on update restrict on delete restrict,
  source_reference text not null,
  is_approved boolean not null default false,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  effective_from date not null default current_date,
  effective_to date,
  notes text,
  created_at timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from),
  check (not is_approved or (approved_by is not null and approved_at is not null)),
  unique(family_code, finished_item_code, effective_from)
);

-- Cycle count campaigns support individual-item counts, family counts, periodic counts and surprise counts.
create table if not exists public.shadow_stocktakes (
  id uuid primary key default gen_random_uuid(),
  stocktake_no text not null unique,
  stocktake_type text not null check (stocktake_type in ('periodic','continuous','family','surprise','opening','closing')),
  warehouse_id uuid not null references public.shadow_warehouses(id),
  family_code text references public.shadow_production_families(family_code),
  count_date date not null default current_date,
  cutoff_at timestamptz not null default now(),
  status text not null default 'draft' check (status in ('draft','counting','review','approved','cancelled')),
  blind_count boolean not null default true,
  created_by uuid not null references auth.users(id),
  reviewed_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  check (status <> 'approved' or (approved_by is not null and approved_at is not null))
);
create table if not exists public.shadow_stocktake_lines (
  id uuid primary key default gen_random_uuid(),
  stocktake_id uuid not null references public.shadow_stocktakes(id) on delete restrict,
  item_code text not null references public.shadow_items(code) on update restrict on delete restrict,
  location_id uuid references public.shadow_storage_locations(id),
  book_qty numeric(18,3),
  counted_qty numeric(18,3) check (counted_qty is null or counted_qty >= 0),
  unit text not null,
  variance_qty numeric(18,3) generated always as
    (case when counted_qty is null or book_qty is null then null else counted_qty-book_qty end) stored,
  first_counter text,
  second_counter text,
  recount_qty numeric(18,3) check (recount_qty is null or recount_qty >= 0),
  variance_reason text,
  line_status text not null default 'not_counted' check (line_status in ('not_counted','counted','recount_required','reviewed','approved')),
  notes text,
  created_at timestamptz not null default now(),
  unique(stocktake_id,item_code,location_id)
);

-- Opening balances are tracked as a distinct approved document type; no fabricated opening values are seeded.
create or replace view public.shadow_stock_balances_by_period
with (security_invoker=true)
as
select l.item_code, i.name as item_name, i.color_code, i.color_name,
       l.warehouse_id, w.code as warehouse_code, w.name as warehouse_name,
       l.location_id, l.unit,
       sum(case when d.document_date < current_date + 1 then l.quantity*l.direction else 0 end)::numeric(18,3) as current_balance_qty,
       sum(case when d.document_type='opening_balance' then l.quantity*l.direction else 0 end)::numeric(18,3) as opening_balance_qty
from public.shadow_document_lines l
join public.shadow_documents d on d.id=l.document_id and d.status='approved'
join public.shadow_items i on i.code=l.item_code
join public.shadow_warehouses w on w.id=l.warehouse_id
group by l.item_code,i.name,i.color_code,i.color_name,l.warehouse_id,w.code,w.name,l.location_id,l.unit;

create or replace view public.shadow_inventory_period_report
with (security_invoker=true)
as
select l.item_code, i.name as item_name, i.color_code, i.color_name,
       l.warehouse_id, w.code as warehouse_code, w.name as warehouse_name,
       l.location_id, l.unit,
       sum(case when d.document_type='opening_balance' then l.quantity*l.direction else 0 end)::numeric(18,3) as opening_qty_all_time,
       sum(case when d.document_type<>'opening_balance' and l.direction=1 then l.quantity else 0 end)::numeric(18,3) as total_receipts,
       sum(case when d.document_type<>'opening_balance' and l.direction=-1 then l.quantity else 0 end)::numeric(18,3) as total_issues,
       sum(l.quantity*l.direction)::numeric(18,3) as closing_qty_all_time,
       count(distinct d.id) as approved_document_count
from public.shadow_document_lines l
join public.shadow_documents d on d.id=l.document_id and d.status='approved'
join public.shadow_items i on i.code=l.item_code
join public.shadow_warehouses w on w.id=l.warehouse_id
group by l.item_code,i.name,i.color_code,i.color_name,l.warehouse_id,w.code,w.name,l.location_id,l.unit;

create index if not exists shadow_items_name_idx on public.shadow_items(lower(trim(name)));
create index if not exists shadow_items_color_idx on public.shadow_items(color_code,color_name);
create index if not exists shadow_family_products_family_idx on public.shadow_family_products(family_code,is_approved);
create index if not exists shadow_stocktakes_date_status_idx on public.shadow_stocktakes(count_date,status);
create index if not exists shadow_stocktake_lines_item_idx on public.shadow_stocktake_lines(item_code,stocktake_id);

alter table public.shadow_family_products enable row level security;
alter table public.shadow_stocktakes enable row level security;
alter table public.shadow_stocktake_lines enable row level security;

drop policy if exists shadow_family_products_read on public.shadow_family_products;
create policy shadow_family_products_read on public.shadow_family_products for select to authenticated using(public.shadow_is_active_user());
drop policy if exists shadow_family_products_admin on public.shadow_family_products;
create policy shadow_family_products_admin on public.shadow_family_products for all to authenticated using(public.shadow_role()='admin') with check(public.shadow_role()='admin');

drop policy if exists shadow_stocktakes_read on public.shadow_stocktakes;
create policy shadow_stocktakes_read on public.shadow_stocktakes for select to authenticated using(public.shadow_is_active_user());
drop policy if exists shadow_stocktakes_insert on public.shadow_stocktakes;
create policy shadow_stocktakes_insert on public.shadow_stocktakes for insert to authenticated
with check(public.shadow_is_active_user() and created_by=auth.uid() and status='draft');
drop policy if exists shadow_stocktakes_update on public.shadow_stocktakes;
create policy shadow_stocktakes_update on public.shadow_stocktakes for update to authenticated
using(public.shadow_is_active_user() and status in ('draft','counting','review') and (created_by=auth.uid() or public.shadow_role() in ('admin','reviewer')))
with check(public.shadow_is_active_user() and status in ('draft','counting','review') and (created_by=auth.uid() or public.shadow_role() in ('admin','reviewer')));

drop policy if exists shadow_stocktake_lines_read on public.shadow_stocktake_lines;
create policy shadow_stocktake_lines_read on public.shadow_stocktake_lines for select to authenticated using(public.shadow_is_active_user());
drop policy if exists shadow_stocktake_lines_insert on public.shadow_stocktake_lines;
create policy shadow_stocktake_lines_insert on public.shadow_stocktake_lines for insert to authenticated
with check(public.shadow_is_active_user() and exists(select 1 from public.shadow_stocktakes s where s.id=stocktake_id and s.status in ('draft','counting') and (s.created_by=auth.uid() or public.shadow_role()='admin')));
drop policy if exists shadow_stocktake_lines_update on public.shadow_stocktake_lines;
create policy shadow_stocktake_lines_update on public.shadow_stocktake_lines for update to authenticated
using(public.shadow_is_active_user() and exists(select 1 from public.shadow_stocktakes s where s.id=stocktake_id and s.status in ('draft','counting','review') and (s.created_by=auth.uid() or public.shadow_role() in ('admin','reviewer'))))
with check(public.shadow_is_active_user() and exists(select 1 from public.shadow_stocktakes s where s.id=stocktake_id and s.status in ('draft','counting','review') and (s.created_by=auth.uid() or public.shadow_role() in ('admin','reviewer'))));

drop trigger if exists shadow_family_products_audit on public.shadow_family_products;
create trigger shadow_family_products_audit after insert or update or delete on public.shadow_family_products for each row execute function public.shadow_audit_generic();
drop trigger if exists shadow_stocktakes_audit on public.shadow_stocktakes;
create trigger shadow_stocktakes_audit after insert or update or delete on public.shadow_stocktakes for each row execute function public.shadow_audit_generic();
drop trigger if exists shadow_stocktake_lines_audit on public.shadow_stocktake_lines;
create trigger shadow_stocktake_lines_audit after insert or update or delete on public.shadow_stocktake_lines for each row execute function public.shadow_audit_generic();

grant select,insert,update,delete on public.shadow_family_products,public.shadow_stocktakes,public.shadow_stocktake_lines to authenticated;
grant select on public.shadow_stock_balances_by_period,public.shadow_inventory_period_report to authenticated;

-- Item code/name/color lookups are supported by indexed columns; duplicate names remain legal.
-- Official deletion is soft-archive through is_active=false; approved transactions retain referential integrity.
commit;
