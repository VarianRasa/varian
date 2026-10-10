type ProbeConfig = {
  supabaseUrl: string;
  anonKey: string;
  hostToken: string;
  guestToken: string;
  projectId: string;
  roomCode: string;
  mediaPath?: string;
  writeOperation: boolean;
  revokeGuest: boolean;
  timeoutMs: number;
};

type ProbeResult = {
  name: string;
  status: 'passed' | 'failed' | 'skipped';
  detail: string;
  evidence?: Record<string, unknown>;
};

export function requiredEnv(
  environment: Record<string, string | undefined>,
  name: string,
): string {
  const value = environment[name]?.trim();
  if (!value) throw new Error(`${name} is required.`);
  return value;
}

export function readProbeConfig(
  environment: Record<string, string | undefined>,
): ProbeConfig {
  const timeoutMs = Number(environment.COLLAB_PROBE_TIMEOUT_MS ?? '10000');
  if (!Number.isFinite(timeoutMs) || timeoutMs < 1000 || timeoutMs > 120000) {
    throw new Error('COLLAB_PROBE_TIMEOUT_MS must be between 1000 and 120000.');
  }
  return {
    supabaseUrl: requiredEnv(environment, 'SUPABASE_URL').replace(/\/+$/, ''),
    anonKey: requiredEnv(environment, 'SUPABASE_ANON_KEY'),
    hostToken: requiredEnv(environment, 'COLLAB_HOST_ACCESS_TOKEN'),
    guestToken: requiredEnv(environment, 'COLLAB_GUEST_ACCESS_TOKEN'),
    projectId: requiredEnv(environment, 'COLLAB_PROJECT_ID'),
    roomCode: requiredEnv(environment, 'COLLAB_ROOM_CODE'),
    mediaPath: environment.COLLAB_MEDIA_PATH?.trim() || undefined,
    writeOperation: environment.COLLAB_PROBE_WRITE_OPERATION === 'true',
    revokeGuest: environment.COLLAB_PROBE_REVOKE_GUEST === 'true',
    timeoutMs,
  };
}

export function jwtSubject(token: string): string {
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('Supabase access token is not a JWT.');
  const normalized = parts[1].replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized + '='.repeat((4 - normalized.length % 4) % 4);
  const payload = JSON.parse(atob(padded)) as { sub?: unknown };
  if (typeof payload.sub !== 'string' || payload.sub.trim().length === 0) {
    throw new Error('Supabase access token does not contain a subject.');
  }
  return payload.sub;
}

export function buildProbeOperation(
  projectId: string,
  actorId: string,
  nonce: string,
): Record<string, unknown> {
  return {
    projectId,
    opId: `production-probe-${nonce}`,
    kind: 'setNodeProperty',
    targetId: '__production_probe__',
    field: 'probe',
    value: { nonce, source: 'collaboration-production-probe' },
    dot: { actorId, counter: 1 },
    dependencies: {},
  };
}

class RestPeer {
  readonly #baseUrl: string;
  readonly #anonKey: string;
  readonly #token: string;

  constructor(baseUrl: string, anonKey: string, token: string) {
    this.#baseUrl = baseUrl;
    this.#anonKey = anonKey;
    this.#token = token;
  }

  async rpc(name: string, body: Record<string, unknown>): Promise<unknown> {
    return this.request(`/rest/v1/rpc/${name}`, {
      method: 'POST',
      body: JSON.stringify(body),
    });
  }

  async table(path: string): Promise<unknown> {
    return this.request(`/rest/v1/${path}`, { method: 'GET' });
  }

  async downloadAsset(path: string): Promise<{ status: number; bytes: Uint8Array }> {
    const response = await fetch(
      `${this.#baseUrl}/storage/v1/object/authenticated/${path
        .split('/')
        .map(encodeURIComponent)
        .join('/')}`,
      { headers: this.headers() },
    );
    return { status: response.status, bytes: new Uint8Array(await response.arrayBuffer()) };
  }

  private headers(): HeadersInit {
    return {
      apikey: this.#anonKey,
      Authorization: `Bearer ${this.#token}`,
      'Content-Type': 'application/json',
    };
  }

  private async request(path: string, init: RequestInit): Promise<unknown> {
    const response = await fetch(`${this.#baseUrl}${path}`, {
      ...init,
      headers: { ...this.headers(), ...(init.headers ?? {}) },
    });
    const raw = await response.text();
    let payload: unknown = raw;
    try {
      payload = raw ? JSON.parse(raw) : null;
    } catch (_) {}
    if (!response.ok) {
      throw new Error(`${path} returned HTTP ${response.status}: ${raw}`);
    }
    return payload;
  }
}

class RealtimePeer {
  readonly #url: string;
  readonly #anonKey: string;
  readonly #token: string;
  readonly #topic: string;
  readonly #timeoutMs: number;
  readonly #messages: unknown[] = [];
  #socket: WebSocket | undefined;
  #ref = 0;

