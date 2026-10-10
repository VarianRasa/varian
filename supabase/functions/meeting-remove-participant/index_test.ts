import {
  createMeetingRemoveParticipantHandler,
  type MeetingRemovalDependencies,
  type MeetingRemovalSession,
  type MeetingRemovalUser,
} from './index.ts';

const USER_ID = '11111111-1111-4111-8111-111111111111';
const TARGET_ID = '33333333-3333-4333-8333-333333333333';
const MEETING_ID = '22222222-2222-4222-8222-222222222222';
const ROOM = 'meeting-room-internal';

function fail(message: string): never {
  throw new Error(message);
}

function expect(value: unknown, message: string): asserts value {
  if (!value) fail(message);
}

async function payload(response: Response): Promise<Record<string, unknown>> {
  return await response.json() as Record<string, unknown>;
}

function errorCode(body: Record<string, unknown>): unknown {
  return (body.error as Record<string, unknown> | undefined)?.code;
}

function request(
  method = 'POST',
  body: unknown = { meetingId: MEETING_ID, identity: TARGET_ID },
  headers: Record<string, string> = { authorization: 'Bearer fixture.jwt' },
): Request {
  return new Request('https://functions.example/meeting-remove-participant', {
    method,
    headers: { 'content-type': 'application/json', ...headers },
    body: method === 'POST' ? JSON.stringify(body) : undefined,
  });
}

function fixture(overrides: Partial<MeetingRemovalDependencies> = {}) {
  const removed: string[] = [];
  const state: {
    deps: MeetingRemovalDependencies;
    removed: string[];
  } = {
    deps: {
      config: () => ({
        supabaseUrl: 'https://supabase.example',
        supabaseAnonKey: 'anon-fixture',
        livekitUrl: 'wss://video.example',
        livekitApiKey: 'key-fixture',
        livekitApiSecret: 'secret-fixture',
        allowedOrigins: ['https://allowed.example'],
      }),
      authenticate: async (): Promise<MeetingRemovalUser | null> => ({ id: USER_ID }),
      joinSession: async (): Promise<MeetingRemovalSession> => ({
        id: MEETING_ID,
        project_id: 'project-1',
        provider: 'livekit',
        provider_room_name: ROOM,
        status: 'active',
      }),
      projectRole: async () => 'owner',
      listParticipants: async () => [{ identity: TARGET_ID }],
      removeParticipant: async (_roomName, identity) => {
        removed.push(identity);
      },
      ...overrides,
    },
    removed,
  };
  return state;
}

Deno.test('rejects malformed bodies and non-v1-to-v5 UUIDs', async () => {
  for (const body of [
    null,
    [],
    {},
    { meetingId: MEETING_ID },
    { identity: TARGET_ID },
    { meetingId: 42, identity: TARGET_ID },
    { meetingId: 'not-uuid', identity: TARGET_ID },
    { meetingId: MEETING_ID, identity: '00000000-0000-0000-8000-000000000000' },
    { meetingId: MEETING_ID, identity: '00000000-0000-6000-8000-000000000000' },
    { meetingId: MEETING_ID, identity: TARGET_ID, extra: true },
  ]) {
    const response = await createMeetingRemoveParticipantHandler(fixture().deps)(request('POST', body));
    expect(response.status === 400, 'malformed body accepted');
    expect(errorCode(await payload(response)) === 'validation_error', 'validation code unstable');
  }
});

Deno.test('requires a strict bounded Bearer token', async () => {
  for (const authorization of [
    '',
    'Basic fixture',
    'Bearer',
    'bearer fixture.jwt',
    'Bearer  fixture.jwt',
    'Bearer fixture token',
    'Bearer fixture.jwt,',
    'Bearer ' + 'x'.repeat(4097),
  ]) {
    const headers: Record<string, string> = authorization ? { authorization } : {};
    const response = await createMeetingRemoveParticipantHandler(fixture().deps)(request('POST', undefined, headers));
    expect(response.status === 401, `invalid authorization accepted: ${JSON.stringify(authorization)}`);
    expect(errorCode(await payload(response)) === 'authorization_error', 'auth code unstable');
  }
});

Deno.test('requires exact configured Origin while allowing missing Origin for native clients', async () => {
  const denied = await createMeetingRemoveParticipantHandler(fixture().deps)(request('POST', undefined, {
    authorization: 'Bearer fixture.jwt',
    origin: 'https://evil.example',
  }));
  expect(denied.status === 403, 'disallowed origin accepted');
  expect(!denied.headers.has('access-control-allow-origin'), 'disallowed origin received CORS');

  const native = await createMeetingRemoveParticipantHandler(fixture().deps)(request());
  expect(native.status === 200, 'missing Origin rejected');
  const allowed = await createMeetingRemoveParticipantHandler(fixture().deps)(request('POST', undefined, {
    authorization: 'Bearer fixture.jwt',
    origin: 'https://allowed.example',
  }));
  expect(allowed.status === 200, 'allowed Origin rejected');
  expect(allowed.headers.get('access-control-allow-origin') === 'https://allowed.example', 'allowed Origin missing');
  expect(allowed.headers.get('access-control-allow-methods') === 'POST, OPTIONS', 'CORS methods mismatch');
  expect(allowed.headers.get('access-control-allow-headers') === 'authorization, apikey, content-type, x-client-info', 'CORS headers mismatch');
});

