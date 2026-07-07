import { Controller } from "@hotwired/stimulus"

// Reloads the grocery turbo-frame every few seconds while the list is building
// in the background, until the cached list renders (this placeholder, and this
// controller, are then gone). Cleans up on disconnect and before Turbo caches
// the page so a restored snapshot never keeps polling.
export default class extends Controller {
  static values = { interval: { type: Number, default: 3000 } }

  connect() {
    this.timer = setTimeout(() => this.reload(), this.intervalValue)
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

  reload() {
    const frame = this.element.closest("turbo-frame")
    if (frame && typeof frame.reload === "function") frame.reload()
  }
}
