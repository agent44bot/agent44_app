import { Controller } from "@hotwired/stimulus"

// Per-agent task pools. Agents not listed here fall back to tasksValue.
const SPECIAL_TASKS = {
  "007": [
    "martini, shaken, not stirred",
    "tailing mark through Monte Carlo",
    "decoding MI6 cipher",
    "evading pursuit in Aston Martin",
    "scaling alpine ridge",
    "briefing M",
    "checking Q's new gadget",
    "losing a tail in Istanbul"
  ],
  "004": [
    "drafting an Instagram post",
    "drafting a Facebook post",
    "drafting a TikTok caption",
    "writing a LinkedIn post",
    "polishing a caption",
    "generating hashtags",
    "A/B testing two headlines",
    "scheduling tomorrow's feed"
  ],
  "002": [
    "drafting a welcome email",
    "writing newsletter intro",
    "A/B testing subject lines",
    "drafting cart abandonment email",
    "writing promo blast",
    "scheduling drip sequence",
    "proofreading newsletter",
    "tagging CTAs"
  ]
}

// Restart-fallback flavor text per agent
const SPECIAL_RESTART = {
  "007": "martini, shaken, not stirred",
  "004": "drafting an Instagram post",
  "002": "drafting a welcome email"
}

// Smoke-and-mirrors fleet animation. Periodically cycles mock agent
// statuses (online / busy / offline / restarting) and occasionally
// promotes a row to the top to simulate activity.
export default class extends Controller {
  static targets = ["line"]
  static values = { tasks: Array }

  connect() {
    this.cycleTimer = setInterval(() => this.tick(), 1400 + Math.random() * 900)
    this.shuffleTimer = setInterval(() => this.shuffle(), 5200 + Math.random() * 1800)
  }

  disconnect() {
    clearInterval(this.cycleTimer)
    clearInterval(this.shuffleTimer)
  }

  tick() {
    if (this.lineTargets.length === 0) return
    const line = this.lineTargets[Math.floor(Math.random() * this.lineTargets.length)]
    const nameEl = line.querySelector("[data-name]")
    const name = nameEl ? nameEl.textContent.trim() : ""
    const pool = SPECIAL_TASKS[name] || this.tasksValue
    const restartTask = SPECIAL_RESTART[name] || "restarting…"

    const roll = Math.random()
    if (roll < 0.4) {
      this.setStatus(line, "online")
    } else if (roll < 0.75) {
      const task = pool[Math.floor(Math.random() * pool.length)]
      this.setStatus(line, "busy", task)
    } else if (roll < 0.9) {
      this.setStatus(line, "offline")
    } else {
      this.setStatus(line, "busy", restartTask)
    }
  }

  setStatus(line, status, task = null) {
    const dot = line.querySelector("[data-dot]")
    const name = line.querySelector("[data-name]")
    const role = line.querySelector("[data-role]")
    const taskEl = line.querySelector("[data-task]")
    line.dataset.status = status

    const palette = {
      online:  { dot: "bg-green-400 animate-pulse",      name: "text-green-400", role: "text-green-700" },
      busy:    { dot: "bg-amber-400 animate-agent-pulse", name: "text-amber-400", role: "text-amber-700" },
      offline: { dot: "bg-gray-600",                      name: "text-gray-500", role: "text-gray-600"  }
    }
    const p = palette[status] || palette.online
    const dotBase = dot.className.match(/h-\d\.?\d?/)?.[0] ?? "h-2"
    const dotW = dot.className.match(/w-\d\.?\d?/)?.[0] ?? "w-2"
    dot.className = `inline-block ${dotBase} ${dotW} rounded-full shrink-0 ${p.dot}`

    const nameSize = name.className.match(/text-\[\d+px\]/)?.[0] ?? "text-[11px]"
    name.className = `${nameSize} ${p.name}`

    const roleSize = role.className.match(/text-\[\d+px\]/)?.[0] ?? "text-[9px]"
    role.className = `${roleSize} ${p.role}`

    if (status === "busy" && task) {
      taskEl.textContent = `(${task})`
      taskEl.style.display = ""
    } else {
      taskEl.textContent = ""
      taskEl.style.display = "none"
    }
  }

  shuffle() {
    const lines = Array.from(this.lineTargets)
    if (lines.length < 2) return
    const idx = Math.floor(Math.random() * lines.length)
    const line = lines[idx]
    const parent = line.parentElement
    if (line === parent.firstElementChild) return
    parent.insertBefore(line, parent.firstElementChild)
    line.style.backgroundColor = "rgba(245, 158, 11, 0.12)"
    setTimeout(() => { line.style.backgroundColor = "" }, 600)
  }
}
