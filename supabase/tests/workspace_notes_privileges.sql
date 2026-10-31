create extension if not exists pgtap;
begin;
set local search_path = public, extensions;
select plan(25);

select ok(
  has_table_privilege('authenticated', 'public.workspace_notes', 'SELECT'),
  'authenticated can select workspace notes subject to RLS'
);
select ok(
  has_table_privilege('authenticated', 'public.workspace_notes', 'INSERT'),
  'authenticated can insert workspace notes subject to RLS'
);
select ok(
  has_table_privilege('authenticated', 'public.workspace_notes', 'UPDATE'),
  'authenticated can update workspace notes subject to RLS'
);
select ok(
  has_table_privilege('authenticated', 'public.workspace_notes', 'DELETE'),
  'authenticated can delete workspace notes subject to RLS'
);

select ok(
  not has_table_privilege('authenticated', 'public.workspace_notes', 'TRUNCATE'),
  'authenticated cannot truncate workspace notes'
);
select ok(
  not has_table_privilege('authenticated', 'public.workspace_notes', 'TRIGGER'),
  'authenticated cannot create triggers on workspace notes'
);
select ok(
  not has_table_privilege('authenticated', 'public.workspace_notes', 'REFERENCES'),
  'authenticated cannot reference workspace notes'
);

select ok(
  not has_table_privilege('anon', 'public.workspace_notes', 'SELECT'),
  'anon cannot select workspace notes'
);
select ok(
  not has_table_privilege('anon', 'public.workspace_notes', 'INSERT'),
  'anon cannot insert workspace notes'
);
select ok(
  not has_table_privilege('anon', 'public.workspace_notes', 'UPDATE'),
  'anon cannot update workspace notes'
);
select ok(
  not has_table_privilege('anon', 'public.workspace_notes', 'DELETE'),
  'anon cannot delete workspace notes'
);
select ok(
  not has_table_privilege('anon', 'public.workspace_notes', 'TRUNCATE'),
  'anon cannot truncate workspace notes'
);
select ok(
  not has_table_privilege('anon', 'public.workspace_notes', 'TRIGGER'),
  'anon cannot create triggers on workspace notes'
);
select ok(
  not has_table_privilege('anon', 'public.workspace_notes', 'REFERENCES'),
  'anon cannot reference workspace notes'
);

select ok(
  not exists (
    select 1
    from pg_class as relation
    cross join lateral aclexplode(
      coalesce(relation.relacl, acldefault('r', relation.relowner))
    ) as privilege
    where relation.oid = 'public.workspace_notes'::regclass
      and privilege.grantee = 0
  ),
  'PUBLIC has no table privileges on workspace notes'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.workspace_notes'::regclass
  ),
  'row-level security remains enabled for workspace notes'
);

select ok(
  (
    select count(*) = 4
      and bool_and(roles = array['authenticated']::name[])
      and bool_and(
        case cmd
          when 'SELECT' then qual like '%workspace_note_can_read%'
          when 'INSERT' then with_check like '%created_by%auth.uid()%'
          when 'UPDATE' then qual like '%workspace_note_can_edit%'
            and with_check like '%workspace_note_can_edit%'
          when 'DELETE' then qual like '%workspace_note_can_edit%'
          else false
        end
      )
    from pg_policies
    where schemaname = 'public'
      and tablename = 'workspace_notes'
      and policyname in ('workspace_notes_read', 'workspace_notes_insert', 'workspace_notes_update', 'workspace_notes_delete')
  ),
  'private and project notes use the four narrow authenticated policies'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'workspace_notes'
      and policyname = 'workspace_notes_read'
      and qual like '%workspace_note_can_read%'
  ),
  'project members read only through current membership helper'
);
select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'workspace_notes'
      and policyname = 'workspace_notes_update'
      and qual like '%workspace_note_can_edit%'
      and with_check like '%workspace_note_can_edit%'
  ),
  'only private owners and current project editors can write notes'
);

select ok(
  has_table_privilege('authenticated', 'public.workspace_note_folders', 'SELECT')
    and has_table_privilege('authenticated', 'public.workspace_note_folders', 'INSERT')
    and has_table_privilege('authenticated', 'public.workspace_note_folders', 'UPDATE')
    and has_table_privilege('authenticated', 'public.workspace_note_folders', 'DELETE'),
  'authenticated folder DML is granted subject to RLS'
);
select ok(
  has_table_privilege('authenticated', 'public.workspace_note_preferences', 'SELECT')
    and has_table_privilege('authenticated', 'public.workspace_note_preferences', 'INSERT')
    and has_table_privilege('authenticated', 'public.workspace_note_preferences', 'UPDATE')
    and has_table_privilege('authenticated', 'public.workspace_note_preferences', 'DELETE'),
  'authenticated preference DML is granted subject to RLS'
);
select ok(
  not has_table_privilege('anon', 'public.workspace_note_folders', 'SELECT')
    and not has_table_privilege('anon', 'public.workspace_note_preferences', 'SELECT')
    and not has_table_privilege('anon', 'public.workspace_note_folders', 'INSERT')
    and not has_table_privilege('anon', 'public.workspace_note_preferences', 'INSERT'),
  'anon cannot read or insert folders or preferences'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.workspace_note_folders'::regclass)
    and (select relrowsecurity from pg_class where oid = 'public.workspace_note_preferences'::regclass),
  'folders and preferences both enforce RLS'
);
select ok(
  (
    select count(*) = 4
      and bool_and(roles = array['authenticated']::name[])
      and bool_and(
        case cmd
          when 'SELECT' then qual like '%workspace_note_can_read%'
          when 'INSERT' then with_check like '%can_edit_project%'
          when 'UPDATE' then qual like '%workspace_note_can_edit%'
            and with_check like '%workspace_note_can_edit%'
          when 'DELETE' then qual like '%workspace_note_can_edit%'
          else false
        end
      )
    from pg_policies
    where schemaname = 'public'
      and tablename = 'workspace_note_folders'
      and policyname in ('workspace_note_folders_select', 'workspace_note_folders_insert', 'workspace_note_folders_update', 'workspace_note_folders_delete')
  ),
  'folder policies use current membership helpers'
);
select ok(
  (
    select count(*) = 3
      and bool_and(roles = array['authenticated']::name[])
      and bool_and(
        case cmd
          when 'SELECT' then qual like '%user_id = auth.uid()%'
            and qual like '%workspace_note_can_read%'
          when 'INSERT' then with_check like '%user_id = auth.uid()%'
            and with_check like '%workspace_note_can_read%'
          when 'DELETE' then qual like '%user_id = auth.uid()%'
          else false
        end
      )
    from pg_policies
    where schemaname = 'public'
      and tablename = 'workspace_note_preferences'
      and policyname in ('workspace_note_preferences_read', 'workspace_note_preferences_insert', 'workspace_note_preferences_delete')
  ),
  'preference policies enforce per-user visibility and writes'
);

select * from finish();
rollback;
