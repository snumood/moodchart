import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { execFileSync } from "node:child_process";

const repoRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const indexHtml = readFileSync(path.join(repoRoot, "index.html"), "utf8");
const configUrl = indexHtml.match(/SUPABASE_URL\s*=\s*'([^']+)'/)?.[1];
const configKey = indexHtml.match(/SUPABASE_KEY\s*=\s*'([^']+)'/)?.[1];

const supabaseUrl = (process.env.MOODCHART_SUPABASE_URL || configUrl || "").replace(/\/$/, "");
const supabaseKey = process.env.MOODCHART_SUPABASE_KEY || configKey;
const timeoutMs = Number(process.env.MOODCHART_AUDIT_TIMEOUT_MS || 20000);
const outputPath = process.env.MOODCHART_AUDIT_OUTPUT || path.join(repoRoot, ".monthly-audit", "latest.json");

const githubWorkflowUrl = "https://raw.githubusercontent.com/snumood/moodchart/main/.github/workflows/supabase-keepalive.yml";
const githubRunsUrl = "https://api.github.com/repos/snumood/moodchart/actions/workflows/supabase-keepalive.yml/runs?per_page=1";

async function fetchText(url, options = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
    const text = await response.text();
    return { ok: response.ok, status: response.status, text };
  } finally {
    clearTimeout(timer);
  }
}

async function checkSupabase() {
  const result = await fetchText(`${supabaseUrl}/auth/v1/settings`, {
    headers: {
      apikey: supabaseKey,
      Authorization: `Bearer ${supabaseKey}`,
      Accept: "application/json",
      "User-Agent": "Moodchart-Monthly-Safety-Audit/1.0",
    },
  });
  return {
    name: "supabase_auth_settings",
    ok: result.ok,
    status: result.status,
    response_bytes: result.text.length,
  };
}

async function checkGitHubWorkflowFile() {
  const result = await fetchText(githubWorkflowUrl, {
    headers: { "User-Agent": "Moodchart-Monthly-Safety-Audit/1.0" },
  });
  return {
    name: "github_workflow_file",
    ok: result.status === 404 ? true : result.ok && result.text.includes("Moodchart Supabase keepalive") && result.text.includes("schedule:"),
    status: result.status,
    warning: result.status === 404 ? "workflow_not_pushed_yet" : undefined,
    response_bytes: result.text.length,
  };
}

async function checkGitHubLatestRun() {
  const result = await fetchText(githubRunsUrl, {
    headers: {
      Accept: "application/vnd.github+json",
      "User-Agent": "Moodchart-Monthly-Safety-Audit/1.0",
    },
  });
  if (!result.ok) {
    return { name: "github_keepalive_latest_run", ok: result.status === 404, status: result.status, warning: result.status === 404 ? "workflow_not_pushed_yet" : undefined };
  }
  const json = JSON.parse(result.text);
  const run = json.workflow_runs?.[0];
  if (!run) {
    return { name: "github_keepalive_latest_run", ok: true, status: result.status, warning: "no_runs_yet" };
  }
  const updatedAt = new Date(run.updated_at || run.created_at);
  const ageDays = (Date.now() - updatedAt.getTime()) / 86400000;
  return {
    name: "github_keepalive_latest_run",
    ok: ageDays <= 45 && ["success", null].includes(run.conclusion),
    status: result.status,
    run_status: run.status,
    conclusion: run.conclusion,
    updated_at: run.updated_at,
    age_days: Number(ageDays.toFixed(2)),
    html_url: run.html_url,
  };
}

function checkVmTimer() {
  try {
    const out = execFileSync("systemctl", ["--user", "is-active", "moodchart-supabase-keepalive.timer"], { encoding: "utf8" }).trim();
    return { name: "vm_keepalive_timer", ok: out === "active", status: out };
  } catch (error) {
    if (error?.code === "ENOENT") {
      return { name: "vm_keepalive_timer", ok: true, status: "skipped", warning: "systemctl_not_available" };
    }
    return { name: "vm_keepalive_timer", ok: false, status: "error", error: String(error.message || error) };
  }
}

const startedAt = new Date().toISOString();
const checks = [];
for (const fn of [checkSupabase, checkGitHubWorkflowFile, checkGitHubLatestRun]) {
  try {
    checks.push(await fn());
  } catch (error) {
    checks.push({ name: fn.name, ok: false, error: String(error.message || error) });
  }
}
checks.push(checkVmTimer());

const report = {
  ok: checks.every((check) => check.ok),
  started_at: startedAt,
  finished_at: new Date().toISOString(),
  checks,
};

mkdirSync(path.dirname(outputPath), { recursive: true });
writeFileSync(outputPath, JSON.stringify(report, null, 2));
console.log(JSON.stringify(report));

if (!report.ok) {
  process.exitCode = 1;
}
