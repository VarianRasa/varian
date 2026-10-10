import { createMeetingTokenHandler, roomCapacityMatches, roomMatchesNameAndCapacity, type MeetingTokenDependencies, type MeetingTokenGrant } from './index.ts';

const USER_ID = '11111111-1111-4111-8111-111111111111';
const MEETING_ID = '22222222-2222-4222-8222-222222222222';
const ROOM = 'meeting-room-internal';
function fail(message: string): never { throw new Error(message); }
function expect(value: unknown, message: string): asserts value { if (!value) fail(message); }
async function payload(response: Response): Promise<Record<string, unknown>> { return await response.json() as Record<string, unknown>; }
function code(body: Record<string, unknown>): unknown { return (body.error as Record<string, unknown>)?.code; }
function fixture(overrides: Partial<MeetingTokenDependencies> = {}) {
  const grants: MeetingTokenGrant[] = []; let calls = 0;
  const deps: MeetingTokenDependencies = {
    config: () => ({ supabaseUrl: 'https://supabase.example', supabaseAnonKey: 'anon-fixture', livekitUrl: 'wss://video.example', livekitApiKey: 'key-fixture', livekitApiSecret: 'secret-fixture', allowedOrigins: ['https://allowed.example'] }),
    authenticate: async () => ({ id: USER_ID, userMetadata: { full_name: 'Verified User' } }),
    joinSession: async () => ({ id: MEETING_ID, project_id: 'project-1', provider: 'livekit', provider_room_name: ROOM, status: 'active', max_participants: 8 }),
    projectRole: async () => 'owner',
    ensureRoom: async () => {},
    listParticipants: async () => [],
    signToken: async (grant: MeetingTokenGrant) => { calls++; grants.push(grant); return 'signed-fixture-token'; },
    now: () => new Date('2026-09-16T00:00:00.000Z'), ...overrides,
  }; return { deps, grants, calls: () => calls };
}
function request(method = 'POST', body: unknown = { meetingId: MEETING_ID }, headers: Record<string, string> = { authorization: 'Bearer fixture.jwt' }): Request {
  return new Request('https://functions.example/meeting-token', { method, headers: { 'content-type': 'application/json', ...headers }, body: method === 'POST' ? JSON.stringify(body) : undefined });
}

