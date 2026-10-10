-- External provider catalog rows must retain a license before they can be
-- saved. Uploads may use the app's explicit user-supplied provenance, while
-- provider references without licensing metadata must stay out of the catalog.
create or replace function public.validate_asset_library_external_license()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.source in ('openverse', 'wikimedia', 'remote')
      and length(btrim(coalesce(new.license, ''))) = 0 then
    raise exception using
      errcode = '22023',
      message = 'External asset licenses are required';
  end if;
  return new;
end;
$$;

revoke all on function public.validate_asset_library_external_license()
from public, anon, authenticated;

drop trigger if exists validate_asset_library_external_license_trigger
  on public.asset_library_items;
create trigger validate_asset_library_external_license_trigger
before insert or update on public.asset_library_items
for each row execute function public.validate_asset_library_external_license();
