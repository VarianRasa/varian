-- Public, non-sensitive sample data for the chart database source.
-- The Flutter adapter reads this table with an explicit category/value allowlist.
create table if not exists public.sales_chart (
  category text primary key,
  revenue double precision,
  cost double precision,
  constraint sales_chart_category_not_blank
    check (length(btrim(category)) > 0),
  constraint sales_chart_revenue_finite
    check (
      revenue is null
      or (revenue > '-Infinity'::double precision
          and revenue < 'Infinity'::double precision)
    ),
  constraint sales_chart_cost_finite
    check (
      cost is null
      or (cost > '-Infinity'::double precision
          and cost < 'Infinity'::double precision)
    )
);

comment on table public.sales_chart is
  'Non-sensitive sample rows for read-only chart database demonstrations.';
comment on column public.sales_chart.category is
  'Chart category label and stable row key.';
comment on column public.sales_chart.revenue is
  'Sample revenue measure.';
comment on column public.sales_chart.cost is
  'Sample cost measure.';

alter table public.sales_chart enable row level security;

revoke all on table public.sales_chart from public, anon, authenticated;
grant select on table public.sales_chart to anon, authenticated;

drop policy if exists sales_chart_read on public.sales_chart;
create policy sales_chart_read on public.sales_chart
  for select
  to anon, authenticated
  using (true);

insert into public.sales_chart (category, revenue, cost)
values
  ('Q1', 120, 72),
  ('Q2', 148, 81),
  ('Q3', 171, 95),
  ('Q4', 205, 109)
on conflict (category) do update
set revenue = excluded.revenue,
    cost = excluded.cost;
