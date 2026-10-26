-- SHADOW central inventory schema v1
-- Apply only to a NEW Supabase project after reviewing the deployment guide.
-- No factory balances, items, weights, or BOM data are seeded here.
begin;

create extension if not exists pgcrypto;

create table if not exists public.shadow_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null check (role in ('admin','warehouse_operator','reviewer','planner','viewer')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create or replace function public.shadow_role()
returns text language sql stable security definer
set search_path = public, auth
as $$
  select role from public.shadow_profiles
  where user_id = auth.uid() and is_active = true
  limit 1
$$;

create or replace function public.shadow_is_active_user()
returns boolean language sql stable security definer
set search_path = public, auth
as $$
  select exists(select 1 from public.shadow_profiles where user_id=auth.uid() and is_active)
$$;

create table if not exists public.shadow_warehouses (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.shadow_storage_locations (
  id uuid primary key default gen_random_uuid(),
  warehouse_id uuid not null references public.shadow_warehouses(id),
  code text not null,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(warehouse_id, code),
  unique(warehouse_id, id)
);

-- One official code must identify one item. Resolve duplicate codes in source data before import.
create table if not exists public.shadow_items (
  code text primary key,
  name text not null,
  item_type text not null check (item_type in ('raw','finished','scrap','other')),
  base_unit text not null,
  source_name text not null default 'factory_master',
  source_reference text,
  source_row jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.shadow_documents (
  id uuid primary key default gen_random_uuid(),
  document_no text not null unique,
  document_type text not null check (document_type in
    ('receipt','issue','opening_balance','adjustment','transfer','return_to_stock','scrap_return','production_receipt','production_issue')),
  document_date date not null,
  status text not null default 'draft' check (status in ('draft','pending','approved','rejected','void')),
  warehouse_reference text,
  external_reference text,
  source_module text not null default 'manual',
  source_id text,
  operator_id uuid not null references auth.users(id),
  reviewer_id uuid references auth.users(id),
  submitted_at timestamptz,
  approved_at timestamptz,
  rejected_at timestamptz,
  rejection_reason text,
  negative_stock_reason text,
  notes text,
  idempotency_key text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (status <> 'approved' or (reviewer_id is not null and approved_at is not null)),
  check (status <> 'rejected' or (reviewer_id is not null and rejected_at is not null and nullif(trim(rejection_reason),'') is not null))
);

create table if not exists public.shadow_document_lines (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.shadow_documents(id) on delete restrict,
  line_no integer not null check (line_no > 0),
  item_code text not null references public.shadow_items(code) on update restrict on delete restrict,
  warehouse_id uuid not null references public.shadow_warehouses(id),
  location_id uuid,
  quantity numeric(18,3) not null check (quantity > 0),
  unit text not null,
  direction smallint not null check (direction in (-1,1)),
  package_count integer check (package_count is null or package_count >= 0),
  gross_weight_kg numeric(18,3) check (gross_weight_kg is null or gross_weight_kg >= 0),
  tare_weight_kg numeric(18,3) check (tare_weight_kg is null or tare_weight_kg >= 0),
  estimated_count numeric(18,3) check (estimated_count is null or estimated_count >= 0),
  actual_count boolean not null default false,
  line_note text,
  created_at timestamptz not null default now(),
  unique(document_id, line_no),
  foreign key (warehouse_id, location_id) references public.shadow_storage_locations(warehouse_id, id),
  check (actual_count = false or estimated_count is null or estimated_count >= 0)
);

create table if not exists public.shadow_audit_events (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  actor_id uuid,
  entity_type text not null,
  entity_id text not null,
  action text not null,
  before_data jsonb,
  after_data jsonb,
  reason text,
  request_id text
);

create table if not exists public.shadow_unit_conversions (
  id uuid primary key default gen_random_uuid(),
  item_code text not null references public.shadow_items(code),
  from_unit text not null,
  to_unit text not null,
  factor numeric(24,9) not null check (factor > 0),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  is_active boolean not null default false,
  notes text,
  check (from_unit <> to_unit),
  check (not is_active or (approved_by is not null and approved_at is not null)),
  unique(item_code, from_unit, to_unit)
);

create table if not exists public.shadow_item_weight_profiles (
  id uuid primary key default gen_random_uuid(),
  item_code text not null references public.shadow_items(code),
  package_type text not null check (package_type in ('bag','carton','other')),
  net_weight_kg numeric(18,4) not null check (net_weight_kg > 0),
  unit_weight_g numeric(18,6) check (unit_weight_g is null or unit_weight_g > 0),
  effective_from date not null,
  effective_to date,
  approved_by uuid not null references auth.users(id),
  approved_at timestamptz not null,
  is_active boolean not null default true,
  notes text,
  check (effective_to is null or effective_to >= effective_from)
);

create table if not exists public.shadow_production_families (
  family_code text primary key,
  family_name text not null,
  source_reference text not null,
  is_active boolean not null default true,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  notes text
);

create table if not exists public.shadow_bom_lines (
  id uuid primary key default gen_random_uuid(),
  family_code text not null references public.shadow_production_families(family_code),
  component_code text not null references public.shadow_items(code),
  usage_qty numeric(18,6) not null check (usage_qty > 0),
  usage_unit text not null,
  effective_from date not null,
  effective_to date,
  source_reference text not null,
  is_approved boolean not null default false,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  check (effective_to is null or effective_to >= effective_from),
  check (not is_approved or (approved_by is not null and approved_at is not null))
);

create table if not exists public.shadow_production_plans (
  id uuid primary key default gen_random_uuid(),
  plan_name text not null,
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check (status in ('draft','reviewed','approved','closed')),
  source_reference text,
  created_by uuid not null references auth.users(id),
  reviewed_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  check (period_end >= period_start),
  check (status <> 'approved' or (approved_by is not null and approved_at is not null))
);

create table if not exists public.shadow_production_plan_lines (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.shadow_production_plans(id) on delete restrict,
  family_code text not null references public.shadow_production_families(family_code),
  planned_qty numeric(18,3) not null check (planned_qty > 0),
  unit text not null,
  source_row text,
  unique(plan_id, family_code, source_row)
);

create index if not exists shadow_doc_status_date_idx on public.shadow_documents(status, document_date);
create index if not exists shadow_lines_item_warehouse_idx on public.shadow_document_lines(item_code, warehouse_id, location_id);
create index if not exists shadow_lines_document_idx on public.shadow_document_lines(document_id);
create index if not exists shadow_audit_entity_idx on public.shadow_audit_events(entity_type, entity_id, occurred_at desc);
create index if not exists shadow_bom_component_idx on public.shadow_bom_lines(component_code, is_approved);
create index if not exists shadow_plan_period_idx on public.shadow_production_plans(period_start, period_end, status);

create or replace function public.shadow_set_updated_at()
returns trigger language plpgsql set search_path=public
as $$ begin new.updated_at=now(); return new; end $$;
drop trigger if exists shadow_items_updated_at on public.shadow_items;
create trigger shadow_items_updated_at before update on public.shadow_items for each row execute function public.shadow_set_updated_at();
drop trigger if exists shadow_docs_updated_at on public.shadow_documents;
create trigger shadow_docs_updated_at before update on public.shadow_documents for each row execute function public.shadow_set_updated_at();

create or replace function public.shadow_audit_document()
returns trigger language plpgsql security definer set search_path=public,auth
as $$
declare oldj jsonb; newj jsonb; ent text;
begin
  if tg_op='INSERT' then oldj:=null; newj:=to_jsonb(new); ent:=new.id::text;
  elsif tg_op='UPDATE' then oldj:=to_jsonb(old); newj:=to_jsonb(new); ent:=new.id::text;
  else oldj:=to_jsonb(old); newj:=null; ent:=old.id::text; end if;
  insert into public.shadow_audit_events(actor_id,entity_type,entity_id,action,before_data,after_data,reason)
  values(auth.uid(),'document',ent,tg_op,oldj,newj,coalesce(new.notes,old.notes));
  if tg_op='DELETE' then return old; else return new; end if;
end $$;
drop trigger if exists shadow_documents_audit on public.shadow_documents;
create trigger shadow_documents_audit after insert or update or delete on public.shadow_documents for each row execute function public.shadow_audit_document();

create or replace function public.shadow_audit_line()
returns trigger language plpgsql security definer set search_path=public,auth
as $$
declare oldj jsonb; newj jsonb; ent text; docid uuid;
begin
  if tg_op='INSERT' then oldj:=null; newj:=to_jsonb(new); ent:=new.id::text; docid:=new.document_id;
  elsif tg_op='UPDATE' then oldj:=to_jsonb(old); newj:=to_jsonb(new); ent:=new.id::text; docid:=new.document_id;
  else oldj:=to_jsonb(old); newj:=null; ent:=old.id::text; docid:=old.document_id; end if;
  insert into public.shadow_audit_events(actor_id,entity_type,entity_id,action,before_data,after_data,reason)
  values(auth.uid(),'document_line',ent,tg_op,oldj,newj,'document_id='||docid::text);
  if tg_op='DELETE' then return old; else return new; end if;
end $$;
drop trigger if exists shadow_document_lines_audit on public.shadow_document_lines;
create trigger shadow_document_lines_audit after insert or update or delete on public.shadow_document_lines for each row execute function public.shadow_audit_line();

create or replace function public.shadow_audit_generic()
returns trigger language plpgsql security definer set search_path=public,auth
as $$
declare oldj jsonb; newj jsonb; ent text;
begin
  if tg_op='INSERT' then oldj:=null; newj:=to_jsonb(new);
  elsif tg_op='UPDATE' then oldj:=to_jsonb(old); newj:=to_jsonb(new);
  else oldj:=to_jsonb(old); newj:=null; end if;
  ent:=coalesce(newj->>'id',newj->>'code',newj->>'family_code',newj->>'user_id',
                oldj->>'id',oldj->>'code',oldj->>'family_code',oldj->>'user_id','unknown');
  insert into public.shadow_audit_events(actor_id,entity_type,entity_id,action,before_data,after_data)
  values(auth.uid(),tg_table_name,ent,tg_op,oldj,newj);
  if tg_op='DELETE' then return old; else return new; end if;
end $$;

drop trigger if exists shadow_profiles_audit on public.shadow_profiles;
create trigger shadow_profiles_audit after insert or update or delete on public.shadow_profiles for each row execute function public.shadow_audit_generic();
drop trigger if exists shadow_warehouses_audit on public.shadow_warehouses;
create trigger shadow_warehouses_audit after insert or update or delete on public.shadow_warehouses for each row execute function public.shadow_audit_generic();
drop trigger if exists shadow_locations_audit on public.shadow_storage_locations;
create trigger shadow_locations_audit after insert or update or delete on public.shadow_storage_locations for each row execute function public.shadow_audit_generic();
drop trigger if exists shadow_items_audit on public.shadow_items;
create trigger shadow_items_audit after insert or update or delete on public.shadow_items for each row execute function public.shadow_audit_generic();
drop trigger if exists shadow_conversions_audit on public.shadow_unit_conversions;
create trigger shadow_conversions_audit after insert or update or delete on public.shadow_unit_conversions for each row execute function public.shadow_audit_generic();
drop trigger if exists shadow_weights_audit on public.shadow_item_weight_profiles;
create trigger shadow_weights_audit after insert or update or delete on public.shadow_item_weight_profiles for each row execute function public.shadow_audit_generic();
drop trigger if exists shadow_families_audit on public.shadow_production_families;
create trigger shadow_families_audit after insert or update or delete on public.shadow_production_families for each row execute function public.shadow_audit_generic();
drop trigger if exists shadow_bom_audit on public.shadow_bom_lines;
create trigger shadow_bom_audit after insert or update or delete on public.shadow_bom_lines for each row execute function public.shadow_audit_generic();
drop trigger if exists shadow_plans_audit on public.shadow_production_plans;
create trigger shadow_plans_audit after insert or update or delete on public.shadow_production_plans for each row execute function public.shadow_audit_generic();
drop trigger if exists shadow_plan_lines_audit on public.shadow_production_plan_lines;
create trigger shadow_plan_lines_audit after insert or update or delete on public.shadow_production_plan_lines for each row execute function public.shadow_audit_generic();

create or replace function public.shadow_guard_document()
returns trigger language plpgsql set search_path=public
as $$
begin
  if old.status in ('approved','void') then
    raise exception 'Approved/void documents are immutable; create a documented correction document.';
  end if;
  if tg_op='DELETE' and old.status <> 'draft' then
    raise exception 'Only draft documents can be deleted.';
  end if;
  if tg_op='DELETE' then return old; else return new; end if;
end $$;
drop trigger if exists shadow_documents_guard on public.shadow_documents;
create trigger shadow_documents_guard before update or delete on public.shadow_documents for each row execute function public.shadow_guard_document();

create or replace function public.shadow_guard_line()
returns trigger language plpgsql set search_path=public
as $$
declare doc_status text; doc_operator uuid;
begin
  if tg_op='DELETE' then select status,operator_id into doc_status,doc_operator from public.shadow_documents where id=old.document_id for update; else select status,operator_id into doc_status,doc_operator from public.shadow_documents where id=new.document_id for update; end if;
  if doc_status is distinct from 'draft' then
    raise exception 'Lines can only be changed while their document is draft.';
  end if;
  if auth.uid() is not null and doc_operator <> auth.uid() and public.shadow_role() <> 'admin' then
    raise exception 'Only the document owner or an admin can edit draft lines.';
  end if;
  if tg_op='DELETE' then return old; else return new; end if;
end $$;
drop trigger if exists shadow_lines_guard on public.shadow_document_lines;
create trigger shadow_lines_guard before insert or update or delete on public.shadow_document_lines for each row execute function public.shadow_guard_line();

create or replace view public.shadow_stock_balances
with (security_invoker=true)
as
select l.item_code, l.warehouse_id, l.location_id, l.unit,
       sum(l.quantity*l.direction)::numeric(18,3) as balance_qty
from public.shadow_document_lines l
join public.shadow_documents d on d.id=l.document_id and d.status='approved'
group by l.item_code,l.warehouse_id,l.location_id,l.unit;

create or replace function public.shadow_submit_document(p_document_id uuid)
returns void language plpgsql security definer set search_path=public,auth
as $$
declare d public.shadow_documents%rowtype; line_count integer;
begin
  if not public.shadow_is_active_user() then raise exception 'Active authenticated profile required.'; end if;
  select * into d from public.shadow_documents where id=p_document_id for update;
  if not found then raise exception 'Document not found.'; end if;
  if d.operator_id<>auth.uid() and public.shadow_role()<>'admin' then raise exception 'Only owner/admin may submit.'; end if;
  if d.status<>'draft' then raise exception 'Only draft documents can be submitted.'; end if;
  select count(*) into line_count from public.shadow_document_lines where document_id=d.id;
  if line_count=0 then raise exception 'Cannot submit an empty document.'; end if;
  if exists(
    select 1 from public.shadow_document_lines l
    left join public.shadow_items i on i.code=l.item_code and i.is_active
    where l.document_id=d.id and (i.code is null or trim(l.unit)<>trim(i.base_unit))
  ) then raise exception 'Item code inactive/missing or unit differs from official base unit. Approved conversion is not automatic.'; end if;
  if d.document_type='transfer' then
    if exists(select item_code,unit from public.shadow_document_lines where document_id=d.id group by item_code,unit having sum(quantity*direction)<>0)
      or (select count(distinct warehouse_id) from public.shadow_document_lines where document_id=d.id)<2
    then raise exception 'Transfer must balance by item/unit and include at least two warehouses.'; end if;
  end if;
  update public.shadow_documents set status='pending',submitted_at=now() where id=d.id;
end $$;

create or replace function public.shadow_approve_document(p_document_id uuid, p_negative_stock_reason text default null)
returns void language plpgsql security definer set search_path=public,auth
as $$
declare d public.shadow_documents%rowtype; bad record; lockrow record;
begin
  if not public.shadow_is_active_user() or public.shadow_role() not in ('admin','reviewer') then
    raise exception 'Only active reviewer/admin may approve inventory documents.';
  end if;
  select * into d from public.shadow_documents where id=p_document_id for update;
  if not found then raise exception 'Document not found.'; end if;
  if d.status<>'pending' then raise exception 'Only pending documents can be approved.'; end if;
  if d.operator_id=auth.uid() and public.shadow_role()<>'admin' then
    raise exception 'Maker-checker rule: the operator cannot approve their own document.';
  end if;
  if exists(select 1 from public.shadow_document_lines l join public.shadow_items i on i.code=l.item_code
            where l.document_id=d.id and (not i.is_active or trim(l.unit)<>trim(i.base_unit))) then
    raise exception 'Item master/unit validation failed.';
  end if;
  -- Serialize approvals that touch the same stock keys, preventing concurrent approvals from overspending stock.
  for lockrow in
    select distinct item_code,warehouse_id,location_id,unit
    from public.shadow_document_lines where document_id=d.id
    order by item_code,warehouse_id,location_id nulls first,unit
  loop
    perform pg_advisory_xact_lock(hashtextextended(
      lockrow.item_code||'|'||lockrow.warehouse_id::text||'|'||coalesce(lockrow.location_id::text,'')||'|'||lockrow.unit,0));
  end loop;
  for bad in
    select l.item_code,l.warehouse_id,l.location_id,l.unit,
      coalesce((select b.balance_qty from public.shadow_stock_balances b
        where b.item_code=l.item_code and b.warehouse_id=l.warehouse_id
          and b.location_id is not distinct from l.location_id and b.unit=l.unit),0)
      + sum(l.quantity*l.direction) as next_balance
    from public.shadow_document_lines l where l.document_id=d.id
    group by l.item_code,l.warehouse_id,l.location_id,l.unit
  loop
    if bad.next_balance < 0 then
      if public.shadow_role()<>'admin' or nullif(trim(coalesce(p_negative_stock_reason,'')),'') is null then
        raise exception 'Approval would create negative stock for item %. Admin approval with documented exception reason is required.',bad.item_code;
      end if;
    end if;
  end loop;
  update public.shadow_documents
    set status='approved',reviewer_id=auth.uid(),approved_at=now(),
        negative_stock_reason=nullif(trim(coalesce(p_negative_stock_reason,'')),'')
    where id=d.id;
end $$;

create or replace function public.shadow_reject_document(p_document_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,auth
as $$
declare d public.shadow_documents%rowtype;
begin
  if not public.shadow_is_active_user() or public.shadow_role() not in ('admin','reviewer') then raise exception 'Reviewer/admin role required.'; end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Rejection reason is required.'; end if;
  select * into d from public.shadow_documents where id=p_document_id for update;
  if not found or d.status<>'pending' then raise exception 'Only existing pending documents can be rejected.'; end if;
  if d.operator_id=auth.uid() and public.shadow_role()<>'admin' then raise exception 'Maker-checker rule: operator cannot reject own document.'; end if;
  update public.shadow_documents set status='rejected',reviewer_id=auth.uid(),rejected_at=now(),rejection_reason=trim(p_reason) where id=d.id;
end $$;

create or replace function public.shadow_create_correction(p_original_document_id uuid,p_document_no text,p_document_date date,p_notes text)
returns uuid language plpgsql security definer set search_path=public,auth
as $$
declare original public.shadow_documents%rowtype; new_id uuid;
begin
  if not public.shadow_is_active_user() or public.shadow_role() not in ('admin','warehouse_operator','reviewer') then raise exception 'Authorized active user required.'; end if;
  select * into original from public.shadow_documents where id=p_original_document_id;
  if not found or original.status<>'approved' then raise exception 'Only approved documents may be corrected.'; end if;
  if nullif(trim(coalesce(p_notes,'')),'') is null then raise exception 'Correction reason is required.'; end if;
  insert into public.shadow_documents(document_no,document_type,document_date,status,external_reference,source_module,operator_id,notes)
  values(p_document_no,'adjustment',p_document_date,'draft',original.document_no,'correction',auth.uid(),'Correction of '||original.document_no||': '||trim(p_notes))
  returning id into new_id;
  insert into public.shadow_document_lines(document_id,line_no,item_code,warehouse_id,location_id,quantity,unit,direction,line_note)
  select new_id,row_number() over(order by line_no),item_code,warehouse_id,location_id,quantity,unit,-direction,
         'Correction reversal of document '||original.document_no
  from public.shadow_document_lines where document_id=original.id;
  return new_id;
end $$;


create or replace view public.shadow_plan_component_exceptions
with (security_invoker=true)
as
select p.id as plan_id, p.plan_name, pl.id as plan_line_id, pl.family_code,
       case
         when count(b.id)=0 then 'لا يوجد معدل مكون معتمد وساري خلال فترة الخطة'
         when count(b.id)>1 then 'يوجد أكثر من معدل معتمد متداخل للصنف/العائلة خلال فترة الخطة'
         when bool_or(i.code is null or not i.is_active) then 'كود مكون مفقود أو غير نشط'
         when bool_or(trim(b.usage_unit)<>trim(i.base_unit)) then 'وحدة معدل المكون لا تطابق الوحدة الأساسية؛ يلزم تحويل معتمد'
         else null
       end as exception_reason,
       count(b.id) as candidate_rate_rows
from public.shadow_production_plans p
join public.shadow_production_plan_lines pl on pl.plan_id=p.id
left join public.shadow_bom_lines b
  on b.family_code=pl.family_code and b.is_approved
 and b.effective_from<=p.period_end
 and (b.effective_to is null or b.effective_to>=p.period_start)
left join public.shadow_items i on i.code=b.component_code
group by p.id,p.plan_name,pl.id,pl.family_code
having count(b.id)=0 or count(b.id)>1
   or bool_or(i.code is null or not i.is_active)
   or bool_or(trim(b.usage_unit)<>trim(i.base_unit));

create or replace view public.shadow_plan_component_requirements
with (security_invoker=true)
as
with candidates as (
  select p.id as plan_id,p.plan_name,p.period_start,p.period_end,
         pl.id as plan_line_id,pl.family_code,pl.planned_qty,pl.unit as planned_unit,
         b.component_code,b.usage_qty,b.usage_unit,i.base_unit,
         count(b.id) over(partition by p.id,pl.id,b.component_code) as rate_count
  from public.shadow_production_plans p
  join public.shadow_production_plan_lines pl on pl.plan_id=p.id
  join public.shadow_bom_lines b
    on b.family_code=pl.family_code and b.is_approved
   and b.effective_from<=p.period_end
   and (b.effective_to is null or b.effective_to>=p.period_start)
  join public.shadow_items i on i.code=b.component_code and i.is_active
  where p.status='approved'
)
select plan_id,plan_name,period_start,period_end,component_code,base_unit as required_unit,
       sum(planned_qty*usage_qty)::numeric(18,3) as required_qty,
       count(distinct family_code) as contributing_families,
       array_agg(distinct family_code order by family_code) as family_codes
from candidates
where rate_count=1 and trim(usage_unit)=trim(base_unit)
group by plan_id,plan_name,period_start,period_end,component_code,base_unit;

create or replace function public.shadow_approve_production_plan(p_plan_id uuid)
returns void language plpgsql security definer set search_path=public,auth
as $$
declare p public.shadow_production_plans%rowtype;
begin
  if not public.shadow_is_active_user() or public.shadow_role() not in ('admin','planner') then
    raise exception 'Only active planner/admin may approve a production plan.';
  end if;
  select * into p from public.shadow_production_plans where id=p_plan_id for update;
  if not found or p.status not in ('draft','reviewed') then
    raise exception 'Only an existing draft/reviewed plan may be approved.';
  end if;
  if p.created_by=auth.uid() and public.shadow_role()<>'admin' then
    raise exception 'Maker-checker rule: planner cannot approve own plan.';
  end if;
  if not exists(select 1 from public.shadow_production_plan_lines where plan_id=p.id) then
    raise exception 'Cannot approve an empty production plan.';
  end if;
  if exists(select 1 from public.shadow_plan_component_exceptions where plan_id=p.id) then
    raise exception 'Plan has missing, ambiguous, inactive, or unit-mismatched component rates. Resolve exceptions before approval.';
  end if;
  update public.shadow_production_plans
    set status='approved',reviewed_by=coalesce(reviewed_by,auth.uid()),
        approved_by=auth.uid(),approved_at=now()
    where id=p.id;
end $$;

alter table public.shadow_profiles enable row level security;
alter table public.shadow_warehouses enable row level security;
alter table public.shadow_storage_locations enable row level security;
alter table public.shadow_items enable row level security;
alter table public.shadow_documents enable row level security;
alter table public.shadow_document_lines enable row level security;
alter table public.shadow_audit_events enable row level security;
alter table public.shadow_unit_conversions enable row level security;
alter table public.shadow_item_weight_profiles enable row level security;
alter table public.shadow_production_families enable row level security;
alter table public.shadow_bom_lines enable row level security;
alter table public.shadow_production_plans enable row level security;
alter table public.shadow_production_plan_lines enable row level security;

drop policy if exists shadow_profiles_read_self_or_admin on public.shadow_profiles;
create policy shadow_profiles_read_self_or_admin on public.shadow_profiles for select to authenticated
using (user_id=auth.uid() or public.shadow_role()='admin');
drop policy if exists shadow_profiles_admin_write on public.shadow_profiles;
create policy shadow_profiles_admin_write on public.shadow_profiles for all to authenticated
using (public.shadow_role()='admin') with check (public.shadow_role()='admin');

drop policy if exists shadow_warehouses_read on public.shadow_warehouses;
create policy shadow_warehouses_read on public.shadow_warehouses for select to authenticated using(public.shadow_is_active_user());
drop policy if exists shadow_warehouses_admin on public.shadow_warehouses;
create policy shadow_warehouses_admin on public.shadow_warehouses for all to authenticated using(public.shadow_role()='admin') with check(public.shadow_role()='admin');

drop policy if exists shadow_locations_read on public.shadow_storage_locations;
create policy shadow_locations_read on public.shadow_storage_locations for select to authenticated using(public.shadow_is_active_user());
drop policy if exists shadow_locations_admin on public.shadow_storage_locations;
create policy shadow_locations_admin on public.shadow_storage_locations for all to authenticated using(public.shadow_role()='admin') with check(public.shadow_role()='admin');

drop policy if exists shadow_items_read on public.shadow_items;
create policy shadow_items_read on public.shadow_items for select to authenticated using(public.shadow_is_active_user());
drop policy if exists shadow_items_admin on public.shadow_items;
create policy shadow_items_admin on public.shadow_items for all to authenticated using(public.shadow_role()='admin') with check(public.shadow_role()='admin');

drop policy if exists shadow_docs_read on public.shadow_documents;
create policy shadow_docs_read on public.shadow_documents for select to authenticated using(public.shadow_is_active_user());
drop policy if exists shadow_docs_insert on public.shadow_documents;
create policy shadow_docs_insert on public.shadow_documents for insert to authenticated
with check (public.shadow_is_active_user() and operator_id=auth.uid() and status='draft');
drop policy if exists shadow_docs_update on public.shadow_documents;
create policy shadow_docs_update on public.shadow_documents for update to authenticated
using (public.shadow_is_active_user() and status='draft' and (operator_id=auth.uid() or public.shadow_role()='admin'))
with check (public.shadow_is_active_user() and status='draft' and (operator_id=auth.uid() or public.shadow_role()='admin'));
drop policy if exists shadow_docs_delete on public.shadow_documents;
create policy shadow_docs_delete on public.shadow_documents for delete to authenticated
using (public.shadow_role()='admin' and status='draft');

drop policy if exists shadow_lines_read on public.shadow_document_lines;
create policy shadow_lines_read on public.shadow_document_lines for select to authenticated using(public.shadow_is_active_user());
drop policy if exists shadow_lines_insert on public.shadow_document_lines;
create policy shadow_lines_insert on public.shadow_document_lines for insert to authenticated
with check (public.shadow_is_active_user() and exists(select 1 from public.shadow_documents d where d.id=document_id and d.status='draft' and (d.operator_id=auth.uid() or public.shadow_role()='admin')));
drop policy if exists shadow_lines_update on public.shadow_document_lines;
create policy shadow_lines_update on public.shadow_document_lines for update to authenticated
using (public.shadow_is_active_user() and exists(select 1 from public.shadow_documents d where d.id=document_id and d.status='draft' and (d.operator_id=auth.uid() or public.shadow_role()='admin')))
with check (public.shadow_is_active_user() and exists(select 1 from public.shadow_documents d where d.id=document_id and d.status='draft' and (d.operator_id=auth.uid() or public.shadow_role()='admin')));
drop policy if exists shadow_lines_delete on public.shadow_document_lines;
create policy shadow_lines_delete on public.shadow_document_lines for delete to authenticated
using (public.shadow_is_active_user() and exists(select 1 from public.shadow_documents d where d.id=document_id and d.status='draft' and (d.operator_id=auth.uid() or public.shadow_role()='admin')));

drop policy if exists shadow_audit_read on public.shadow_audit_events;
create policy shadow_audit_read on public.shadow_audit_events for select to authenticated using(public.shadow_role() in ('admin','reviewer'));
-- No client insert/update/delete policies for audit events.

drop policy if exists shadow_conversion_read on public.shadow_unit_conversions;
create policy shadow_conversion_read on public.shadow_unit_conversions for select to authenticated using(public.shadow_is_active_user());
drop policy if exists shadow_conversion_admin on public.shadow_unit_conversions;
create policy shadow_conversion_admin on public.shadow_unit_conversions for all to authenticated using(public.shadow_role()='admin') with check(public.shadow_role()='admin');

drop policy if exists shadow_weights_read on public.shadow_item_weight_profiles;
create policy shadow_weights_read on public.shadow_item_weight_profiles for select to authenticated using(public.shadow_is_active_user());
drop policy if exists shadow_weights_admin on public.shadow_item_weight_profiles;
create policy shadow_weights_admin on public.shadow_item_weight_profiles for all to authenticated using(public.shadow_role()='admin') with check(public.shadow_role()='admin');

drop policy if exists shadow_families_read on public.shadow_production_families;
create policy shadow_families_read on public.shadow_production_families for select to authenticated using(public.shadow_is_active_user());
drop policy if exists shadow_families_admin on public.shadow_production_families;
create policy shadow_families_admin on public.shadow_production_families for all to authenticated using(public.shadow_role()='admin') with check(public.shadow_role()='admin');

drop policy if exists shadow_bom_read on public.shadow_bom_lines;
create policy shadow_bom_read on public.shadow_bom_lines for select to authenticated using(public.shadow_is_active_user());
drop policy if exists shadow_bom_admin on public.shadow_bom_lines;
create policy shadow_bom_admin on public.shadow_bom_lines for all to authenticated using(public.shadow_role()='admin') with check(public.shadow_role()='admin');

drop policy if exists shadow_plans_read on public.shadow_production_plans;
create policy shadow_plans_read on public.shadow_production_plans for select to authenticated using(public.shadow_is_active_user());
drop policy if exists shadow_plans_insert on public.shadow_production_plans;
create policy shadow_plans_insert on public.shadow_production_plans for insert to authenticated with check(public.shadow_is_active_user() and created_by=auth.uid() and status='draft');
drop policy if exists shadow_plans_update on public.shadow_production_plans;
create policy shadow_plans_update on public.shadow_production_plans for update to authenticated using(public.shadow_is_active_user() and status='draft' and (created_by=auth.uid() or public.shadow_role() in ('admin','planner'))) with check(public.shadow_is_active_user() and status='draft' and (created_by=auth.uid() or public.shadow_role() in ('admin','planner')));

drop policy if exists shadow_plan_lines_read on public.shadow_production_plan_lines;
create policy shadow_plan_lines_read on public.shadow_production_plan_lines for select to authenticated using(public.shadow_is_active_user());
drop policy if exists shadow_plan_lines_insert on public.shadow_production_plan_lines;
create policy shadow_plan_lines_insert on public.shadow_production_plan_lines for insert to authenticated with check(public.shadow_is_active_user() and exists(select 1 from public.shadow_production_plans p where p.id=plan_id and p.status='draft' and (p.created_by=auth.uid() or public.shadow_role() in ('admin','planner'))));
drop policy if exists shadow_plan_lines_update on public.shadow_production_plan_lines;
create policy shadow_plan_lines_update on public.shadow_production_plan_lines for update to authenticated using(public.shadow_is_active_user() and exists(select 1 from public.shadow_production_plans p where p.id=plan_id and p.status='draft' and (p.created_by=auth.uid() or public.shadow_role() in ('admin','planner')))) with check(public.shadow_is_active_user() and exists(select 1 from public.shadow_production_plans p where p.id=plan_id and p.status='draft' and (p.created_by=auth.uid() or public.shadow_role() in ('admin','planner'))));

revoke all on all tables in schema public from anon;
revoke all on all functions in schema public from public;
grant usage on schema public to authenticated;
grant select,insert,update,delete on public.shadow_profiles,public.shadow_warehouses,public.shadow_storage_locations,public.shadow_items,public.shadow_documents,public.shadow_document_lines,public.shadow_unit_conversions,public.shadow_item_weight_profiles,public.shadow_production_families,public.shadow_bom_lines,public.shadow_production_plans,public.shadow_production_plan_lines to authenticated;
grant select on public.shadow_audit_events,public.shadow_stock_balances,public.shadow_plan_component_exceptions,public.shadow_plan_component_requirements to authenticated;
grant usage,select on sequence public.shadow_audit_events_id_seq to authenticated;
grant execute on function public.shadow_role() to authenticated;
grant execute on function public.shadow_is_active_user() to authenticated
grant execute on function public.shadow_submit_document(uuid) to authenticated;
grant execute on function public.shadow_approve_document(uuid,text) to authenticated;
grant execute on function public.shadow_reject_document(uuid,text) to authenticated;
grant execute on function public.shadow_create_correction(uuid,text,date,text) to authenticated;
grant execute on function public.shadow_approve_production_plan(uuid) to authenticated;


-- Immutable source-import staging preserves source rows without promoting provisional values.
create table if not exists public.shadow_source_import_batches (
  id uuid primary key default gen_random_uuid(),
  source_name text not null,
  source_type text not null check (source_type in ('item_master','production_rates','legacy_movements','other')),
  source_reference text,
  source_sha256 text,
  imported_by uuid not null references auth.users(id),
  imported_at timestamptz not null default now(),
  row_count integer not null default 0 check (row_count >= 0),
  status text not null default 'staged' check (status in ('staged','reviewing','partially_reviewed','approved','rejected')),
  notes text
);
create table if not exists public.shadow_source_import_rows (
  id bigint generated always as identity primary key,
  batch_id uuid not null references public.shadow_source_import_batches(id) on delete restrict,
  source_row_no integer not null check (source_row_no > 0),
  source_sheet text not null default '',
  row_type text not null check (row_type in ('item_master','production_rate','legacy_movement','other')),
  source_key text,
  source_data jsonb not null,
  review_status text not null default 'pending' check (review_status in ('pending','matched','approved','rejected','needs_mapping')),
  matched_item_code text references public.shadow_items(code) on update restrict on delete restrict,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_note text,
  unique(batch_id, row_type, source_row_no)
);
create index if not exists shadow_source_rows_batch_idx on public.shadow_source_import_rows(batch_id, review_status);
alter table public.shadow_source_import_batches enable row level security;
alter table public.shadow_source_import_rows enable row level security;
drop policy if exists shadow_source_batches_admin on public.shadow_source_import_batches;
create policy shadow_source_batches_admin on public.shadow_source_import_batches for all to authenticated
using (public.shadow_role()='admin') with check (public.shadow_role()='admin');
drop policy if exists shadow_source_rows_admin on public.shadow_source_import_rows;
create policy shadow_source_rows_admin on public.shadow_source_import_rows for all to authenticated
using (public.shadow_role()='admin') with check (public.shadow_role()='admin');
grant select,insert,update,delete on public.shadow_source_import_batches,public.shadow_source_import_rows to authenticated;
grant usage,select on sequence public.shadow_source_import_rows_id_seq to authenticated;
drop trigger if exists shadow_source_batches_audit on public.shadow_source_import_batches;
create trigger shadow_source_batches_audit after insert or update or delete on public.shadow_source_import_batches for each row execute function public.shadow_audit_generic();
drop trigger if exists shadow_source_rows_audit on public.shadow_source_import_rows;
create trigger shadow_source_rows_audit after insert or update or delete on public.shadow_source_import_rows for each row execute function public.shadow_audit_generic();

commit;
