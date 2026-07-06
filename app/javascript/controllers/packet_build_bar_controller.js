import { Controller } from "@hotwired/stimulus"

// Global navbar progress bar for background recipe builds. Polls the
// active_builds feed and shows the current build's stage + a progress fill,
// then a "ready" link when it finishes. Because the bar element is
// data-turbo-permanent, this controller stays connected across page
// navigations, so the poll keeps running as the user roams the app.
export default class extends Controller {
  static targets = ["label", "fill", "spinner", "link", "dismiss"]
  static values = { url: String }

  // stage -> [percent, message]
  static STAGES = {
    queued:    [8,  "Queued, starting soon..."],
    reading:   [25, "Reading the document..."],
    recipes:   [65, "Writing the recipe..."],
    equipment: [88, "Adding the equipment list..."],
    ready:     [100, "Ready"],
  }

  // Poll fast while a build is in flight (snappy stage updates), slowly when
  // idle, so the app-wide bar adds almost no baseline load when nothing is
  // building. A self-scheduling timeout (not setInterval) lets the interval
  // adapt and avoids overlapping in-flight fetches.
  static ACTIVE_MS = 2500
  static IDLE_MS = 9000

  connect() {
    this.dismissed = new Set(JSON.parse(sessionStorage.getItem("dismissedBuilds") || "[]"))
    this.schedule(0)
    this.beforeCache = () => this.stop()
    document.addEventListener("turbo:before-cache", this.beforeCache)
  }

  disconnect() {
    this.stop()
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  stop() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
  }

  schedule(delay) {
    this.stop()
    this.timer = setTimeout(() => this.tick(), delay)
  }

  async tick() {
    let building = null
    let done = null
    try {
      const res = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (res.ok) {
        const builds = ((await res.json()).builds || []).filter((b) => !this.dismissed.has(b.id))
        building = builds.find((b) => b.status === "building")
        done = builds.find((b) => b.status === "ready" || b.status === "failed")
      }
    } catch (_e) {
      // transient; fall through and reschedule
    }

    if (building) this.showBuilding(building)
    else if (done) this.showDone(done)
    else this.hide()

    this.schedule(building ? this.constructor.ACTIVE_MS : this.constructor.IDLE_MS)
  }

  showBuilding(b) {
    const [pct, msg] = this.constructor.STAGES[b.stage] || this.constructor.STAGES.queued
    this.spinnerTarget.classList.remove("hidden")
    this.linkTarget.classList.add("hidden")
    this.dismissTarget.classList.add("hidden")
    this.fillTarget.classList.remove("bg-red-500", "bg-emerald-500")
    this.fillTarget.classList.add("bg-orange-500")
    this.labelTarget.textContent = `Building ${b.title}: ${msg}`
    this.fillTarget.style.width = `${pct}%`
    this.show()
  }

  showDone(b) {
    this.spinnerTarget.classList.add("hidden")
    this.dismissTarget.classList.remove("hidden")
    this.fillTarget.style.width = "100%"
    this.fillTarget.classList.remove("bg-orange-500")
    if (b.status === "failed") {
      this.fillTarget.classList.add("bg-red-500")
      this.labelTarget.textContent = `Could not build ${b.title}: ${b.error || "something went wrong"}`
      this.linkTarget.textContent = "Try again →"
    } else {
      this.fillTarget.classList.add("bg-emerald-500")
      this.labelTarget.textContent = `✓ ${b.title} is ready`
      this.linkTarget.textContent = "Open packet →"
    }
    this.linkTarget.href = b.edit_url
    this.linkTarget.classList.remove("hidden")
    this.currentDoneId = b.id
    this.show()
  }

  dismiss() {
    if (this.currentDoneId != null) {
      this.dismissed.add(this.currentDoneId)
      sessionStorage.setItem("dismissedBuilds", JSON.stringify([...this.dismissed]))
    }
    this.hide()
  }

  show() { this.element.classList.remove("hidden") }
  hide() { this.element.classList.add("hidden") }
}
