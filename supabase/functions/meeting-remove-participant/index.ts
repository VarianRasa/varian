import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';
import { RoomServiceClient } from 'npm:livekit-server-sdk@2.15.0';

const MAX_BODY_BYTES = 16 * 1024;
const MAX_BEARER_BYTES = 4096;
const MAX_ROOM_NAME_LENGTH = 256;
const MAX_PROJECT_ID_LENGTH = 256;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export interface MeetingRemovalConfig {
  supabaseUrl: string;
  supabaseAnonKey: string;
  livekitUrl: string;
  livekitApiKey: string;
  livekitApiSecret: string;
  allowedOrigins: string[];
}

export interface MeetingRemovalUser {
  id: string;
}

export interface MeetingRemovalSession {
  id: string;
  project_id: string;
  provider: string;
  provider_room_name: string;
  status: 'active' | 'ended';
}


export interface MeetingRemovalDependencies {
  config: () => MeetingRemovalConfig | null;
  authenticate: (bearerToken: string) => Promise<MeetingRemovalUser | null>;
  joinSession: (meetingId: string, userId: string, bearerToken: string) => Promise<unknown>;
  projectRole: (projectId: string, userId: string, bearerToken: string) => Promise<unknown>;
  listParticipants: (roomName: string, config: MeetingRemovalConfig) => Promise<readonly unknown[]>;
  removeParticipant: (
    roomName: string,
    identity: string,
    config: MeetingRemovalConfig,
  ) => Promise<boolean | void>;
}

type RemovalRequest = {
  meetingId: string;
  identity: string;
};

type PublicErrorCode =
  | 'validation_error'
  | 'authorization_error'
  | 'unavailable'
  | 'ended'
  | 'provider_unavailable';

const ALLOWED_ERROR_CODES: Record<PublicErrorCode, true> = {
  validation_error: true,
  authorization_error: true,
  unavailable: true,
  ended: true,
  provider_unavailable: true,
};

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: PublicErrorCode,
    readonly userMessage: string,
  ) {
    super(userMessage);
  }
}

class DependencyError extends Error {
  constructor(readonly kind: 'configuration' | 'provider') {
    super(kind);
  }
}

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

function jsonResponse(body: Record<string, unknown>, status: number, origin?: string): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders(origin),
  });
}

function errorResponse(error: HttpError, origin?: string): Response {
  return jsonResponse({ error: { code: error.code, message: error.userMessage } }, error.status, origin);
}

function isSafeUrl(value: unknown, protocols: readonly string[]): value is string {
  if (typeof value !== 'string' || value.trim().length === 0) return false;
  try {
    const parsed = new URL(value);
    return protocols.includes(parsed.protocol) &&
      parsed.hostname.length > 0 &&
      parsed.username.length === 0 &&
      parsed.password.length === 0 &&
      parsed.search.length === 0 &&
      parsed.hash.length === 0;
  } catch {
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
  } catch {
    return false;
  }
}

function readConfigFromEnvironment(): MeetingRemovalConfig | null {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')?.trim();
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')?.trim();
  const livekitUrl = Deno.env.get('LIVEKIT_URL')?.trim();
  const livekitApiKey = Deno.env.get('LIVEKIT_API_KEY')?.trim();
  const livekitApiSecret = Deno.env.get('LIVEKIT_API_SECRET')?.trim();
  if (!supabaseUrl || !supabaseAnonKey || !livekitUrl || !livekitApiKey || !livekitApiSecret) return null;
  if (!isSafeUrl(supabaseUrl, ['https:']) || !isSafeUrl(livekitUrl, ['wss:', 'https:'])) return null;
  const allowedOrigins = (Deno.env.get('ALLOWED_ORIGINS') ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);
  if (!allowedOrigins.every((origin) => isSafeOrigin(origin))) return null;
  return { supabaseUrl, supabaseAnonKey, livekitUrl, livekitApiKey, livekitApiSecret, allowedOrigins };
}

