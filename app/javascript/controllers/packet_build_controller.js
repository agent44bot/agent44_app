import { Controller } from "@hotwired/stimulus"

// Polls the packet's status endpoint while ExtractRecipeJob runs in the
// background, then reloads the page (rendering the editor, or the failure
// state) the moment the job finishes. Timer is cleared on disconnect and
// before Turbo caches the page so a restored snapshot never keeps polling.
export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 3000 } }

  connect() {
    this.timer = setInterval(() => this.check(), this.intervalValue)
    this.beforeCache = () => this.stop()
    document.addEventListener("turbo:before-cache", this.beforeCache)
  }

  disconnect() {
    this.stop()
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  stop() {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
  }

  async check() {
    try {
      const res = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (!res.ok) return
      const data = await res.json()
      if (data.status && data.status !== "building") {
        this.stop()
        window.location.reload()
      }
    } catch (_e) {
      // transient network hiccup: keep polling on the next tick
    }
  }
}
