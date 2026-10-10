create extension if not exists pgtap;
begin;
set local search_path = public, extensions;
select plan(16);

select ok(
  not has_table_privilege('anon', 'public.projects', 'SELECT'),
  'anon cannot read projects'
);
select ok(
  not has_table_privilege('anon', 'public.projects', 'INSERT'),
  'anon cannot insert projects'
);
select ok(
  not has_table_privilege('anon', 'public.projects', 'UPDATE'),
  'anon cannot update projects'
);
select ok(
  not has_table_privilege('anon', 'public.projects', 'DELETE'),
  'anon cannot delete projects'
);
select ok(
  not has_table_privilege('anon', 'public.canvas_snapshots', 'SELECT'),
  'anon cannot read canvas snapshots'
);
select ok(
  not has_table_privilege('anon', 'public.canvas_snapshots', 'INSERT'),
  'anon cannot insert canvas snapshots'
);
select ok(
  not has_table_privilege('anon', 'public.canvas_snapshots', 'UPDATE'),
  'anon cannot update canvas snapshots'
);
select ok(
  not has_table_privilege('anon', 'public.canvas_snapshots', 'DELETE'),
  'anon cannot delete canvas snapshots'
);
select ok(
  not has_table_privilege('anon', 'public.comments', 'SELECT'),
  'anon cannot read comments'
);
select ok(
  not has_table_privilege('anon', 'public.comments', 'INSERT'),
  'anon cannot insert comments'
);
select ok(
  not has_table_privilege('anon', 'public.comments', 'UPDATE'),
  'anon cannot update comments'
);
select ok(
  not has_table_privilege('anon', 'public.comments', 'DELETE'),
  'anon cannot delete comments'
);

select ok(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename in ('projects', 'canvas_snapshots', 'comments')
      and roles && array['anon']::name[]
  ),
  'no anon policy exists on core canvas data'
);

select ok(
  has_table_privilege('authenticated', 'public.projects', 'SELECT'),
  'authenticated role retains project table access for RLS-scoped policies'
);
select ok(
  has_table_privilege('authenticated', 'public.canvas_snapshots', 'SELECT'),
  'authenticated role retains snapshot table access for RLS-scoped policies'
);
select ok(
  has_table_privilege('authenticated', 'public.comments', 'SELECT'),
  'authenticated role retains comment table access for RLS-scoped policies'
);

select * from finish();
rollback;