Deno.test('accepts only an exact numeric room capacity', () => {
  expect(roomCapacityMatches({ maxParticipants: 8 }, 8), 'matching room capacity rejected');
  expect(roomMatchesNameAndCapacity({ name: ROOM, maxParticipants: 8 }, ROOM, 8), 'matching room name and capacity rejected');
  expect(!roomMatchesNameAndCapacity({ name: 'other-room', maxParticipants: 8 }, ROOM, 8), 'wrong room name accepted');
  for (const room of [null, undefined, {}, { maxParticipants: 7 }, { maxParticipants: '8' }, { maxParticipants: true }]) {
    expect(!roomCapacityMatches(room, 8), 'non-exact room capacity accepted');
  }
});
Deno.test('rejects malformed bodies and UUIDs', async () => {
  for (const body of [null, [], {}, { meetingId: 42 }, { meetingId: 'not-uuid' }]) {
    const response = await createMeetingTokenHandler(fixture().deps)(request('POST', body));
    expect(response.status === 400, 'malformed body accepted'); expect(code(await payload(response)) === 'validation_error', 'validation code unstable');
  }
});
Deno.test('requires a bounded Bearer token', async () => {
  for (const authorization of ['', 'Basic fixture', 'Bearer', 'Bearer fixture token', 'Bearer ' + 'x'.repeat(5000)]) {
    const headers: Record<string, string> = authorization ? { authorization } : {};
    const response = await createMeetingTokenHandler(fixture().deps)(request('POST', undefined, headers));
    expect(response.status === 401, 'invalid authorization accepted: ' + authorization.slice(0, 20)); expect(code(await payload(response)) === 'authorization_error', 'auth details leaked');
  }
});
Deno.test('validates exact Origin and permits missing Origin for native clients', async () => {
  const denied = await createMeetingTokenHandler(fixture().deps)(request('POST', undefined, { authorization: 'Bearer fixture.jwt', origin: 'https://evil.example' }));
  expect(denied.status === 403, 'disallowed origin accepted'); expect(!denied.headers.has('access-control-allow-origin'), 'rejected origin received CORS');
  const native = await createMeetingTokenHandler(fixture().deps)(request()); expect(native.status === 200, 'missing origin rejected');
  const allowed = await createMeetingTokenHandler(fixture().deps)(request('POST', undefined, { authorization: 'Bearer fixture.jwt', origin: 'https://allowed.example' }));
  expect(allowed.headers.get('access-control-allow-origin') === 'https://allowed.example', 'allowed origin missing');
  expect(allowed.headers.get('access-control-allow-headers') === 'authorization, apikey, content-type, x-client-info', 'preflight headers incomplete');
});
Deno.test('supports OPTIONS and rejects other methods', async () => {
  const handler = createMeetingTokenHandler(fixture().deps);
  const options = await handler(request('OPTIONS', undefined, { origin: 'https://allowed.example' }));
  expect(options.status === 204, 'OPTIONS failed'); expect(options.headers.get('access-control-allow-methods') === 'POST, OPTIONS', 'OPTIONS methods mismatch');
  expect((await handler(request('GET'))).status === 405, 'GET accepted');
});
Deno.test('rejects a session row that does not match the requested meeting', async () => {
  const state = fixture({ joinSession: async () => ({ id: '33333333-3333-4333-8333-333333333333', project_id: 'project-1', provider: 'livekit', provider_room_name: ROOM, status: 'active', max_participants: 8 }) });
  const response = await createMeetingTokenHandler(state.deps)(request());
  expect(response.status === 404, 'mismatched session accepted');
  expect(code(await payload(response)) === 'unavailable', 'mismatch details leaked');
});

