const encoder = new TextEncoder();
const MAX_LOGIN_BODY_BYTES = 4096;
const MAX_PASSWORD_CHARS = 512;
const LOGIN_WINDOW_SECONDS = 15 * 60;
const LOGIN_MAX_FAILURES = 5;
const TOKEN_VERSION = 1;

type TokenPayload = {
  v: number;
  iat: number;
  exp: number;
};

type LoginAttempt = {
  count: number;
  resetAt: number;
};

type AverageCostData = {
  schemaVersion: number;
  generatedAt: string;
  source: Record<string, unknown>;
  items: Record<string, { averageCost: number | null }>;
  summary: Record<string, unknown>;
};

function securityHeaders(): Headers {
  return new Headers({
    "Cache-Control": "no-store, max-age=0",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    "Cross-Origin-Resource-Policy": "cross-origin",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
  });
}

function addCorsHeaders(headers: Headers, request: Request, env: Env): void {
  const origin = request.headers.get("Origin");
  if (origin === env.ALLOWED_ORIGIN) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Access-Control-Allow-Headers", "Authorization, Content-Type");
    headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    headers.set("Access-Control-Max-Age", "600");
  }
  headers.append("Vary", "Origin");
}

function jsonResponse(
  request: Request,
  env: Env,
  payload: unknown,
  status = 200,
  extraHeaders?: HeadersInit,
): Response {
  const headers = securityHeaders();
  headers.set("Content-Type", "application/json; charset=utf-8");
  if (extraHeaders) {
    new Headers(extraHeaders).forEach((value, key) => headers.set(key, value));
  }
  addCorsHeaders(headers, request, env);
  return Response.json(payload, { status, headers });
}

function originAllowed(request: Request, env: Env): boolean {
  const origin = request.headers.get("Origin");
  return origin === null || origin === env.ALLOWED_ORIGIN;
}

function secretsReady(env: Env): boolean {
  return Boolean(env.INVENTORY_SHARED_PASSWORD && env.SESSION_SECRET);
}

function sessionLifetimeSeconds(env: Env): number {
  const days = Number.parseInt(env.SESSION_DAYS, 10);
  const safeDays = Number.isFinite(days) && days > 0 && days <= 90 ? days : 30;
  return safeDays * 24 * 60 * 60;
}

