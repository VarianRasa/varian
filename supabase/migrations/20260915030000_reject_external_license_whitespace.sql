-- Keep provider provenance values canonical at the database boundary too.
create or replace function public.validate_asset_library_external_license()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.source in ('openverse', 'wikimedia', 'remote') then
    if length(btrim(coalesce(new.license, ''))) = 0 then
      raise exception using
        errcode = '22023',
        message = 'External asset licenses are required';
    end if;
    if new.license <> btrim(new.license) then
      raise exception using
        errcode = '22023',
        message = 'Asset license cannot contain surrounding whitespace';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.validate_asset_library_external_license()
from public, anon, authenticated;
