import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';
import { AccessToken, RoomServiceClient } from 'npm:livekit-server-sdk@2.15.0';
import { TrackSource } from 'npm:@livekit/protocol@1.34.0';

const MAX_BODY_BYTES = 16 * 1024;
const TOKEN_TTL_SECONDS = 600;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ALLOWED_ROLES = new Set(['owner', 'editor', 'commenter', 'viewer']);

export interface MeetingConfig {
  supabaseUrl: string;
  supabaseAnonKey: string;
  livekitUrl: string;
  livekitApiKey: string;
  livekitApiSecret: string;
  allowedOrigins: string[];
}

export interface MeetingUser {
  id: string;
  userMetadata?: Record<string, unknown>;
}

export interface MeetingSessionRow {
  id: string;
  project_id: string;
  provider: string;
  provider_room_name: string;
  status: string;
  max_participants: number;
}

export interface MeetingTokenGrant {
  identity: string;
  name?: string;
  room: string;
  roomJoin: boolean;
  canSubscribe: boolean;
  canPublish: boolean;
  canPublishData: boolean;
  canPublishSources: TrackSource[];
  ttlSeconds: number;
}

export interface MeetingTokenDependencies {
  config: () => MeetingConfig | null;
  authenticate: (bearerToken: string) => Promise<MeetingUser | null>;
  joinSession: (meetingId: string, userId: string, bearerToken: string) => Promise<unknown>;
  projectRole: (projectId: string, userId: string, bearerToken: string) => Promise<unknown>;
  ensureRoom: (roomName: string, maxParticipants: number, config: MeetingConfig) => Promise<void>;
  listParticipants: (roomName: string, config: MeetingConfig) => Promise<unknown[]>;
  signToken: (grant: MeetingTokenGrant, config: MeetingConfig) => Promise<string>;
  now: () => Date;
}

class HttpError extends Error {
  constructor(readonly status: number, readonly code: string, readonly userMessage: string) {
    super(userMessage);
  }
}

class DependencyError extends Error {}

function jsonHeaders(origin?: string): Headers {
  const headers = new Headers({
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    vary: 'Origin',
  });
  if (origin !== undefined) {
    headers.set('access-control-allow-origin', origin);
    headers.set('access-control-allow-methods', 'POST, OPTIONS');
    headers.set('access-control-allow-headers', 'authorization, apikey, content-type, x-client-info');
  }
  return headers;
}

function response(body: Record<string, unknown>, status: number, origin?: string): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders(origin) });
}

function errorResponse(error: HttpError, origin?: string): Response {
  return response({ error: { code: error.code, message: error.userMessage } }, error.status, origin);
}
function isSafeSupabaseUrl(value: string): boolean {
  try {
    const parsed = new URL(value);
    return parsed.protocol === 'https:' && parsed.hostname.length > 0 && !parsed.username && !parsed.password && !parsed.search && !parsed.hash;
  } catch (_) {
    return false;
  }
}
function isSafeOrigin(value: unknown): value is string {
  if (typeof value !== 'string' || value.length === 0 || value !== value.trim() || value === '*') return false;
  try {
    const parsed = new URL(value);
    return (parsed.protocol === 'https:' || parsed.protocol === 'http:') &&
      parsed.hostname.length > 0 &&
      parsed.username.length === 0 &&
      parsed.password.length === 0 &&
      parsed.pathname === '/' &&
      parsed.search.length === 0 &&
      parsed.hash.length === 0 &&
      parsed.origin === value;
  } catch (_) {
    return false;
  }
}

