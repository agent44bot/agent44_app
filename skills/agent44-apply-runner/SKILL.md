---
name: agent44-apply-runner
description: "Phase 2 of assisted apply. Polls the Agent44 apply queue, opens each queued job posting in a headed browser on the Mac Mini, auto-fills a supported ATS (Greenhouse) from Rich's application profile + uploads his resume, and STOPS at the submit button for him to review and click. Nothing is auto-submitted."
version: 0.1.0
metadata:
  openclaw:
    requires:
      env:
        - AGENT44_API_TOKEN
      bins:
        - node
    primaryEnv: AGENT44_API_TOKEN
---

# Agent44 Apply Runner

Consumes the apply queue Rich fills by clicking **Apply** at
`agent44labs.com/jobs/opportunities` (Phase 1). For each queued role it opens
the posting, and where it recognizes a supported ATS it fills the standard
fields and uploads the resume, then halts at the submit button. **Rich clicks
Submit.** Nothing is ever auto-submitted.

## Reality of the queue

Most job URLs in the board are **aggregator listings** (LinkedIn, Indeed,
Google Jobs), not direct application forms. For those the runner just **opens**
the page so Rich can click through and apply manually (LinkedIn/Indeed autofill
is skipped on purpose — their ToS prohibits automation). Auto-fill kicks in only
when a job links directly to, or embeds, a **Greenhouse** form. Lever/Ashby are
detected but not yet auto-filled.

## Run it

```bash
bash ~/.openclaw/skills/agent44-apply-runner/scripts/run.sh
```

A browser opens with one tab per queued role, each filled to the submit button
(Greenhouse) or just opened (everything else). Review and Submit the ones you
want, then close the browser window to end the run. Status is reported back to
the app per role: `opened` -> `filled` -> (`applied`, which Rich marks himself).

## Flags / env

- `HEADLESS=1 …` — run headless (testing/CI; screenshots to `/tmp/apply-runner-*.png`).
- `--url <URL>` — fill a single URL, bypassing the queue (debug).
- `RESUME_PATH` — resume PDF (default `~/apps/my-digital-story-23/public/resume.pdf`).
- `AGENT44_API_TOKEN` — bearer token (else read from `~/.openclaw/credentials/agent44.json`).

## Setup

```bash
cd ~/.openclaw/skills/agent44-apply-runner/scripts
npm install                      # installs playwright
npx playwright install chromium  # one-time browser download (uses shared cache)
```
