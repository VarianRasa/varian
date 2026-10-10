import {
  normalizeBillingWebhook,
  parseSignatureHeader,
  signWebhookPayload,
  verifyWebhookSignature,
} from "./helpers.ts";

Deno.test("normalizes a provider event and redacts the persisted payload", () => {
  const event = normalizeBillingWebhook({
    id: "evt_202609140001",
    type: "customer.subscription.updated",
    data: {
      object: {
        metadata: { project_id: "project-1", plan_id: "pro" },
        status: "trialing",
        revision: 4,
        limits: { storageBytes: 1000, seats: 3 },
        customer: "cus_secret",
        subscriptionId: "sub_1",
      },
    },
    card: { number: "4111111111111111" },
  });
  if (event.projectId !== "project-1") throw new Error("project was not normalized");
  if (event.planId !== "pro") throw new Error("plan was not normalized");
  if (event.status !== "trialing") throw new Error("status was not normalized");
  if (event.limits.seats !== 3) throw new Error("limits were not normalized");
  if ("card" in event.payload) throw new Error("raw provider fields were persisted");
});

Deno.test("accepts nested metadata and maps failed payments to past_due", () => {
  const event = normalizeBillingWebhook({
    id: "evt_202609140002",
    type: "invoice.payment_failed",
    data: {
      object: {
        metadata: { workspace_id: "project-2", plan_id: "team" },
      },
    },
  });
  if (event.projectId !== "project-2") throw new Error("workspace metadata was ignored");
  if (event.status !== "past_due") throw new Error("payment failure was not mapped");
});

Deno.test("verifies a fresh HMAC signature and rejects replayed timestamps", async () => {
  const timestamp = "1789344000";
  const rawBody = '{"id":"evt_202609140003"}';
  const secret = "billing-webhook-test-secret";
  const signature = await signWebhookPayload(secret, timestamp, rawBody);
  const header = `v1=${signature}`;
  const parsed = parseSignatureHeader(header);
  if (parsed.signature !== signature) throw new Error("signature header was not parsed");
  const now = Number(timestamp) * 1000;
  if (!await verifyWebhookSignature({
    secret,
    timestamp,
    rawBody,
    signatureHeader: header,
    now,
  })) throw new Error("valid signature was rejected");
  if (await verifyWebhookSignature({
    secret,
    timestamp,
    rawBody,
    signatureHeader: header,
    now: now + 301_000,
  })) throw new Error("replayed signature was accepted");
});

Deno.test("rejects malformed limits and signatures", async () => {
  let rejected = false;
  try {
    normalizeBillingWebhook({
      id: "evt_202609140004",
      type: "invoice.paid",
      projectId: "project-1",
      planId: "pro",
      limits: { seats: -1 },
    });
  } catch (_) {
    rejected = true;
  }
  if (!rejected) throw new Error("negative limits were accepted");
  if (await verifyWebhookSignature({
    secret: "billing-webhook-test-secret",
    timestamp: "1789344000",
    rawBody: "{}",
    signatureHeader: "v1=invalid",
    now: 1789344000000,
  })) throw new Error("malformed signature was accepted");
});
