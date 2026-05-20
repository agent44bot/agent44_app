import { Controller } from "@hotwired/stimulus"

const ROLE_POOL = [
  "Smoke Runner", "QA Engineer", "Linter", "Profiler", "Log Watcher",
  "Crawler", "Replayer", "Deploy Bot", "DB Migrator", "API Monitor",
  "Cert Watcher", "Edge Warmer", "Link Checker", "Latency Probe",
  "DNS Sentinel", "Sitemap Crawler", "Cache Warmer", "Health Probe",
  "Error Tracer", "Build Bot", "Test Runner", "PR Reviewer",
  "Dependency Bot", "Schema Diff", "Heap Profiler", "Queue Watcher",
  "Webhook Replayer", "Uptime Probe", "Sentry Triager", "Migration Bot"
]

const FIXED_ROLES = {
  "001": "Smoke Runner",
  "002": "QA Engineer",
  "007": "Security Scanner"
}

const SPECIAL_TASKS = {
  "007": [
    "running CVE scan",
    "rotating API key",
    "auditing IAM roles",
    "checking signed cookies",
    "diffing CSP headers",
    "probing for SSRF",
    "auditing dependency tree",
    "verifying TLS chain"
  ],
  "002": [
    "running unit tests",
    "running smoke suite",
    "comparing baseline screenshots",
    "rerunning a flake",
    "writing a regression test",
    "filing a flaky-test issue",
    "bisecting a failure",
    "tagging CI flake"
  ],
  "001": [
    "starting smoke run",
    "loading calendar page",
    "round-tripping event grid",
    "diffing class list",
    "capturing console errors",
    "saving page source",
    "uploading run artifact",
    "alerting on regression"
  ]
}

const TOTAL_AGENTS = 99
const ROW_HEIGHT_PX = 20

// Smoke-and-mirrors fleet animation. Maintains a pool of 99 agents and
// always shows 10. Periodically promotes a visible agent to "busy" (yellow,
// moves to top), then after a few seconds slides it out the bottom and
// brings a fresh pool agent in.
export default class extends Controller {
  static targets = ["list", "line"]
  static values = { tasks: Array, visibleCount: { type: Number, default: 10 } }

  connect() {
    const visible = this.visibleCountValue || 10

    this.allAgents = []
    for (let i = 1; i <= TOTAL_AGENTS; i++) {
      const id = String(i).padStart(3, "0")
      const role = FIXED_ROLES[id] || ROLE_POOL[Math.floor(Math.random() * ROLE_POOL.length)]
      this.allAgents.push({ id, role })
    }
    this.shuffle(this.allAgents)

    const initial = this.allAgents.slice(0, visible)
    this.poolIds = this.allAgents.slice(visible).map(a => a.id)
    this.byId = Object.fromEntries(this.allAgents.map(a => [a.id, a]))

    this.renderInitial(initial)

    // Slow the cycle when fewer rows are visible — otherwise the same
    // agent gets promoted too often and the list feels frantic.
    const baseInterval = visible <= 5 ? 4000 : 2200
    const jitter = visible <= 5 ? 2000 : 1800
    this.cycleTimer = setInterval(() => this.startTask(), baseInterval + Math.random() * jitter)
  }

  disconnect() {
    clearInterval(this.cycleTimer)
  }

  renderInitial(initial) {
    const list = this.listTarget
    list.innerHTML = ""
    initial.forEach(agent => list.appendChild(this.buildRow(agent.id)))
  }

  buildRow(id) {
    const agent = this.byId[id]
    const row = document.createElement("div")
    row.className = "flex items-center gap-2 rounded px-1 -mx-1 overflow-hidden min-w-0 max-w-full"
    row.dataset.mockAgentsTarget = "line"
    row.dataset.id = id
    row.dataset.status = "online"
    row.style.maxHeight = `${ROW_HEIGHT_PX}px`
    row.style.opacity = "1"
    row.innerHTML = `
      <span class="inline-block h-2 w-2 rounded-full shrink-0 bg-green-400 animate-pulse" data-dot></span>
      <span class="text-[11px] text-green-400 shrink-0" data-name>${id}</span>
      <span class="text-[9px] text-green-500 shrink-0" data-role>${agent.role}</span>
      <span class="text-[8px] text-amber-500 italic min-w-0 truncate" data-task style="display:none"></span>
    `
    return row
  }

  shuffle(arr) {
    for (let i = arr.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1))
      ;[arr[i], arr[j]] = [arr[j], arr[i]]
    }
  }

  startTask() {
    const list = this.listTarget
    const candidates = Array.from(list.children).filter(r => r.dataset.status === "online")
    if (candidates.length === 0) return

    const row = candidates[Math.floor(Math.random() * candidates.length)]
    const id = row.dataset.id
    const taskPool = SPECIAL_TASKS[id] || this.tasksValue
    const task = taskPool[Math.floor(Math.random() * taskPool.length)]

    list.insertBefore(row, list.firstElementChild)
    this.setBusy(row, task)

    const taskDuration = 2400 + Math.random() * 3200
    setTimeout(() => this.finishTask(row), taskDuration)
  }

  setBusy(row, task) {
    row.dataset.status = "busy"
    const dot = row.querySelector("[data-dot]")
    const name = row.querySelector("[data-name]")
    const taskEl = row.querySelector("[data-task]")
    dot.className = "inline-block h-2 w-2 rounded-full shrink-0 bg-amber-400 animate-agent-pulse"
    name.className = "text-[11px] text-amber-400"
    taskEl.textContent = `(${task})`
    taskEl.style.display = ""
    row.style.transition = "background-color 600ms ease"
    row.style.backgroundColor = "rgba(245, 158, 11, 0.12)"
    setTimeout(() => { row.style.backgroundColor = "" }, 600)
    this.webPulses?.spawn(row.dataset.id)
  }

  finishTask(row) {
    if (!row.parentElement) return
    const list = this.listTarget
    const id = row.dataset.id

    this.webPulses?.complete(id)

    row.style.transition = "max-height 500ms ease, opacity 500ms ease, transform 500ms ease, margin 500ms ease"
    row.style.maxHeight = "0px"
    row.style.opacity = "0"
    row.style.transform = "translateY(8px)"

    setTimeout(() => {
      row.remove()
      this.poolIds.push(id)
      this.addNewAgent()
    }, 500)
  }

  get webPulses() {
    if (this._webPulses) return this._webPulses
    const el = document.querySelector('[data-controller~="web-pulses"]')
    if (!el) return null
    this._webPulses = this.application.getControllerForElementAndIdentifier(el, "web-pulses")
    return this._webPulses
  }

  addNewAgent() {
    if (this.poolIds.length === 0) return
    const idx = Math.floor(Math.random() * this.poolIds.length)
    const newId = this.poolIds.splice(idx, 1)[0]

    const row = this.buildRow(newId)
    row.style.maxHeight = "0px"
    row.style.opacity = "0"
    row.style.transform = "translateY(8px)"
    this.listTarget.appendChild(row)

    requestAnimationFrame(() => {
      row.style.transition = "max-height 500ms ease, opacity 500ms ease, transform 500ms ease"
      row.style.maxHeight = `${ROW_HEIGHT_PX}px`
      row.style.opacity = "1"
      row.style.transform = "translateY(0)"
    })
  }
}