Deno.test('supports OPTIONS and rejects non-POST methods', async () => {
  const handler = createMeetingRemoveParticipantHandler(fixture().deps);
  const options = await handler(request('OPTIONS', undefined, { origin: 'https://allowed.example' }));
  expect(options.status === 204, 'OPTIONS failed');
  expect(options.headers.get('access-control-allow-methods') === 'POST, OPTIONS', 'OPTIONS methods mismatch');
  const get = await handler(request('GET'));
  expect(get.status === 405, 'GET accepted');
  expect(errorCode(await payload(get)) === 'validation_error', 'method error code unstable');
});

Deno.test('authenticates the caller, requires owner role, and rejects self-removal', async () => {
  let joinedUser = '';
  let roleProject = '';
  const owner = fixture({
    joinSession: async (_meetingId, userId) => {
      joinedUser = userId;
      return {
        id: MEETING_ID,
        project_id: 'project-1',
        provider: 'livekit',
        provider_room_name: ROOM,
        status: 'active',
      };
    },
    projectRole: async (projectId) => {
      roleProject = projectId;
      return 'owner';
    },
  });
  const response = await createMeetingRemoveParticipantHandler(owner.deps)(request());
  expect(response.status === 200, 'owner removal failed');
  expect(joinedUser === USER_ID, 'authenticated identity was not passed to session lookup');
  expect(roleProject === 'project-1', 'session project was not passed to role lookup');

  const nonOwner = await createMeetingRemoveParticipantHandler(fixture({ projectRole: async () => 'editor' }).deps)(request());
  expect(nonOwner.status === 403, 'non-owner removal accepted');
  expect(errorCode(await payload(nonOwner)) === 'authorization_error', 'non-owner code unstable');

  const self = await createMeetingRemoveParticipantHandler(fixture({ listParticipants: async () => [{ identity: USER_ID }] }).deps)(request('POST', {
    meetingId: MEETING_ID,
    identity: USER_ID,
  }));
  expect(self.status === 403, 'self-removal accepted');
  expect(errorCode(await payload(self)) === 'authorization_error', 'self-removal code unstable');
});

Deno.test('enforces an active, matching LiveKit session', async () => {
  const ended = await createMeetingRemoveParticipantHandler(fixture({
    joinSession: async () => ({ errorCode: 'P0003' }),
  }).deps)(request());
  expect(ended.status === 410, 'ended marker status mismatch');
  expect(errorCode(await payload(ended)) === 'ended', 'ended marker code mismatch');

  const endedRow = await createMeetingRemoveParticipantHandler(fixture({
    joinSession: async () => ({ id: MEETING_ID, project_id: 'project-1', provider: 'livekit', provider_room_name: ROOM, status: 'ended' }),
  }).deps)(request());
  expect(endedRow.status === 410, 'ended row status mismatch');
  expect(errorCode(await payload(endedRow)) === 'ended', 'ended row code mismatch');

  for (const session of [null, { id: '44444444-4444-4444-8444-444444444444', project_id: 'project-1', provider: 'livekit', provider_room_name: ROOM, status: 'active' }, { id: MEETING_ID, project_id: 'project-1', provider: 'other', provider_room_name: ROOM, status: 'active' }]) {
    const unavailable = await createMeetingRemoveParticipantHandler(fixture({ joinSession: async () => session }).deps)(request());
    expect(unavailable.status === 404, 'unavailable session accepted');
    expect(errorCode(await payload(unavailable)) === 'unavailable', 'unavailable code unstable');
  }
});

Deno.test('returns idempotent false without provider removal when target is absent', async () => {
  const state = fixture({ listParticipants: async () => [] });
  const response = await createMeetingRemoveParticipantHandler(state.deps)(request());
  expect(response.status === 200, 'absent target failed');
  expect(JSON.stringify(await payload(response)) === '{"removed":false}', 'absent success shape mismatch');
  expect(state.removed.length === 0, 'absent target was sent to provider');
});

Deno.test('removes a present target and returns the exact success shape', async () => {
  const state = fixture();
  const response = await createMeetingRemoveParticipantHandler(state.deps)(request());
  expect(response.status === 200, 'present target failed');
  expect(JSON.stringify(await payload(response)) === '{"removed":true}', 'success shape leaked details');
  expect(state.removed.length === 1 && state.removed[0] === TARGET_ID, 'wrong participant removal call');
});

Deno.test('redacts provider failures and never discloses secrets or identities', async () => {
  const state = fixture({
    removeParticipant: async () => {
      throw new Error(`provider failed ${TARGET_ID} secret-fixture https://video.example`);
    },
  });
  const response = await createMeetingRemoveParticipantHandler(state.deps)(request());
  expect(response.status === 503, 'provider failure status mismatch');
  const text = await response.text();
  expect(errorCode(JSON.parse(text) as Record<string, unknown>) === 'provider_unavailable', 'provider failure code unstable');
  for (const secret of ['secret-fixture', 'key-fixture', 'https://video.example', TARGET_ID, 'provider failed']) {
    expect(!text.includes(secret), `response disclosed ${secret}`);
  }
});

Deno.test('fails closed on missing configuration before authentication or provider calls', async () => {
  let authenticated = false;
  let listed = false;
  const state = fixture({
    config: () => null,
    authenticate: async () => {
      authenticated = true;
      return { id: USER_ID };
    },
    listParticipants: async () => {
      listed = true;
      return [];
    },
  });
  const response = await createMeetingRemoveParticipantHandler(state.deps)(request());
  expect(response.status === 500, 'configuration status mismatch');
  expect(errorCode(await payload(response)) === 'unavailable', 'configuration code unstable');
  expect(!authenticated && !listed, 'configuration reached an external dependency');
});
