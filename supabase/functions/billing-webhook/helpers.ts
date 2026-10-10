export type JsonRecord = Record<string, unknown>;

export type BillingEntitlementStatus =
  | "active"
  | "trialing"
  | "past_due"
  | "canceled"
  | "paused";

export type BillingOveragePolicy = "block" | "grace" | "allow";

export type NormalizedBillingEvent = {
  provider: string;
  eventId: string;
  eventType: string;
  projectId: string;
  planId: string;
  status: BillingEntitlementStatus;
  revision: number;
  limits: Record<string, number>;
  overagePolicy: BillingOveragePolicy;
  graceUntil: string | null;
  externalCustomerId: string | null;
  externalSubscriptionId: string | null;
  payload: JsonRecord;
};

const entitlementLimitKeys = [
  "storageBytes",
  "assetBytes",
  "transferBytes",
  "aiCredits",
  "renderSeconds",
  "projectCount",
  "seats",
] as const;

const statusValues = new Set<BillingEntitlementStatus>([
  "active",
  "trialing",
  "past_due",
  "canceled",
  "paused",
]);

const overagePolicyValues = new Set<BillingOveragePolicy>([
  "block",
  "grace",
  "allow",
]);

export function asRecord(value: unknown): JsonRecord | null {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  return value as JsonRecord;
}

function firstString(...values: unknown[]): string | null {
  for (const value of values) {
    if (typeof value === "string" && value.trim().length > 0) {
      return value.trim();
    }
  }
  return null;
}

function readMetadata(...records: Array<JsonRecord | null>): JsonRecord {
  for (const record of records) {
    const metadata = asRecord(record?.metadata);
    if (metadata !== null) return metadata;
  }
  return {};
}

function readNumber(...values: unknown[]): number | null {
  for (const value of values) {
    if (typeof value === "number" && Number.isSafeInteger(value) && value >= 0) {
      return value;
    }
    if (typeof value === "string" && /^\d+$/.test(value.trim())) {
      const parsed = Number(value.trim());
      if (Number.isSafeInteger(parsed)) return parsed;
    }
  }
  return null;
}

function normalizeStatus(
  rawStatus: string | null,
  eventType: string,
): BillingEntitlementStatus {
  const normalized = rawStatus?.toLowerCase().trim().replace(/-/g, "_");
  if (normalized !== null && statusValues.has(normalized as BillingEntitlementStatus)) {
    return normalized as BillingEntitlementStatus;
  }
  const normalizedType = eventType.toLowerCase().replace(/-/g, "_");
  if (normalizedType.includes("deleted") || normalizedType.includes("canceled")) {
    return "canceled";
  }
  if (normalizedType.includes("payment_failed") || normalizedType.includes("past_due")) {
    return "past_due";
  }
  return "active";
}

function normalizeLimits(...values: unknown[]): Record<string, number> {
  const source = values.map(asRecord).find((record) => record !== null) ?? {};
  const limits: Record<string, number> = {};
  for (const key of entitlementLimitKeys) {
    const value = source[key];
    if (value === undefined || value === null) continue;
    if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
      throw new Error(`Invalid entitlement limit: ${key}`);
    }
    limits[key] = value;
  }
  return limits;
}

function normalizeDate(value: unknown): string | null {
  if (value === null || value === undefined || value === "") return null;
  const date = new Date(typeof value === "number" ? value * 1000 : String(value));
  if (Number.isNaN(date.getTime())) throw new Error("Invalid entitlement graceUntil");
  return date.toISOString();
}

