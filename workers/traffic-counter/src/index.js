const DEFAULT_APP_ID = "phoenixes-film-inventory";
const DEFAULT_ALLOWED_ORIGINS = [
  "https://phoenixes-marketing.github.io",
  "http://127.0.0.1:8765",
  "http://localhost:8765"
];

export default {
  async fetch(request, env) {
    const cors = corsHeaders(request, env);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }

    try {
      if (!originAllowed(request, env)) {
        return json({ error: "Origin is not allowed." }, 403, cors);
      }

      if (request.method === "GET") {
        return readCount(request, env, cors);
      }

      if (request.method === "POST") {
        return recordCount(request, env, cors);
      }

      return json({ error: "Method is not allowed." }, 405, {
        ...cors,
        Allow: "GET, POST, OPTIONS"
      });
    } catch (error) {
      return json({ error: "Traffic counter is unavailable." }, 503, cors);
    }
  }
};

async function recordCount(request, env, cors) {
  const payload = await readJson(request);
  const app = normalizeApp(payload.app || env.APP_ID);
  const today = todayKeyInTaipei();
  const now = Date.now();
  const cooldownMs = cooldownSeconds(env) * 1000;
  const clientKey = await anonymousClientKey(request, env, app, today);

  await env.DB.prepare(
    "DELETE FROM client_cooldowns WHERE app = ?1 AND date < ?2"
  ).bind(app, today).run();

  const cooldownResult = await env.DB.prepare(`
    INSERT INTO client_cooldowns (app, date, client_key, last_counted_at)
    VALUES (?1, ?2, ?3, ?4)
    ON CONFLICT(app, date, client_key) DO UPDATE SET
      last_counted_at = excluded.last_counted_at
    WHERE client_cooldowns.last_counted_at <= ?5
  `).bind(app, today, clientKey, now, now - cooldownMs).run();

  const counted = Number(cooldownResult.meta?.changes || 0) > 0;
  if (counted) {
    await env.DB.prepare(`
      INSERT INTO daily_counts (app, date, count, updated_at)
      VALUES (?1, ?2, 1, ?3)
      ON CONFLICT(app, date) DO UPDATE SET
        count = daily_counts.count + 1,
        updated_at = excluded.updated_at
    `).bind(app, today, now).run();
  }

  const count = await countForDate(env, app, today);
  return json({
    app,
    date: today,
    count,
    counted,
    cooldownSeconds: cooldownSeconds(env)
  }, 200, cors);
}

async function readCount(request, env, cors) {
  const url = new URL(request.url);
  const app = normalizeApp(url.searchParams.get("app") || env.APP_ID);
  const today = todayKeyInTaipei();
  const count = await countForDate(env, app, today);

  return json({
    app,
    date: today,
    count,
    counted: false,
    cooldownSeconds: cooldownSeconds(env)
  }, 200, cors);
}

async function countForDate(env, app, date) {
  const row = await env.DB.prepare(
    "SELECT count FROM daily_counts WHERE app = ?1 AND date = ?2"
  ).bind(app, date).first();
  return Number(row?.count || 0);
}

async function readJson(request) {
  try {
    return await request.json();
  } catch {
    return {};
  }
}

function normalizeApp(value) {
  const app = String(value || DEFAULT_APP_ID)
    .trim()
    .replace(/[^a-z0-9_-]/gi, "")
    .slice(0, 64);
  return app || DEFAULT_APP_ID;
}

function cooldownSeconds(env) {
  const seconds = Number(env.COOLDOWN_SECONDS || 180);
  return Number.isFinite(seconds) && seconds > 0 ? Math.round(seconds) : 180;
}

function todayKeyInTaipei() {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Taipei",
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

async function anonymousClientKey(request, env, app, date) {
  const ip = request.headers.get("CF-Connecting-IP") || "";
  const salt = env.COUNTER_SALT || "replace-this-counter-salt";
  const fields = [app, date, salt, ip];

  if (String(env.CLIENT_KEY_MODE || "ip").toLowerCase() === "ip-browser") {
    fields.push(
      request.headers.get("User-Agent") || "",
      request.headers.get("Accept-Language") || ""
    );
  }

  const source = fields.join("\n");
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(source));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function allowedOrigins(env) {
  return String(env.ALLOWED_ORIGINS || DEFAULT_ALLOWED_ORIGINS.join(","))
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);
}

function originAllowed(request, env) {
  const origin = request.headers.get("Origin");
  if (!origin) return true;
  const allowed = allowedOrigins(env);
  return allowed.includes("*") || allowed.includes(origin);
}

function corsHeaders(request, env) {
  const origin = request.headers.get("Origin");
  const allowed = allowedOrigins(env);
  const allowOrigin = origin && (allowed.includes("*") || allowed.includes(origin))
    ? origin
    : allowed[0] || "https://phoenixes-marketing.github.io";

  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Cache-Control": "no-store",
    "Vary": "Origin"
  };
}

function json(payload, status = 200, headers = {}) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...headers,
      "Content-Type": "application/json; charset=utf-8"
    }
  });
}
