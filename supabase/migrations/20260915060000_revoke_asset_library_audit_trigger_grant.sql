-- Audit rows are emitted by the catalog trigger and must not be writable as an
-- arbitrary public RPC.
revoke all on function public.audit_asset_library_item_change()
from public, anon, authenticated;
