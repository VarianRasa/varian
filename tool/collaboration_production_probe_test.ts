import {
  buildProbeOperation,
  readProbeConfig,
  requiredEnv,
} from './collaboration_production_probe.ts';

Deno.test('production collaboration probe rejects missing credentials', () => {
  try {
    requiredEnv({}, 'SUPABASE_URL');
    throw new Error('missing credential was accepted');
  } catch (error) {
    if (!String(error).includes('SUPABASE_URL is required')) throw error;
  }
});

Deno.test('production collaboration probe validates two-session config', () => {
  const config = readProbeConfig({
    SUPABASE_URL: 'https://example.supabase.co/',
    SUPABASE_ANON_KEY: 'anon',
    COLLAB_HOST_ACCESS_TOKEN: 'host',
    COLLAB_GUEST_ACCESS_TOKEN: 'guest',
    COLLAB_PROJECT_ID: 'project',
    COLLAB_ROOM_CODE: '123456',
    COLLAB_PROBE_TIMEOUT_MS: '5000',
  });
  if (config.supabaseUrl !== 'https://example.supabase.co') throw new Error('URL was not normalized');
  if (config.writeOperation || config.revokeGuest) throw new Error('unsafe probe options defaulted on');
});

Deno.test('production probe operation is deterministic and scoped', () => {
  const operation = buildProbeOperation('project', 'user', 'nonce');
  if (operation.projectId !== 'project' || operation.opId !== 'production-probe-nonce') throw new Error('operation scope is invalid');
  if ((operation.dot as Record<string, unknown>).actorId !== 'user') throw new Error('operation actor is invalid');
});