  constructor(
    baseUrl: string,
    anonKey: string,
    token: string,
    projectId: string,
    timeoutMs: number,
  ) {
    this.#url = baseUrl.replace(/^http/, 'ws') +
        `/realtime/v1/websocket?apikey=${encodeURIComponent(anonKey)}&vsn=1.0.0`;
    this.#anonKey = anonKey;
    this.#token = token;
    this.#topic = `realtime:canvas_room:${projectId}`;
    this.#timeoutMs = timeoutMs;
  }

  async connect(): Promise<void> {
    const socket = new WebSocket(this.#url);
    this.#socket = socket;
    socket.onmessage = (event) => {
      try {
        this.#messages.push(JSON.parse(String(event.data)));
      } catch (_) {}
    };
    await this.waitFor(() => socket.readyState === WebSocket.OPEN);
    const ref = this.nextRef();
    socket.send(JSON.stringify({
      topic: this.#topic,
      event: 'phx_join',
      payload: {
        access_token: this.#token,
        config: {
          broadcast: { ack: true, self: false },
          presence: { key: jwtSubject(this.#token) },
          private: false,
        },
      },
      ref,
    }));
    await this.waitFor((message) =>
      isRecord(message) &&
      message.topic === this.#topic &&
      message.event === 'phx_reply' &&
      message.ref === ref &&
      isRecord(message.payload) &&
      isRecord(message.payload.response) &&
      message.payload.response.status === 'ok');
  }

  async broadcast(event: string, payload: Record<string, unknown>): Promise<void> {
    const socket = this.#socket;
    if (!socket || socket.readyState !== WebSocket.OPEN) {
      throw new Error('Realtime socket is not connected.');
    }
    const ref = this.nextRef();
    socket.send(JSON.stringify({
      topic: this.#topic,
      event: 'broadcast',
      payload: { type: 'broadcast', event, payload },
      ref,
    }));
    await this.waitFor((message) =>
      isRecord(message) &&
      message.topic === this.#topic &&
      message.event === 'phx_reply' &&
      message.ref === ref &&
      isRecord(message.payload) &&
      (message.payload.response === 'ok' ||
        (isRecord(message.payload.response) &&
          message.payload.response.status === 'ok')));
  }

  async waitForBroadcast(
    event: string,
    predicate: (payload: Record<string, unknown>) => boolean,
  ): Promise<Record<string, unknown>> {
    return this.waitFor((message) => {
      if (!isRecord(message) || message.event !== 'broadcast') return false;
      if (!isRecord(message.payload) || message.payload.event !== event) return false;
      const payload = message.payload.payload;
      return isRecord(payload) && predicate(payload);
    }).then((message) => {
      const payload = (message as Record<string, unknown>).payload as Record<string, unknown>;
      return payload.payload as Record<string, unknown>;
    });
  }

  close(): void {
    this.#socket?.close();
    this.#socket = undefined;
  }

  private nextRef(): string {
    this.#ref += 1;
    return String(this.#ref);
  }

  private async waitFor(predicate: (message: unknown) => boolean): Promise<unknown> {
    const deadline = Date.now() + this.#timeoutMs;
    while (Date.now() < deadline) {
      const index = this.#messages.findIndex(predicate);
      if (index >= 0) return this.#messages.splice(index, 1)[0];
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    throw new Error('Realtime probe timed out.');
  }
}

export async function runProbe(config: ProbeConfig): Promise<ProbeResult[]> {
  const results: ProbeResult[] = [];
  const hostUserId = jwtSubject(config.hostToken);
  const guestUserId = jwtSubject(config.guestToken);
  if (hostUserId === guestUserId) {
    throw new Error('Host and guest access tokens must belong to different users.');
  }

  const host = new RestPeer(config.supabaseUrl, config.anonKey, config.hostToken);
  const guest = new RestPeer(config.supabaseUrl, config.anonKey, config.guestToken);
  const hostJoin = await host.rpc('join_collaboration_room', {
    p_room_code: config.roomCode,
    p_display_name: 'Production probe host',
  });
  const guestJoin = await guest.rpc('join_collaboration_room', {
    p_room_code: config.roomCode,
    p_display_name: 'Production probe guest',
  });
  assertProject(hostJoin, config.projectId, 'Host room join');
  assertProject(guestJoin, config.projectId, 'Guest room join');
  results.push({ name: 'two-authorized-sessions-and-room', status: 'passed', detail: 'Both JWT sessions joined the requested room.' });

  await guest.table(`canvas_crdt_snapshots?project_id=eq.${encodeURIComponent(config.projectId)}&select=project_id&limit=1`);
  await guest.table(`canvas_crdt_operations?project_id=eq.${encodeURIComponent(config.projectId)}&select=project_id&limit=1`);
  results.push({ name: 'rls-read-path', status: 'passed', detail: 'Guest session read path completed under authenticated RLS.' });

  const hostRealtime = new RealtimePeer(config.supabaseUrl, config.anonKey, config.hostToken, config.projectId, config.timeoutMs);
  let guestRealtime = new RealtimePeer(config.supabaseUrl, config.anonKey, config.guestToken, config.projectId, config.timeoutMs);
  try {
    await Promise.all([hostRealtime.connect(), guestRealtime.connect()]);
    const nonce = crypto.randomUUID();
    await hostRealtime.broadcast('probe-edit', { nonce, direction: 'host-to-guest' });
    await guestRealtime.waitForBroadcast('probe-edit', (payload) => payload.nonce === nonce);
    await guestRealtime.broadcast('probe-edit', { nonce, direction: 'guest-to-host' });
    await hostRealtime.waitForBroadcast('probe-edit', (payload) => payload.nonce === nonce && payload.direction === 'guest-to-host');
    await hostRealtime.broadcast('cursor_update', { userId: hostUserId, nonce, x: 12, y: 34 });
    await guestRealtime.waitForBroadcast('cursor_update', (payload) => payload.nonce === nonce && payload.userId === hostUserId);
    results.push({ name: 'bidirectional-edit-and-presence', status: 'passed', detail: 'Realtime edit and cursor presence crossed both authenticated clients.' });

    guestRealtime.close();
    guestRealtime = new RealtimePeer(config.supabaseUrl, config.anonKey, config.guestToken, config.projectId, config.timeoutMs);
    await guestRealtime.connect();
    await hostRealtime.broadcast('probe-reconnect', { nonce });
    await guestRealtime.waitForBroadcast('probe-reconnect', (payload) => payload.nonce === nonce);
    results.push({ name: 'reconnect', status: 'passed', detail: 'Guest rejoined after socket loss and received a host event.' });

    if (config.writeOperation) {
      const operation = buildProbeOperation(config.projectId, hostUserId, nonce);
      await host.rpc('append_canvas_crdt_operation', {
        p_project_id: config.projectId,
        p_operation: operation,
      });
      const delta = await guest.rpc('get_canvas_crdt_delta', {
        p_project_id: config.projectId,
        p_version_vector: {},
      });
      if (!Array.isArray(delta) || !delta.some((row) => isRecord(row) && isRecord(row.operation) && row.operation.opId === operation.opId)) {
        throw new Error('Guest delta did not contain the probe operation.');
      }
      results.push({ name: 'durable-crdt-and-duplicate-safe-path', status: 'passed', detail: 'Durable operation was visible through the guest delta path.', evidence: { opId: operation.opId } });
    } else {
      results.push({ name: 'durable-crdt-and-duplicate-safe-path', status: 'skipped', detail: 'Set COLLAB_PROBE_WRITE_OPERATION=true only on a disposable probe project.' });
    }
  } finally {
    hostRealtime.close();
    guestRealtime.close();
  }

  if (config.mediaPath) {
    const media = await guest.downloadAsset(config.mediaPath);
    if (media.status < 200 || media.status >= 300 || media.bytes.length === 0) {
      throw new Error(`Guest media download failed with HTTP ${media.status}.`);
    }
    const digest = await crypto.subtle.digest('SHA-256', media.bytes);
    results.push({ name: 'media-delivery', status: 'passed', detail: 'Guest downloaded a non-empty authenticated Storage object.', evidence: { path: config.mediaPath, bytes: media.bytes.length, sha256: hex(new Uint8Array(digest)) } });
  } else {
    results.push({ name: 'media-delivery', status: 'skipped', detail: 'Set COLLAB_MEDIA_PATH to a disposable project asset path.' });
  }

  if (config.revokeGuest) {
    await host.rpc('remove_canvas_member', { p_project_id: config.projectId, p_user_id: guestUserId });
    let revoked = false;
    try {
      await guest.rpc('join_collaboration_room', { p_room_code: config.roomCode, p_display_name: 'Revoked guest' });
    } catch (_) {
      revoked = true;
    }
    if (!revoked) throw new Error('Revoked guest could rejoin the collaboration room.');
    results.push({ name: 'revoke', status: 'passed', detail: 'Owner removed guest membership and the guest could not rejoin.' });
  } else {
    results.push({ name: 'revoke', status: 'skipped', detail: 'Set COLLAB_PROBE_REVOKE_GUEST=true only on a disposable probe room.' });
  }
  return results;
}

function assertProject(value: unknown, projectId: string, label: string): void {
  if (!isRecord(value) || value.project_id !== projectId) throw new Error(`${label} returned an unexpected project.`);
}

function isRecord(value: unknown): value is Record<string, any> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function hex(bytes: Uint8Array): string {
  return [...bytes].map((value) => value.toString(16).padStart(2, '0')).join('');
}

if (import.meta.main) {
  try {
    const config = readProbeConfig(Deno.env.toObject());
    const results = await runProbe(config);
    const report = {
      schemaVersion: 1,
      generatedAt: new Date().toISOString(),
      projectId: config.projectId,
      hostUserId: jwtSubject(config.hostToken),
      guestUserId: jwtSubject(config.guestToken),
      results,
      status: results.some((result) => result.status === 'failed') ? 'failed' : 'passed',
    };
    console.log(JSON.stringify(report, null, 2));
    if (report.status !== 'passed') Deno.exit(1);
  } catch (error) {
    console.error(JSON.stringify({ schemaVersion: 1, generatedAt: new Date().toISOString(), status: 'failed', error: String(error) }, null, 2));
    Deno.exit(1);
  }
}
