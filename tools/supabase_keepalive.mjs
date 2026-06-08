import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const repoRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const indexHtml = readFileSync(path.join(repoRoot, "index.html"), "utf8");
const configUrl = indexHtml.match(/SUPABASE_URL\s*=\s*'([^']+)'/)?.[1];
const configKey = indexHtml.match(/SUPABASE_KEY\s*=\s*'([^']+)'/)?.[1];

const url = (process.env.MOODCHART_SUPABASE_URL || configUrl || "").replace(/\/$/, "");
const key = process.env.MOODCHART_SUPABASE_KEY || configKey;
const timeoutMs = Number(process.env.MOODCHART_KEEPALIVE_TIMEOUT_MS || 15000);

if (!url || !key) {
  throw new Error("Moodchart Supabase URL/key is missing.");
}

const controller = new AbortController();
const timer = setTimeout(() => controller.abort(), timeoutMs);
const startedAt = new Date();

try {
  const response = await fetch(`${url}/auth/v1/settings`, {
    method: "GET",
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      Accept: "application/json",
      "User-Agent": "Moodchart-Supabase-Keepalive/1.0",
    },
    signal: controller.signal,
  });

  const body = await response.text();
  const detail = {
    ok: response.ok,
    status: response.status,
    started_at: startedAt.toISOString(),
    finished_at: new Date().toISOString(),
    response_bytes: body.length,
  };

  console.log(JSON.stringify(detail));

  if (!response.ok) {
    process.exitCode = 1;
  }
} catch (error) {
  console.error(JSON.stringify({
    ok: false,
    started_at: startedAt.toISOString(),
    finished_at: new Date().toISOString(),
    error: error?.name === "AbortError" ? "timeout" : String(error?.message || error),
  }));
  process.exitCode = 1;
} finally {
  clearTimeout(timer);
}
