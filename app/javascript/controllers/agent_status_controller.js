import { Controller } from "@hotwired/stimulus"

// Polls /api/v1/agents/statuses every 10s and updates dots + text live
export default class extends Controller {
  static targets = ["agent"]

  connect() {
    this.poll()
    this._interval = setInterval(() => this.poll(), 10000)
  }

  disconnect() {
    clearInterval(this._interval)
  }

  async poll() {
    try {
      const res = await fetch("/api/v1/agents/statuses")
      if (!res.ok) return
      const agents = await res.json()
      agents.forEach(agent => this.updateAgent(agent))
    } catch (_) { /* silent */ }
  }

  updateAgent(agent) {
    const el = this.agentTargets.find(t => t.dataset.agentName === agent.name)
    if (!el) return

    const dot = el.querySelector("[data-dot]")
    const nameEl = el.querySelector("[data-name]")
    const roleEl = el.querySelector("[data-role]")
    const taskEl = el.querySelector("[data-task]")

    // Update dot color and animation
    dot.className = this.dotClasses(agent.status)
    dot.style.opacity = "1"

    // Update name color
    nameEl.className = this.nameClasses(agent.status)

    // Update role color
    roleEl.className = this.roleClasses(agent.status)

    // Update task label
    if (taskEl) {
      if (agent.status === "busy" || agent.status === "error") {
        taskEl.textContent = `(${agent.task})`
        taskEl.className = this.taskClasses(agent.status)
        taskEl.style.display = ""
      } else {
        taskEl.textContent = ""
        taskEl.style.display = "none"
      }
    }
  }

  dotClasses(status) {
    const base = "inline-block h-2 w-2 rounded-full transition-opacity"
    switch (status) {
      case "busy":    return `${base} bg-amber-400 animate-agent-pulse`
      case "error":   return `${base} bg-red-500`
      case "online":  return `${base} bg-green-400 animate-pulse`
      default:        return `${base} bg-gray-600`
    }
  }

  nameClasses(status) {
    const base = "text-[11px]"
    switch (status) {
      case "busy":    return `${base} text-amber-400`
      case "error":   return `${base} text-red-400`
      default:        return `${base} text-green-400`
    }
  }

  roleClasses(status) {
    const base = "text-[9px]"
    switch (status) {
      case "busy":    return `${base} text-amber-700`
      case "error":   return `${base} text-red-700`
      default:        return `${base} text-green-700`
    }
  }

  taskClasses(status) {
    return status === "busy"
      ? "text-[8px] text-amber-500 italic"
      : "text-[8px] text-red-500 italic"
  }
}