function readConfigFromEnvironment(): MeetingConfig | null {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')?.trim();
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')?.trim();
  const livekitUrl = Deno.env.get('LIVEKIT_URL')?.trim();
  const livekitApiKey = Deno.env.get('LIVEKIT_API_KEY')?.trim();
  const livekitApiSecret = Deno.env.get('LIVEKIT_API_SECRET')?.trim();
  if (
    !supabaseUrl ||
    !supabaseAnonKey ||
    !livekitUrl ||
    !livekitApiKey ||
    !livekitApiSecret ||
    !isSafeSupabaseUrl(supabaseUrl)
  ) return null;
  let parsed: URL;
  try {
    parsed = new URL(livekitUrl);
  } catch (_) {
    return null;
  }
  if (
    (parsed.protocol !== 'wss:' && parsed.protocol !== 'https:') ||
    !parsed.hostname ||
    parsed.username ||
    parsed.password ||
    parsed.search ||
    parsed.hash
  ) return null;
  const allowedOrigins = (Deno.env.get('ALLOWED_ORIGINS') ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
  if (!allowedOrigins.every(isSafeOrigin)) return null;
  return {
    supabaseUrl,
    supabaseAnonKey,
    livekitUrl,
    livekitApiKey,
    livekitApiSecret,
    allowedOrigins,
  };
}

function isUsableConfig(config: unknown): config is MeetingConfig {
  if (config === null || typeof config !== 'object') return false;
  const candidate = config as Record<string, unknown>;
  if (
    typeof candidate.supabaseUrl !== 'string' ||
    typeof candidate.supabaseAnonKey !== 'string' ||
    typeof candidate.livekitUrl !== 'string' ||
    typeof candidate.livekitApiKey !== 'string' ||
    typeof candidate.livekitApiSecret !== 'string' ||
    !Array.isArray(candidate.allowedOrigins) ||
    !candidate.supabaseUrl ||
    !candidate.supabaseAnonKey ||
    !candidate.livekitUrl ||
    !candidate.livekitApiKey ||
    !candidate.livekitApiSecret ||
    !isSafeSupabaseUrl(candidate.supabaseUrl)
  ) return false;
  try {
    const provider = new URL(candidate.livekitUrl);
    return (
      (provider.protocol === 'wss:' || provider.protocol === 'https:') &&
      provider.hostname.length > 0 &&
      provider.username.length === 0 &&
      provider.password.length === 0 &&
      provider.search.length === 0 &&
      provider.hash.length === 0 &&
      candidate.allowedOrigins.every(isSafeOrigin)
    );
  } catch (_) {
    return false;
  }
}

function hasParticipantIdentity(participants: unknown[], identity: string): boolean {
  return participants.some(
    (participant) =>
      participant !== null &&
      typeof participant === 'object' &&
      (participant as Record<string, unknown>).identity === identity,
  );
}


function parseBearer(request: Request): string {
  const value = request.headers.get('authorization');
  if (value === null || value.length > 4096 || !/^Bearer [A-Za-z0-9._~+/=-]{1,4096}$/.test(value)) {
    throw new HttpError(401, 'authorization_error', 'Authentication is required.');
  }
  return value.slice(7);
}

function checkOrigin(request: Request, config: MeetingConfig): string | undefined {
  const origin = request.headers.get('origin');
  if (origin === null) return undefined;
  if (!config.allowedOrigins.includes(origin)) {
    throw new HttpError(403, 'authorization_error', 'This origin is not allowed.');
  }
  return origin;
}

async function readBody(request: Request): Promise<Record<string, unknown>> {
  const length = request.headers.get('content-length');
  if (length !== null && Number.isFinite(Number(length)) && Number(length) > MAX_BODY_BYTES) {
    throw new HttpError(400, 'validation_error', 'Request body is invalid.');
  }
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength > MAX_BODY_BYTES) throw new HttpError(400, 'validation_error', 'Request body is invalid.');
  let parsed: unknown;
  try { parsed = JSON.parse(new TextDecoder().decode(bytes)); } catch (_) {
    throw new HttpError(400, 'validation_error', 'Request body is invalid.');
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new HttpError(400, 'validation_error', 'Request body is invalid.');
  }
  return parsed as Record<string, unknown>;
}

function meetingIdFromBody(body: Record<string, unknown>): string {
  if (
    Object.keys(body).length !== 1 ||
    typeof body.meetingId !== 'string' ||
    !UUID_PATTERN.test(body.meetingId)
  ) {
    throw new HttpError(400, 'validation_error', 'Request body is invalid.');
  }
  return body.meetingId;
}

function unwrapSession(value: unknown): unknown {
  if (Array.isArray(value)) return value[0] ?? null;
  if (value !== null && typeof value === 'object' && 'data' in value) return unwrapSession((value as { data?: unknown }).data);
  return value;
}

