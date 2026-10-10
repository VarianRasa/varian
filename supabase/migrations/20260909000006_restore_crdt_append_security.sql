-- Keep CRDT authorization in the RPC while avoiding table-level RLS failures
-- during an authenticated operation append.

alter function public.append_canvas_crdt_operation(text, jsonb)
  security definer;

revoke execute on function public.append_canvas_crdt_operation(text, jsonb)
from public, anon;

grant execute on function public.append_canvas_crdt_operation(text, jsonb)
to authenticated;