Deno.test('maps ended, unavailable, and unauthorized roles safely', async () => {
  const ended = await createMeetingTokenHandler(fixture({ joinSession: async () => ({ errorCode: 'P0003' }) }).deps)(request());
  expect(ended.status === 410, 'ended status mismatch'); expect(code(await payload(ended)) === 'ended', 'ended code mismatch');
  const unavailable = await createMeetingTokenHandler(fixture({ joinSession: async () => null }).deps)(request());
  expect(unavailable.status === 404, 'unavailable status mismatch'); expect(code(await payload(unavailable)) === 'unavailable', 'unavailable code mismatch');
  for (const role of [null, 'admin']) { const response = await createMeetingTokenHandler(fixture({ projectRole: async () => role }).deps)(request()); expect(response.status === 403, 'unknown role accepted'); expect(code(await payload(response)) === 'authorization_error', 'role code mismatch'); }
});
Deno.test('maps provider failure and capacity without minting', async () => {
  const provider = fixture({ listParticipants: async () => { throw new Error('internal provider detail'); } });
  const failure = await createMeetingTokenHandler(provider.deps)(request()); expect(failure.status === 503, 'provider status mismatch'); expect(code(await payload(failure)) === 'provider_unavailable', 'provider code mismatch');
  let roomCapacity: number | undefined;
  const full = fixture({ ensureRoom: async (_room, max) => { roomCapacity = max; }, listParticipants: async () => Array.from({ length: 8 }, () => ({})) });
  const response = await createMeetingTokenHandler(full.deps)(request()); expect(response.status === 409, 'capacity status mismatch'); expect(code(await payload(response)) === 'capacity_full', 'capacity code mismatch'); expect(full.calls() === 0, 'capacity minted token'); expect(roomCapacity === 8, 'room capacity was not configured');
  const existing = fixture({ listParticipants: async () => Array.from({ length: 8 }, (_, index) => ({ identity: index === 0 ? USER_ID : 'other-' + index })) });
  const existingResponse = await createMeetingTokenHandler(existing.deps)(request());
  expect(existingResponse.status === 200, 'existing participant could not refresh at capacity'); expect(existing.calls() === 1, 'existing participant was not signed');
});
Deno.test('returns exact success shape and owner publishing grant', async () => {
  const state = fixture(); const response = await createMeetingTokenHandler(state.deps)(request()); expect(response.status === 200, 'success failed');
  expect(response.headers.get('cache-control') === 'no-store', 'missing no-store'); expect(response.headers.get('vary') === 'Origin', 'missing Vary');
  const body = await payload(response); expect(JSON.stringify(Object.keys(body).sort()) === JSON.stringify(['expiresAt', 'identity', 'serverUrl', 'token']), 'response shape leaked');
  expect(body.token === 'signed-fixture-token', 'token mismatch'); expect(body.serverUrl === 'wss://video.example', 'URL mismatch'); expect(body.identity === USER_ID, 'identity mismatch'); expect(!JSON.stringify(body).includes(ROOM), 'room leaked');
  const grant = state.grants[0]; expect(grant.canPublish === true, 'owner cannot publish'); expect(grant.canSubscribe === true, 'owner cannot subscribe'); expect(grant.canPublishData === false, 'data publishing enabled'); expect(grant.room === ROOM, 'room signer mismatch'); expect(grant.identity === USER_ID, 'identity not verified'); expect(grant.ttlSeconds === 600, 'TTL not bounded');
});
Deno.test('viewer receives subscribe-only grant', async () => {
  const state = fixture({ projectRole: async () => 'viewer' }); expect((await createMeetingTokenHandler(state.deps)(request())).status === 200, 'viewer failed');
  expect(state.grants[0].canPublish === false, 'viewer can publish'); expect(state.grants[0].canSubscribe === true, 'viewer cannot subscribe'); expect(state.grants[0].canPublishSources.length === 0, 'viewer has publish sources');
});
Deno.test('rejects provider URLs that could carry credentials or hidden destinations', async () => {
  for (const livekitUrl of ['wss://user:password@video.example', 'wss://video.example?credential=fixture', 'wss://video.example/#fragment']) {
    const state = fixture({ config: () => ({ ...fixture().deps.config()!, livekitUrl }) });
    const response = await createMeetingTokenHandler(state.deps)(request());
    expect(response.status === 500, 'unsafe provider URL accepted');
    expect(code(await payload(response)) === 'unavailable', 'unsafe URL details leaked');
  }
});

Deno.test('rejects unsafe Supabase URLs before authentication or signing', async () => {
  for (const supabaseUrl of ['', 'http://supabase.example', 'https://', 'https://user:password@supabase.example', 'https://supabase.example?credential=fixture', 'https://supabase.example/#fragment']) {
    let authenticated = false;
    let signed = false;
    const state = fixture({
      config: () => ({ ...fixture().deps.config()!, supabaseUrl }),
      authenticate: async () => { authenticated = true; return { id: USER_ID }; },
      signToken: async () => { signed = true; return 'unexpected-token'; },
    });
    const response = await createMeetingTokenHandler(state.deps)(request());
    expect(response.status === 500, 'unsafe Supabase URL accepted: ' + supabaseUrl);
    expect(code(await payload(response)) === 'unavailable', 'unsafe Supabase URL details leaked');
    expect(!authenticated && !signed, 'unsafe Supabase URL reached auth or signing');
  }
});
Deno.test('fails configuration before auth or provider calls', async () => {
  let authenticated = false; const state = fixture({ config: () => null, authenticate: async () => { authenticated = true; return { id: USER_ID }; } });
  const response = await createMeetingTokenHandler(state.deps)(request()); expect(response.status === 500, 'configuration status mismatch'); expect(code(await payload(response)) === 'unavailable', 'configuration code mismatch'); expect(!authenticated, 'configuration authenticated');
});
Deno.test('does not disclose credentials, room names, or internal errors', async () => {
  const state = fixture({ joinSession: async () => { throw new Error('supabase fixture detail'); } }); const text = await (await createMeetingTokenHandler(state.deps)(request())).text();
  for (const secret of ['secret-fixture', 'key-fixture', ROOM, 'supabase fixture detail']) expect(!text.includes(secret), 'response disclosed ' + secret);
});
