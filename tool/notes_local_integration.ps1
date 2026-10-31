[CmdletBinding()]
param(
    [string]$HostName = '127.0.0.1',
    [string]$DatabaseName = 'notes_test_local',
    [string]$User = 'postgres',
    [string]$PgPassFile = $env:PGPASSFILE,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

if ($HostName -cne '127.0.0.1') {
    throw "Refusing non-loopback host '$HostName'; only 127.0.0.1 is permitted."
}
if ($DatabaseName -notmatch '^notes_test_[A-Za-z0-9_]+$') {
    throw "Refusing database name '$DatabaseName'; names must use the notes_test_ prefix and safe characters."
}
if ([string]::IsNullOrWhiteSpace($PgPassFile)) {
    throw 'PGPASSFILE must identify a password file; its contents are never read or displayed.'
}
if (-not $DryRun -and -not (Test-Path -LiteralPath $PgPassFile -PathType Leaf)) {
    throw 'The PGPASSFILE path does not exist.'
}

$uniqueName = '{0}_{1}' -f $DatabaseName, ([Guid]::NewGuid().ToString('N'))
$assertionFile = Join-Path $env:TEMP "$uniqueName.sql"
if ($DryRun) {
    Write-Output "Dry run: host=127.0.0.1 database=$uniqueName user=$User"
    Write-Output 'No connection opened; no database created.'
    return
}

$psql = Get-Command psql -ErrorAction Stop
$migrationDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'supabase\migrations'
$migrations = @(
    Get-ChildItem -LiteralPath $migrationDir -Filter '*workspace_note*.sql'
    Get-Item -LiteralPath (Join-Path $migrationDir '20261016120000_notes_project_folders_favorites.sql')
    Get-Item -LiteralPath (Join-Path $migrationDir '20261016120150_notes_import_rpc.sql')
    Get-Item -LiteralPath (Join-Path $migrationDir '20261016120200_notes_crdt_collaboration.sql')
) | Sort-Object Name -Unique
if (-not $migrations) { throw 'No local workspace note migrations were found.' }

$createdRoles = [System.Collections.Generic.List[string]]::new()
$createdDatabase = $false
$env:PGPASSFILE = $PgPassFile
$common = @('--host=127.0.0.1', "--username=$User", '--no-password', '--no-psqlrc', '--set=ON_ERROR_STOP=1')
function Invoke-Psql([string[]]$Arguments) {
    & $psql.Source @Arguments
    if ($LASTEXITCODE -ne 0) { throw "psql exited with status $LASTEXITCODE." }
}
try {
    $roles = (& $psql.Source @common '--dbname=postgres' '--tuples-only' '--no-align' '--command=select rolname from pg_roles where rolname in (''anon'', ''authenticated'')')
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect local PostgreSQL roles.' }
    foreach ($role in @('anon', 'authenticated')) {
        if ($roles -notcontains $role) {
            Invoke-Psql ($common + @('--dbname=postgres', "--command=CREATE ROLE $role NOLOGIN"))
            $createdRoles.Add($role)
        }
    }
    Invoke-Psql ($common + @('--dbname=postgres', "--command=CREATE DATABASE `"$uniqueName`""))
    $createdDatabase = $true
    $fixture = @'
create schema if not exists auth;
create table auth.users (id uuid primary key);
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
create table public.projects (id text primary key, owner_id uuid references auth.users(id));
create table public.workspace_members (project_id text not null references public.projects(id) on delete cascade, user_id uuid not null references auth.users(id), role text not null check (role in ('owner','editor','commenter','viewer')), primary key(project_id,user_id));
create or replace function public.project_role(p_project text) returns text language sql stable security definer set search_path=pg_catalog,public,auth as $$
 select case when p.owner_id=auth.uid() then 'owner' else (select m.role from public.workspace_members m where m.project_id=p.id and m.user_id=auth.uid()) end from public.projects p where p.id=p_project
$$;
create or replace function public.can_read_project(p_project text) returns boolean language sql stable security definer set search_path=pg_catalog,public,auth as $$ select public.project_role(p_project) is not null $$;
create or replace function public.can_edit_project(p_project text) returns boolean language sql stable security definer set search_path=pg_catalog,public,auth as $$ select public.project_role(p_project) in ('owner','editor') $$;
create or replace function public.is_project_owner(p_project text) returns boolean language sql stable security definer set search_path=pg_catalog,public,auth as $$ select exists(select 1 from public.projects p where p.id=p_project and p.owner_id=auth.uid()) $$;
'@
    Invoke-Psql ($common + @("--dbname=$uniqueName", "--command=$fixture"))
    $identitySeed = @'
INSERT INTO auth.users(id) VALUES
 ('00000000-0000-4000-8000-000000000001'), ('00000000-0000-4000-8000-000000000002'),
 ('00000000-0000-4000-8000-000000000003'), ('00000000-0000-4000-8000-000000000004'),
 ('00000000-0000-4000-8000-000000000005'), ('00000000-0000-4000-8000-000000000006');
'@
    Invoke-Psql ($common + @("--dbname=$uniqueName", "--command=$identitySeed"))
    foreach ($migration in $migrations) {
        if ($migration.Name -eq '20261016120100_workspace_note_history.sql') {
            $legacyNote = @'
SET request.jwt.claim.sub = '00000000-0000-4000-8000-000000000001';
INSERT INTO public.workspace_notes(id, owner_user_id, created_by, title, markdown_content)
VALUES ('10000000-0000-4000-8000-000000000007', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', 'Legacy note', 'before history migration');
'@
            Invoke-Psql ($common + @("--dbname=$uniqueName", "--command=$legacyNote"))
        }
        Invoke-Psql ($common + @("--dbname=$uniqueName", "--file=$($migration.FullName)"))
    }
    $assertions = @'
DO $check$
BEGIN
  IF to_regclass('public.workspace_notes') IS NULL THEN
    RAISE EXCEPTION 'workspace_notes table missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = 'public.workspace_notes'::regclass AND relrowsecurity) THEN
    RAISE EXCEPTION 'workspace_notes RLS is not enabled';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rename_workspace_notes_with_links') THEN
    RAISE EXCEPTION 'notes rename RPC missing';
  END IF;
END
$check$;

DO $legacy_history$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_note_versions
    WHERE note_id='10000000-0000-4000-8000-000000000007'
      AND revision=1 AND title='Legacy note'
      AND markdown_content='before history migration'
      AND actor_id='00000000-0000-4000-8000-000000000001'
  ) THEN RAISE EXCEPTION 'legacy note initial version backfill failed'; END IF;
END
$legacy_history$;

-- Fixed records are synthetic; seed as the harness superuser with an actor claim for triggers.
SET request.jwt.claim.sub = '00000000-0000-4000-8000-000000000001';
INSERT INTO public.projects(id,owner_id) VALUES ('notes-fixture-project','00000000-0000-4000-8000-000000000001'), ('notes-fixture-empty-owner','00000000-0000-4000-8000-000000000006'), ('notes-fixture-null-owner',NULL), ('notes-fixture-other-project','00000000-0000-4000-8000-000000000001');
INSERT INTO public.workspace_members(project_id,user_id,role) VALUES
 ('notes-fixture-project','00000000-0000-4000-8000-000000000001','owner'),
 ('notes-fixture-project','00000000-0000-4000-8000-000000000002','editor'),
 ('notes-fixture-project','00000000-0000-4000-8000-000000000003','commenter'),
 ('notes-fixture-project','00000000-0000-4000-8000-000000000004','viewer'),
 ('notes-fixture-project','00000000-0000-4000-8000-000000000005','viewer');
INSERT INTO public.workspace_notes(id,owner_user_id,created_by,title,markdown_content,project_id) VALUES
 ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','Project note','fixture','notes-fixture-project'),
 ('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','Private note','fixture',NULL),
 ('10000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002','Other private','fixture',NULL),
 ('10000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000005','Child folder note','preserved project content','notes-fixture-project'),
 ('10000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-000000000002','Null-owner project note','must remain','notes-fixture-null-owner');
DO $initial_history$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_note_versions
    WHERE note_id='10000000-0000-4000-8000-000000000001'
      AND revision=1 AND title='Project note' AND markdown_content='fixture'
      AND actor_id='00000000-0000-4000-8000-000000000001'
  ) THEN RAISE EXCEPTION 'new note initial version capture failed'; END IF;
END
$initial_history$;
INSERT INTO public.workspace_note_folders(id,owner_user_id,project_id,name,parent_folder_id) VALUES
 ('20000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','notes-fixture-project','Project folder',NULL),
 ('20000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001',NULL,'Private folder',NULL),
 ('20000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000001','notes-fixture-project','Delete parent',NULL),
 ('20000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000001','notes-fixture-project','Child', '20000000-0000-4000-8000-000000000003'),
 ('20000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000006','notes-fixture-null-owner','Null owner folder',NULL),
 ('20000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-000000000001','notes-fixture-other-project','Other project folder',NULL),
 ('20000000-0000-4000-8000-000000000007','00000000-0000-4000-8000-000000000001','notes-fixture-project','Grandchild','20000000-0000-4000-8000-000000000004'),
 ('20000000-0000-4000-8000-000000000008','00000000-0000-4000-8000-000000000001','notes-fixture-project','Nested project folder','20000000-0000-4000-8000-000000000001');
UPDATE public.workspace_notes SET folder_id='20000000-0000-4000-8000-000000000001' WHERE id='10000000-0000-4000-8000-000000000001';
UPDATE public.workspace_notes SET folder_id='20000000-0000-4000-8000-000000000004' WHERE id='10000000-0000-4000-8000-000000000004';
UPDATE public.workspace_notes SET folder_id='20000000-0000-4000-8000-000000000005' WHERE id='10000000-0000-4000-8000-000000000005';
INSERT INTO public.workspace_note_preferences(user_id,note_id) VALUES
 ('00000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002');

SET ROLE authenticated;
SET request.jwt.claim.sub = '00000000-0000-4000-8000-000000000001';
DO $import_batch$
DECLARE
  v_imported integer;
BEGIN
  SELECT count(*) INTO v_imported
  FROM public.import_workspace_notes_batch(
    '[{"id":"30000000-0000-4000-8000-000000000001","title":"Imported fixture","markdown_content":"exact\nmarkdown","folder_path":"Import parent/Child"}]'::jsonb,
    '["Import parent","Import parent/Child"]'::jsonb,
    'notes-fixture-project'
  );
  IF v_imported <> 1 THEN RAISE EXCEPTION 'atomic import did not return its inserted note'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_notes n
    JOIN public.workspace_note_folders f ON f.id=n.folder_id
    WHERE n.id='30000000-0000-4000-8000-000000000001'
      AND n.owner_user_id=auth.uid() AND n.created_by=auth.uid()
      AND n.project_id='notes-fixture-project' AND n.title='Imported fixture'
      AND n.markdown_content=E'exact\nmarkdown' AND f.name='Child'
      AND f.parent_folder_id=(SELECT id FROM public.workspace_note_folders
        WHERE project_id='notes-fixture-project' AND name='Import parent')
  ) THEN RAISE EXCEPTION 'import did not preserve content, hierarchy, or server attribution'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_note_versions
    WHERE note_id='30000000-0000-4000-8000-000000000001'
      AND revision=1 AND actor_id=auth.uid() AND markdown_content=E'exact\nmarkdown'
  ) THEN RAISE EXCEPTION 'import did not create attributed initial history'; END IF;
END
$import_batch$;

DO $import_rollback$
DECLARE
  v_rejected boolean := false;
BEGIN
  BEGIN
    PERFORM * FROM public.import_workspace_notes_batch(
      '[{"id":"30000000-0000-4000-8000-000000000002","title":"Atomic collision","markdown_content":"one"},{"id":"30000000-0000-4000-8000-000000000003","title":"Atomic collision","markdown_content":"two"}]'::jsonb,
      '[]'::jsonb,
      'notes-fixture-project'
    );
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'invalid atomic import unexpectedly succeeded'; END IF;
  IF EXISTS (SELECT 1 FROM public.workspace_notes WHERE id IN (
    '30000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000003'
  )) THEN RAISE EXCEPTION 'failed import left partial notes behind'; END IF;
END
$import_rollback$;

DO $notes_crdt_rpc$
DECLARE
  v_note public.workspace_notes%rowtype;
  v_added boolean;
  v_delta_count integer;
  v_denied boolean := false;
  v_rollback boolean := false;
BEGIN
  v_note := public.create_workspace_note_from_sync(
    '30000000-0000-4000-8000-000000000004',
    'Offline CRDT fixture',
    'seed text',
    'notes-fixture-project',
    '{"sequence":{"atoms":[]}}'::jsonb,
    '{}'::jsonb
  );
  IF v_note.revision <> 1 OR v_note.created_by <> auth.uid() THEN
    RAISE EXCEPTION 'offline note create attribution failed';
  END IF;

  -- Deliver a causally later operation before its prerequisite to exercise delayed replay.
  v_added := public.append_workspace_note_crdt_operation(
    v_note.id,
    '{"noteId":"30000000-0000-4000-8000-000000000004","opId":"30000000-0000-4000-8000-000000000004:device-harness:2","replicaId":"device-harness","dot":{"actorId":"device-harness","counter":2},"dependencies":{"device-harness":1},"insertions":[],"deletions":[]}'::jsonb
  );
  IF NOT v_added THEN RAISE EXCEPTION 'delayed CRDT operation was not inserted before its prerequisite'; END IF;
  v_added := public.append_workspace_note_crdt_operation(
    v_note.id,
    '{"noteId":"30000000-0000-4000-8000-000000000004","opId":"30000000-0000-4000-8000-000000000004:device-harness:1","replicaId":"device-harness","dot":{"actorId":"device-harness","counter":1},"dependencies":{},"insertions":[],"deletions":[]}'::jsonb
  );
  IF NOT v_added THEN RAISE EXCEPTION 'late prerequisite CRDT operation was not inserted'; END IF;
  v_added := public.append_workspace_note_crdt_operation(
    v_note.id,
    '{"noteId":"30000000-0000-4000-8000-000000000004","opId":"30000000-0000-4000-8000-000000000004:device-harness:1","replicaId":"device-harness","dot":{"actorId":"device-harness","counter":1},"dependencies":{},"insertions":[],"deletions":[]}'::jsonb
  );
  IF v_added THEN RAISE EXCEPTION 'duplicate CRDT operation was inserted twice'; END IF;
  SELECT count(*) INTO v_delta_count FROM public.get_workspace_note_crdt_delta(
    v_note.id, '{}'::jsonb, 10
  );
  IF v_delta_count <> 2 THEN RAISE EXCEPTION 'out-of-order CRDT delta did not return both operations'; END IF;

  v_note := public.materialize_workspace_note_crdt(
    v_note.id,
    1,
    'materialized text',
    '{"sequence":{"atoms":[]}}'::jsonb,
    '{"device-harness":2}'::jsonb
  );
  IF v_note.revision <> 2 OR v_note.markdown_content <> 'materialized text'
     OR NOT EXISTS (
       SELECT 1 FROM public.workspace_note_versions
       WHERE note_id=v_note.id AND revision=2 AND actor_id=auth.uid()
     ) THEN RAISE EXCEPTION 'CRDT materialization/history was not atomic'; END IF;

  BEGIN
    PERFORM public.materialize_workspace_note_crdt(
      v_note.id, 1, 'stale text', '{"sequence":{"atoms":[]}}'::jsonb,
      '{"device-harness":2}'::jsonb
    );
  EXCEPTION WHEN SQLSTATE '40001' THEN
    v_rollback := true;
  END;
  IF NOT v_rollback OR (SELECT markdown_content FROM public.workspace_notes WHERE id=v_note.id) <> 'materialized text' THEN
    RAISE EXCEPTION 'stale CRDT materialization changed the note';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000003', true);
  BEGIN
    PERFORM public.append_workspace_note_crdt_operation(
      v_note.id,
      '{"noteId":"30000000-0000-4000-8000-000000000004","opId":"30000000-0000-4000-8000-000000000004:commenter-device:1","replicaId":"commenter-device","dot":{"actorId":"commenter-device","counter":1},"dependencies":{},"insertions":[],"deletions":[]}'::jsonb
    );
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'commenter wrote Notes CRDT operation'; END IF;
  PERFORM set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', true);

  v_rollback := false;
  BEGIN
    PERFORM public.create_workspace_note_from_sync(
      '30000000-0000-4000-8000-000000000005', 'Invalid state', 'text',
      'notes-fixture-project', '[]'::jsonb, '{}'::jsonb
    );
  EXCEPTION WHEN SQLSTATE '22023' THEN
    v_rollback := true;
  END;
  IF NOT v_rollback OR EXISTS (
    SELECT 1 FROM public.workspace_notes WHERE id='30000000-0000-4000-8000-000000000005'
  ) THEN RAISE EXCEPTION 'failed offline create left a note behind'; END IF;
END
$notes_crdt_rpc$;

SET request.jwt.claim.sub = '00000000-0000-4000-8000-000000000001';
DO $rls_owner$
DECLARE
  v_before_count bigint;
  v_before_revision integer;
  v_error text;
BEGIN
  IF (SELECT count(*) FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000001') <> 1 THEN RAISE EXCEPTION 'owner cannot read project note'; END IF;
  IF (SELECT count(*) FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000004') <> 1 THEN RAISE EXCEPTION 'owner cannot read removed-creator note'; END IF;
  IF (SELECT count(*) FROM public.workspace_note_versions WHERE note_id='10000000-0000-4000-8000-000000000001') <> 1 THEN RAISE EXCEPTION 'project member can read note versions'; END IF;
  UPDATE public.workspace_notes SET title='owner-write', revision=revision+1 WHERE id='10000000-0000-4000-8000-000000000001';
  IF NOT FOUND THEN RAISE EXCEPTION 'owner cannot write project note'; END IF;
  IF (SELECT count(*) FROM public.workspace_note_versions WHERE note_id='10000000-0000-4000-8000-000000000001') <> 2
     OR NOT EXISTS (SELECT 1 FROM public.workspace_note_versions WHERE note_id='10000000-0000-4000-8000-000000000001' AND revision=2 AND title='owner-write' AND actor_id=auth.uid()) THEN
    RAISE EXCEPTION 'changed content creates one version';
  END IF;

  SELECT count(*) INTO v_before_count FROM public.workspace_note_versions WHERE note_id='10000000-0000-4000-8000-000000000001';
  UPDATE public.workspace_notes SET markdown_content=markdown_content, revision=revision WHERE id='10000000-0000-4000-8000-000000000001';
  IF (SELECT count(*) FROM public.workspace_note_versions WHERE note_id='10000000-0000-4000-8000-000000000001') <> v_before_count THEN
    RAISE EXCEPTION 'no-op content update creates no version';
  END IF;

  UPDATE public.workspace_notes SET deleted_at=now(), revision=revision+1 WHERE id='10000000-0000-4000-8000-000000000001';
  UPDATE public.workspace_notes SET deleted_at=NULL, revision=revision+1 WHERE id='10000000-0000-4000-8000-000000000001';
  IF (SELECT count(*) FROM public.workspace_note_versions WHERE note_id='10000000-0000-4000-8000-000000000001') <> v_before_count
     OR (SELECT deleted_at FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000001') IS NOT NULL THEN
    RAISE EXCEPTION 'soft delete and restore do not create content versions';
  END IF;

  v_error := NULL;
  BEGIN
    UPDATE public.workspace_notes SET title='missing-revision-bump' WHERE id='10000000-0000-4000-8000-000000000001';
  EXCEPTION WHEN others THEN GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
  END;
  IF v_error IS DISTINCT FROM 'workspace_note_revision_mismatch'
     OR (SELECT count(*) FROM public.workspace_note_versions WHERE note_id='10000000-0000-4000-8000-000000000001') <> v_before_count
     OR (SELECT title FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000001') <> 'owner-write' THEN
    RAISE EXCEPTION 'content change without one revision increment rejected';
  END IF;

  SELECT revision INTO v_before_revision FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000001';
  v_error := NULL;
  BEGIN
    UPDATE public.workspace_notes SET revision=revision+1 WHERE id='10000000-0000-4000-8000-000000000001';
  EXCEPTION WHEN others THEN GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
  END;
  IF v_error IS DISTINCT FROM 'workspace_note_revision_without_content_change'
     OR (SELECT count(*) FROM public.workspace_note_versions WHERE note_id='10000000-0000-4000-8000-000000000001') <> v_before_count
     OR (SELECT revision FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000001') <> v_before_revision THEN
    RAISE EXCEPTION 'revision-only update rejected without content change';
  END IF;

  v_error := NULL;
  BEGIN
    UPDATE public.workspace_notes SET title='rolled-back', revision=revision+1 WHERE id='10000000-0000-4000-8000-000000000001';
    RAISE EXCEPTION 'history rollback sentinel';
  EXCEPTION WHEN others THEN GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
  END;
  IF v_error IS DISTINCT FROM 'history rollback sentinel'
     OR (SELECT count(*) FROM public.workspace_note_versions WHERE note_id='10000000-0000-4000-8000-000000000001') <> v_before_count
     OR (SELECT title FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000001') <> 'owner-write' THEN
    RAISE EXCEPTION 'rolled back note update leaves no version';
  END IF;

  IF (SELECT count(*) FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000002') <> 1 THEN RAISE EXCEPTION 'private note owner cannot read'; END IF;
  IF (SELECT count(*) FROM public.workspace_note_folders WHERE id='20000000-0000-4000-8000-000000000001') <> 1 THEN RAISE EXCEPTION 'owner cannot read project folder'; END IF;
END $rls_owner$;
DO $history_privileges$
BEGIN
  IF has_table_privilege('authenticated', 'public.workspace_note_versions', 'INSERT') THEN RAISE EXCEPTION 'history insert privilege was granted'; END IF;
  IF has_table_privilege('authenticated', 'public.workspace_note_versions', 'UPDATE') THEN RAISE EXCEPTION 'history update privilege was granted'; END IF;
  IF has_table_privilege('authenticated', 'public.workspace_note_versions', 'DELETE') THEN RAISE EXCEPTION 'history delete privilege was granted'; END IF;
  IF has_table_privilege('authenticated', 'public.workspace_note_versions', 'TRUNCATE') THEN RAISE EXCEPTION 'history truncate privilege was granted'; END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname ILIKE '%workspace_note%version%prun%') THEN RAISE EXCEPTION 'history pruning routine detected'; END IF;
END $history_privileges$;
DO $forged_creator_insert$
DECLARE rejected boolean := false;
BEGIN
  BEGIN
    INSERT INTO public.workspace_notes(id, owner_user_id, created_by, title, markdown_content, project_id)
    VALUES ('10000000-0000-4000-8000-000000000006', auth.uid(), '00000000-0000-4000-8000-000000000002', 'Forged creator', 'must be rejected', 'notes-fixture-project');
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'forged created_by insert rejected assertion failed'; END IF;
END $forged_creator_insert$;
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '00000000-0000-4000-8000-000000000002';
DO $rls_editor$ BEGIN
  IF (SELECT count(*) FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000001') <> 1 THEN RAISE EXCEPTION 'editor cannot read project note'; END IF;
  IF (SELECT count(*) FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000004') <> 1 THEN RAISE EXCEPTION 'editor cannot read removed-creator note'; END IF;
  IF (SELECT count(*) FROM public.workspace_note_versions WHERE note_id='10000000-0000-4000-8000-000000000001') <> 2 THEN RAISE EXCEPTION 'project member can read note versions'; END IF;
  UPDATE public.workspace_notes SET title='editor-write', revision=revision+1 WHERE id='10000000-0000-4000-8000-000000000001';
  IF NOT FOUND THEN RAISE EXCEPTION 'editor cannot write project note'; END IF;
  IF (SELECT count(*) FROM public.workspace_note_preferences WHERE user_id=auth.uid()) <> 1 THEN RAISE EXCEPTION 'personal favorite visibility failed'; END IF;
  IF EXISTS (SELECT 1 FROM public.workspace_note_preferences WHERE user_id <> auth.uid()) THEN RAISE EXCEPTION 'favorite user isolation failed'; END IF;
  IF (SELECT count(*) FROM public.workspace_note_folders WHERE id='20000000-0000-4000-8000-000000000001') <> 1 THEN RAISE EXCEPTION 'editor cannot read project folder'; END IF;
END $rls_editor$;
DO $favorite_write$
DECLARE rejected boolean := false;
BEGIN
  BEGIN INSERT INTO public.workspace_note_preferences(user_id,note_id) VALUES ('00000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001');
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'favorite write isolation failed'; END IF;
END $favorite_write$;
DO $rename_scope$
DECLARE
  v_target_revision integer;
  v_private_revision integer;
  v_mixed_snapshot jsonb;
  v_project_snapshot jsonb;
  v_error text;
BEGIN
  SELECT revision INTO v_target_revision FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000001';
  SELECT jsonb_agg(jsonb_build_object('id', n.id, 'revision', n.revision) ORDER BY n.id)
    INTO v_project_snapshot
    FROM public.workspace_notes n
    WHERE n.project_id='notes-fixture-project' AND n.deleted_at IS NULL;
  PERFORM * FROM public.rename_workspace_notes_with_links(
    '10000000-0000-4000-8000-000000000001', v_target_revision, 'renamed project note', v_project_snapshot, '[]'::jsonb
  );
  IF NOT EXISTS (SELECT 1 FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000001' AND title='renamed project note' AND revision=v_target_revision+1) THEN RAISE EXCEPTION 'same-scope project rename failed'; END IF;

  SELECT revision INTO v_target_revision FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000001';
  SELECT jsonb_agg(jsonb_build_object('id', n.id, 'revision', n.revision) ORDER BY n.id)
    INTO v_project_snapshot
    FROM public.workspace_notes n
    WHERE n.project_id='notes-fixture-project' AND n.deleted_at IS NULL;
  v_private_revision := 1; -- The private fixture note is untouched and revision defaults to 1.
  v_mixed_snapshot := v_project_snapshot || jsonb_build_array(
    jsonb_build_object('id','10000000-0000-4000-8000-000000000002','revision',v_private_revision)
  );
  v_error := NULL;
  BEGIN
    PERFORM * FROM public.rename_workspace_notes_with_links(
      '10000000-0000-4000-8000-000000000001', v_target_revision, 'mixed scope', v_mixed_snapshot, '[]'::jsonb
    );
  EXCEPTION WHEN others THEN GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
  END;
  IF v_error IS DISTINCT FROM 'workspace_notes_conflict' THEN RAISE EXCEPTION 'mixed private/project rename was not rejected as scope conflict (got: %)', COALESCE(v_error, '<null>'); END IF;
  IF (SELECT title FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000001') <> 'renamed project note' THEN RAISE EXCEPTION 'mixed scope rename modified target'; END IF;

  v_error := NULL;
  BEGIN
    PERFORM * FROM public.rename_workspace_notes_with_links(
      '10000000-0000-4000-8000-000000000001', v_target_revision-1, 'stale rename', v_project_snapshot, '[]'::jsonb
    );
  EXCEPTION WHEN others THEN GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
  END;
  IF v_error IS DISTINCT FROM 'workspace_notes_conflict' THEN RAISE EXCEPTION 'stale rename snapshot conflict missing'; END IF;
  IF (SELECT title FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000001') <> 'renamed project note' THEN RAISE EXCEPTION 'stale rename changed target'; END IF;
END $rename_scope$;
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '00000000-0000-4000-8000-000000000003';
DO $rls_commenter$ BEGIN
  IF (SELECT count(*) FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000001') <> 1 THEN RAISE EXCEPTION 'commenter cannot read project note'; END IF;
  IF (SELECT count(*) FROM public.workspace_note_versions WHERE note_id='10000000-0000-4000-8000-000000000001') <> 4 THEN RAISE EXCEPTION 'project member can read note versions'; END IF;
  IF (SELECT count(*) FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000004') <> 1 THEN RAISE EXCEPTION 'commenter cannot read removed-creator note'; END IF;
  UPDATE public.workspace_notes SET title='denied' WHERE id='10000000-0000-4000-8000-000000000001';
  IF FOUND THEN RAISE EXCEPTION 'commenter wrote project note'; END IF;
  IF (SELECT count(*) FROM public.workspace_note_folders WHERE id='20000000-0000-4000-8000-000000000001') <> 1 THEN RAISE EXCEPTION 'commenter cannot read project folder'; END IF;
  UPDATE public.workspace_note_folders SET name='denied' WHERE id='20000000-0000-4000-8000-000000000001';
  IF FOUND THEN RAISE EXCEPTION 'commenter wrote project folder'; END IF;
END $rls_commenter$;
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '00000000-0000-4000-8000-000000000004';
DO $rls_viewer$ BEGIN
  IF (SELECT count(*) FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000001') <> 1 THEN RAISE EXCEPTION 'viewer cannot read project note'; END IF;
  IF (SELECT count(*) FROM public.workspace_note_versions WHERE note_id='10000000-0000-4000-8000-000000000001') <> 4 THEN RAISE EXCEPTION 'project member can read note versions'; END IF;
  IF (SELECT count(*) FROM public.workspace_note_versions WHERE note_id='10000000-0000-4000-8000-000000000002') <> 0 THEN RAISE EXCEPTION 'unauthorized note versions remain hidden'; END IF;
  IF (SELECT count(*) FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000004') <> 1 THEN RAISE EXCEPTION 'viewer cannot read removed-creator note'; END IF;
  UPDATE public.workspace_notes SET title='denied' WHERE id='10000000-0000-4000-8000-000000000001';
  IF FOUND THEN RAISE EXCEPTION 'viewer wrote project note'; END IF;
  IF (SELECT count(*) FROM public.workspace_note_folders WHERE id='20000000-0000-4000-8000-000000000001') <> 1 THEN RAISE EXCEPTION 'viewer cannot read project folder'; END IF;
  UPDATE public.workspace_note_folders SET name='denied' WHERE id='20000000-0000-4000-8000-000000000001';
  IF FOUND THEN RAISE EXCEPTION 'viewer wrote project folder'; END IF;
  IF (SELECT count(*) FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000002') <> 0 THEN RAISE EXCEPTION 'private note remains invisible'; END IF;
END $rls_viewer$;
RESET ROLE;
DELETE FROM public.workspace_members WHERE project_id='notes-fixture-project' AND user_id='00000000-0000-4000-8000-000000000005';
SET ROLE authenticated;
SET request.jwt.claim.sub = '00000000-0000-4000-8000-000000000005';
DO $rls_removed$ BEGIN
  IF (SELECT count(*) FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000001') <> 0 THEN RAISE EXCEPTION 'removed member cannot read linked note'; END IF;
  IF (SELECT count(*) FROM public.workspace_note_versions WHERE note_id='10000000-0000-4000-8000-000000000001') <> 0 THEN RAISE EXCEPTION 'unauthorized note versions remain hidden'; END IF;
  IF (SELECT count(*) FROM public.workspace_note_folders WHERE id='20000000-0000-4000-8000-000000000001') <> 0 THEN RAISE EXCEPTION 'removed member cannot read folders'; END IF;
END $rls_removed$;
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '00000000-0000-4000-8000-000000000001';
DO $remaining_owner$ BEGIN IF (SELECT count(*) FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000004') <> 1 THEN RAISE EXCEPTION 'project owner lost note after creator removal'; END IF; END $remaining_owner$;
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '00000000-0000-4000-8000-000000000002';
DO $remaining_editor$ BEGIN IF (SELECT count(*) FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000004') <> 1 THEN RAISE EXCEPTION 'editor lost note after creator removal'; END IF; END $remaining_editor$;
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '00000000-0000-4000-8000-000000000004';
DO $remaining_viewer$ BEGIN IF (SELECT count(*) FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000004') <> 1 THEN RAISE EXCEPTION 'remaining viewer lost note after creator removal'; END IF; END $remaining_viewer$;
RESET ROLE;

-- Trigger and scope outcomes run with an actual authenticated role; fixture mutations reset to superuser.
SET ROLE authenticated;
SET request.jwt.claim.sub = '00000000-0000-4000-8000-000000000001';
DO $guards$
DECLARE rejected boolean := false;
BEGIN
  BEGIN
    UPDATE public.workspace_notes SET created_by='00000000-0000-4000-8000-000000000002' WHERE id='10000000-0000-4000-8000-000000000001';
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'created_by mutation rejection failed'; END IF;
  rejected := false;
  BEGIN
    UPDATE public.workspace_notes SET folder_id='20000000-0000-4000-8000-000000000002' WHERE id='10000000-0000-4000-8000-000000000001';
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'folder project scope mismatch rejected assertion failed'; END IF;
  rejected := false;
  BEGIN
    UPDATE public.workspace_notes SET folder_id='20000000-0000-4000-8000-000000000006' WHERE id='10000000-0000-4000-8000-000000000001';
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'cross-project folder scope rejection failed'; END IF;
  rejected := false;
  BEGIN
    UPDATE public.workspace_note_folders SET parent_folder_id='20000000-0000-4000-8000-000000000002' WHERE id='20000000-0000-4000-8000-000000000001';
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'private-owner folder scope mismatch rejected assertion failed'; END IF;
END
$guards$;
RESET ROLE;
SET ROLE authenticated;
SET request.jwt.claim.sub = '00000000-0000-4000-8000-000000000002';
DO $private_owner_mismatch$
DECLARE rejected boolean := false;
BEGIN
  BEGIN
    UPDATE public.workspace_notes SET folder_id='20000000-0000-4000-8000-000000000002' WHERE id='10000000-0000-4000-8000-000000000003';
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'private owner folder mismatch rejection failed'; END IF;
END $private_owner_mismatch$;
RESET ROLE;

-- The delete trigger reparents children and notes instead of deleting their content.
DELETE FROM public.workspace_note_folders WHERE id='20000000-0000-4000-8000-000000000004';
DO $child_delete$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000004' AND folder_id='20000000-0000-4000-8000-000000000003' AND markdown_content='preserved project content') THEN RAISE EXCEPTION 'folder child deletion did not reparent note'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.workspace_note_folders WHERE id='20000000-0000-4000-8000-000000000007' AND parent_folder_id='20000000-0000-4000-8000-000000000003') THEN RAISE EXCEPTION 'child folder deletion did not reparent child'; END IF;
END $child_delete$;
DELETE FROM public.workspace_note_folders WHERE id='20000000-0000-4000-8000-000000000003';
DO $parent_delete$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000004' AND folder_id IS NULL AND markdown_content='preserved project content') THEN RAISE EXCEPTION 'folder delete did not reparent note to root'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.workspace_note_folders WHERE id='20000000-0000-4000-8000-000000000007' AND parent_folder_id IS NULL) THEN RAISE EXCEPTION 'parent folder deletion did not reparent child to root'; END IF;
END $parent_delete$;

-- A null-owner project with linked content must reject deletion atomically.
SET request.jwt.claim.sub = '00000000-0000-4000-8000-000000000006';
DO $null_owner_delete$
DECLARE rejected boolean := false;
BEGIN
  BEGIN DELETE FROM public.projects WHERE id='notes-fixture-null-owner';
  EXCEPTION WHEN others THEN rejected := true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'null-owner project delete rejection failed'; END IF;
END $null_owner_delete$;
DO $null_owner_preserved$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.projects WHERE id='notes-fixture-null-owner') OR NOT EXISTS (SELECT 1 FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000005' AND project_id='notes-fixture-null-owner' AND markdown_content='must remain') OR NOT EXISTS (SELECT 1 FROM public.workspace_note_folders WHERE id='20000000-0000-4000-8000-000000000005' AND project_id='notes-fixture-null-owner') THEN RAISE EXCEPTION 'null-owner rejection did not preserve linked content'; END IF;
END $null_owner_preserved$;

-- Project deletion must rehome linked rows to its owner without losing creator/content.
SET request.jwt.claim.sub = '00000000-0000-4000-8000-000000000001';
DELETE FROM public.projects WHERE id='notes-fixture-project';
DO $project_rehome$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000001' AND project_id IS NULL AND owner_user_id='00000000-0000-4000-8000-000000000001' AND created_by='00000000-0000-4000-8000-000000000001' AND markdown_content='fixture') THEN RAISE EXCEPTION 'project delete rehomes notes or created_by preserved failed'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.workspace_notes WHERE id='10000000-0000-4000-8000-000000000004' AND project_id IS NULL AND owner_user_id='00000000-0000-4000-8000-000000000001' AND created_by='00000000-0000-4000-8000-000000000005' AND markdown_content='preserved project content') THEN RAISE EXCEPTION 'project delete rehomes notes content failed'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.workspace_note_folders WHERE id='20000000-0000-4000-8000-000000000001' AND project_id IS NULL AND owner_user_id='00000000-0000-4000-8000-000000000001') THEN RAISE EXCEPTION 'project delete rehomes folders failed'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.workspace_note_folders WHERE id='20000000-0000-4000-8000-000000000008' AND project_id IS NULL AND parent_folder_id IS NULL AND owner_user_id='00000000-0000-4000-8000-000000000001') THEN RAISE EXCEPTION 'project delete rehomes nested folders'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.workspace_note_preferences WHERE user_id='00000000-0000-4000-8000-000000000002' AND note_id='10000000-0000-4000-8000-000000000001') THEN RAISE EXCEPTION 'project delete preserves favorite'; END IF;
END
$project_rehome$;
RESET ROLE;
'@
    [System.IO.File]::WriteAllText($assertionFile, $assertions)
    Invoke-Psql ($common + @("--dbname=$uniqueName", "--file=$assertionFile"))
    Write-Output "Local integration assertions passed for $uniqueName."
}
finally {
    if ($createdDatabase) {
        Invoke-Psql ($common + @('--dbname=postgres', "--command=DROP DATABASE IF EXISTS `"$uniqueName`" WITH (FORCE)"))
    }
    foreach ($role in $createdRoles) {
        Invoke-Psql ($common + @('--dbname=postgres', "--command=DROP ROLE IF EXISTS $role"))
    }
    if (Test-Path -LiteralPath $assertionFile -PathType Leaf) {
        Remove-Item -LiteralPath $assertionFile -Force
    }
}