export function isUsableMeetingRemovalConfig(config: unknown): config is MeetingRemovalConfig {
  if (config === null || typeof config !== 'object') return false;
  const candidate = config as Record<string, unknown>;
  if (!isSafeUrl(candidate.supabaseUrl, ['https:']) ||
    typeof candidate.supabaseAnonKey !== 'string' || candidate.supabaseAnonKey.trim().length === 0 ||
    !isSafeUrl(candidate.livekitUrl, ['wss:', 'https:']) ||
    typeof candidate.livekitApiKey !== 'string' || candidate.livekitApiKey.trim().length === 0 ||
    typeof candidate.livekitApiSecret !== 'string' || candidate.livekitApiSecret.trim().length === 0 ||
    !Array.isArray(candidate.allowedOrigins)) {
    return false;
  }
  return candidate.allowedOrigins.every((origin) => isSafeOrigin(origin));
}

function parseBearer(request: Request): string {
  const value = request.headers.get('authorization');
  if (value === null || value.length > MAX_BEARER_BYTES || !/^Bearer [A-Za-z0-9._~+/=-]{1,4096}$/.test(value)) {
    throw new HttpError(401, 'authorization_error', 'Authentication is required.');
  }
  return value.slice('Bearer '.length);
}

function checkOrigin(request: Request, config: MeetingRemovalConfig): string | undefined {
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
  if (bytes.byteLength > MAX_BODY_BYTES) {
    throw new HttpError(400, 'validation_error', 'Request body is invalid.');
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new HttpError(400, 'validation_error', 'Request body is invalid.');
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new HttpError(400, 'validation_error', 'Request body is invalid.');
  }
  return parsed as Record<string, unknown>;
}

function parseRemovalRequest(body: Record<string, unknown>): RemovalRequest {
  const keys = Object.keys(body);
  if (keys.length !== 2 || !keys.includes('meetingId') || !keys.includes('identity')) {
    throw new HttpError(400, 'validation_error', 'Request body is invalid.');
  }
  const meetingId = body.meetingId;
  const identity = body.identity;
  if (typeof meetingId !== 'string' || !UUID_PATTERN.test(meetingId) ||
    typeof identity !== 'string' || !UUID_PATTERN.test(identity)) {
    throw new HttpError(400, 'validation_error', 'Request body is invalid.');
  }
  return { meetingId, identity };
}

function unwrapSession(value: unknown): unknown {
  if (Array.isArray(value)) return value[0] ?? null;
  if (value !== null && typeof value === 'object' && 'data' in value) {
    return unwrapSession((value as { data?: unknown }).data);
  }
  return value;
}

function sessionErrorCode(value: unknown): string | null {
  const unwrapped = unwrapSession(value);
  if (unwrapped === null || typeof unwrapped !== 'object') return null;
  const candidate = unwrapped as Record<string, unknown>;
  const code = candidate.errorCode ?? candidate.code;
  if (typeof code === 'string') return code;
  const nested = candidate.error;
  if (nested !== null && typeof nested === 'object') {
    const nestedCode = (nested as Record<string, unknown>).code;
    if (typeof nestedCode === 'string') return nestedCode;
  }
  return null;
}


function validBoundedString(value: unknown, maxLength: number): value is string {
  return typeof value === 'string' && value.length > 0 && value.length <= maxLength && !/[\u0000-\u001f\u007f]/.test(value);
}

function validateSession(value: unknown, requestedMeetingId: string): MeetingRemovalSession {
  const row = unwrapSession(value);
  if (row === null || typeof row !== 'object' || Array.isArray(row)) {
    throw new HttpError(404, 'unavailable', 'Meeting is unavailable.');
  }
  const candidate = row as Record<string, unknown>;
  const id = candidate.id;
  if (typeof id === 'string' && UUID_PATTERN.test(id) && id.toLowerCase() === requestedMeetingId.toLowerCase() && candidate.status === 'ended') {
    throw new HttpError(410, 'ended', 'Meeting has ended.');
  }
  if (typeof id !== 'string' || !UUID_PATTERN.test(id) || id.toLowerCase() !== requestedMeetingId.toLowerCase() ||
    !validBoundedString(candidate.project_id, MAX_PROJECT_ID_LENGTH) || candidate.provider !== 'livekit' ||
    !validBoundedString(candidate.provider_room_name, MAX_ROOM_NAME_LENGTH) || candidate.status !== 'active') {
    throw new HttpError(404, 'unavailable', 'Meeting is unavailable.');
  }
  return {
    id,
    project_id: candidate.project_id,
    provider: 'livekit',
    provider_room_name: candidate.provider_room_name,
    status: 'active',
  };
}

