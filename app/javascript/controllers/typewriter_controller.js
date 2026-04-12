import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["line"]
  static values = { agents: Array }

  connect() {
    this.agentData = this.agentsValue
    this.currentIndex = 0
    this.startCycle()
  }

  disconnect() {
    clearTimeout(this._timeout)
  }

  startCycle() {
    this.currentIndex = 0
    this.clearAll()
    this.typeNext()
  }

  clearAll() {
    this.lineTargets.forEach(line => {
      line.querySelector("[data-name]").textContent = ""
      line.querySelector("[data-role]").textContent = ""
      line.querySelector("[data-dot]").style.opacity = "0"
    })
  }

  typeNext() {
    if (this.currentIndex >= this.lineTargets.length) {
      this._timeout = setTimeout(() => this.startCycle(), 1500)
      return
    }

    const line = this.lineTargets[this.currentIndex]
    const nameEl = line.querySelector("[data-name]")
    const roleEl = line.querySelector("[data-role]")
    const dotEl = line.querySelector("[data-dot]")
    const agent = this.agentData[this.currentIndex]

    dotEl.style.opacity = "1"
    this.type(nameEl, agent.name, () => {
      this.type(roleEl, " " + agent.role, () => {
        this.currentIndex++
        this._timeout = setTimeout(() => this.typeNext(), 300)
      })
    })
  }

  type(el, text, callback) {
    let i = 0
    const tick = () => {
      i++
      el.textContent = text.slice(0, i)
      if (i < text.length) {
        this._timeout = setTimeout(tick, 30 + Math.random() * 25)
      } else if (callback) {
        callback()
      }
    }
    tick()
  }
}
