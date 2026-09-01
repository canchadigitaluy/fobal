import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";

const attempts = globalThis.__canteraPreviewAttempts ?? new Map();
globalThis.__canteraPreviewAttempts = attempts;

export default async function handler(req, res) {
  res.setHeader("access-control-allow-origin", "*");
  res.setHeader("access-control-allow-methods", "POST, OPTIONS");
  res.setHeader("access-control-allow-headers", "content-type");
  res.setHeader("cache-control", "no-store");

  if (req.method === "OPTIONS") return res.status(200).json({ ok: true });
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const expectedCode = process.env.CANTERA_PREVIEW_CODE;
  const signingKey = process.env.CANTERA_PREVIEW_SIGNING_KEY;
  if (!expectedCode || !signingKey) {
    return res.status(503).json({
      error: "preview_not_configured",
      message: "El acceso de prueba no esta configurado.",
    });
  }

  const ip = String(
    req.headers["x-forwarded-for"] || req.socket?.remoteAddress || "unknown",
  ).split(',')[0].trim();
  if (!allowAttempt(ip)) {
    return res.status(429).json({
      error: "too_many_attempts",
      message: "Demasiados intentos. Espera unos minutos.",
    });
  }

  const providedCode = String(req.body?.code || "").trim();
  if (!secureEqual(providedCode, expectedCode)) {
    return res.status(401).json({
      error: "invalid_code",
      message: "Codigo incorrecto.",
    });
  }

  const encodedPayload = Buffer.from(
    JSON.stringify({
      scope: "preview_ai",
      exp: Date.now() + 4 * 60 * 60 * 1000,
      nonce: randomBytes(12).toString("hex"),
    }),
  ).toString("base64url");
  const signature = createHmac("sha256", signingKey)
    .update(encodedPayload)
    .digest("base64url");
  return res.status(200).json({ token: `${encodedPayload}.${signature}` });
}

function allowAttempt(ip) {
  const now = Date.now();
  const windowMs = 15 * 60 * 1000;
  const previous = attempts.get(ip) ?? [];
  const recent = previous.filter((time) => now - time < windowMs);
  if (recent.length >= 12) return false;
  recent.push(now);
  attempts.set(ip, recent);
  return true;
}

function secureEqual(left, right) {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  if (leftBuffer.length !== rightBuffer.length) return false;
  return timingSafeEqual(leftBuffer, rightBuffer);
}