function validateSession(value: unknown, requestedMeetingId: string): MeetingSessionRow {
  const row = unwrapSession(value);
  if (row === null || typeof row !== 'object') throw new HttpError(404, 'unavailable', 'Meeting is unavailable.');
  const candidate = row as Record<string, unknown>;
  if (typeof candidate.id !== 'string' || !UUID_PATTERN.test(candidate.id) || candidate.id.toLowerCase() !== requestedMeetingId.toLowerCase() || typeof candidate.project_id !== 'string' || candidate.project_id.length === 0 || candidate.provider !== 'livekit' || typeof candidate.provider_room_name !== 'string' || candidate.provider_room_name.length === 0 || candidate.provider_room_name.length > 256 || candidate.status !== 'active' || typeof candidate.max_participants !== 'number' || !Number.isInteger(candidate.max_participants) || candidate.max_participants < 2 || candidate.max_participants > 8) {
    throw new HttpError(404, 'unavailable', 'Meeting is unavailable.');
  }
  return candidate as unknown as MeetingSessionRow;
}

function displayName(user: MeetingUser): string | undefined {
  const metadata = user.userMetadata;
  const raw = metadata?.full_name ?? metadata?.name;
  if (typeof raw !== 'string') return undefined;
  const safe = raw.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, 80);
  return safe || undefined;
}

function sourcesForRole(role: string): TrackSource[] {
  return role === 'viewer' ? [] : [TrackSource.MICROPHONE, TrackSource.CAMERA, TrackSource.SCREEN_SHARE];
}

