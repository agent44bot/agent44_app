// Agent44 Apply Runner (Phase 2)
// Polls the app's apply queue, opens each posting in a HEADED browser on the
// Mac Mini, auto-fills a supported ATS (Greenhouse) from Rich's application
// profile + uploads his resume, and STOPS at the submit button. Rich reviews
// and clicks Submit. Nothing is ever auto-submitted.
//
// Usage:
//   node apply_runner.mjs                 # process the live queue (headed)
//   HEADLESS=1 node apply_runner.mjs      # headless (for CI/testing)
//   node apply_runner.mjs --url <URL>     # test one URL, bypassing the queue
//
// Env: AGENT44_API_TOKEN (else read from ~/.openclaw/credentials/agent44.json)
//      AGENT44_API_URL  (default https://agent44-app.fly.dev)
//      RESUME_PATH      (default ~/apps/my-digital-story-23/public/resume.pdf)

import { chromium } from "playwright";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const API_URL = process.env.AGENT44_API_URL || "https://agent44-app.fly.dev";
const RESUME = process.env.RESUME_PATH || path.join(os.homedir(), "apps/my-digital-story-23/public/resume.pdf");
const HEADLESS = process.env.HEADLESS === "1" || process.argv.includes("--headless");
const argUrl = (() => { const i = process.argv.indexOf("--url"); return i > -1 ? process.argv[i + 1] : null; })();

function token() {
  if (process.env.AGENT44_API_TOKEN) return process.env.AGENT44_API_TOKEN;
  const f = path.join(os.homedir(), ".openclaw/credentials/agent44.json");
  return JSON.parse(fs.readFileSync(f, "utf8")).AGENT44_API_TOKEN;
}
const AUTH = { Authorization: `Bearer ${token()}` };

async function fetchQueue() {
  const r = await fetch(`${API_URL}/api/v1/apply_requests`, { headers: AUTH });
  if (!r.ok) throw new Error(`queue GET ${r.status}`);
  return r.json();
}
async function patch(id, status, notes) {
  if (!id) return; // --url test mode uses a fake id 0
  const r = await fetch(`${API_URL}/api/v1/apply_requests/${id}`, {
    method: "PATCH",
    headers: { ...AUTH, "Content-Type": "application/json" },
    body: JSON.stringify({ status, notes }),
  });
  if (!r.ok) console.error(`  ! PATCH ${id} ${status} -> ${r.status}`);
}

// Which ATS is this? Returns { kind, frame } (frame may be an embedded iframe) or null.
async function detectAts(page) {
  const host = (page.url() || "").toLowerCase();
  if (host.includes("greenhouse.io") || host.includes("grnh.se")) return { kind: "greenhouse", frame: page };
  if (host.includes("lever.co")) return { kind: "lever", frame: page };
  if (host.includes("ashbyhq.com")) return { kind: "ashby", frame: page };
  for (const f of page.frames()) {
    const fu = (f.url() || "").toLowerCase();
    if (fu.includes("greenhouse.io")) return { kind: "greenhouse", frame: f };
    if (fu.includes("lever.co")) return { kind: "lever", frame: f };
  }
  // Field-shape heuristic: Greenhouse-style forms expose #first_name.
  if (await page.locator('#first_name, input[name="first_name"]').count().catch(() => 0)) {
    return { kind: "greenhouse", frame: page };
  }
  return null;
}

// Greenhouse's React inputs wipe a plain .fill() if the form is still hydrating,
// so fill, VERIFY the value stuck, and retry (typing char-by-char as a fallback).
async function fill(scope, selectors, value) {
  if (!value) return false;
  const val = String(value);
  for (const sel of selectors) {
    const loc = scope.locator(sel).first();
    if (!(await loc.count().catch(() => 0))) continue;
    for (let i = 0; i < 3; i++) {
      try {
        await loc.fill("", { timeout: 3000 });
        await loc.fill(val, { timeout: 3000 });
        if ((await loc.inputValue().catch(() => "")) === val) return true;
        await loc.click({ timeout: 2000 });
        await loc.pressSequentially(val, { delay: 15 });
        if ((await loc.inputValue().catch(() => "")) === val) return true;
      } catch { /* re-render mid-fill; retry */ }
      await scope.waitForTimeout?.(400).catch(() => {});
    }
  }
  return false;
}

