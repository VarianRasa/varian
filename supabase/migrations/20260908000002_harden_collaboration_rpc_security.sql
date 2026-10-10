alter function public.append_canvas_crdt_operation(text, jsonb)
  security definer;

alter function public.save_canvas_crdt_snapshot(text, jsonb, jsonb)
  security definer;

revoke execute on function public.append_canvas_crdt_operation(text, jsonb)
from public, anon;

revoke execute on function public.save_canvas_crdt_snapshot(text, jsonb, jsonb)
from public, anon;

grant execute on function public.append_canvas_crdt_operation(text, jsonb)
to authenticated;

grant execute on function public.save_canvas_crdt_snapshot(text, jsonb, jsonb)
to authenticated;