function productionClient(config: MeetingConfig, bearerToken: string): SupabaseClient {
  return createClient(config.supabaseUrl, config.supabaseAnonKey, {
    global: { headers: { Authorization: 'Bearer ' + bearerToken } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export function roomCapacityMatches(room: unknown, expected: number): boolean {
  if (room === null || typeof room !== 'object') return false;
  const value = (room as Record<string, unknown>).maxParticipants;
  return typeof value === 'number' && Number.isFinite(value) && value === expected;
}

export function roomMatchesNameAndCapacity(room: unknown, expectedName: string, expectedCapacity: number): boolean {
  if (room === null || typeof room !== 'object') return false;
  return (room as Record<string, unknown>).name === expectedName && roomCapacityMatches(room, expectedCapacity);
}

function createProductionDependencies(): MeetingTokenDependencies {
  return {
    config: readConfigFromEnvironment,
    authenticate: async (bearerToken) => {
      const config = readConfigFromEnvironment();
      if (config === null) throw new DependencyError('configuration');
      const client = productionClient(config, bearerToken);
      const { data, error } = await client.auth.getUser(bearerToken);
      if (error || data.user === null) return null;
      return { id: data.user.id, userMetadata: data.user.user_metadata as Record<string, unknown> | undefined };
    },
    joinSession: async (meetingId, _userId, bearerToken) => {
      const config = readConfigFromEnvironment();
      if (config === null) throw new DependencyError('configuration');
      const client = productionClient(config, bearerToken);
      const { data, error } = await client.rpc('join_meeting_session', { p_meeting_id: meetingId });
      if (error) return { errorCode: error.code === 'P0003' ? 'P0003' : 'control-plane' };
      return unwrapSession(data);
    },
    projectRole: async (projectId, _userId, bearerToken) => {
      const config = readConfigFromEnvironment();
      if (config === null) throw new DependencyError('configuration');
      const client = productionClient(config, bearerToken);
      const { data, error } = await client.rpc('project_role', { p_project_id: projectId });
      if (error) throw new DependencyError('control-plane');
      return data;
    },
    ensureRoom: async (roomName, maxParticipants, config) => {
      const host = config.livekitUrl.replace(/^wss:/, 'https:');
      const api = new RoomServiceClient(host, config.livekitApiKey, config.livekitApiSecret);
      try {
        const created = await api.createRoom({ name: roomName, maxParticipants });
        if (!roomMatchesNameAndCapacity(created, roomName, maxParticipants)) throw new DependencyError('provider');
      } catch (error) {
        if (error instanceof DependencyError) throw error;
        try {
          const rooms = await api.listRooms([roomName]);
          const existing = rooms.find((room) => room.name === roomName);
          if (!roomMatchesNameAndCapacity(existing, roomName, maxParticipants)) throw new DependencyError('provider');
        } catch (_) {
          throw new DependencyError('provider');
        }
      }
    },
    listParticipants: async (roomName, config) => {
      const host = config.livekitUrl.replace(/^wss:/, 'https:');
      const api = new RoomServiceClient(host, config.livekitApiKey, config.livekitApiSecret);
      return await api.listParticipants(roomName) as unknown[];
    },
    signToken: async (grant, config) => {
      const token = new AccessToken(config.livekitApiKey, config.livekitApiSecret, {
        identity: grant.identity,
        name: grant.name,
        ttl: TOKEN_TTL_SECONDS,
      });
      token.addGrant({
        roomJoin: grant.roomJoin,
        room: grant.room,
        canSubscribe: grant.canSubscribe,
        canPublish: grant.canPublish,
        canPublishData: grant.canPublishData,
        canPublishSources: grant.canPublishSources,
      });
      return await token.toJwt();
    },
    now: () => new Date(),
  };
}

export function createMeetingTokenHandler(overrides: Partial<MeetingTokenDependencies> = {}): (request: Request) => Promise<Response> {
  const dependencies = { ...createProductionDependencies(), ...overrides };
  return async (request) => {
    let origin: string | undefined;
    try {
      const config = dependencies.config();
      if (config === null || !isUsableConfig(config)) throw new HttpError(500, 'unavailable', 'Video meeting is not configured.');
      origin = checkOrigin(request, config);
      if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: jsonHeaders(origin) });
      if (request.method !== 'POST') throw new HttpError(405, 'unavailable', 'Method not allowed.');
      const bearerToken = parseBearer(request);
      const body = await readBody(request);
      const meetingId = meetingIdFromBody(body);
      const user = await dependencies.authenticate(bearerToken);
      if (user === null || !UUID_PATTERN.test(user.id)) throw new HttpError(401, 'authorization_error', 'Authentication is required.');
      let joined: unknown;
      try { joined = await dependencies.joinSession(meetingId, user.id, bearerToken); } catch (_) {
        throw new HttpError(404, 'unavailable', 'Meeting is unavailable.');
      }
      if (joined !== null && typeof joined === 'object' && ['ended', 'P0003'].includes((joined as Record<string, unknown>).errorCode as string)) {
        throw new HttpError(410, 'ended', 'Meeting has ended.');
      }
      const session = validateSession(joined, meetingId);
      let roleValue: unknown;
      try { roleValue = await dependencies.projectRole(session.project_id, user.id, bearerToken); } catch (_) {
        throw new HttpError(403, 'authorization_error', 'Meeting access denied.');
      }
      const role = typeof roleValue === 'string' ? roleValue : '';
      if (!ALLOWED_ROLES.has(role)) throw new HttpError(403, 'authorization_error', 'Meeting access denied.');
      let participants: unknown[];
      try {
        await dependencies.ensureRoom(
          session.provider_room_name,
          session.max_participants,
          config,
        );
        participants = await dependencies.listParticipants(
          session.provider_room_name,
          config,
        );
        if (!Array.isArray(participants)) throw new DependencyError('provider');
      } catch (_) {
        throw new HttpError(503, 'provider_unavailable', 'Video service is unavailable.');
      }
      if (participants.length >= session.max_participants && !hasParticipantIdentity(participants, user.id)) throw new HttpError(409, 'capacity_full', 'Meeting is full.');
      const grant: MeetingTokenGrant = {
        identity: user.id,
        name: displayName(user),
        room: session.provider_room_name,
        roomJoin: true,
        canSubscribe: true,
        canPublish: role !== 'viewer',
        canPublishData: false,
        canPublishSources: sourcesForRole(role),
        ttlSeconds: TOKEN_TTL_SECONDS,
      };
      let signedToken: string;
      try { signedToken = await dependencies.signToken(grant, config); } catch (_) {
        throw new HttpError(503, 'provider_unavailable', 'Video service is unavailable.');
      }
      const expiresAt = new Date(dependencies.now().getTime() + TOKEN_TTL_SECONDS * 1000).toISOString();
      return response({ token: signedToken, serverUrl: config.livekitUrl, expiresAt, identity: user.id }, 200, origin);
    } catch (error) {
      if (error instanceof HttpError) return errorResponse(error, origin);
      if (error instanceof DependencyError && error.message === 'configuration') return errorResponse(new HttpError(500, 'unavailable', 'Video meeting is not configured.'), origin);
      return errorResponse(new HttpError(500, 'unavailable', 'Video meeting is unavailable.'), origin);
    }
  };
}

if (import.meta.main) Deno.serve(createMeetingTokenHandler());