function participantRecord(value: unknown): value is { identity: string } {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  return validBoundedString((value as Record<string, unknown>).identity, MAX_ROOM_NAME_LENGTH);
}

function participantIsPresent(participants: unknown, identity: string): boolean {
  if (!Array.isArray(participants) || !participants.every(participantRecord)) {
    throw new DependencyError('provider');
  }
  const normalizedIdentity = identity.toLowerCase();
  return participants.some((participant) => participant.identity.toLowerCase() === normalizedIdentity);
}

function isNotFoundError(error: unknown): boolean {
  if (error !== null && typeof error === 'object') {
    const candidate = error as Record<string, unknown>;
    const status = candidate.status ?? candidate.statusCode ?? candidate.code;
    if (status === 404 || status === '404' || status === 'NOT_FOUND' || status === 'not_found') return true;
  }
  if (error instanceof Error) {
    return /(?:not[\s_-]*found|does not exist)/i.test(error.message);
  }
  return false;
}

function productionClient(config: MeetingRemovalConfig, bearerToken: string): SupabaseClient {
  return createClient(config.supabaseUrl, config.supabaseAnonKey, {
    global: { headers: { Authorization: 'Bearer ' + bearerToken } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

function createProductionDependencies(): MeetingRemovalDependencies {
  return {
    config: readConfigFromEnvironment,
    authenticate: async (bearerToken) => {
      const config = readConfigFromEnvironment();
      if (config === null) throw new DependencyError('configuration');
      const client = productionClient(config, bearerToken);
      const { data, error } = await client.auth.getUser(bearerToken);
      if (error || data.user === null) return null;
      return { id: data.user.id };
    },
    joinSession: async (meetingId, _userId, bearerToken) => {
      const config = readConfigFromEnvironment();
      if (config === null) throw new DependencyError('configuration');
      const client = productionClient(config, bearerToken);
      const { data, error } = await client.rpc('join_meeting_session', { p_meeting_id: meetingId });
      if (error !== null) return { errorCode: typeof error.code === 'string' ? error.code : 'control-plane' };
      return unwrapSession(data);
    },
    projectRole: async (projectId, _userId, bearerToken) => {
      const config = readConfigFromEnvironment();
      if (config === null) throw new DependencyError('configuration');
      const client = productionClient(config, bearerToken);
      const { data, error } = await client.rpc('project_role', { p_project_id: projectId });
      if (error !== null) return null;
      return data;
    },
    listParticipants: async (roomName, config) => {
      const host = config.livekitUrl.replace(/^wss:/, 'https:');
      const client = new RoomServiceClient(host, config.livekitApiKey, config.livekitApiSecret);
      try {
        return await client.listParticipants(roomName) as unknown[];
      } catch (error) {
        if (isNotFoundError(error)) return [];
        throw new DependencyError('provider');
      }
    },
    removeParticipant: async (roomName, identity, config) => {
      const host = config.livekitUrl.replace(/^wss:/, 'https:');
      const client = new RoomServiceClient(host, config.livekitApiKey, config.livekitApiSecret);
      try {
        await client.removeParticipant(roomName, identity);
        return true;
      } catch (error) {
        if (isNotFoundError(error)) return false;
        throw new DependencyError('provider');
      }
    },
  };
}

export function createMeetingRemoveParticipantHandler(
  overrides: Partial<MeetingRemovalDependencies> = {},
): (request: Request) => Promise<Response> {
  const dependencies = { ...createProductionDependencies(), ...overrides };
  return async (request) => {
    let origin: string | undefined;
    try {
      const config = dependencies.config();
      if (config === null || !isUsableMeetingRemovalConfig(config)) {
        throw new HttpError(500, 'unavailable', 'Video meeting is not configured.');
      }
      origin = checkOrigin(request, config);
      if (request.method === 'OPTIONS') {
        return new Response(null, { status: 204, headers: jsonHeaders(origin) });
      }
      if (request.method !== 'POST') {
        throw new HttpError(405, 'validation_error', 'Request method is not supported.');
      }
      const bearerToken = parseBearer(request);
      const body = await readBody(request);
      const { meetingId, identity } = parseRemovalRequest(body);
      const user = await dependencies.authenticate(bearerToken);
      if (user === null || typeof user !== 'object' || typeof user.id !== 'string' || !UUID_PATTERN.test(user.id)) {
        throw new HttpError(401, 'authorization_error', 'Authentication is required.');
      }
      let joined: unknown;
      try {
        joined = await dependencies.joinSession(meetingId, user.id, bearerToken);
      } catch (error) {
        const code = sessionErrorCode(error);
        if (code === 'P0003' || code === 'ended') {
          throw new HttpError(410, 'ended', 'Meeting has ended.');
        }
        if (error instanceof DependencyError && error.kind === 'configuration') {
          throw new HttpError(500, 'unavailable', 'Video meeting is not configured.');
        }
        throw new HttpError(404, 'unavailable', 'Meeting is unavailable.');
      }
      if (sessionErrorCode(joined) === 'P0003' || sessionErrorCode(joined) === 'ended') {
        throw new HttpError(410, 'ended', 'Meeting has ended.');
      }
      const session = validateSession(joined, meetingId);
      let roleValue: unknown;
      try {
        roleValue = await dependencies.projectRole(session.project_id, user.id, bearerToken);
      } catch (error) {
        if (error instanceof DependencyError && error.kind === 'configuration') {
          throw new HttpError(500, 'unavailable', 'Video meeting is not configured.');
        }
        throw new HttpError(403, 'authorization_error', 'Meeting access denied.');
      }
      if (roleValue !== 'owner') {
        throw new HttpError(403, 'authorization_error', 'Meeting access denied.');
      }
      if (identity.toLowerCase() === user.id.toLowerCase()) {
        throw new HttpError(403, 'authorization_error', 'Meeting access denied.');
      }
      let participants: readonly unknown[];
      try {
        participants = await dependencies.listParticipants(session.provider_room_name, config);
        if (!participantIsPresent(participants, identity)) return jsonResponse({ removed: false }, 200, origin);
      } catch (error) {
        if (isNotFoundError(error)) return jsonResponse({ removed: false }, 200, origin);
        throw new HttpError(503, 'provider_unavailable', 'Video service is unavailable.');
      }
      try {
        const result = await dependencies.removeParticipant(session.provider_room_name, identity, config);
        if (result !== undefined && typeof result !== 'boolean') {
          throw new DependencyError('provider');
        }
        return jsonResponse({ removed: result !== false }, 200, origin);
      } catch (error) {
        if (isNotFoundError(error)) return jsonResponse({ removed: false }, 200, origin);
        throw new HttpError(503, 'provider_unavailable', 'Video service is unavailable.');
      }
    } catch (error) {
      if (error instanceof HttpError && ALLOWED_ERROR_CODES[error.code]) {
        return errorResponse(error, origin);
      }
      if (error instanceof DependencyError && error.kind === 'configuration') {
        return errorResponse(new HttpError(500, 'unavailable', 'Video meeting is not configured.'), origin);
      }
      return errorResponse(new HttpError(500, 'unavailable', 'Video meeting is unavailable.'), origin);
    }
  };
}

if (import.meta.main) Deno.serve(createMeetingRemoveParticipantHandler());
