-- SHADOW unique-code governance + report hardening v1.2
-- Additive only. Suggestions are not official item master data until a reviewer approves the record.
begin;

create sequence if not exists public.shadow_finished_code_seq start 1 increment 1;
create sequence if not exists public.shadow_family_code_seq start 1 increment 1;

create or replace function public.shadow_suggest_finished_code()
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_code text;
begin
  if not public.shadow_is_active_user() or public.shadow_role() not in ('admin','reviewer','planner') then
    raise exception 'Not authorized to request official-code suggestions';
  end if;
  loop
    v_code := 'FG-' || lpad(nextval('public.shadow_finished_code_seq')::text, 6, '0');
    exit when not exists (select 1 from public.shadow_items where code = v_code);
  end loop;
  return v_code;
end;
$$;

create or replace function public.shadow_suggest_family_code()
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare v_code text;
begin
  if not public.shadow_is_active_user() or public.shadow_role() not in ('admin','reviewer','planner') then
    raise exception 'Not authorized to request family-code suggestions';
  end if;
  loop
    v_code := 'FAM-' || lpad(nextval('public.shadow_family_code_seq')::text, 6, '0');
    exit when not exists (select 1 from public.shadow_production_families where family_code = v_code);
  end loop;
  return v_code;
end;
$$;

revoke all on function public.shadow_suggest_finished_code() from public, anon;
revoke all on function public.shadow_suggest_family_code() from public, anon;
grant execute on function public.shadow_suggest_finished_code() to authenticated;
grant execute on function public.shadow_suggest_family_code() to authenticated;

-- Add validation indexes without changing or fabricating existing codes.
create index if not exists shadow_items_type_active_idx on public.shadow_items(item_type,is_active,code);
create index if not exists shadow_items_family_code_idx on public.shadow_items(family_code,code);
create index if not exists shadow_docs_date_status_idx on public.shadow_documents(document_date,status,document_type);
create index if not exists shadow_doc_lines_item_wh_idx on public.shadow_document_lines(item_code,warehouse_id,location_id);

-- Correct, bounded reporting function: only approved documents in the requested inclusive date range.
-- PostgreSQL cannot replace a function when its OUT/RETURNS TABLE signature changes.
drop function if exists public.shadow_inventory_period_summary(date,date);
create function public.shadow_inventory_period_summary(p_start_date date, p_end_date date)
returns table (
  item_code text,
  item_name text,
  item_type text,
  color_code text,
  color_name text,
  warehouse_code text,
  warehouse_name text,
  location_id uuid,
  unit text,
  opening_qty numeric,
  receipts_qty numeric,
  issues_qty numeric,
  net_movement numeric,
  closing_qty numeric,
  approved_document_count bigint
)
language plpgsql
security invoker
set search_path = public, auth
as $$
begin
  if not public.shadow_is_active_user() then
    raise exception 'Active SHADOW user required';
  end if;
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Invalid report date range';
  end if;

  return query
  with keys as (
    select distinct l.item_code,l.warehouse_id,l.location_id,l.unit
    from public.shadow_document_lines l
    join public.shadow_documents d on d.id=l.document_id and d.status='approved'
    where d.document_date <= p_end_date
  ),
  balances as (
    select k.item_code,k.warehouse_id,k.location_id,k.unit,
      coalesce(sum(case when d.document_date < p_start_date then l.quantity*l.direction else 0 end),0)::numeric(18,3) opening_qty,
      coalesce(sum(case when d.document_date between p_start_date and p_end_date and l.direction=1 then l.quantity else 0 end),0)::numeric(18,3) receipts_qty,
      coalesce(sum(case when d.document_date between p_start_date and p_end_date and l.direction=-1 then l.quantity else 0 end),0)::numeric(18,3) issues_qty,
      coalesce(sum(case when d.document_date between p_start_date and p_end_date then l.quantity*l.direction else 0 end),0)::numeric(18,3) net_movement,
      coalesce(sum(case when d.document_date <= p_end_date then l.quantity*l.direction else 0 end),0)::numeric(18,3) closing_qty,
      count(distinct d.id) filter (where d.document_date between p_start_date and p_end_date)::bigint approved_document_count
    from keys k
    left join public.shadow_document_lines l on l.item_code=k.item_code and l.warehouse_id=k.warehouse_id and l.location_id is not distinct from k.location_id and l.unit=k.unit
    left join public.shadow_documents d on d.id=l.document_id and d.status='approved' and d.document_date <= p_end_date
    group by k.item_code,k.warehouse_id,k.location_id,k.unit
  )
  select b.item_code,i.name,i.item_type,i.color_code,i.color_name,w.code,w.name,b.location_id,b.unit,
         b.opening_qty,b.receipts_qty,b.issues_qty,b.net_movement,b.closing_qty,b.approved_document_count
  from balances b
  join public.shadow_items i on i.code=b.item_code
  join public.shadow_warehouses w on w.id=b.warehouse_id
  order by w.code,i.item_type,i.code;
end;
$$;
grant execute on function public.shadow_inventory_period_summary(date,date) to authenticated;

commit;
