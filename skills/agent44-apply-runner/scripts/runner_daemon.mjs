// Agent44 Apply Runner daemon (Phase 3)
// Lets the whole apply flow stay in the browser: Rich clicks "Run now on the
// Mac Mini" at /jobs/opportunities, which raises a flag in the app; this daemon
// polls for that flag and launches the HEADED runner (run.sh) once. Nothing is
// ever auto-submitted; the runner still stops at the submit button.
//
// Run it in Rich's GUI session on the Mac Mini so the browser is visible:
//   node runner_daemon.mjs            # poll forever (Ctrl-C to stop)
//   POLL_INTERVAL=10 node runner_daemon.mjs
//
// Env: AGENT44_API_TOKEN (else ~/.openclaw/credentials/agent44.json)
//      AGENT44_API_URL   (default https://agent44-app.fly.dev)
//      POLL_INTERVAL     (seconds between polls, default 15)

import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const API_URL = process.env.AGENT44_API_URL || "https://agent44-app.fly.dev";
const INTERVAL = Math.max(5, Number(process.env.POLL_INTERVAL || 15)) * 1000;
const RUN_SH = new URL("./run.sh", import.meta.url).pathname;

function token() {
  if (process.env.AGENT44_API_TOKEN) return process.env.AGENT44_API_TOKEN;
  const f = path.join(os.homedir(), ".openclaw/credentials/agent44.json");
  return JSON.parse(fs.readFileSync(f, "utf8")).AGENT44_API_TOKEN;
}
const AUTH = { Authorization: `Bearer ${token()}` };

let running = false;   // true while a headed runner is open (skip polls until it closes)
let lastSeen = null;   // dedupe guard in case a clear is briefly missed

async function tick() {
  if (running) return;
  let data;
  try {
    const r = await fetch(`${API_URL}/api/v1/apply_requests`, { headers: AUTH });
    if (!r.ok) throw new Error(`queue GET ${r.status}`);
    data = await r.json();
  } catch (e) {
    console.error(`poll error: ${e.message}`);
    return;
  }

  const requested = data.run_requested_at;
  if (!requested || requested === lastSeen) return;
  lastSeen = requested;

  // Clear the flag immediately so one button press = one run.
  await fetch(`${API_URL}/api/v1/apply_requests/run_request`, { method: "DELETE", headers: AUTH }).catch(() => {});

  const pending = (data.requests || []).filter((r) => ["queued", "opened", "error"].includes(r.status));
  if (!pending.length) {
    console.log(`[${stamp()}] Run requested, but nothing is queued. Skipping.`);
    return;
  }

  running = true;
  console.log(`[${stamp()}] Run requested -> launching headed runner for ${pending.length} role(s)...`);
  const child = spawn("bash", [RUN_SH], { stdio: "inherit" });
  child.on("exit", (code) => {
    running = false;
    console.log(`[${stamp()}] Runner exited (${code}). Back to polling.`);
  });
}

// A monotonic-ish label without Date.now (fine for logs).
function stamp() {
  return new Date().toISOString().slice(11, 19);
}

console.log(`apply-runner daemon: polling ${API_URL} every ${INTERVAL / 1000}s. Waiting for a "Run now" click...`);
setInterval(tick, INTERVAL);
tick();
