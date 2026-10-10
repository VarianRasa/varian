-- These functions are invoked only by table triggers. They must not be
-- reachable as public RPCs merely because they live in the public schema.
revoke all on function public.validate_asset_library_item_boundaries()
from public, anon, authenticated;
revoke all on function public.validate_asset_library_folder_boundaries()
from public, anon, authenticated;
revoke all on function public.validate_asset_library_item_folder()
from public, anon, authenticated;
