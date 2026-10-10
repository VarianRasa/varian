# Charts database source contract

The chart database source is a read-only Supabase/PostgREST adapter. This repository owns the public `public.sales_chart` sample table through `supabase/migrations/20260824020000_create_chart_sales_sample.sql`. Use that table for the built-in database chart example; private or tenant-scoped tables require a separate authorization contract and policy.

## Request

- The app uses the configured Supabase URL and publishable/anon key, plus the current Supabase session if one exists.
- The app issues `SELECT` through the Supabase client only. It never writes, invokes SQL, stores credentials in a chart payload, or follows a user-provided URL.
- `table` is one unquoted PostgreSQL identifier matching `[A-Za-z_][A-Za-z0-9_]{0,62}`. Schema-qualified names, quoted identifiers, expressions, and SQL fragments are rejected.
- `categoryColumn` uses the same identifier rule and defaults to `category`.
- `valueColumns` is required and contains at most 12 validated identifiers. Requiring an explicit allowlist prevents unrelated table columns from being fetched.
- `rowLimit` is clamped to `1..100` before the request.
- The optional persisted `categoryFilter` is applied client-side after the bounded read so the chart and exports use the same filter semantics.

## Response

The PostgREST response must be a list of JSON objects. The category column must exist and contain a non-empty value. Value cells may be JSON numbers or finite numeric strings; null cells become `0`. A selected value column must contain at least one finite numeric value. Rows and series are bounded before they become `ChartPayload` data.

The adapter returns the existing chart configuration with categories and series replaced by the response data. If the table is empty, the response shape is invalid, the user is unauthorized by RLS, the request fails, or a value is malformed, the chart keeps its saved categories and series and shows the existing saved-data fallback state.

## Authorization

Supabase RLS remains the authority. The app does not elevate privileges or create an anonymous session for chart reads. The configured anon/publishable key or current user session must have `SELECT` permission on the table. The repository-owned sample table exposes only non-sensitive demo values and has a `SELECT` policy for `anon` and `authenticated`; it has no app-facing write grant or write policy.

Configure the built-in database chart with:

- Table: `sales_chart`
- Category column: `category`
- Value columns: `revenue, cost`
- Row limit: `100` or lower

The migration creates the concrete table and seed rows:

```sql
create table public.sales_chart (
  category text primary key,
  revenue double precision,
  cost double precision
);

alter table public.sales_chart enable row level security;
grant select on public.sales_chart to anon, authenticated;

create policy sales_chart_read on public.sales_chart
  for select to anon, authenticated using (true);
```

The migration also rejects blank categories and non-finite numeric values. Do not put private, tenant-specific, or user-owned data in this public sample table. Those sources must use a table-specific RLS policy and a contract that supplies the required authorization filter.