async function secretEquals(provided: string, expected: string): Promise<boolean> {
  const [providedHash, expectedHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(provided)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const [providedKey, expectedKey] = await Promise.all([
    crypto.subtle.importKey(
      "raw",
      providedHash,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    ),
    crypto.subtle.importKey(
      "raw",
      expectedHash,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"],
    ),
  ]);
  const comparisonMessage = encoder.encode("phoenixes-password-comparison-v1");
  const signature = await crypto.subtle.sign(
    "HMAC",
    providedKey,
    comparisonMessage,
  );
  return crypto.subtle.verify(
    "HMAC",
    expectedKey,
    signature,
    comparisonMessage,
  );
}

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function fromBase64Url(value: string): Uint8Array<ArrayBuffer> {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new Error("Invalid base64url");
  }
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

async function signingKey(env: Env): Promise<CryptoKey> {
  const material = encoder.encode(
    `${env.SESSION_SECRET}\u0000${env.INVENTORY_SHARED_PASSWORD}`,
  );
  const digest = await crypto.subtle.digest("SHA-256", material);
  return crypto.subtle.importKey(
    "raw",
    digest,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

async function createToken(env: Env): Promise<{
  token: string;
  expiresAt: string;
}> {
  const issuedAt = Math.floor(Date.now() / 1000);
  const payload: TokenPayload = {
    v: TOKEN_VERSION,
    iat: issuedAt,
    exp: issuedAt + sessionLifetimeSeconds(env),
  };
  const payloadPart = toBase64Url(
    encoder.encode(JSON.stringify(payload)),
  );
  const key = await signingKey(env);
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(payloadPart),
  );
  return {
    token: `${payloadPart}.${toBase64Url(new Uint8Array(signature))}`,
    expiresAt: new Date(payload.exp * 1000).toISOString(),
  };
}

async function verifyToken(env: Env, token: string): Promise<TokenPayload | null> {
  if (!secretsReady(env) || token.length > 2048) {
    return null;
  }
  const parts = token.split(".");
  if (parts.length !== 2 || !parts[0] || !parts[1]) {
    return null;
  }

  try {
    const signature = fromBase64Url(parts[1]);
    if (signature.byteLength !== 32) {
      return null;
    }
    const key = await signingKey(env);
    const validSignature = await crypto.subtle.verify(
      "HMAC",
      key,
      signature,
      encoder.encode(parts[0]),
    );
    if (!validSignature) {
      return null;
    }

    const payloadText = new TextDecoder().decode(fromBase64Url(parts[0]));
    const payload = JSON.parse(payloadText) as Partial<TokenPayload>;
    const now = Math.floor(Date.now() / 1000);
    const maxLifetime = sessionLifetimeSeconds(env) + 5 * 60;
    if (
      payload.v !== TOKEN_VERSION ||
      typeof payload.iat !== "number" ||
      typeof payload.exp !== "number" ||
      payload.iat > now + 5 * 60 ||
      payload.exp <= now ||
      payload.exp - payload.iat > maxLifetime
    ) {
      return null;
    }
    return payload as TokenPayload;
  } catch {
    return null;
  }
}

function bearerToken(request: Request): string {
  const authorization = request.headers.get("Authorization") || "";
  const match = authorization.match(/^Bearer ([A-Za-z0-9._-]+)$/);
  return match?.[1] || "";
}

async function authenticatedPayload(
  request: Request,
  env: Env,
): Promise<TokenPayload | null> {
  const token = bearerToken(request);
  return token ? verifyToken(env, token) : null;
}

async function loginAttemptKey(request: Request): Promise<string> {
  const clientAddress =
    request.headers.get("CF-Connecting-IP") ||
    request.headers.get("X-Forwarded-For") ||
    "unknown";
  const digest = await crypto.subtle.digest(
    "SHA-256",
    encoder.encode(clientAddress),
  );
  return `login-attempt:${toBase64Url(new Uint8Array(digest))}`;
}

async function readLoginAttempt(
  env: Env,
  key: string,
): Promise<LoginAttempt | null> {
  const value = await env.COST_DATA.get<LoginAttempt>(key, "json");
  if (
    !value ||
    typeof value.count !== "number" ||
    typeof value.resetAt !== "number"
  ) {
    return null;
  }
  return value;
}

async function checkLoginLimit(
  request: Request,
  env: Env,
): Promise<{ key: string; blocked: boolean; retryAfter: number }> {
  const key = await loginAttemptKey(request);
  const now = Math.floor(Date.now() / 1000);
  const attempt = await readLoginAttempt(env, key);
  if (!attempt || attempt.resetAt <= now || attempt.count < LOGIN_MAX_FAILURES) {
    return { key, blocked: false, retryAfter: 0 };
  }
  return {
    key,
    blocked: true,
    retryAfter: Math.max(1, attempt.resetAt - now),
  };
}

async function recordLoginFailure(env: Env, key: string): Promise<void> {
  const now = Math.floor(Date.now() / 1000);
  const previous = await readLoginAttempt(env, key);
  const active = previous && previous.resetAt > now ? previous : null;
  const next: LoginAttempt = {
    count: (active?.count || 0) + 1,
    resetAt: active?.resetAt || now + LOGIN_WINDOW_SECONDS,
  };
  await env.COST_DATA.put(key, JSON.stringify(next), {
    expirationTtl: LOGIN_WINDOW_SECONDS,
  });
}

async function handleLogin(request: Request, env: Env): Promise<Response> {
  if (!secretsReady(env)) {
    return jsonResponse(
      request,
      env,
      { message: "成本登入服務尚未完成密碼設定。" },
      503,
    );
  }

  const contentLength = Number(request.headers.get("Content-Length") || "0");
  if (contentLength > MAX_LOGIN_BODY_BYTES) {
    return jsonResponse(request, env, { message: "請求內容過大。" }, 413);
  }

  const limit = await checkLoginLimit(request, env);
  if (limit.blocked) {
    return jsonResponse(
      request,
      env,
      { message: "嘗試次數過多，請稍後再試。" },
      429,
      { "Retry-After": String(limit.retryAfter) },
    );
  }

  let password = "";
  try {
    const body = await request.text();
    if (encoder.encode(body).byteLength > MAX_LOGIN_BODY_BYTES) {
      return jsonResponse(request, env, { message: "請求內容過大。" }, 413);
    }
    const payload = JSON.parse(body) as { password?: unknown };
    password = typeof payload.password === "string" ? payload.password : "";
  } catch {
    return jsonResponse(request, env, { message: "密碼格式不正確。" }, 400);
  }

  if (!password || password.length > MAX_PASSWORD_CHARS) {
    await recordLoginFailure(env, limit.key);
    return jsonResponse(request, env, { message: "密碼不正確。" }, 401);
  }

  const validPassword = await secretEquals(
    password,
    env.INVENTORY_SHARED_PASSWORD,
  );
  if (!validPassword) {
    await recordLoginFailure(env, limit.key);
    return jsonResponse(request, env, { message: "密碼不正確。" }, 401);
  }

  await env.COST_DATA.delete(limit.key);
  const session = await createToken(env);
  return jsonResponse(request, env, {
    authenticated: true,
    token: session.token,
    expiresAt: session.expiresAt,
  });
}

async function handleSession(request: Request, env: Env): Promise<Response> {
  const payload = await authenticatedPayload(request, env);
  if (!payload) {
    return jsonResponse(
      request,
      env,
      { authenticated: false, message: "請重新輸入密碼。" },
      401,
    );
  }
  return jsonResponse(request, env, {
    authenticated: true,
    expiresAt: new Date(payload.exp * 1000).toISOString(),
  });
}

async function handleInternalData(
  request: Request,
  env: Env,
): Promise<Response> {
  const payload = await authenticatedPayload(request, env);
  if (!payload) {
    return jsonResponse(
      request,
      env,
      { message: "請先輸入密碼解鎖平均成本。" },
      401,
    );
  }

  const data = await env.COST_DATA.get<AverageCostData>(env.DATA_KEY, "json");
  if (
    !data ||
    data.schemaVersion !== 1 ||
    typeof data.items !== "object" ||
    data.items === null
  ) {
    return jsonResponse(
      request,
      env,
      { message: "平均成本資料尚未上傳。" },
      503,
    );
  }
  return jsonResponse(request, env, data);
}

async function route(request: Request, env: Env): Promise<Response> {
  if (!originAllowed(request, env)) {
    return jsonResponse(request, env, { message: "不允許的來源。" }, 403);
  }

  const url = new URL(request.url);
  if (request.method === "OPTIONS") {
    const headers = securityHeaders();
    addCorsHeaders(headers, request, env);
    return new Response(null, { status: 204, headers });
  }
  if (url.pathname === "/" && request.method === "GET") {
    return jsonResponse(request, env, {
      service: "封王封膜庫存－平均成本登入服務",
      status: "ok",
      configured: secretsReady(env),
    });
  }
  if (url.pathname === "/api/login" && request.method === "POST") {
    return handleLogin(request, env);
  }
  if (url.pathname === "/api/session" && request.method === "GET") {
    return handleSession(request, env);
  }
  if (url.pathname === "/api/internal-data" && request.method === "GET") {
    return handleInternalData(request, env);
  }
  return jsonResponse(request, env, { message: "找不到這個服務路徑。" }, 404);
}

export default {
  async fetch(request, env): Promise<Response> {
    try {
      return await route(request, env);
    } catch (error) {
      console.error(
        JSON.stringify({
          event: "request_error",
          message: error instanceof Error ? error.message : "Unknown error",
        }),
      );
      return jsonResponse(
        request,
        env,
        { message: "服務暫時無法使用，請稍後再試。" },
        500,
      );
    }
  },
} satisfies ExportedHandler<Env>;