// Attach the resume and REPORT whether Greenhouse actually registered it.
// Modern Greenhouse uses a React uploader that often ignores a raw setInputFiles,
// so we try the real "Attach" button (native file chooser) first, then fall back
// to the raw input, then verify by checking the uploader shows the filename.
// Returns "attached" | "NOT attached (attach manually)" | "skipped (no resume file)".
async function attachResume(page, frame) {
  if (!fs.existsSync(RESUME)) return "skipped (no resume file)";
  const base = path.basename(RESUME).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const shown = () => frame.getByText(new RegExp(base, "i")).count().catch(() => 0);

  // Preferred: click the resume section's visible "Attach" button (the FIRST one on
  // the page is the resume, cover-letter's is below it) and answer its native chooser.
  const handler = async (fc) => { try { await fc.setFiles(RESUME); } catch { /* ignore */ } };
  page.on("filechooser", handler);
  try {
    const attach = frame.getByRole("button", { name: /^attach$/i }).filter({ visible: true }).first();
    if (await attach.count()) { await attach.scrollIntoViewIfNeeded(); await attach.click({ timeout: 4000 }); await page.waitForTimeout(2000); }
  } catch { /* try fallback */ }
  page.off("filechooser", handler);
  if (await shown()) return "attached"; // stop here so we don't also fill the cover-letter input

  // Fallback: set the raw resume input ONLY (never the generic first file input,
  // which could be the cover letter). Older Greenhouse forms accept this directly.
  try {
    const fi = frame.locator("#resume").first();
    if (await fi.count()) { await fi.setInputFiles(RESUME); await page.waitForTimeout(600); }
  } catch { /* best effort */ }
  return (await shown()) ? "attached" : "NOT attached (attach manually before submitting)";
}

async function fillGreenhouse(page, frame, p) {
  await page.waitForLoadState("networkidle", { timeout: 15000 }).catch(() => {}); // let React hydrate first
  const [first, ...rest] = String(p.full_name || "").split(/\s+/);
  const done = [];
  if (await fill(frame, ["#first_name", 'input[name="first_name"]', 'input[autocomplete="given-name"]'], first)) done.push("first name");
  if (await fill(frame, ["#last_name", 'input[name="last_name"]', 'input[autocomplete="family-name"]'], rest.join(" "))) done.push("last name");
  if (await fill(frame, ["#email", 'input[type="email"]', 'input[name="email"]'], p.contact_email)) done.push("email");
  if (await fill(frame, ["#phone", 'input[type="tel"]', 'input[name="phone"]'], p.phone)) done.push("phone");
  const linkedin = p.links && (p.links.LinkedIn || p.links.linkedin);
  if (linkedin) {
    try { const l = frame.getByLabel(/linkedin/i).first(); if (await l.count()) { await l.fill(linkedin, { timeout: 2000 }); done.push("linkedin"); } } catch { /* optional */ }
  }
  done.push(`resume: ${await attachResume(page, frame)}`);
  return done;
}

async function processReq(context, req, profile) {
  const job = req.job;
  console.log(`\n▶ ${job.title} @ ${job.company}\n  ${job.url}`);
  const page = await context.newPage();
  try {
    await patch(req.id, "opened", "runner opened the posting");
    await page.goto(job.url, { waitUntil: "domcontentloaded", timeout: 45000 });
    const ats = await detectAts(page);
    if (ats?.kind === "greenhouse") {
      const filled = await fillGreenhouse(page, ats.frame, profile);
      const note = filled.length
        ? `Greenhouse: filled ${filled.join(", ")}. Stopped at submit — review and click Submit.`
        : "Greenhouse detected but no standard fields matched; fill manually.";
      console.log("  " + note);
      await patch(req.id, filled.length ? "filled" : "opened", note);
    } else {
      const note = ats
        ? `${ats.kind} detected (autofill not built yet) — fill manually.`
        : "Not a supported ATS (likely an aggregator listing). Click through to Apply and fill manually.";
      console.log("  " + note);
      await patch(req.id, "opened", note);
    }
  } catch (e) {
    console.error("  ERROR " + e.message);
    await patch(req.id, "error", String(e.message).slice(0, 300));
  }
  return page;
}

async function main() {
  const data = argUrl
    ? {
        profile: { full_name: "Rich Downie", contact_email: "botwhisperer@hey.com", phone: "+1 (585) 766-7424", links: { LinkedIn: "https://www.linkedin.com/in/richdownie/" } },
        requests: [{ id: 0, status: "queued", job: { title: "TEST", company: "TEST", url: argUrl } }],
      }
    : await fetchQueue();

  const queued = data.requests.filter((r) => ["queued", "opened", "error"].includes(r.status));
  if (!queued.length) { console.log("Nothing to apply to. Click Apply on a role at /jobs/opportunities first."); return; }

  console.log(`Resume: ${RESUME}${fs.existsSync(RESUME) ? "" : "  ⚠ NOT FOUND (resume upload will be skipped)"}`);
  console.log(`Processing ${queued.length} role(s)...`);

  const browser = await chromium.launch({ headless: HEADLESS });
  const context = await browser.newContext();
  for (const req of queued) await processReq(context, req, data.profile);

  if (HEADLESS) {
    let i = 0;
    for (const pg of context.pages()) { await pg.screenshot({ path: `/tmp/apply-runner-${i++}.png`, fullPage: true }).catch(() => {}); }
    await browser.close();
    console.log(`\n(headless run done; ${i} screenshot(s) in /tmp/apply-runner-*.png)`);
  } else {
    console.log("\n✅ Forms filled to the submit button. Review each tab and click Submit yourself.");
    console.log("   Close the browser window when you're done to end the runner.");
    await new Promise((resolve) => {
      if (!browser.isConnected()) return resolve();
      browser.on("disconnected", resolve);
    });
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