export function normalizeBillingWebhook(
  input: unknown,
  defaultProvider = "generic",
): NormalizedBillingEvent {
  const body = asRecord(input);
  if (body === null) throw new Error("Webhook payload must be an object");

  const data = asRecord(body.data);
  const dataObject = asRecord(data?.object) ?? data ?? {};
  const bodyMetadata = readMetadata(body);
  const objectMetadata = readMetadata(dataObject);
  const eventId = firstString(body.id, body.event_id);
  const eventType = firstString(body.type, body.event_type);
  const provider = firstString(body.provider, defaultProvider);
  const projectId = firstString(
    body.projectId,
    body.project_id,
    body.workspaceId,
    body.workspace_id,
    dataObject.projectId,
    dataObject.project_id,
    dataObject.workspaceId,
    dataObject.workspace_id,
    bodyMetadata.projectId,
    bodyMetadata.project_id,
    bodyMetadata.workspaceId,
    bodyMetadata.workspace_id,
    objectMetadata.projectId,
    objectMetadata.project_id,
    objectMetadata.workspaceId,
    objectMetadata.workspace_id,
  );
  const plan = asRecord(dataObject.plan);
  const planMetadata = readMetadata(plan);
  const planId = firstString(
    body.planId,
    body.plan_id,
    dataObject.planId,
    dataObject.plan_id,
    dataObject.priceId,
    dataObject.price_id,
    plan?.id,
    plan?.lookupKey,
    plan?.lookup_key,
    bodyMetadata.planId,
    bodyMetadata.plan_id,
    objectMetadata.planId,
    objectMetadata.plan_id,
    planMetadata.planId,
    planMetadata.plan_id,
  );
  if (eventId === null || eventId.length < 8 || eventId.length > 200) {
    throw new Error("Webhook event ID is invalid");
  }
  if (eventType === null || eventType.length < 2 || eventType.length > 128) {
    throw new Error("Webhook event type is invalid");
  }
  if (provider === null || !/^[a-z0-9._-]{2,64}$/.test(provider)) {
    throw new Error("Webhook provider is invalid");
  }
  if (projectId === null || projectId.length > 128) {
    throw new Error("Webhook project ID is required");
  }
  if (planId === null || planId.length > 80) {
    throw new Error("Webhook plan ID is required");
  }

  const rawStatus = firstString(body.status, dataObject.status, dataObject.subscriptionStatus);
  const status = normalizeStatus(rawStatus, eventType);
  const revision = readNumber(body.revision, dataObject.revision, dataObject.version) ?? 0;
  const limits = normalizeLimits(body.limits, dataObject.limits, plan?.limits);
  const rawOveragePolicy = firstString(
    body.overagePolicy,
    body.overage_policy,
    dataObject.overagePolicy,
    dataObject.overage_policy,
  ) ?? "block";
  const overagePolicy = rawOveragePolicy.replace(/-/g, "_") as BillingOveragePolicy;
  if (!overagePolicyValues.has(overagePolicy)) {
    throw new Error("Webhook overage policy is invalid");
  }
  const graceUntil = normalizeDate(
    body.graceUntil ?? body.grace_until ?? dataObject.graceUntil ?? dataObject.grace_until,
  );
  const externalCustomerId = firstString(
    body.externalCustomerId,
    body.external_customer_id,
    dataObject.customerId,
    dataObject.customer_id,
  );
  const externalSubscriptionId = firstString(
    body.externalSubscriptionId,
    body.external_subscription_id,
    dataObject.subscriptionId,
    dataObject.subscription_id,
  );

  const payload: JsonRecord = {
    eventId,
    eventType,
    provider,
    projectId,
    planId,
    status,
    revision,
    limits,
    overagePolicy,
    graceUntil,
    externalCustomerId,
    externalSubscriptionId,
  };
  return {
    provider,
    eventId,
    eventType,
    projectId,
    planId,
    status,
    revision,
    limits,
    overagePolicy,
    graceUntil,
    externalCustomerId,
    externalSubscriptionId,
    payload,
  };
}

export function signingMessage(timestamp: string, rawBody: string): string {
  return `${timestamp}.${rawBody}`;
}

export function parseSignatureHeader(
  header: string | null,
): { timestamp: string | null; signature: string | null } {
  const value = header?.trim() ?? "";
  if (value.length === 0) return { timestamp: null, signature: null };
  let timestamp: string | null = null;
  let signature: string | null = null;
  for (const part of value.split(/[\s,]+/)) {
    const [key, rawValue] = part.split("=", 2);
    if (key === "t" && rawValue !== undefined) timestamp = rawValue;
    if ((key === "v1" || key === "sha256") && rawValue !== undefined) signature = rawValue;
  }
  if (signature === null && /^[a-f0-9]{64}$/i.test(value)) signature = value;
  if (signature !== null && !/^[a-f0-9]{64}$/i.test(signature)) {
    return { timestamp, signature: null };
  }
  return { timestamp, signature: signature?.toLowerCase() ?? null };
}

export function isFreshTimestamp(
  timestamp: string | null,
  now = Date.now(),
  maxAgeSeconds = 300,
): boolean {
  if (timestamp === null || !/^\d{1,15}$/.test(timestamp)) return false;
  const seconds = Number(timestamp);
  if (!Number.isSafeInteger(seconds)) return false;
  return Math.abs(now - seconds * 1000) <= maxAgeSeconds * 1000;
}

export async function signWebhookPayload(
  secret: string,
  timestamp: string,
  rawBody: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(signingMessage(timestamp, rawBody)),
  );
  return Array.from(new Uint8Array(digest), (value) => value.toString(16).padStart(2, "0")).join("");
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

export async function verifyWebhookSignature({
  secret,
  timestamp,
  rawBody,
  signatureHeader,
  now = Date.now(),
  maxAgeSeconds = 300,
}: {
  secret: string;
  timestamp: string | null;
  rawBody: string;
  signatureHeader: string | null;
  now?: number;
  maxAgeSeconds?: number;
}): Promise<boolean> {
  if (secret.trim().length < 16) return false;
  const parsed = parseSignatureHeader(signatureHeader);
  const effectiveTimestamp = timestamp?.trim() || parsed.timestamp;
  if (!isFreshTimestamp(effectiveTimestamp, now, maxAgeSeconds) || parsed.signature === null) {
    return false;
  }
  const expected = await signWebhookPayload(secret, effectiveTimestamp!, rawBody);
  return constantTimeEqual(expected, parsed.signature);
}
